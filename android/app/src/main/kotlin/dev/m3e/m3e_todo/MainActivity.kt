package dev.m3e.m3e_todo

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
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
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.widget.RemoteViews
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar
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
            // Habit reminders repeat, so they are not "pending alarms" in the
            // store above: their rule survives and the next occurrence is
            // derived from it again here.
            HabitAlarmStore.rescheduleAll(context)
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

    /**
     * Kept so the activity can talk *to* Dart, which only two things need: the
     * home-screen widget telling a running app that it was tapped. Without it,
     * a check-in made on the widget while the app was open would sit in the
     * queue until the next resume — and a resume only happens when the app is
     * not already in front of the user.
     */
    private var platformChannel: MethodChannel? = null

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

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        platformChannel = channel
        channel.setMethodCallHandler { call, result ->
            runCatching { handle(call.method, call.arguments, result) }
                .onFailure { result.error("PLATFORM_ERROR", it.message, null) }
        }
    }

    /** Tells Dart that the widget was used, so a running app picks it up at once. */
    private fun notifyWidgetTapped() {
        runCatching { platformChannel?.invokeMethod("habitWidgetChanged", null) }
            .onFailure { Log.w(TAG, "Could not notify Dart of a widget tap: ${it.message}") }
    }

    /**
     * The widget's ＋ button brings the app forward through `singleTop`, so this
     * — not a resume — is what fires when the app was already open.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        rememberOpenRequest(intent)
        notifyWidgetTapped()
    }

    override fun onResume() {
        super.onResume()
        // A cold start from the widget's ＋ carries its habit in the launch
        // intent, and Dart asks for it right after the first frame — so it has
        // to be stored before that, not when the activity resumes.
        rememberOpenRequest(intent)
        notifyWidgetTapped()
    }

    /** Stores the habit a widget launch asked for, for Dart to pick up. */
    private fun rememberOpenRequest(intent: Intent?) {
        val habitId = intent?.getStringExtra(HabitWidgetProvider.EXTRA_OPEN_HABIT) ?: return
        HabitWidgetStore.requestOpen(this, habitId)
        // Consumed: leaving it on the intent would re-open the same editor every
        // time the activity is resumed, including after the user closed it.
        intent.removeExtra(HabitWidgetProvider.EXTRA_OPEN_HABIT)
    }

    /** Asks the launcher to place the habit widget; Android shows its own sheet. */
    private fun requestHabitWidgetPin(): Boolean {
        if (Build.VERSION.SDK_INT < 26) {
            return false
        }
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) {
            return false
        }
        val provider = ComponentName(this, HabitWidgetProvider::class.java)
        return runCatching { manager.requestPinAppWidget(provider, null, null) }
            .getOrDefault(false)
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
            // --- Habit widget and habit reminders ---------------------------
            // Whole-schedule, like the todo alarms: a habit's next occurrence
            // comes from a time of day and a weekday mask, so the native side
            // re-derives it rather than being handed a moment in time.
            "syncHabitAlarms" -> {
                HabitAlarmStore.replaceAll(this, arguments as List<Map<*, *>>)
                result.success(null)
            }
            // The widget draws from what it is given here, and answers whether
            // it is on a home screen at all, so the app can stop offering to add
            // one that is already there.
            "updateHabitWidget" -> {
                HabitWidgetStore.writeSnapshot(this, JSONObject(arguments as Map<*, *>))
                HabitWidgetProvider.refresh(this)
                result.success(HabitWidgetProvider.placed(this))
            }
            "requestHabitWidgetPin" -> result.success(requestHabitWidgetPin())
            // What the widget did while this process was dead. Draining clears
            // the queue, so the Dart side owns turning these into check-ins.
            "drainHabitCheckIns" -> {
                val pending = HabitWidgetStore.drainActions(this)
                val actions = ArrayList<Map<String, Any?>>()
                for (index in 0 until pending.length()) {
                    val entry = pending.optJSONObject(index) ?: continue
                    actions.add(
                        mapOf(
                            "habitId" to entry.optString("habitId"),
                            "dayKey" to entry.optInt("dayKey"),
                            "done" to entry.optBoolean("done"),
                            "atMillis" to entry.optLong("atMillis"),
                        ),
                    )
                }
                result.success(actions)
            }
            "takeHabitOpenRequest" -> result.success(HabitWidgetStore.takeOpen(this))
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

