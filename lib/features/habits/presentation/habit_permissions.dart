import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/platform/app_platform.dart';

/// Makes sure a reminder the user has just asked for can actually arrive.
///
/// Asking at the moment the switch is turned on is the whole point: the user has
/// just said "remind me at 08:00", so anything standing between the app and that
/// promise has to be dealt with there and then, not discovered at 08:00 the next
/// morning. It is also the only moment when the request makes sense to them.
///
/// Two different mechanisms, because Android offers two: the notification
/// permission has a dialog, and "Alarms & reminders" has none — it can only be
/// granted on a settings screen, so the app opens that screen and says why.
class HabitPermissions {
  const HabitPermissions();

  /// Returns whether reminders can be delivered exactly after this ran.
  Future<bool> ensureReminderDelivery(ScaffoldMessengerState messenger) async {
    if (!AppPlatform.isAndroid) {
      // Nothing to ask for, and nothing to explain: the habit still works, it
      // just cannot ring.
      return false;
    }

    if (!await AppPlatform.notificationsEnabled()) {
      final bool granted = await AppPlatform.requestNotificationPermission();
      if (!granted) {
        // The dialog is spent: Android will not show it again after a refusal,
        // so the switch itself is opened rather than asked a second time.
        await AppPlatform.openNotificationSettings();
        messenger.showSnackBar(
          const SnackBar(
            content: Text(AppStrings.habitNotificationPermissionHint),
            duration: Duration(seconds: 6),
          ),
        );
        return false;
      }
    }

    if (!await AppPlatform.canScheduleExactAlarms()) {
      // This one is a screen, not a dialog — there is no other way to ask.
      await AppPlatform.requestExactAlarmPermission();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(AppStrings.habitExactAlarmHint),
          duration: Duration(seconds: 6),
        ),
      );
      return false;
    }
    return true;
  }
}

/// Overridden in tests, so the wiring — ask when a reminder is set, stay quiet
/// when it is not — can be checked without an Android device.
final Provider<HabitPermissions> habitPermissionsProvider =
    Provider<HabitPermissions>(
  (ref) => const HabitPermissions(),
  name: 'habitPermissions',
);

/// What stands between a habit's reminder and the user, right now.
class HabitPermissionStatus {
  const HabitPermissionStatus({
    required this.notifications,
    required this.exactAlarms,
  });

  /// Whether notifications can be posted at all.
  final bool notifications;

  /// Whether they can be posted *on time*. False while [notifications] is false
  /// as well: there is no point asking for punctuality from something that
  /// cannot be delivered.
  final bool exactAlarms;

  bool get remindersWork => notifications && exactAlarms;
}

/// Read when a habit with a reminder exists, so the habits page can say so when
/// its reminders have quietly stopped being possible — a permission revoked
/// later, or never granted in the first place.
///
/// Invalidated when the app comes back to the foreground, because that is when
/// the user may have just changed it.
final FutureProvider<HabitPermissionStatus> habitPermissionStatusProvider =
    FutureProvider<HabitPermissionStatus>(
  (ref) async {
    if (!AppPlatform.isAndroid) {
      // No permissions to hold, so nothing to warn about.
      return const HabitPermissionStatus(
        notifications: true,
        exactAlarms: true,
      );
    }
    final bool notifications = await AppPlatform.notificationsEnabled();
    return HabitPermissionStatus(
      notifications: notifications,
      exactAlarms:
          notifications && await AppPlatform.canScheduleExactAlarms(),
    );
  },
  name: 'habitPermissionStatus',
);

/// Opens whichever screen can fix [status] — the notification switch, or the
/// "Alarms & reminders" grant that has no dialog of its own.
Future<void> openReminderPermissionSettings(HabitPermissionStatus status) {
  if (!status.notifications) {
    return AppPlatform.openNotificationSettings();
  }
  return AppPlatform.requestExactAlarmPermission();
}
