package dev.m3e.m3e_todo

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues.TAG
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID
import androidx.core.content.FileProvider

/**
 * Posts a due-date notification when an alarm fires.
 *
 * A named receiver class so the manifest can instantiate it while the app
 * process is dead — which is exactly the state the device is usually in when a
 * reminder is due.
 */
class DueAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_RING = "ring"
        const val EXTRA_RINGTONE = "ringtoneUri"

        /** The quiet channel, shared by every todo that asks for "just a message". */
        const val SILENT_CHANNEL_ID = "due_silent"

        /** Ringing with the system's own notification sound. */
        const val DEFAULT_RING_CHANNEL_ID = "due_ring_default"

        /** Prefix for the channel of one particular ringtone; see [PlatformHost]. */
        const val RING_CHANNEL_PREFIX = "due_ring_"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""
        val ring = intent.getBooleanExtra(EXTRA_RING, false)
        val ringtone = intent.getStringExtra(EXTRA_RINGTONE)

        // Android 13+ gates notifications behind a runtime permission; honour it
        // rather than crashing or posting a notification the user has banned.
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PERMISSION_GRANTED
        ) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        @Suppress("DEPRECATION")
        val builder =
            if (PlatformHost.channelsSupported()) {
                Notification.Builder(context, PlatformHost.channelForReminder(context, ring, ringtone))
            } else {
                // Before Android 8 there are no channels: the sound belongs to
                // the notification itself, so it is set here instead.
                Notification.Builder(context)
                    .setPriority(
                        if (ring) Notification.PRIORITY_HIGH else Notification.PRIORITY_DEFAULT,
                    )
                    .setSound(if (ring) PlatformHost.soundUri(ringtone) else null)
            }
        builder
            // A monochrome glyph, not the launcher icon: the status bar masks a
            // small icon down to a single colour, so a colour bitmap would show
            // up as a featureless blob.
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    context,
                    id,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        manager.notify(id, builder.build())

        // The alarm has fired; drop it from the persisted schedule so a reboot
        // does not resurrect it.
        AlarmStore.remove(context, id)
    }
}

/** Re-registers every pending due-date alarm after the device reboots. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            AlarmStore.rescheduleAll(context)
        }
    }
}

/**
 * Persists scheduled alarms so [BootReceiver] can restore them after a reboot,
 * and registers/cancels the actual [AlarmManager] alarms.
 */
