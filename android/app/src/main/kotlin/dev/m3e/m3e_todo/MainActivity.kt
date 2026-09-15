package dev.m3e.m3e_todo

import android.Manifest
import android.app.Activity
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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import kotlin.math.roundToInt
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RemoteViews
import android.widget.TextView
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
     * The widgets bring the app forward through `singleTop`, so this — not a
     * resume — is what fires when the app was already open.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        rememberOpenRequest(intent)
        rememberTimetableRequest(intent)
        notifyWidgetTapped()
    }

    override fun onResume() {
        super.onResume()
        // A cold start from the widget's ＋ carries its habit in the launch
        // intent, and Dart asks for it right after the first frame — so it has
        // to be stored before that, not when the activity resumes.
        rememberOpenRequest(intent)
        rememberTimetableRequest(intent)
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

    /**
     * Remembers that a course tile asked for the timetable.
     *
     * The course widget opens the app on the timetable rather than on whatever
     * screen it was last left on: a tap on a course row is a question about the
     * timetable, and landing anywhere else answers a different one.
     */
    private fun rememberTimetableRequest(intent: Intent?) {
        if (intent?.getBooleanExtra(CourseWidgetProvider.EXTRA_OPEN_TIMETABLE, false) != true) {
            return
        }
        CourseWidgetStore.requestOpen(this)
        intent.removeExtra(CourseWidgetProvider.EXTRA_OPEN_TIMETABLE)
    }

    /**
     * Asks the launcher to place a habit widget; Android shows its own sheet.
     *
     * [habitIds] travels with the request as an extra, and Android hands that
     * extra to the arrangement screen — so pinning from a habit menu starts that
     * tile with the habit already ticked, while a widget added from the launcher
     * opens with everything ticked.
     */
    private fun requestHabitWidgetPin(habitIds: List<String>): Boolean {
        if (Build.VERSION.SDK_INT < 26) {
            return false
        }
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) {
            return false
        }
        val provider = ComponentName(this, HabitWidgetProvider::class.java)
        val extras = if (habitIds.isEmpty()) {
            null
        } else {
            Bundle().apply {
                putString(HabitWidgetProvider.EXTRA_PIN_HABITS, habitIds.joinToString(","))
            }
        }
        return runCatching { manager.requestPinAppWidget(provider, extras, null) }
            .getOrDefault(false)
    }

    /** Asks the launcher to place a course widget; it needs nothing configured. */
    private fun requestCourseWidgetPin(): Boolean {
        if (Build.VERSION.SDK_INT < 26) {
            return false
        }
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) {
            return false
        }
        val provider = ComponentName(this, CourseWidgetProvider::class.java)
        return runCatching { manager.requestPinAppWidget(provider, null, null) }
            .getOrDefault(false)
    }

    /**
     * Opens this app's notification settings.
     *
     * The screen, not the dialog: once the runtime prompt has been refused, the
     * system will not offer it again, so a reminder that cannot be delivered has
     * to be fixable somewhere — and that somewhere is this screen.
     */
    private fun openNotificationSettings(): Boolean {
        val intent =
            if (Build.VERSION.SDK_INT >= 26) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", packageName, null))
            }
        return runCatching {
            startActivity(intent)
            true
        }.getOrElse {
            Log.w(TAG, "No notification settings screen: ${it.message}")
            false
        }
    }

    /**
     * Opens this app's own page in system settings.
     *
     * The generic destination, used when what is missing is not a runtime
     * permission: several launchers gate placing a widget behind a permission of
     * their own, and the app cannot request that — it can only take the user to
     * the page where it lives.
     */
    private fun openAppSettings(): Boolean {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", packageName, null))
        return runCatching {
            startActivity(intent)
            true
        }.getOrElse {
            Log.w(TAG, "No app settings screen: ${it.message}")
            false
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
            // Where a permission has to be granted by hand rather than by a
            // dialog: Android stops showing the notification prompt after a
            // refusal or two, and the exact-alarm grant has no dialog at all.
            // Sending the user to the screen itself is the only way left to ask.
            "openNotificationSettings" -> result.success(openNotificationSettings())
            "openAppSettings" -> result.success(openAppSettings())
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
            "requestHabitWidgetPin" -> result.success(
                requestHabitWidgetPin(
                    ((arguments as? Map<*, *>)?.get("habitIds") as? List<*>)
                        ?.mapNotNull { it as? String }
                        ?: emptyList(),
                ),
            )
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
            // The arrangement screen's pencil: the app opens that habit's editor
            // rather than its check-in sheet, because what the user asked to do
            // was change the habit, not tick it.
            "takeHabitEditRequest" -> result.success(HabitWidgetStore.takeEdit(this))
            // Debug-only: draws the widget's view tree without a launcher and
            // answers with the text that came out of it. See
            // HabitWidgetProvider.selfCheck for why this exists at all.
            "selfCheckHabitWidget" -> result.success(HabitWidgetProvider.selfCheck(this))
            // --- The course widget ------------------------------------------
            "updateCourseWidget" -> {
                CourseWidgetStore.writeSnapshot(this, JSONObject(arguments as Map<*, *>))
                CourseWidgetProvider.refresh(this)
                result.success(CourseWidgetProvider.placed(this))
            }
            // --- The tiles' background --------------------------------------
            // One picture and one scrim strength for every home-screen tile: the
            // app has a single background setting for its widgets, so both tiles
            // repaint together and neither can be left showing a picture the
            // user has already removed.
            "updateWidgetBackground" -> {
                val args = arguments as? Map<*, *>
                WidgetBackground.store(
                    this,
                    args?.get("path") as? String,
                    (args?.get("dim") as? Number)?.toDouble() ?: 0.35,
                )
                HabitWidgetProvider.refresh(this)
                CourseWidgetProvider.refresh(this)
                result.success(true)
            }
            "requestCourseWidgetPin" -> result.success(requestCourseWidgetPin())
            // A tap on the course tile asks for the timetable, which is a screen
            // rather than a habit: Dart pushes the page when it hears about it.
            "takeCourseOpenRequest" -> result.success(CourseWidgetStore.takeOpen(this))
            // Debug-only: draws the course tile without a launcher. See
            // CourseWidgetProvider.selfCheck.
            "selfCheckCourseWidget" -> result.success(CourseWidgetSelfCheck.selfCheck(this))
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

    // --- 识图导课 ---------------------------------------------------------------

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
/**
 * The picture the home-screen tiles are drawn on, and how strongly the surface
 * covers it.
 *
 * Kept here rather than read from Flutter's settings file because a tile is
 * drawn by the launcher, in the launcher's process, before — and often without
 * — this app ever running: whatever a tile needs has to be somewhere the widget
 * provider can reach on its own. Dart writes it through `updateWidgetBackground`
 * whenever the setting changes, so the two cannot drift apart for long.
 */
internal object WidgetBackground {
    private const val PREFS = "widget_background"
    private const val KEY_PATH = "path"
    private const val KEY_DIM = "dim"

    /** The default when a tile is drawn before the app has ever said. */
    private const val DEFAULT_DIM = 0.35f

    /** Widest the picture is decoded to, in pixels. */
    private const val MAX_WIDTH = 512

    fun store(context: Context, path: String?, dim: Double) {
        prefs(context).edit()
            .putString(KEY_PATH, path)
            .putFloat(KEY_DIM, dim.toFloat().coerceIn(0f, 0.9f))
            .apply()
    }

    fun path(context: Context): String? =
        prefs(context).getString(KEY_PATH, null)?.takeIf { it.isNotBlank() }

    fun dim(context: Context): Float =
        prefs(context).getFloat(KEY_DIM, DEFAULT_DIM).coerceIn(0f, 0.9f)

    /**
     * Binds the picture into a tile's tree, or hides the two views it lives in.
     *
     * Every branch of a tile's `buildViews` has to call this, which is why it is
     * called once at the top of each: a tile saying "no classes today" still has
     * a background, and one that lost its picture by taking a different branch
     * would flicker between the two every time the day changed.
     */
    fun apply(context: Context, views: RemoteViews, backgroundId: Int, scrimId: Int) {
        val bitmap = path(context)?.let { decode(it) }
        if (bitmap == null) {
            // No picture, or one that has been deleted behind the app's back: the
            // tile falls back to its own surface rather than to a blank card.
            views.setViewVisibility(backgroundId, View.GONE)
            views.setViewVisibility(scrimId, View.GONE)
            return
        }
        views.setImageViewBitmap(backgroundId, bitmap)
        views.setViewVisibility(backgroundId, View.VISIBLE)

        // The scrim is the same surface the card is drawn on, at the user's
        // strength rather than at its own: the picture has to be dimmed by the
        // colour the tile's text was chosen against.
        val surface = context.getColor(R.color.widget_background)
        val strength = dim(context)
        views.setInt(
            scrimId,
            "setBackgroundColor",
            Color.argb(
                (strength * 255f).roundToInt().coerceIn(0, 255),
                Color.red(surface),
                Color.green(surface),
                Color.blue(surface),
            ),
        )
        views.setViewVisibility(scrimId, if (strength > 0f) View.VISIBLE else View.GONE)
    }

    /**
     * Decodes the picture at tile size, never as a second copy of the photo.
     *
     * Two limits decide the numbers. A tile's tree travels to the launcher as a
     * bitmap in a binder transaction, and anything approaching a megabyte is
     * over that limit on its own — so RGB_565, and a width a home screen cannot
     * show more of. And the file is the user's own photo, straight out of the
     * camera, so decoding it whole to draw it 400dp wide would spend most of the
     * memory and time on pixels that are then thrown away.
     */
    private fun decode(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return null
        }
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= MAX_WIDTH) {
            sample *= 2
        }
        return runCatching {
            BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply {
                    inSampleSize = sample
                    inPreferredConfig = Bitmap.Config.RGB_565
                    inScaled = false
                },
            )
        }.getOrNull()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

internal object HabitWidgetStore {
    private const val PREFS = "habit_widget"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_PENDING = "pending"
    private const val KEY_OPEN = "openHabit"
    private const val KEY_EDIT = "editHabit"

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
     * Flips one habit's tick in the stored payload.
     *
     * Only that habit's own flag is touched: rebuilding the payload here would
     * mean re-implementing the app's idea of which habits are due, and two
     * implementations of that would eventually disagree. The line under the name
     * is composed from the words the app sent (see `subFor`), so a tick and a
     * sentence can never contradict each other in the seconds before the app
     * runs again.
     */
    fun markLocally(context: Context, habitId: String, done: Boolean) {
        val payload = snapshot(context) ?: return
        val tile = payload.optJSONObject("tiles")?.optJSONObject(habitId) ?: return
        tile.put("done", done)
        writeSnapshot(context, payload)
    }

    /** Every habit the payload knows about, for the configuration dialog. */
    fun configuredHabits(context: Context): List<Pair<String, JSONObject>> {
        val tiles = snapshot(context)?.optJSONObject("tiles") ?: return emptyList()
        return tiles.keys().asSequence().mapNotNull { id ->
            tiles.optJSONObject(id)?.let { id to it }
        }.toList()
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
    /** Remembers that one habit should be edited when the app comes up. */
    fun requestEdit(context: Context, habitId: String) {
        prefs(context).edit().putString(KEY_EDIT, habitId).apply()
    }

    fun takeEdit(context: Context): String? {
        val habitId = prefs(context).getString(KEY_EDIT, null) ?: return null
        prefs(context).edit().remove(KEY_EDIT).apply()
        return habitId
    }

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


        /** Which habits one widget instance shows, comma separated. */
        const val OPTION_HABIT_IDS = "habitIds"

        /** The habits a pinned widget should show, comma separated. */
        const val EXTRA_PIN_HABITS = "habitIds"

        /** The habit the arrangement screen asked the app to edit. */
        const val EXTRA_EDIT_HABIT = "editHabitId"

        /** How many habits the row holds; the layout has this many columns. */
        private const val MAX_ITEMS = 4

        private const val REQUEST_OPEN = 5000
        private const val REQUEST_ARRANGE = 5050
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
            val snapshot = HabitWidgetStore.snapshot(context)
            manager.updateAppWidget(
                id,
                buildViews(context, snapshot, id, habitIdsOf(manager, id)),
            )
        }

        /**
         * Builds the widget's view tree and binds [snapshot] into it.
         *
         * Separate from [render] because a launcher is not always available to
         * draw the result: [selfCheck] applies the same tree to a throwaway
         * parent so the layout, every view id in it, and every value bound to
         * them can be exercised on a device that will not host the widget.
         */
        private fun buildViews(
            context: Context,
            payload: JSONObject?,
            widgetId: Int,
            habitIds: List<String>,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.habit_widget)
            // First, so that every branch below — data, no data, stale — leaves
            // the tile wearing the same background.
            WidgetBackground.apply(
                context,
                views,
                R.id.habit_widget_background,
                R.id.habit_widget_scrim,
            )

            if (payload == null) {
                views.setOnClickPendingIntent(R.id.habit_widget_root, openApp(context))
                return messageTile(context, views, context.getString(R.string.habit_widget_no_data))
            }

            val tiles = payload.optJSONObject("tiles")
            // The habits this tile shows: its own choice when it has one, and
            // everything the app sent when it has not. A tile that shows nothing
            // until it is configured is a tile that does nothing, and several
            // launchers never run the configuration screen at all.
            val chosen = habitIds.filter { tiles?.optJSONObject(it) != null }
            val order = payload.optJSONArray("order")
            val all = ArrayList<String>()
            for (index in 0 until (order?.length() ?: 0)) {
                val id = order?.optString(index) ?: continue
                if (tiles?.optJSONObject(id) != null) all.add(id)
            }
            val shown = (if (chosen.isEmpty()) all else chosen).take(MAX_ITEMS)

            if (shown.isEmpty()) {
                views.setOnClickPendingIntent(R.id.habit_widget_root, openApp(context))
                return messageTile(context, views, payload.optString("emptyTitle"))
            }

            // A payload is a picture of one day, and the day it was taken for is
            // in it. When that day is no longer today the app has not been opened
            // since, so the ticks would be yesterday's: the habits stay visible —
            // a tile that blanks out tells the user nothing — but the circles go,
            // because a tap on one would file a check-in against the wrong day.
            val stale = payload.optInt("dayKey", 0).let { it != 0 && it != todayKey() }
            val dayKey = payload.optInt("dayKey", 0)

            views.setViewVisibility(R.id.habit_widget_message, android.view.View.GONE)
            for (index in 0 until MAX_ITEMS) {
                val habitId = shown.getOrNull(index)
                val tile = habitId?.let { tiles?.optJSONObject(it) }
                if (habitId == null || tile == null) {
                    views.setViewVisibility(itemId(index), android.view.View.GONE)
                    continue
                }
                val done = !stale && tile.optBoolean("done")

                views.setViewVisibility(itemId(index), android.view.View.VISIBLE)
                views.setTextViewText(itemEmojiId(index), tile.optString("emoji"))
                views.setTextViewText(itemNameId(index), tile.optString("name"))
                views.setTextColor(
                    itemNameId(index),
                    context.getColor(
                        if (done) R.color.widget_done else R.color.widget_text,
                    ),
                )
                views.setViewVisibility(
                    itemCheckId(index),
                    if (stale) android.view.View.GONE else android.view.View.VISIBLE,
                )
                // The column is the way into the arrangement screen, and the
                // circle inside it is the only thing that checks anything off: a
                // tap that lands a millimetre off the ring does not change the
                // day's record by accident, it opens the screen that says what
                // this tile is showing.
                views.setOnClickPendingIntent(
                    itemId(index),
                    if (stale) openApp(context) else arrangeIntent(context, widgetId),
                )
                if (!stale) {
                    views.setImageViewResource(
                        itemCheckId(index),
                        if (done) R.drawable.habit_check_done else R.drawable.habit_check_todo,
                    )
                    views.setOnClickPendingIntent(
                        itemCheckId(index),
                        toggleIntent(context, habitId, dayKey, !done),
                    )
                }
            }
            return views
        }

        /**
         * The tile with nothing to draw in it: one line of text and the app
         * behind it.
         */
        private fun messageTile(
            context: Context,
            views: RemoteViews,
            message: String,
        ): RemoteViews {
            views.setViewVisibility(R.id.habit_widget_message, android.view.View.VISIBLE)
            views.setTextViewText(R.id.habit_widget_message, message)
            for (index in 0 until MAX_ITEMS) {
                views.setViewVisibility(itemId(index), android.view.View.GONE)
            }
            return views
        }

        /** Today as `20260915`, the packing the app uses for a day. */
        private fun todayKey(): Int {
            val now = Calendar.getInstance()
            return now.get(Calendar.YEAR) * 10000 +
                (now.get(Calendar.MONTH) + 1) * 100 +
                now.get(Calendar.DAY_OF_MONTH)
        }
        /** The habit ids a widget instance shows; empty means "all of them". */
        fun habitIdsOf(manager: AppWidgetManager, id: Int): List<String> {
            val stored = manager.getAppWidgetOptions(id).getString(OPTION_HABIT_IDS)
            if (stored.isNullOrEmpty()) return emptyList()
            return stored.split(',').filter { it.isNotEmpty() }
        }

        /** Writes the habits a widget instance shows. */
        fun setHabitIds(context: Context, manager: AppWidgetManager, id: Int, ids: List<String>) {
            val options = manager.getAppWidgetOptions(id)
            options.putString(OPTION_HABIT_IDS, ids.joinToString(","))
            manager.updateAppWidgetOptions(id, options)
            refresh(context)
        }

        private fun itemId(index: Int) = when (index) {
            0 -> R.id.habit_item_0
            1 -> R.id.habit_item_1
            2 -> R.id.habit_item_2
            else -> R.id.habit_item_3
        }

        private fun itemCheckId(index: Int) = when (index) {
            0 -> R.id.habit_item_0_check
            1 -> R.id.habit_item_1_check
            2 -> R.id.habit_item_2_check
            else -> R.id.habit_item_3_check
        }

        private fun itemEmojiId(index: Int) = when (index) {
            0 -> R.id.habit_item_0_emoji
            1 -> R.id.habit_item_1_emoji
            2 -> R.id.habit_item_2_emoji
            else -> R.id.habit_item_3_emoji
        }

        private fun itemNameId(index: Int) = when (index) {
            0 -> R.id.habit_item_0_name
            1 -> R.id.habit_item_1_name
            2 -> R.id.habit_item_2_name
            else -> R.id.habit_item_3_name
        }

        /**
         * Draws the widget into a view nobody sees, and reports what came out.
         *
         * This exists because the widget's most failure-prone part — that every
         * id in `habit_widget.xml` is what the code assumes it is, and that the
         * launcher's own inflation of the layout succeeds — cannot be reached by
         * a Flutter test and, on a launcher that will not host the widget, not by
         * a device either. Applying the tree here runs the same inflation and the
         * same actions the launcher would run, and the text it returns is the
         * proof that the binding happened.
         *
         * Only ever called from a debug build; see `HabitWidgetSync`.
         */
        fun selfCheck(context: Context): Map<String, Any?> {
            val payload = HabitWidgetStore.snapshot(context)
            val ids = payload?.optJSONArray("order")
            val first = if (ids != null && ids.length() > 0) ids.optString(0) else null
            return runCatching {
                mapOf(
                    "ok" to true,
                    // The column as the launcher would draw it.
                    "row" to renderTexts(context, payload, emptyList(), 0),
                    // The same payload dated yesterday: what the widget finds
                    // after a day it was not opened during.
                    "stale" to renderTexts(
                        context,
                        WidgetSelfCheck.forcedDay(payload, -1),
                        emptyList(),
                        0,
                    ),
                    // One habit ticked on the tile, and the arrangement screen
                    // narrowed to it.
                    "chosen" to renderTexts(
                        context,
                        payload,
                        first?.let { listOf(it) } ?: emptyList(),
                        0,
                    ),
                    "empty" to renderTexts(context, null, emptyList(), 0),
                    "habits" to (ids?.length() ?: 0),
                )
            }.getOrElse { error ->
                mapOf("ok" to false, "reason" to error.toString())
            }
        }


        /**
         * Draws one column and answers with the text that came out.
         *
         * A thin wrapper over the shared self-check: what differs per widget is
         * only which view tree to build.
         */
        private fun renderTexts(
            context: Context,
            payload: JSONObject?,
            habitIds: List<String>,
            widgetId: Int,
        ): List<String> =
            WidgetSelfCheck.renderTexts(
                context,
                buildViews(context, payload, widgetId, habitIds),
            )

        /**
         * The line under the name: the state in words, plus whatever facts the
         * habit has to add.
         *
         * Composed here rather than sent ready-made because a tap can change the
         * state with the app closed — the tick flips locally at once, and the
         * line has to flip with it instead of contradicting the tick until the
         * app next runs.
         */
        private fun subFor(payload: JSONObject, tile: JSONObject): String {
            val details = if (tile.isNull("details")) "" else tile.optString("details")
            if (tile.optBoolean("done")) {
                val done = payload.optString("subDone")
                return if (details.isEmpty()) done else "$done · $details"
            }
            if (!tile.optBoolean("due")) {
                return payload.optString("subOff")
            }
            return if (details.isEmpty()) payload.optString("subTodo") else details
        }

        /**
         * Opens the arrangement screen for one widget instance.
         *
         * An activity intent rather than a broadcast: it is the screen that says
         * which habits this tile shows and offers to edit them, and it is
         * reachable from the tile itself because a tap that is not on a circle
         * has to do *something* useful, and opening the app would be the one
         * thing it must not do.
         */
        private fun arrangeIntent(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, HabitWidgetConfigActivity::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(
                context,
                REQUEST_ARRANGE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
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
            habitId: String,
            dayKey: Int,
            done: Boolean,
        ): PendingIntent {
            // One request code per habit: a PendingIntent is identified by its
            // request code and its intent's data, not by its extras, so sharing
            // one code between habits would make every tile check off whichever
            // habit happened to be drawn last.
            val intent = Intent(context, HabitWidgetProvider::class.java)
                .setAction(ACTION_TOGGLE)
                .putExtra(EXTRA_HABIT_ID, habitId)
                .putExtra(EXTRA_DAY_KEY, dayKey)
                .putExtra("done", done)
            return PendingIntent.getBroadcast(
                context,
                REQUEST_TOGGLE_BASE + habitId.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun noteIntent(
            context: Context,
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
                REQUEST_NOTE_BASE + habitId.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
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
                }
                // Deliberately nothing else: a tap on the tile checks the habit
                // off and stays where it is. Starting the app here — which this
                // used to do, to tell a running app its queue had grown — made
                // every check-in on the home screen throw the user into the app,
                // which is the opposite of what a widget is for. The queue keeps
                // until the app is next opened, and opening it drains the queue
                // before it publishes anything.
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
 * Draws a widget's view tree into a view nobody sees, and reports what came out.
 *
 * This exists because a widget's most failure-prone part — that every id in its
 * layout is what the code assumes it is, and that the launcher's own inflation of
 * that layout succeeds — cannot be reached by a Flutter test and, on a launcher
 * that will not host the widget, not by a device either. Applying the tree here
 * runs the same inflation and the same actions the launcher would run, and the
 * text it returns is the proof that the binding happened.
 *
 * Only ever called from a debug build; see the two sync classes on the Dart side.
 */
internal object WidgetSelfCheck {
    /** The visible text in a view tree, in draw order. */
    fun collectText(view: View, into: MutableList<String>) {
        if (view.visibility != View.VISIBLE) return
        if (view is TextView) {
            into.add(view.text?.toString().orEmpty())
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                collectText(view.getChildAt(index), into)
            }
        }
    }

    /** Draws one view tree and answers with the text that came out. */
    fun renderTexts(context: Context, views: RemoteViews): List<String> {
        val root = views.apply(context, FrameLayout(context))
        val texts = ArrayList<String>()
        collectText(root, texts)
        return texts
    }

    /**
     * Draws one view tree and answers with the colours it painted, sampled on a
     * coarse grid.
     *
     * The text a tree binds says nothing about what is *behind* the text, and a
     * launcher that will not host the widget cannot be asked — so the tile's
     * background would otherwise be the one part of it nobody ever sees until a
     * user does. Drawing it here is the same tree, the same inflation and the
     * same bitmap the launcher would get; the colours are the proof that the
     * user's picture and its scrim actually reached the tile.
     *
     * Only ever called from a debug build.
     */
    fun renderColors(context: Context, views: RemoteViews, size: Int = 200): List<String> {
        val root = views.apply(context, FrameLayout(context))
        val spec = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)
        root.measure(spec, spec)
        root.layout(0, 0, size, size)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        root.draw(Canvas(bitmap))

        // The corners are the card's own rounded surface and the middle is
        // whatever the tile draws over it, so a 3x3 sample says both what colour
        // the picture came out as and whether anything was drawn over it at all.
        val colours = ArrayList<String>()
        for (row in 0 until 3) {
            for (column in 0 until 3) {
                val x = (size * (2 * column + 1) / 6).coerceIn(0, size - 1)
                val y = (size * (2 * row + 1) / 6).coerceIn(0, size - 1)
                colours.add(String.format("#%08X", bitmap.getPixel(x, y)))
            }
        }
        bitmap.recycle()
        return colours
    }

    /** A copy of [payload] dated [daysFromToday] days ago. */
    fun forcedDay(payload: JSONObject?, daysFromToday: Int): JSONObject? {
        if (payload == null) return null
        val calendar = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, daysFromToday)
        }
        val dayKey = calendar.get(Calendar.YEAR) * 10000 +
            (calendar.get(Calendar.MONTH) + 1) * 100 +
            calendar.get(Calendar.DAY_OF_MONTH)
        return JSONObject(payload.toString()).put("dayKey", dayKey)
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

/**
 * The arrangement screen: which habits one tile shows, and how to change them.
 *
 * The system runs this when a widget is added — and refuses to place the widget
 * until it answers — and the tile opens it again on any tap that is not on a
 * circle. That is why it does two jobs: choosing what goes on the tile, and
 * getting out of the way of the habits themselves, which are edited in the app
 * (this screen only says *which*, never *what*).
 *
 * Native rather than Flutter because it has to answer the system in a moment and
 * has to be reachable from a widget tap; the list it draws comes from the same
 * payload the widgets draw from, so nothing here reads `habits.json` a second
 * time.
 */
class HabitWidgetConfigActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    /** The habits ticked so far, in the order they will appear on the tile. */
    private val selected = LinkedHashSet<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            // Not about a real widget: nothing to arrange.
            finish()
            return
        }

        setContentView(R.layout.habit_widget_config)
        val manager = AppWidgetManager.getInstance(this)
        val habits = HabitWidgetStore.configuredHabits(this)

        // What the tile shows now, or — on the first run — whatever the pin
        // request suggested, or everything, because a tile that shows nothing by
        // default is a tile that does nothing.
        val existing = HabitWidgetProvider.habitIdsOf(manager, widgetId)
        selected.addAll(
            existing.ifEmpty {
                intent?.getStringExtra(HabitWidgetProvider.EXTRA_PIN_HABITS)
                    ?.split(',')
                    ?.filter { it.isNotEmpty() }
                    ?: habits.map { it.first }
            },
        )

        if (habits.isEmpty()) {
            findViewById<View>(R.id.habit_config_empty).visibility = View.VISIBLE
        } else {
            val list = findViewById<LinearLayout>(R.id.habit_config_list)
            for ((id, tile) in habits) {
                list.addView(configRow(id, tile))
            }
        }

        findViewById<View>(R.id.habit_config_cancel).setOnClickListener { finish() }
        findViewById<View>(R.id.habit_config_done).setOnClickListener { save() }
    }

    private fun configRow(id: String, tile: JSONObject): View {
        val row = layoutInflater.inflate(R.layout.habit_widget_config_row, null)
        row.findViewById<TextView>(R.id.habit_config_row_emoji).text = tile.optString("emoji")
        row.findViewById<TextView>(R.id.habit_config_row_name).text = tile.optString("name")
        val check = row.findViewById<CheckBox>(R.id.habit_config_row_check)
        check.isChecked = id in selected

        // The row adds or removes the habit; the pencil edits it in the app.
        row.setOnClickListener {
            if (id in selected) selected.remove(id) else selected.add(id)
            check.isChecked = id in selected
        }
        row.findViewById<View>(R.id.habit_config_row_edit).setOnClickListener {
            editInApp(id)
        }
        return row
    }

    /** Hands one habit to the app, which opens its editor. */
    private fun editInApp(habitId: String) {
        HabitWidgetStore.requestEdit(this, habitId)
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        runCatching { startActivity(launch) }
    }

    /** Records the chosen habits and tells the system the widget may be placed. */
    private fun save() {
        runCatching {
            val manager = AppWidgetManager.getInstance(this)
            HabitWidgetProvider.setHabitIds(this, manager, widgetId, selected.toList())
        }.onFailure { Log.w(TAG, "Could not arrange widget $widgetId: ${it.message}") }
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId),
        )
        finish()
    }
}