/**
 * What the home-screen widget draws itself from, plus everything it does while
 * the app's process is dead.
 *
 * The widget runs in the launcher's process. It cannot read the app's JSON
 * documents (they are parsed by Dart) and cannot write them either, so it keeps
 * two things of its own in `SharedPreferences`:
 *
 *  * the *snapshot* — today's habits as the app last described them, which is
 *    all the widget needs to draw;
 *  * the *queue* — what the user tapped, waiting for the app to turn it into
 *    real check-ins the next time it runs.
 *
 * The snapshot is also updated locally on a tap, so the tick appears instantly
 * instead of waiting for the app to be opened. That optimistic tick is a
 * convenience, not the truth: the queue is the truth, and the app republishes
 * the snapshot from its own records as soon as it drains it.
 */
internal object HabitWidgetStore {
    private const val PREFS = "habit_widget"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_PENDING = "pending"
    private const val KEY_OPEN = "openHabit"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun snapshot(context: Context): JSONObject? {
        val raw = prefs(context).getString(KEY_SNAPSHOT, null) ?: return null
        return runCatching { JSONObject(raw) }.getOrNull()
    }

    fun writeSnapshot(context: Context, snapshot: JSONObject) {
        prefs(context).edit().putString(KEY_SNAPSHOT, snapshot.toString()).apply()
    }

    /**
     * Flips one row in the stored snapshot and recounts the header.
     *
     * Only the row that was tapped is touched: rebuilding the snapshot here
     * would mean re-implementing the Dart side's idea of which habits are due,
     * and two implementations of that would eventually disagree.
     */
    fun markLocally(context: Context, habitId: String, done: Boolean) {
        val snapshot = snapshot(context) ?: return
        val rows = snapshot.optJSONArray("rows") ?: return
        var doneCount = 0
        for (index in 0 until rows.length()) {
            val row = rows.optJSONObject(index) ?: continue
            if (row.optString("id") == habitId) {
                row.put("done", done)
            }
            if (row.optBoolean("done")) {
                doneCount++
            }
        }
        snapshot.put("done", doneCount)
        // The header is rebuilt from its parts for the same reason: leaving it
        // reading "0/3" above a row that now shows a tick would be a summary
        // that contradicts itself. The words come from Dart (`countSuffix`);
        // only the numbers are counted here.
        val total = snapshot.optInt("total", rows.length())
        val suffix = snapshot.optString("countSuffix")
        snapshot.put("countLabel", "$doneCount/$total $suffix".trim())
        writeSnapshot(context, snapshot)
    }

    /** Queues a tap for the app to pick up. */
    fun appendAction(context: Context, habitId: String, dayKey: Int, done: Boolean) {
        val pending = pendingArray(context)
        pending.put(
            JSONObject()
                .put("habitId", habitId)
                .put("dayKey", dayKey)
                .put("done", done)
                .put("atMillis", System.currentTimeMillis()),
        )
        prefs(context).edit().putString(KEY_PENDING, pending.toString()).apply()
    }

    /** Takes the queue and clears it: the caller owns what it just took. */
    fun drainActions(context: Context): JSONArray {
        val pending = pendingArray(context)
        prefs(context).edit().remove(KEY_PENDING).apply()
        return pending
    }

    private fun pendingArray(context: Context): JSONArray {
        val raw = prefs(context).getString(KEY_PENDING, null) ?: return JSONArray()
        return runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
    }

    /** Remembers that one habit's editor should open when the app comes up. */
    fun requestOpen(context: Context, habitId: String) {
        prefs(context).edit().putString(KEY_OPEN, habitId).apply()
    }

    fun takeOpen(context: Context): String? {
        val habitId = prefs(context).getString(KEY_OPEN, null) ?: return null
        prefs(context).edit().remove(KEY_OPEN).apply()
        return habitId
    }
}