internal object AlarmStore {
    private const val PREFS = "due_alarms"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun schedule(
        context: Context,
        id: Int,
        title: String,
        body: String,
        triggerAtMillis: Long,
        ring: Boolean,
        ringtoneUri: String?,
    ) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, DueAlarmReceiver::class.java)
            .putExtra(DueAlarmReceiver.EXTRA_NOTIFICATION_ID, id)
            .putExtra(DueAlarmReceiver.EXTRA_TITLE, title)
            .putExtra(DueAlarmReceiver.EXTRA_BODY, body)
            .putExtra(DueAlarmReceiver.EXTRA_RING, ring)
            .putExtra(DueAlarmReceiver.EXTRA_RINGTONE, ringtoneUri)
        val pending = PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val exactAllowed = Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()
        if (exactAllowed) {
            alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending)
        } else {
            // No exact-alarm grant: ask for a 10 minute window rather than
            // failing, since an inexact reminder still beats none. Do not read
            // the delivered window back out of `dumpsys alarm` to check this
            // branch: on the Android 13 device this was built against, an alarm
            // set for 2026-09-20 09:00 was listed with a one hour window *and*
            // `exactAllowReason=permission`, so the log alone cannot tell the
            // two branches apart. The settings page reports what
            // `canScheduleExactAlarms` actually returns, which is the honest
            // answer.
            alarm.setWindow(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                10 * 60 * 1000L,
                pending,
            )
        }

        prefs(context).edit().putString(
            id.toString(),
            JSONObject()
                .put("title", title)
                .put("body", body)
                .put("triggerAt", triggerAtMillis)
                .put("ring", ring)
                .put("ringtoneUri", ringtoneUri)
                .toString(),
        ).apply()
    }

    fun cancel(context: Context, id: Int) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = PendingIntent.getBroadcast(
            context,
            id,
            Intent(context, DueAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarm.cancel(pending)
        prefs(context).edit().remove(id.toString()).apply()
    }

    /**
     * Makes the stored schedule exactly [alarms].
     *
     * Everything stored but not in the list is cancelled first: those alarms
     * belong to todos that no longer exist, so the Dart side cannot name them to
     * cancel them one by one — and a reminder for a deleted todo firing days
     * later is exactly the kind of ghost this method exists to prevent.
     */
    fun replaceAll(
        context: Context,
        alarms: List<Map<*, *>>,
    ) {
        val wanted = alarms.mapNotNull { (it["notificationId"] as? Number)?.toInt() }.toSet()
        for (key in prefs(context).all.keys) {
            val id = key.toIntOrNull() ?: continue
            if (id !in wanted) {
                cancel(context, id)
            }
        }
        for (args in alarms) {
            schedule(
                context,
                (args["notificationId"] as Number).toInt(),
                args["title"] as? String ?: "",
                args["body"] as? String ?: "",
                (args["triggerAtMillis"] as Number).toLong(),
                args["ring"] as? Boolean ?: false,
                args["ringtoneUri"] as? String,
            )
        }
    }

    fun remove(context: Context, id: Int) {
        prefs(context).edit().remove(id.toString()).apply()
    }

    /** Restores every still-future alarm; past ones are dropped. */
    fun rescheduleAll(context: Context) {
        val now = System.currentTimeMillis()
        val editor = prefs(context).edit()
        for ((key, value) in prefs(context).all) {
            if (value !is String) continue
            val stored = runCatching { JSONObject(value) }.getOrNull() ?: continue
            val triggerAt = stored.optLong("triggerAt", 0L)
            val id = key.toIntOrNull() ?: continue
            if (triggerAt <= now) {
                editor.remove(key)
                continue
            }
            schedule(
                context,
                id,
                stored.optString("title"),
                stored.optString("body"),
                triggerAt,
                stored.optBoolean("ring", false),
                if (stored.isNull("ringtoneUri")) null else stored.optString("ringtoneUri"),
            )
        }
        editor.apply()
    }
}

/**
 * Holds process-wide state shared by [MainActivity] and the receivers, and
 * owns the notification channels.
 */
internal object PlatformHost {
    /** Notification channels arrived in Android 8; before that, none of this
     *  exists and setting one up would be a crash on a supported device. */
    fun channelsSupported(): Boolean = Build.VERSION.SDK_INT >= 26

    /** The sound an alarm should make: its own ringtone, or the system default. */
    fun soundUri(ringtoneUri: String?): Uri =
        if (ringtoneUri.isNullOrBlank()) {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        } else {
            Uri.parse(ringtoneUri)
        }

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun soundAttributes() = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /**
     * Creates the two channels every reminder starts from: the quiet one, and
     * ringing with the system's own notification sound.
     *
     * Called on every launch, and safe to repeat because a channel that already
     * exists is left alone — Android fixes a channel's sound at creation, and
     * recreating one would throw away the user's own per-channel settings
     * (importance, vibration, lockscreen visibility).
     */
    fun ensureChannels(context: Context) {
        if (!channelsSupported()) return
        ensureChannel(
            context,
            DueAlarmReceiver.SILENT_CHANNEL_ID,
            "待办提醒（仅消息）",
            NotificationManager.IMPORTANCE_DEFAULT,
            sound = null,
        )
        ensureChannel(
            context,
            DueAlarmReceiver.DEFAULT_RING_CHANNEL_ID,
            "待办提醒（响铃）",
            NotificationManager.IMPORTANCE_HIGH,
            sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
        )
        // Channels from the version-numbered scheme this replaced: one was
        // minted per ringtone change, so a long-lived install has collected the
        // debris. Clear it out now that a channel is created once per sound.
        val manager = manager(context)
        manager.notificationChannels
            .filter { it.id.startsWith("due_ring_v") }
            .forEach { manager.deleteNotificationChannel(it.id) }
    }

