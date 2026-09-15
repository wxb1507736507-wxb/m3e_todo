import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The result of a successful attachment pick.
///
/// The native side has already copied the file into the app's attachments
/// directory; [path] points at that private copy.
class PickedAttachment {
  const PickedAttachment({required this.path, required this.name, this.mime});

  final String path;
  final String name;
  final String? mime;
}

/// One alarm to hand to the native scheduler.
///
/// Exists so the batched call and the single call cannot drift apart: both
/// serialise through [toChannelArgs].
class PendingAlarm {
  const PendingAlarm({
    required this.notificationId,
    required this.title,
    required this.body,
    required this.triggerAt,
    required this.ring,
    this.ringtoneUri,
  });

  final int notificationId;
  final String title;
  final String body;
  final DateTime triggerAt;
  final bool ring;

  /// Sound for a ringing alarm, or `null` for the system's default notification
  /// sound. Never set on a silent alarm.
  final String? ringtoneUri;

  Map<String, Object?> toChannelArgs() => <String, Object?>{
        'notificationId': notificationId,
        'title': title,
        'body': body,
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
        'ring': ring,
        'ringtoneUri': ringtoneUri,
      };
}

/// Typed Dart surface over the app's single native method channel.
///
/// Every call degrades gracefully off Android: the app's reminder, picker and
/// recorder features are Android-first, and on other platforms the methods
/// return "unavailable" values (`null`, `false`) instead of throwing, so the UI
/// can simply hide the affected affordances.
///
/// `Platform.isAndroid` throws on web, hence the `kIsWeb` guard first.
abstract final class AppPlatform {
  static const MethodChannel _channel = MethodChannel(
    'dev.m3e.m3e_todo/platform',
  );

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!isAndroid) {
      return null;
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      // A refused permission or a missing picker activity is a normal user
      // outcome, not a crash; report and continue.
      debugPrint('$method failed: ${error.code} ${error.message}');
      return null;
    }
  }

  // --- Notifications ---------------------------------------------------------

  /// Whether the OS will currently show this app's notifications.
  static Future<bool> notificationsEnabled() async {
    if (!isAndroid) {
      return false;
    }
    return await _invoke<bool>('areNotificationsEnabled') ?? false;
  }

  /// Prompts for the Android 13+ notification permission. Returns the user's
  /// answer; `true` trivially on older versions where no prompt exists.
  static Future<bool> requestNotificationPermission() async {
    if (!isAndroid) {
      return false;
    }
    return await _invoke<bool>('requestNotificationPermission') ?? false;
  }

  /// Whether the OS will let this app fire an alarm at an exact moment.
  ///
  /// Separate from the notification permission: from Android 12 an app that
  /// targets 12+ is withheld the "Alarms & reminders" grant by default, and
  /// without it a due reminder is delivered in a coarse window (measured: up to
  /// an hour late) rather than at 09:00. Returns `false` off Android, where
  /// there are no reminders to schedule.
  static Future<bool> canScheduleExactAlarms() async {
    if (!isAndroid) {
      return false;
    }
    return await _invoke<bool>('canScheduleExactAlarms') ?? false;
  }

  /// Opens the system screen where the user grants [canScheduleExactAlarms].
  ///
  /// Returns whether the screen could be opened; the answer to the grant itself
  /// has to be re-read afterwards, since it is decided outside this app.
  static Future<bool> requestExactAlarmPermission() async {
    if (!isAndroid) {
      return false;
    }
    return await _invoke<bool>('requestExactAlarmPermission') ?? false;
  }

  /// The system default notification sound, as a URI string.
  static Future<String?> systemRingtoneUri() =>
      _invoke<String>('systemRingtoneUri');

  /// Schedules a due-date notification. [notificationId] must be stable across
  /// reschedules so an existing alarm is replaced rather than duplicated.
  ///
  /// [ringtoneUri] is the sound this one reminder should make, or `null` for the
  /// system default. It is per alarm because the choice is per todo: Android
  /// gives the *channel* its sound and fixes it at creation, so the native side
  /// keeps one channel per distinct ringtone.
  static Future<void> scheduleAlarm({
    required int notificationId,
    required String title,
    required String body,
    required DateTime triggerAt,
    required bool ring,
    String? ringtoneUri,
  }) {
    return _invoke<Object?>(
      'scheduleAlarm',
      PendingAlarm(
        notificationId: notificationId,
        title: title,
        body: body,
        triggerAt: triggerAt,
        ring: ring,
        ringtoneUri: ringtoneUri,
      ).toChannelArgs(),
    );
  }

  static Future<void> cancelAlarm(int notificationId) =>
      _invoke<Object?>('cancelAlarm', <String, Object?>{
        'notificationId': notificationId,
      });

  /// Replaces the whole native schedule with [alarms].
  ///
  /// The one operation a diff cannot express: alarms left over from a previous
  /// run belong to todos that no longer exist, so there is no id here to cancel
  /// them by. Used for the first sync of a process (and therefore after a
  /// reboot), where "these are all of them" is the truth.
  static Future<void> syncAlarms(List<PendingAlarm> alarms) {
    return _invoke<Object?>(
      'syncAlarms',
      <Object?>[for (final PendingAlarm alarm in alarms) alarm.toChannelArgs()],
    );
  }

  /// Schedules several alarms in one call.
  ///
  /// The single-alarm form costs a channel round trip each, and keeping the
  /// schedule in step after a launch with dozens of dated todos meant dozens of
  /// trips — all of them landing on the platform thread while the first frames
  /// were still being built. Batching makes it one.
  static Future<void> scheduleAlarms(List<PendingAlarm> alarms) {
    if (alarms.isEmpty) {
      return Future<void>.value();
    }
    return _invoke<Object?>(
      'scheduleAlarms',
      <Object?>[for (final PendingAlarm alarm in alarms) alarm.toChannelArgs()],
    );
  }

  /// Cancels several alarms in one call.
  static Future<void> cancelAlarms(List<int> notificationIds) {
    if (notificationIds.isEmpty) {
      return Future<void>.value();
    }
    return _invoke<Object?>(
      'cancelAlarms',
      <Object?>[
        for (final int id in notificationIds)
          <String, Object?>{'notificationId': id},
      ],
    );
  }

  // --- Pickers -----------------------------------------------------------------

  /// Opens the system document picker filtered by [kind]
  /// (`image`/`video`/`audio`/anything else for documents).
  static Future<PickedAttachment?> pickAttachment(String kind) async {
    // The type argument must be `Map<Object?, Object?>` — that is what the
    // standard codec decodes a map into, and `invokeMethod` casts the reply to
    // whatever `T` was asked for. Asking for `Map<Object, Object?>` is a
    // *downcast* (`Object?` is wider than `Object`), so it threw
    // "type '_Map<Object?, Object?>' is not a subtype of type
    // 'Map<Object, Object?>?'" on every single pick: the native side copied the
    // file and reported it, and Dart dropped the answer on the floor.
    final Map<Object?, Object?>? result = await _invoke<Map<Object?, Object?>>(
      'pickAttachment',
      kind,
    );
    if (result == null) {
      return null;
    }
    final Object? path = result['path'];
    if (path is! String) {
      return null;
    }
    return PickedAttachment(
      path: path,
      name: result['name'] as String? ?? path,
      mime: result['mime'] as String?,
    );
  }

  /// Writes an image produced inside the app (a cropped background, for
  /// instance) into the app's attachments directory, returning its path.
  ///
  /// The bytes are encoded on the Dart side; only the *location* is native,
  /// because that is where `filesDir` is known.
  static Future<String?> saveImage({
    required Uint8List bytes,
    String extension = 'png',
  }) {
    return _invoke<String>('saveImage', <String, Object?>{
      'bytes': bytes,
      'extension': extension,
    });
  }

  /// Opens the system ringtone picker; returns the chosen `content://` URI.
  static Future<String?> pickRingtone() => _invoke<String>('pickRingtone');

  // --- Voice recording ------------------------------------------------------------

  /// Starts recording from the microphone. Returns `false` (and does nothing)
  /// when the audio permission has not been granted yet.
  static Future<bool> startVoiceRecording() async {
    if (!isAndroid) {
      return false;
    }
    return await _invoke<bool>('startVoiceRecording') ?? false;
  }

  /// Prompts for the microphone permission, returning whether it was granted.
  ///
  /// Needed because Android does not grant `RECORD_AUDIO` to a fresh install:
  /// without this the recorder could only ever report "permission missing" and
  /// the user would have to find the switch in system settings themselves.
  static Future<bool> requestAudioPermission() async {
    if (!isAndroid) {
      return false;
    }
    return await _invoke<bool>('requestAudioPermission') ?? false;
  }

  /// Stops the recording and returns the file path, or `null` when nothing was
  /// captured (for instance a recording too short to encode).
  static Future<String?> stopVoiceRecording() =>
      _invoke<String>('stopVoiceRecording');

  // --- Files ---------------------------------------------------------------------

  /// Hands a file to whatever app the user has for its type.
  static Future<bool> openAttachment(String path, String? mime) async {
    final bool? opened = await _invoke<bool>(
      'openAttachment',
      <String, Object?>{'path': path, 'mime': mime},
    );
    return opened ?? false;
  }

  /// Previews a ringtone URI through the system audio path.
  static Future<void> playRingtone(String? uri) =>
      _invoke<Object?>('playRingtone', uri);

  static Future<void> stopRingtone() => _invoke<Object?>('stopRingtone');

  // --- Habit widgets and their alarms ------------------------------------------

  /// Replaces the whole habit-reminder schedule with [alarms].
  ///
  /// Whole-schedule rather than a diff, because a habit's next occurrence is
  /// computed from a time of day and a weekday mask: it moves every day by
  /// itself, and the native side owns the repeat. Sending the list on every
  /// change also carries [HabitAlarm.skipToday], which is how a habit ticked at
  /// 07:00 stops nagging at 20:00.
  static Future<void> syncHabitAlarms(List<HabitAlarm> alarms) {
    return _invoke<Object?>(
      'syncHabitAlarms',
      <Object?>[for (final HabitAlarm alarm in alarms) alarm.toChannelArgs()],
    );
  }

  /// Hands the home-screen widget everything it draws.
  ///
  /// Returns whether any widget is currently on a home screen, which is what
  /// lets the habits page say "已添加到桌面" instead of offering to add one that
  /// is already there.
  static Future<bool> updateHabitWidget(Map<String, Object?> snapshot) async {
    if (!isAndroid) {
      return false;
    }
    return await _invoke<bool>('updateHabitWidget', snapshot) ?? false;
  }

  /// Asks the system to place the habit widget on the home screen.
  ///
  /// Android 8+ shows its own confirmation sheet, so a `true` here means the
  /// request was made, not that a widget now exists.
  static Future<bool> requestHabitWidgetPin() async {
    if (!isAndroid) {
      return false;
    }
    return await _invoke<bool>('requestHabitWidgetPin') ?? false;
  }

  /// Takes the check-ins made on the widget since the last call.
  ///
  /// The widget can be pressed with the app's process dead, so it cannot write
  /// the app's documents itself: it queues the taps natively, and this drains
  /// them. Draining clears the queue, so it must only be called by the one place
  /// that turns them into stored check-ins.
  static Future<List<HabitWidgetAction>> drainHabitCheckIns() async {
    final List<Object?>? raw =
        await _invoke<List<Object?>>('drainHabitCheckIns');
    if (raw == null) {
      return const <HabitWidgetAction>[];
    }
    final List<HabitWidgetAction> actions = <HabitWidgetAction>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final Object? habitId = entry['habitId'];
      final Object? dayKey = entry['dayKey'];
      if (habitId is! String || habitId.isEmpty || dayKey is! int) {
        continue;
      }
      final Object? at = entry['atMillis'];
      actions.add(
        HabitWidgetAction(
          habitId: habitId,
          dayKey: dayKey,
          done: entry['done'] == true,
          at: at is int
              ? DateTime.fromMillisecondsSinceEpoch(at)
              : DateTime.now(),
        ),
      );
    }
    return actions;
  }

  /// Takes the habit the widget asked the app to open, if any.
  ///
  /// The widget's ＋ button is the only way to write a note from the home screen:
  /// a `RemoteViews` cannot take typing, so the tap is handed to the app, which
  /// opens that habit's check-in editor.
  static Future<String?> takeHabitOpenRequest() =>
      _invoke<String>('takeHabitOpenRequest');

  /// Asks to be told when the home-screen widget is used.
  ///
  /// The other direction of the same channel, and the only thing the app ever
  /// *hears* from Android. It exists because a widget tap with the app already
  /// on screen produces no lifecycle event at all: resuming is how a background
  /// app notices, and there is nothing to resume when the app never left.
  static void setHabitWidgetListener(Future<void> Function() listener) {
    if (!isAndroid) {
      return;
    }
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'habitWidgetChanged') {
        await listener();
      }
      return null;
    });
  }
}