/**
 * What the course widget draws itself from.
 *
 * The payload comes from the app the same way the habit tile's does — the widget
 * runs in the launcher's process and cannot read the app's documents — but there
 * is nothing to queue back: a course widget shows what is on and offers no
 * action of its own beyond opening the app, so the only state here is the
 * picture and the request to open the timetable.
 */
internal object CourseWidgetStore {
    private const val PREFS = "course_widget"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_OPEN = "openTimetable"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun snapshot(context: Context): JSONObject? {
        val raw = prefs(context).getString(KEY_SNAPSHOT, null) ?: return null
        return runCatching { JSONObject(raw) }.getOrNull()
    }

    fun writeSnapshot(context: Context, snapshot: JSONObject) {
        prefs(context).edit().putString(KEY_SNAPSHOT, snapshot.toString()).apply()
    }

    /** Remembers that tapping the tile should land on the timetable when it opens. */
    fun requestOpen(context: Context) {
        prefs(context).edit().putBoolean(KEY_OPEN, true).apply()
    }

    fun takeOpen(context: Context): Boolean {
        if (!prefs(context).getBoolean(KEY_OPEN, false)) return false
        prefs(context).edit().remove(KEY_OPEN).apply()
        return true
    }
}

/**
 * The course widget: today's classes, one per row.
 *
 * Deliberately without buttons. A timetable is read, not ticked off — the habit
 * tile has circles because checking a habit off is the point of it, and a course
 * has no equivalent — so every tap here leads to the app, which is where a
 * course is edited.
 */