    /**
     * The channel a reminder should be posted through, creating it if needed.
     *
     * One channel per *sound*, because that is the only lever Android offers:
     * a channel owns its sound and forbids changing it afterwards, so a ringtone
     * chosen for a single todo cannot be applied to a shared channel. Channels
     * are therefore created on demand — one for the system default, one per
     * distinct ringtone the user picks — and reused by every todo that chooses
     * the same sound. The channel's name carries the ringtone's own title so the
     * list in Android's settings stays readable, and so a user who wants to mute
     * one particular tone can find it.
     */
    fun channelForReminder(context: Context, ring: Boolean, ringtoneUri: String?): String {
        if (!ring || !channelsSupported()) return DueAlarmReceiver.SILENT_CHANNEL_ID
        if (ringtoneUri.isNullOrBlank()) {
            ensureChannel(
                context,
                DueAlarmReceiver.DEFAULT_RING_CHANNEL_ID,
                "待办提醒（响铃）",
                NotificationManager.IMPORTANCE_HIGH,
                sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
            )
            return DueAlarmReceiver.DEFAULT_RING_CHANNEL_ID
        }
        val uri = Uri.parse(ringtoneUri)
        val id = DueAlarmReceiver.RING_CHANNEL_PREFIX + ringtoneUri.hashCode().toUInt().toString(16)
        ensureChannel(
            context,
            id,
            "待办提醒（" + ringtoneTitle(context, uri) + "）",
            NotificationManager.IMPORTANCE_HIGH,
            sound = uri,
        )
        return id
    }

    /** The ringtone's own name, or a plain fallback when the system has none. */
    private fun ringtoneTitle(context: Context, uri: Uri): String =
        runCatching { RingtoneManager.getRingtone(context, uri)?.getTitle(context) }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: "自定义铃声"