/// One habit reminder for the native scheduler.
///
/// Unlike a todo's, this one repeats: [minutes] and [daysMask] describe *when*,
/// and the native side works out the next occurrence from them — after firing,
/// and again after a reboot.
class HabitAlarm {
  const HabitAlarm({
    required this.habitId,
    required this.title,
    required this.body,
    required this.minutes,
    required this.daysMask,
    required this.ring,
    this.ringtoneUri,
    this.skipToday = false,
  });

  final String habitId;
  final String title;
  final String body;

  /// Minutes after local midnight.
  final int minutes;

  /// Monday-first weekday mask; a habit is reminded only on its own days.
  final int daysMask;

  final bool ring;
  final String? ringtoneUri;

  /// Whether today's occurrence should be skipped — set once the habit has
  /// already been checked off today.
  final bool skipToday;

  Map<String, Object?> toChannelArgs() => <String, Object?>{
        'habitId': habitId,
        'title': title,
        'body': body,
        'minutes': minutes,
        'daysMask': daysMask,
        'ring': ring,
        'ringtoneUri': ringtoneUri,
        'skipToday': skipToday,
      };
}

/// Something the user did on the home-screen widget, waiting to be stored.
class HabitWidgetAction {
  const HabitWidgetAction({
    required this.habitId,
    required this.dayKey,
    required this.done,
    required this.at,
  });

  final String habitId;
  final int dayKey;

  /// `true` for a check-in, `false` for an undo — the widget's button toggles,
  /// because a mis-tap on the home screen is otherwise only fixable by opening
  /// the app.
  final bool done;

  final DateTime at;
}