class CourseWidgetProvider : AppWidgetProvider() {
    companion object {
        /** The course widget asking for the timetable itself. */
        const val EXTRA_OPEN_TIMETABLE = "openTimetable"

        /** How many courses the row list holds; the layout has this many rows. */
        private const val MAX_ROWS = 4

        private const val REQUEST_OPEN_TABLE = 5300

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (id in manager.getAppWidgetIds(component(context))) {
                runCatching { render(context, manager, id) }
                    .onFailure { Log.w(TAG, "Could not draw the course widget: ${it.message}") }
            }
        }

        fun placed(context: Context): Boolean =
            AppWidgetManager.getInstance(context).getAppWidgetIds(component(context)).isNotEmpty()

        private fun component(context: Context) =
            ComponentName(context, CourseWidgetProvider::class.java)

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val snapshot = CourseWidgetStore.snapshot(context)
            manager.updateAppWidget(id, buildViews(context, snapshot))
        }

        /**
         * Builds the tile's view tree, and binds [snapshot] into it.
         *
         * Separate from [render] so it can be drawn without a launcher, exactly
         * as the habit tile's is: see `HabitWidgetProvider.selfCheck`.
         */
        internal fun buildViews(context: Context, snapshot: JSONObject?): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.course_widget)
            // First, so that the "no classes today" branch wears the same
            // background as the one that lists them.
            WidgetBackground.apply(
                context,
                views,
                R.id.course_widget_background,
                R.id.course_widget_scrim,
            )
            // Every tap on this tile goes to the timetable: there is nothing to
            // change here, and the timetable is what a row is *about*.
            val open = openTimetable(context)
            views.setOnClickPendingIntent(R.id.course_widget_root, open)

            val rows = snapshot?.optJSONArray("rows") ?: JSONArray()
            // A payload is a picture of one day. When that day is no longer today
            // the rows are yesterday's classes — a different weekday entirely —
            // and showing them as today's would be worse than saying nothing.
            val stale = snapshot != null &&
                snapshot.optInt("dayKey", 0).let { it != 0 && it != todayKey() }

            if (snapshot == null || stale || rows.length() == 0) {
                val message = when {
                    snapshot == null -> context.getString(R.string.course_widget_no_data)
                    stale -> snapshot.optString("staleText")
                    else -> snapshot.optString("emptyText")
                }
                views.setViewVisibility(R.id.course_widget_message, android.view.View.VISIBLE)
                views.setTextViewText(R.id.course_widget_message, message)
                for (index in 0 until MAX_ROWS) {
                    views.setViewVisibility(rowId(index), android.view.View.GONE)
                }
                return views
            }

            views.setViewVisibility(R.id.course_widget_message, android.view.View.GONE)
            val shown = minOf(rows.length(), MAX_ROWS)
            for (index in 0 until MAX_ROWS) {
                val row = if (index < shown) rows.optJSONObject(index) else null
                if (row == null) {
                    views.setViewVisibility(rowId(index), android.view.View.GONE)
                    continue
                }
                views.setViewVisibility(rowId(index), android.view.View.VISIBLE)
                views.setTextViewText(timeId(index), row.optString("time"))
                views.setTextViewText(nameId(index), row.optString("name"))
                val room = if (row.isNull("room")) "" else row.optString("room")
                views.setTextViewText(roomId(index), room)
                views.setViewVisibility(
                    roomId(index),
                    if (room.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE,
                )
                // One intent for every row: whichever course the user aimed at,
                // what they want is the timetable.
                views.setOnClickPendingIntent(rowId(index), open)
            }
            return views
        }

        /** A tap anywhere on the tile opens the timetable itself. */
        private fun openTimetable(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_OPEN_TIMETABLE, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context,
                REQUEST_OPEN_TABLE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun rowId(index: Int) = when (index) {
            0 -> R.id.course_item_0
            1 -> R.id.course_item_1
            2 -> R.id.course_item_2
            else -> R.id.course_item_3
        }

        private fun timeId(index: Int) = when (index) {
            0 -> R.id.course_item_0_time
            1 -> R.id.course_item_1_time
            2 -> R.id.course_item_2_time
            else -> R.id.course_item_3_time
        }

        private fun nameId(index: Int) = when (index) {
            0 -> R.id.course_item_0_name
            1 -> R.id.course_item_1_name
            2 -> R.id.course_item_2_name
            else -> R.id.course_item_3_name
        }

        private fun roomId(index: Int) = when (index) {
            0 -> R.id.course_item_0_room
            1 -> R.id.course_item_1_room
            2 -> R.id.course_item_2_room
            else -> R.id.course_item_3_room
        }

        /** Today as `20260915`, the packing the app uses for a day. */
        private fun todayKey(): Int {
            val now = Calendar.getInstance()
            return now.get(Calendar.YEAR) * 10000 +
                (now.get(Calendar.MONTH) + 1) * 100 +
                now.get(Calendar.DAY_OF_MONTH)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            runCatching { render(context, manager, id) }
                .onFailure { Log.w(TAG, "Could not draw the course widget: ${it.message}") }
        }
    }
}