/**
 * The home-screen widget itself.
 *
 * `RemoteViews` cannot build a variable-length list without a collection
 * service, so the layout carries four fixed rows and this class hides the ones
 * that do not fit the space the launcher gave it — which is what makes the
 * widget behave when it is resized rather than clipping whatever does not fit.
 */
class HabitWidgetProvider : AppWidgetProvider() {
    companion object {
        const val ACTION_TOGGLE = "dev.m3e.m3e_todo.HABIT_TOGGLE"
        const val ACTION_NOTE = "dev.m3e.m3e_todo.HABIT_NOTE"

        const val EXTRA_HABIT_ID = "habitId"
        const val EXTRA_DAY_KEY = "dayKey"

        /** The habit the widget's ＋ button asked the app to open. */
        const val EXTRA_OPEN_HABIT = "openHabitId"

        /** Maximum rows in `habit_widget.xml`. */
        private const val MAX_ROWS = 4

        /** Row height and header height in dp; kept in step with the styles. */
        private const val ROW_HEIGHT_DP = 38
        private const val HEADER_DP = 34

        private const val REQUEST_OPEN = 5000
        private const val REQUEST_TOGGLE_BASE = 5100
        private const val REQUEST_NOTE_BASE = 5200

        /** Redraws every placed instance. Called after any change. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(component(context))
            for (id in ids) {
                // A launcher that has just removed a widget can leave an id that
                // no longer resolves; drawing it would throw inside a broadcast
                // receiver, where an exception is a crash rather than a message.
                runCatching { render(context, manager, id) }
                    .onFailure { Log.w(TAG, "Could not draw the habit widget: ${it.message}") }
            }
        }

        /** Whether the widget is on a home screen at all. */
        fun placed(context: Context): Boolean =
            AppWidgetManager.getInstance(context).getAppWidgetIds(component(context)).isNotEmpty()

        private fun component(context: Context) =
            ComponentName(context, HabitWidgetProvider::class.java)

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.habit_widget)
            val snapshot = HabitWidgetStore.snapshot(context)

            // Tapping anywhere the buttons are not brings the app forward: the
            // widget is a summary, and the way to change what it summarises is
            // the app.
            views.setOnClickPendingIntent(R.id.habit_widget_root, openApp(context))

            if (snapshot == null) {
                views.setViewVisibility(R.id.habit_widget_title, android.view.View.GONE)
                views.setViewVisibility(R.id.habit_widget_count, android.view.View.GONE)
                for (index in 0 until MAX_ROWS) {
                    views.setViewVisibility(rowId(index), android.view.View.GONE)
                }
                views.setTextViewText(
                    R.id.habit_widget_empty_title,
                    context.getString(R.string.habit_widget_no_data),
                )
                views.setTextViewText(R.id.habit_widget_empty_body, "")
                manager.updateAppWidget(id, views)
                return
            }

            val rows = snapshot.optJSONArray("rows") ?: JSONArray()
            val available = rowsThatFit(manager, id)
            val shown = minOf(available, rows.length())
            val hidden = rows.length() - shown
            val overflow = hidden + snapshot.optInt("overflow", 0)
            val empty = snapshot.optBoolean("empty", false) || rows.length() == 0

            views.setViewVisibility(
                R.id.habit_widget_title,
                if (empty) android.view.View.GONE else android.view.View.VISIBLE,
            )
            views.setViewVisibility(
                R.id.habit_widget_count,
                if (empty) android.view.View.GONE else android.view.View.VISIBLE,
            )
            views.setTextViewText(R.id.habit_widget_title, snapshot.optString("dateLabel"))
            views.setTextViewText(R.id.habit_widget_count, snapshot.optString("countLabel"))
            views.setViewVisibility(
                R.id.habit_widget_empty_title,
                if (empty) android.view.View.VISIBLE else android.view.View.GONE,
            )
            views.setViewVisibility(
                R.id.habit_widget_empty_body,
                if (empty) android.view.View.VISIBLE else android.view.View.GONE,
            )
            views.setTextViewText(
                R.id.habit_widget_empty_title,
                snapshot.optString("emptyTitle"),
            )
            views.setTextViewText(
                R.id.habit_widget_empty_body,
                snapshot.optString("emptyBody"),
            )