    private fun ensureChannel(
        context: Context,
        id: String,
        name: String,
        importance: Int,
        sound: Uri?,
    ) {
        val manager = manager(context)
        if (manager.getNotificationChannel(id) != null) return
        val channel = NotificationChannel(id, name, importance)
        if (sound == null) {
            channel.setSound(null, null)
            channel.enableVibration(false)
        } else {
            channel.setSound(sound, soundAttributes())
            channel.enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }
}

/**
 * The single native surface of the app: one [MethodChannel] answering every
 * question Dart cannot answer on its own — storage paths, due-date alarms,
 * file picking, voice recording, ringtones.
 *
 * Everything here is framework-only on purpose: plugins would create symlinks
 * under `windows/flutter/ephemeral/.plugin_symlinks`, which requires Windows
 * Developer Mode. Keeping the surface in the app's own shell costs a few
 * hundred lines and zero plugin dependencies (the lone Gradle dependency is
 * `androidx.core`, needed for [FileProvider]).
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "dev.m3e.m3e_todo/platform"
        const val STORAGE_CHANNEL = "dev.m3e.m3e_todo/storage"

        // Request codes for the startActivityForResult round-trips.
        const val REQUEST_ATTACHMENT = 41
        const val REQUEST_RINGTONE = 42
        const val REQUEST_NOTIFICATION_PERMISSION = 43
        const val REQUEST_AUDIO_PERMISSION = 44
    }

    private var pendingAttachmentResult: MethodChannel.Result? = null
    private var pendingRingtoneResult: MethodChannel.Result? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private var pendingAudioPermission: MethodChannel.Result? = null

    private var mediaRecorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var ringtonePlayer: MediaPlayer? = null

    private val attachmentsDir: File
        get() = File(filesDir, "attachments").apply { mkdirs() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Channels are created from whatever ringtone was last chosen; Dart
        // re-asserts the saved value moments later, and an unchanged value is a
        // no-op there too.
        PlatformHost.ensureChannels(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // filesDir is private to the app and removed on uninstall,
                    // the correct home for user data.
                    "getDataDirectory" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                runCatching { handle(call.method, call.arguments, result) }
                    .onFailure { result.error("PLATFORM_ERROR", it.message, null) }
            }
    }

    private fun handle(method: String, arguments: Any?, result: MethodChannel.Result) {
        when (method) {
            "areNotificationsEnabled" -> result.success(notificationsEnabled())
            // Exact alarms are gated separately from the notification
            // permission, and without the grant AlarmManager widens the trigger
            // by an hour. Why that matters is in AlarmStore.schedule.
            "canScheduleExactAlarms" -> result.success(canScheduleExactAlarms())
            "requestExactAlarmPermission" -> {
                if (Build.VERSION.SDK_INT < 31) {
                    result.success(true)
                } else {
                    val intent =
                        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            .setData(Uri.fromParts("package", packageName, null))
                    result.success(
                        runCatching {
                            startActivity(intent)
                            true
                        }.getOrDefault(false),
                    )
                }
            }
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT < 33) {
                    result.success(true)
                } else {
                    pendingNotificationPermission = result
                    @Suppress("DEPRECATION")
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
                }
            }
            "requestAudioPermission" -> {
                if (Build.VERSION.SDK_INT < 23) {
                    result.success(true)
                } else {
                    pendingAudioPermission = result
                    @Suppress("DEPRECATION")
                    requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_AUDIO_PERMISSION)
                }
            }
            "systemRingtoneUri" -> result.success(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION).toString(),
            )
            "scheduleAlarm" -> {
                val args = arguments as Map<*, *>
                AlarmStore.schedule(
                    this,
                    (args["notificationId"] as Number).toInt(),
                    args["title"] as String,
                    args["body"] as? String ?: "",
                    (args["triggerAtMillis"] as Number).toLong(),
                    args["ring"] as Boolean,
                    args["ringtoneUri"] as? String,
                )
                result.success(null)
            }
            "cancelAlarm" -> {
                AlarmStore.cancel(this, (arguments as Map<*, *>)["notificationId"] as Int)
                result.success(null)
            }
            // Replaces the whole schedule. Sent once per app run, so the device
            // never keeps counting down to a todo that has since been deleted.
            "syncAlarms" -> {
                AlarmStore.replaceAll(this, arguments as List<Map<*, *>>)
                result.success(null)
            }
            // Batched forms of the two above. Scheduling used to cost one channel
            // round trip per reminder, so a launch with a few dozen dated todos
            // woke the platform thread that many times during startup; the same
            // work now happens in a single hop.
            "scheduleAlarms" -> {
                for (entry in arguments as List<*>) {
                    val args = entry as Map<*, *>
                    AlarmStore.schedule(
                        this,
                        (args["notificationId"] as Number).toInt(),
                        args["title"] as String,
                        args["body"] as? String ?: "",
                        (args["triggerAtMillis"] as Number).toLong(),
                        args["ring"] as Boolean,
                        args["ringtoneUri"] as? String,
                    )
                }
                result.success(null)
            }
            "cancelAlarms" -> {
                for (entry in arguments as List<*>) {
                    AlarmStore.cancel(this, (entry as Map<*, *>)["notificationId"] as Int)
                }
                result.success(null)
            }
            "pickAttachment" -> {
                pendingAttachmentResult = result
                @Suppress("DEPRECATION")
                startActivityForResult(attachmentIntent(arguments as? String ?: "document"), REQUEST_ATTACHMENT)
            }
            "pickRingtone" -> {
                pendingRingtoneResult = result
                val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                    putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_NOTIFICATION)
                    putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "选择提醒铃声")
                    putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                }
                @Suppress("DEPRECATION")
                startActivityForResult(intent, REQUEST_RINGTONE)
            }
            // Writes a cropped image produced in Dart into the app's own
            // attachments directory and answers with its path. Dart can encode
            // the pixels but does not know where that directory lives — the
            // location is this file's concern (see attachmentsDir), and keeping
            // the two in one place is what stops them from drifting apart.
            "saveImage" -> {
                val args = arguments as Map<*, *>
                val bytes = args["bytes"] as ByteArray
                val extension = (args["extension"] as? String)
                    ?.takeIf { it.isNotBlank() }
                    ?.trimStart('.')
                    ?: "png"
                val file = File(attachmentsDir, "image-${UUID.randomUUID()}.$extension")
                file.writeBytes(bytes)
                result.success(file.absolutePath)
            }
            "startVoiceRecording" -> result.success(startRecording())
            "stopVoiceRecording" -> result.success(stopRecording())
            "openAttachment" -> {
                val args = arguments as Map<*, *>
                result.success(openFile(args["path"] as String, args["mime"] as? String))
            }
            "playRingtone" -> playSound(arguments as? String)
            "stopRingtone" -> {
                stopSound()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun notificationsEnabled(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PERMISSION_GRANTED

    /**
     * Whether `setExactAndAllowWhileIdle` is permitted.
     *
     * Before Android 12 there is no such restriction; from 12 on, an app that
     * targets 12+ must be granted "Alarms & reminders" by the user, and the
     * default is to withhold it.
     */
    private fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < 31 ||
            (getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()

    // --- Attachment picking -----------------------------------------------------

    /**
     * The intent that asks the user for one file of [kind].
     *
     * Pictures go through the device's own gallery first: asking for a picture
     * means the photos already on the phone, and the system document picker
     * opens on a file tree — folders, "Recent", cloud providers — which is a
     * detour for anyone who just wants their camera roll. Everything else (and
     * any device with no gallery app at all) still uses the document picker,
     * which is the only thing guaranteed to be there.
     */
    private fun attachmentIntent(kind: String): Intent =
        when (kind) {
            "image" -> galleryIntent() ?: documentIntent("image/*")
            "video" -> documentIntent("video/*")
            "audio" -> documentIntent("audio/*")
            else -> documentIntent("*/*")
        }

    /**
     * The best picture browser this device has, or `null` if it has none.
     *
     * Ordered by how little the user has to think about it:
     *
     *  1. Android 13's photo picker — one screen of thumbnails, and it grants
     *     read access to the single picture chosen, so no storage permission is
     *     ever requested;
     *  2. the same picker backported through Play services, which covers Android
     *     11 and 12 on devices that have it;
     *  3. the gallery app itself, through the old `ACTION_PICK`.
     */
    private fun galleryIntent(): Intent? {
        val candidates = listOf(
            Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*"),
            Intent("com.google.android.gms.provider.action.PICK_IMAGES").setType("image/*"),
            Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                .setType("image/*"),
        )
        return candidates.firstOrNull { candidate ->
            runCatching { candidate.resolveActivity(packageManager) != null }.getOrDefault(false)
        }
    }

    private fun documentIntent(mime: String): Intent =
        Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // Document-style pickers copy the file through us, so no storage
            // permission is ever needed.
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(mime))
        }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_ATTACHMENT -> {
                val result = pendingAttachmentResult
                pendingAttachmentResult = null
                val uri = data?.data
                if (resultCode != RESULT_OK || uri == null || result == null) {
                    result?.success(null)
                    return
                }
                val copied = copyToAttachments(uri)
                result.success(
                    if (copied == null) {
                        null
                    } else {
                        mapOf(
                            "path" to copied.absolutePath,
                            "name" to (queryDisplayName(uri) ?: copied.name),
                            "mime" to contentResolver.getType(uri),
                        )
                    },
                )
            }
            REQUEST_RINGTONE -> {
                val result = pendingRingtoneResult
                pendingRingtoneResult = null
                @Suppress("DEPRECATION")
                val uri = data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                result?.success(uri?.toString())
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_NOTIFICATION_PERMISSION -> {
                pendingNotificationPermission?.success(
                    grantResults.isNotEmpty() && grantResults[0] == PERMISSION_GRANTED,
                )
                pendingNotificationPermission = null
            }
            REQUEST_AUDIO_PERMISSION -> {
                pendingAudioPermission?.success(
                    grantResults.isNotEmpty() && grantResults[0] == PERMISSION_GRANTED,
                )
                pendingAudioPermission = null
            }
        }
    }

    /** Streams the picked content into the app's private attachments folder. */
    private fun copyToAttachments(uri: Uri): File? = runCatching {
        val name = queryDisplayName(uri)
        val extension = name?.substringAfterLast('.', "")?.take(8).orEmpty()
        val file = File(attachmentsDir, "${UUID.randomUUID()}${if (extension.isBlank()) "" else ".$extension"}")
        contentResolver.openInputStream(uri)?.use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        file
    }.getOrNull()

    private fun queryDisplayName(uri: Uri): String? = runCatching {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
        }
    }.getOrNull()

    // --- Voice recording ----------------------------------------------------------

    private fun startRecording(): Boolean {
        if (Build.VERSION.SDK_INT >= 23 &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PERMISSION_GRANTED
        ) {
            return false
        }
        stopRecording()
        val file = File(attachmentsDir, "voice-${UUID.randomUUID()}.m4a")
        val recorder =
            if (Build.VERSION.SDK_INT >= 31) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION") MediaRecorder()
            }
        return runCatching {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            // Low bitrate mono: reminders need intelligible speech, not fidelity,
            // and small files keep the app data footprint modest.
            recorder.setAudioEncodingBitRate(64000)
            recorder.setAudioSamplingRate(22050)
            recorder.setAudioChannels(1)
            recorder.setOutputFile(file.absolutePath)
            recorder.prepare()
            recorder.start()
            mediaRecorder = recorder
            recordingFile = file
            true
        }.getOrElse {
            recorder.release()
            file.delete()
            false
        }
    }

    private fun stopRecording(): String? {
        val recorder = mediaRecorder ?: return null
        mediaRecorder = null
        val file = recordingFile
        recordingFile = null
        val path = runCatching {
            recorder.stop()
            file?.absolutePath
        }.getOrElse {
            // A recording shorter than the encoder's first frame cannot be
            // stopped cleanly; treat it as "nothing recorded".
            file?.delete()
            null
        }
        recorder.release()
        return path
    }

    // --- Opening attachments / previewing ringtones ---------------------------------

    private fun openFile(path: String, mime: String?): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        val uri: Uri = if (Build.VERSION.SDK_INT >= 24) {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } else {
            @Suppress("DEPRECATION") Uri.fromFile(file)
        }
        return runCatching {
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mime ?: "application/octet-stream")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        }.getOrElse {
            Log.w(TAG, "No app can open $path: ${it.message}")
            false
        }
    }

    private fun playSound(uriString: String?) {
        stopSound()
        val uri = uriString?.let(Uri::parse)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val player = MediaPlayer()
        ringtonePlayer = player
        player.setOnCompletionListener { it.release() }
        runCatching {
            player.setDataSource(applicationContext, uri)
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.prepare()
            player.start()
        }.onFailure {
            Log.w(TAG, "Could not play ringtone $uri: ${it.message}")
        }
    }

    private fun stopSound() {
        ringtonePlayer?.let { player ->
            runCatching {
                if (player.isPlaying) player.stop()
                player.release()
            }
        }
        ringtonePlayer = null
    }

    override fun onDestroy() {
        stopRecording()
        stopSound()
        super.onDestroy()
    }
}