/**
 * Draws the course tile for each state it can be in, and reports the text.
 *
 * The same exercise the habit tile runs, and for the same reason: this launcher
 * may never host the widget, and the layout still has to be known to inflate and
 * to take the values bound to it. An object of its own rather than a companion,
 * because a class gets one companion and the provider's is already holding the
 * drawing code.
 */
internal object CourseWidgetSelfCheck {
    fun selfCheck(context: Context): Map<String, Any?> {
        val payload = CourseWidgetStore.snapshot(context)
        val noRows = payload?.let { JSONObject(it.toString()).put("rows", JSONArray()) }
        return runCatching {
            mapOf(
                "ok" to true,
                "today" to WidgetSelfCheck.renderTexts(
                    context,
                    CourseWidgetProvider.buildViews(context, payload),
                ),
                "stale" to WidgetSelfCheck.renderTexts(
                    context,
                    CourseWidgetProvider.buildViews(
                        context,
                        WidgetSelfCheck.forcedDay(payload, -1),
                    ),
                ),
                "empty" to WidgetSelfCheck.renderTexts(
                    context,
                    CourseWidgetProvider.buildViews(context, noRows),
                ),
                "noData" to WidgetSelfCheck.renderTexts(
                    context,
                    CourseWidgetProvider.buildViews(context, null),
                ),
                "rows" to (payload?.optJSONArray("rows")?.length() ?: 0),
                // What the tile actually painted, since no launcher here will
                // show it: the sampled colours are the tile's background.
                "colors" to WidgetSelfCheck.renderColors(
                    context,
                    CourseWidgetProvider.buildViews(context, payload),
                ),
                "background" to WidgetBackground.path(context),
                "dim" to WidgetBackground.dim(context).toDouble(),
            )
        }.getOrElse { error ->
            mapOf("ok" to false, "reason" to error.toString())
        }
    }
}