            val dayKey = snapshot.optInt("dayKey", 0)
            for (index in 0 until MAX_ROWS) {
                val row = if (index < shown) rows.optJSONObject(index) else null
                if (row == null) {
                    views.setViewVisibility(rowId(index), android.view.View.GONE)
                    continue
                }
                val habitId = row.optString("id")
                val done = row.optBoolean("done")
                views.setViewVisibility(rowId(index), android.view.View.VISIBLE)
                views.setTextViewText(emojiId(index), row.optString("emoji"))
                views.setTextViewText(nameId(index), row.optString("name"))
                views.setTextColor(
                    nameId(index),
                    context.getColor(
                        if (done) R.color.habit_widget_done else R.color.habit_widget_text,
                    ),
                )
                val time = row.optString("time")
                views.setTextViewText(timeId(index), time)
                views.setViewVisibility(
                    timeId(index),
                    if (time.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE,
                )
                views.setImageViewResource(
                    checkId(index),
                    if (done) R.drawable.habit_check_done else R.drawable.habit_check_todo,
                )
                views.setOnClickPendingIntent(
                    checkId(index),
                    toggleIntent(context, index, habitId, dayKey, !done),
                )
                // Only habits that accept a note get the ＋: offering to write
                // something the habit does not keep would be a lie.
                val allowsNote = row.optBoolean("note")
                views.setViewVisibility(
                    noteId(index),
                    if (allowsNote) android.view.View.VISIBLE else android.view.View.GONE,
                )
                if (allowsNote) {
                    views.setOnClickPendingIntent(
                        noteId(index),
                        noteIntent(context, index, habitId, dayKey),
                    )
                }
            }

            views.setViewVisibility(
                R.id.habit_widget_more,
                if (overflow > 0) android.view.View.VISIBLE else android.view.View.GONE,
            )
            if (overflow > 0) {
                views.setTextViewText(
                    R.id.habit_widget_more,
                    context.getString(R.string.habit_widget_more, overflow),
                )
            }
            manager.updateAppWidget(id, views)
        }

        /**
         * How many rows the widget has room for.
         *
         * `OPTION_APPWIDGET_MIN_HEIGHT` is what the launcher reports for the
         * space it has given this instance, in dp, and it changes as the user
         * resizes — which is the whole point of reading it on every render.
         */
        private fun rowsThatFit(manager: AppWidgetManager, id: Int): Int {
            val options = manager.getAppWidgetOptions(id)
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
            val available = heightDp - HEADER_DP - 12
            return (available / ROW_HEIGHT_DP).coerceIn(1, MAX_ROWS)
        }

        private fun openApp(context: Context): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent()
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context,
                REQUEST_OPEN,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun toggleIntent(
            context: Context,
            index: Int,
            habitId: String,
            dayKey: Int,
            done: Boolean,
        ): PendingIntent {
            val intent = Intent(context, HabitWidgetProvider::class.java)
                .setAction(ACTION_TOGGLE)
                .putExtra(EXTRA_HABIT_ID, habitId)
                .putExtra(EXTRA_DAY_KEY, dayKey)
                .putExtra("done", done)
            return PendingIntent.getBroadcast(
                context,
                REQUEST_TOGGLE_BASE + index,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun noteIntent(
            context: Context,
            index: Int,
            habitId: String,
            dayKey: Int,
        ): PendingIntent {
            // An *activity* intent, not a broadcast, and deliberately so: from
            // Android 10 a receiver cannot start an activity from the
            // background, so the ＋ button's tap is handed to the launcher as a
            // ready-made launch. The user's own tap is what makes it allowed.
            val intent = Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_OPEN_HABIT, habitId)
                .putExtra(EXTRA_DAY_KEY, dayKey)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context,
                REQUEST_NOTE_BASE + index,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun rowId(index: Int) = when (index) {
            0 -> R.id.habit_row_0
            1 -> R.id.habit_row_1
            2 -> R.id.habit_row_2
            else -> R.id.habit_row_3
        }

        private fun emojiId(index: Int) = when (index) {
            0 -> R.id.habit_row_0_emoji
            1 -> R.id.habit_row_1_emoji
            2 -> R.id.habit_row_2_emoji
            else -> R.id.habit_row_3_emoji
        }

        private fun nameId(index: Int) = when (index) {
            0 -> R.id.habit_row_0_name
            1 -> R.id.habit_row_1_name
            2 -> R.id.habit_row_2_name
            else -> R.id.habit_row_3_name
        }

        private fun timeId(index: Int) = when (index) {
            0 -> R.id.habit_row_0_time
            1 -> R.id.habit_row_1_time
            2 -> R.id.habit_row_2_time
            else -> R.id.habit_row_3_time
        }

        private fun noteId(index: Int) = when (index) {
            0 -> R.id.habit_row_0_note
            1 -> R.id.habit_row_1_note
            2 -> R.id.habit_row_2_note
            else -> R.id.habit_row_3_note
        }

        private fun checkId(index: Int) = when (index) {
            0 -> R.id.habit_row_0_check
            1 -> R.id.habit_row_1_check
            2 -> R.id.habit_row_2_check
            else -> R.id.habit_row_3_check
        }
    }

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        for (id in ids) {
            runCatching { render(context, manager, id) }
                .onFailure { Log.w(TAG, "Could not draw the habit widget: ${it.message}") }
        }
    }

    /** A resize is a different number of rows, so the widget is redrawn. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle,
    ) {
        render(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TOGGLE -> {
                val habitId = intent.getStringExtra(EXTRA_HABIT_ID)
                if (habitId != null) {
                    val done = intent.getBooleanExtra("done", true)
                    // Both halves matter: the queue is what the app will store,
                    // the local flip is what makes the tick appear now.
                    HabitWidgetStore.appendAction(
                        context,
                        habitId,
                        intent.getIntExtra(EXTRA_DAY_KEY, 0),
                        done,
                    )
                    HabitWidgetStore.markLocally(context, habitId, done)
                    refresh(context)
                    notifyRunningApp(context)
                }
            }
            ACTION_NOTE -> {
                // Only reachable from an older widget build; the ＋ button now
                // launches the activity directly.
                val habitId = intent.getStringExtra(EXTRA_HABIT_ID)
                if (habitId != null) {
                    HabitWidgetStore.requestOpen(context, habitId)
                }
            }
        }
        super.onReceive(context, intent)
    }

    /**
     * Tells a *running* app that the widget was used.
     *
     * A tap with the app in the background is picked up by its resume; a tap
     * while the app is on screen produces no resume at all, so the running
     * activity has to be told. Doing nothing here would leave the check-in
     * invisible until the user happened to leave and come back.
     */
    private fun notifyRunningApp(context: Context) {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        // Delivered through the activity's own `onNewIntent`, which forwards it
        // to Dart; starting an activity that is already on screen is a no-op
        // otherwise, which is exactly what is wanted.
        runCatching { context.startActivity(intent) }
    }
}

/**
 * The habit reminders, which repeat.
 *
 * A todo's reminder is one moment and the Dart side computes it; a habit's
 * repeats every week on its own days, so what is stored here is the *rule*
 * (minutes past midnight, weekday mask) and the next occurrence is derived from
 * it — after each firing, and again after a reboot.
 */
internal object HabitAlarmStore {
    private const val PREFS = "habit_alarms"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Base for habit notification ids, to keep them clear of the todos'. */
    private const val NOTIFICATION_BASE = 0x40000000

    fun notificationId(habitId: String): Int = NOTIFICATION_BASE or (habitId.hashCode() and 0x3fffffff)

    /**
     * Makes the stored rule set exactly [alarms].
     *
     * Whole-set rather than a diff because the Dart side sends the complete list
     * on every change: it is the one side that knows which habits exist, which
     * are checked off today, and what the app-wide sound setting is.
     */
    fun replaceAll(context: Context, alarms: List<Map<*, *>>) {
        val wanted = alarms.mapNotNull { it["habitId"] as? String }.toSet()
        for (key in prefs(context).all.keys.toList()) {
            if (key !in wanted) {
                cancel(context, key)
            }
        }
        for (args in alarms) {
            val habitId = args["habitId"] as? String ?: continue
            val minutes = (args["minutes"] as? Number)?.toInt() ?: continue
            val entry = JSONObject()
                .put("title", args["title"] as? String ?: "")
                .put("body", args["body"] as? String ?: "")
                .put("minutes", minutes)
                .put("daysMask", (args["daysMask"] as? Number)?.toInt() ?: 0)
                .put("ring", args["ring"] as? Boolean ?: false)
                .put("ringtoneUri", args["ringtoneUri"] as? String)
            prefs(context).edit().putString(habitId, entry.toString()).apply()
            scheduleNext(context, habitId, entry, args["skipToday"] as? Boolean ?: false)
        }
    }

    /** Re-arms one habit for its next occurrence. */
    fun scheduleNext(
        context: Context,
        habitId: String,
        entry: JSONObject,
        skipToday: Boolean,
    ) {
        val triggerAt = nextTrigger(
            entry.optInt("minutes", 0),
            entry.optInt("daysMask", 0),
            skipToday,
        )
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val id = notificationId(habitId)
        if (triggerAt == null) {
            // No day ahead matches this habit: nothing to schedule, and an old
            // alarm for it must not be left running.
            alarm.cancel(pending(context, id, habitId, entry))
            return
        }
        val pending = pending(context, id, habitId, entry)
        val exactAllowed = Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()
        if (exactAllowed) {
            alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        } else {
            alarm.setWindow(AlarmManager.RTC_WAKEUP, triggerAt, 10 * 60 * 1000L, pending)
        }
    }

    fun rescheduleAll(context: Context) {
        for ((habitId, value) in prefs(context).all) {
            if (value !is String) continue
            val entry = runCatching { JSONObject(value) }.getOrNull() ?: continue
            scheduleNext(context, habitId, entry, skipToday = false)
        }
    }

    /**
     * The stored rule for one habit, or an empty one.
     *
     * The receiver needs this after firing: the alarm's own intent carries only
     * what the notification needs, and re-arming needs the whole rule. An empty
     * object for a habit that has since been deleted is deliberate — it
     * schedules nothing, which is the right outcome for a habit that is gone.
     */
    fun storedEntry(context: Context, habitId: String): JSONObject {
        val raw = prefs(context).getString(habitId, null) ?: return JSONObject()
        return runCatching { JSONObject(raw) }.getOrDefault(JSONObject())
    }

    fun cancel(context: Context, habitId: String) {
        val entry = prefs(context).getString(habitId, null)
            ?.let { runCatching { JSONObject(it) }.getOrNull() }
            ?: JSONObject()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.cancel(pending(context, notificationId(habitId), habitId, entry))
        prefs(context).edit().remove(habitId).apply()
    }

    private fun pending(
        context: Context,
        id: Int,
        habitId: String,
        entry: JSONObject,
    ): PendingIntent {
        val intent = Intent(context, HabitAlarmReceiver::class.java)
            .putExtra(HabitAlarmReceiver.EXTRA_HABIT_ID, habitId)
            .putExtra(HabitAlarmReceiver.EXTRA_NOTIFICATION_ID, id)
            .putExtra(HabitAlarmReceiver.EXTRA_TITLE, entry.optString("title"))
            .putExtra(HabitAlarmReceiver.EXTRA_BODY, entry.optString("body"))
            .putExtra(HabitAlarmReceiver.EXTRA_RING, entry.optBoolean("ring", false))
            .putExtra(
                HabitAlarmReceiver.EXTRA_RINGTONE,
                if (entry.isNull("ringtoneUri")) null else entry.optString("ringtoneUri"),
            )
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * The next moment this habit should be announced, or `null` if none is
     * ahead within a week.
     *
     * The mask is the Dart side's: bit 0 is Monday through bit 6 Sunday, while
     * `Calendar` calls Sunday 1 — hence the shift rather than a lookup table.
     */
    private fun nextTrigger(minutes: Int, daysMask: Int, skipToday: Boolean): Long? {
        val now = Calendar.getInstance()
        for (offset in 0..7) {
            val candidate = (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, minutes / 60)
                set(Calendar.MINUTE, minutes % 60)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                add(Calendar.DAY_OF_YEAR, offset)
            }
            if (offset == 0 && skipToday) continue
            val bit = (candidate.get(Calendar.DAY_OF_WEEK) + 5) % 7
            if (daysMask and (1 shl bit) == 0) continue
            if (candidate.timeInMillis > now.timeInMillis) return candidate.timeInMillis
        }
        return null
    }
}

/**
 * Fires a habit reminder, and re-arms the next one.
 *
 * The re-arming is why habits cannot use the todo path: a todo's alarm is
 * consumed when it fires, but a habit's has to come back tomorrow (or next
 * Monday), and doing that here means it keeps working even if the app is never
 * opened again.
 */
class HabitAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_HABIT_ID = "habitId"
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_RING = "ring"
        const val EXTRA_RINGTONE = "ringtoneUri"

        /** The notification's own 打卡 button. */
        const val ACTION_CHECK_IN = "dev.m3e.m3e_todo.HABIT_CHECK_IN"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_CHECK_IN) {
            checkInFromNotification(context, intent)
            return
        }

        val habitId = intent.getStringExtra(EXTRA_HABIT_ID) ?: return
        val id = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""
        val ring = intent.getBooleanExtra(EXTRA_RING, false)
        val ringtone = intent.getStringExtra(EXTRA_RINGTONE)

        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PERMISSION_GRANTED
        ) {
            // No permission: nothing to post, but tomorrow's reminder still has
            // to be armed, or the habit would go quiet for good.
            HabitAlarmStore.scheduleNext(
                context,
                habitId,
                HabitAlarmStore.storedEntry(context, habitId),
                skipToday = false,
            )
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        @Suppress("DEPRECATION")
        val builder =
            if (PlatformHost.channelsSupported()) {
                Notification.Builder(context, PlatformHost.channelForReminder(context, ring, ringtone))
            } else {
                Notification.Builder(context)
                    .setPriority(
                        if (ring) Notification.PRIORITY_HIGH else Notification.PRIORITY_DEFAULT,
                    )
                    .setSound(if (ring) PlatformHost.soundUri(ringtone) else null)
            }
        builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            // The action is the point of a reminder that repeats: "打卡" from the
            // notification means the check-in never needs the app at all.
            .addAction(
                0,
                context.getString(R.string.habit_notification_action),
                checkInPending(context, habitId),
            )

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

        HabitAlarmStore.scheduleNext(
            context,
            habitId,
            HabitAlarmStore.storedEntry(context, habitId),
            skipToday = false,
        )
    }

    private fun checkInFromNotification(context: Context, intent: Intent) {
        val habitId = intent.getStringExtra(EXTRA_HABIT_ID) ?: return
        val dayKey = intent.getIntExtra(HabitWidgetProvider.EXTRA_DAY_KEY, 0)
        HabitWidgetStore.appendAction(
            context,
            habitId,
            if (dayKey == 0) todayKey() else dayKey,
            true,
        )
        HabitWidgetStore.markLocally(context, habitId, true)
        HabitWidgetProvider.refresh(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(intent.getIntExtra(EXTRA_NOTIFICATION_ID, HabitAlarmStore.notificationId(habitId)))
        // Arms tomorrow's reminder as well: the check-in being done does not mean
        // the habit is over.
        HabitAlarmStore.scheduleNext(
            context,
            habitId,
            HabitAlarmStore.storedEntry(context, habitId),
            skipToday = true,
        )
    }

    private fun checkInPending(context: Context, habitId: String): PendingIntent {
        val intent = Intent(context, HabitAlarmReceiver::class.java)
            .setAction(ACTION_CHECK_IN)
            .putExtra(EXTRA_HABIT_ID, habitId)
            .putExtra(EXTRA_NOTIFICATION_ID, HabitAlarmStore.notificationId(habitId))
            .putExtra(HabitWidgetProvider.EXTRA_DAY_KEY, todayKey())
        return PendingIntent.getBroadcast(
            context,
            HabitAlarmStore.notificationId(habitId) + 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** `20260915`, the same packing the app uses for a day. */
    private fun todayKey(): Int {
        val now = Calendar.getInstance()
        return now.get(Calendar.YEAR) * 10000 +
            (now.get(Calendar.MONTH) + 1) * 100 +
            now.get(Calendar.DAY_OF_MONTH)
    }
}
