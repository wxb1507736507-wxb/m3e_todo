import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../calendar/domain/entities/special_day.dart';
import '../calendar/presentation/providers/special_day_providers.dart';
import '../settings/domain/app_settings.dart';
import '../settings/presentation/settings_controller.dart';
import '../todos/domain/entities/todo.dart';
import '../todos/domain/entities/todo_reminder.dart';
import 'domain/reminder.dart';
import '../todos/presentation/providers/todo_providers.dart';

/// Local time of day at which a due-date reminder fires.
///
/// Due dates are day-granular, so a reminder needs an agreed hour; 09:00 is
/// early enough to be useful and late enough not to wake anyone. A reminder
/// whose time has already passed when it is scheduled is skipped — the list
/// already marks such todos overdue.
const int _reminderHour = 9;
const int _reminderMinute = 0;

/// One pending due-date reminder.
class PendingReminder {
  const PendingReminder({
    required this.triggerAt,
    required this.title,
    required this.body,
    required this.ring,
    this.ringtoneUri,
  });

  final DateTime triggerAt;
  final String title;
  final String body;
  final bool ring;

  /// The sound to play, or `null` for the system's own notification sound.
  ///
  /// Only ever set for a ringing reminder: a silent one has no sound to carry,
  /// and keeping the field `null` there is what lets the diff below tell a
  /// silent reminder apart from one that merely lost its ringtone.
  final String? ringtoneUri;

  @override
  bool operator ==(Object other) =>
      other is PendingReminder &&
      other.triggerAt == triggerAt &&
      other.title == title &&
      other.body == body &&
      other.ring == ring &&
      other.ringtoneUri == ringtoneUri;

  @override
  int get hashCode => Object.hash(triggerAt, title, body, ring, ringtoneUri);
}

/// Keeps the native alarm schedule in step with the todo collection.
///
/// Every time the collection changes, [sync] computes which reminders *should*
/// exist and applies the difference against the last known schedule: added
/// todos get an alarm, edited todos get their alarm replaced, completed and
/// deleted todos get theirs cancelled. Calling native methods only for the
/// diff keeps a checkbox tap cheap — scheduling is O(changed), not O(n).
///
/// Notification ids are derived from the todo id, which is what makes "replace"
/// possible across app restarts without persisting the schedule on the Dart
/// side: the native layer persists its own copy for reboot restoration.
class ReminderCoordinator {
  ReminderCoordinator(this._ref);

  final Ref _ref;

  /// The schedule as of the last successful sync; empty before the first.
  final Map<String, PendingReminder> _scheduled = <String, PendingReminder>{};

  /// Applies the difference between the two collections and the last scheduled
  /// set.
  Future<void> sync() async {
    final AppSettings settings = _ref.read(settingsProvider);
    final Map<String, PendingReminder> desired = <String, PendingReminder>{
      // One schedule, two sources: a birthday is every bit as much a reason to
      // be notified as a deadline, and keeping them in one map is what lets the
      // diff below stay a single comparison. Ids come from the same generator
      // for both, so they cannot collide.
      ..._desiredReminders(
        _ref.read(todoListProvider).value ?? const <Todo>[],
        settings,
      ),
      ..._desiredSpecialDays(
        _ref.read(specialDaysProvider).value ?? const <SpecialDay>[],
        settings,
      ),
    };

    // Anything removed or changed is cancelled first, then the new or changed
    // ones are scheduled. Ids are stable, so an edited todo replaces its own
    // alarm rather than leaking a second one.
    //
    // Both directions are collected and sent as *one* call each: the native side
    // has the same primitives, and a per-reminder round trip made a launch with
    // dozens of dated todos do dozens of platform-channel hops while the first
    // frames were still being built.
    final List<int> toCancel = <int>[];
    for (final MapEntry<String, PendingReminder> entry in _scheduled.entries) {
      final PendingReminder? stillWanted = desired[entry.key];
      if (stillWanted == null || stillWanted != entry.value) {
        toCancel.add(_notificationId(entry.key));
      }
    }
    final List<PendingAlarm> toSchedule = <PendingAlarm>[];
    for (final MapEntry<String, PendingReminder> entry in desired.entries) {
      if (_scheduled[entry.key] == entry.value) {
        continue;
      }
      toSchedule.add(
        PendingAlarm(
          notificationId: _notificationId(entry.key),
          title: entry.value.title,
          body: entry.value.body,
          triggerAt: entry.value.triggerAt,
          ring: entry.value.ring,
          ringtoneUri: entry.value.ringtoneUri,
        ),
      );
    }

    if (_scheduled.isEmpty) {
      // The first sync of this process, and the one case the diff cannot handle:
      // the native side may still be holding alarms from a previous run — a todo
      // deleted after the app was closed, or a schedule left by an older build —
      // and nothing here can name them, because their ids were derived from
      // todos that no longer exist. Replacing the whole schedule is the only way
      // to be sure the device is not left counting down to something that is
      // gone. It is also exactly what a reboot needs.
      await AppPlatform.syncAlarms(toSchedule);
      _scheduled
        ..clear()
        ..addAll(desired);
      return;
    }

    await AppPlatform.cancelAlarms(toCancel);
    await AppPlatform.scheduleAlarms(toSchedule);

    _scheduled
      ..clear()
      ..addAll(desired);
  }

  /// Recomputes the schedule from the current state; used when only the defaults
  /// changed (ring vs silent, the lead time, or the default ringtone), which
  /// does not touch either collection.
  ///
  /// Entries that carry their own choice are unaffected by construction: their
  /// planned reminder is identical before and after, so the diff leaves them
  /// alone.
  Future<void> resync() => sync();

  Map<String, PendingReminder> _desiredReminders(
    List<Todo> todos,
    AppSettings settings,
  ) {
    return desiredReminders(
      todos: todos,
      reminderMode: settings.reminderMode,
      lead: settings.reminderLead,
      ringtoneUri: settings.ringtoneUri,
      now: _ref.read(clockProvider)(),
    );
  }

  Map<String, PendingReminder> _desiredSpecialDays(
    List<SpecialDay> days,
    AppSettings settings,
  ) {
    return desiredSpecialDayReminders(
      days: days,
      reminderMode: settings.reminderMode,
      lead: settings.reminderLead,
      ringtoneUri: settings.ringtoneUri,
      now: _ref.read(clockProvider)(),
    );
  }

  /// Stable notification id for a todo. Reminders are re-derived from the todo
  /// list on every launch, so the id only needs to be stable for one process
  /// lifetime — string hashes guarantee that. Masked to 31 bits, which is what
  /// the notification framework expects.
  static int _notificationId(String todoId) => todoId.hashCode & 0x7fffffff;
}

/// The reminders that *should* exist for [todos] as of [now], keyed by todo id.
///
/// Kept as a pure function, separate from [ReminderCoordinator]'s diffing, for
/// one practical reason: this is where the scheduling rules live (what deserves
/// a reminder, when it fires, and what it sounds like), and a pure function can
/// be tested without an Android device or a mocked method channel — which is
/// exactly what the rest of the coordinator cannot be.
///
/// [reminderMode], [lead] and [ringtoneUri] are the *app-wide defaults*: a todo
/// that carries its own choice wins, and one that does not keeps following the
/// defaults — including when they change later.
Map<String, PendingReminder> desiredReminders({
  required List<Todo> todos,
  required ReminderMode reminderMode,
  required DateTime now,
  ReminderLead lead = ReminderLead.onDue,
  String? ringtoneUri,
}) {
  final Map<String, PendingReminder> result = <String, PendingReminder>{};

  for (final Todo todo in todos) {
    final DateTime? due = todo.dueDate;
    // Finished work and undated work both have nothing to remind about.
    if (todo.isCompleted || due == null) {
      continue;
    }
    // 09:00 on the deadline's own day, less however much warning this todo asked
    // for: the advance notice is measured in whole days, so a "3 days before"
    // reminder for a Friday deadline lands on Tuesday morning.
    final DateTime dueMorning = DateTime(
      due.year,
      due.month,
      due.day,
      _reminderHour,
      _reminderMinute,
    );
    final ReminderLead todoLead = todo.reminderLead ?? lead;
    DateTime trigger = dueMorning.subtract(Duration(days: todoLead.daysBefore));

    // A lead time that no longer fits — a week's notice for something due in
    // three days — falls back to the deadline's own morning rather than being
    // dropped: the user asked to be reminded, and being reminded late beats not
    // being reminded at all. A trigger already in the past would fire the
    // instant it was scheduled, which is worse than staying quiet; the list
    // already marks such todos overdue.
    if (!trigger.isAfter(now)) {
      if (todoLead.daysBefore == 0 || !dueMorning.isAfter(now)) {
        continue;
      }
      trigger = dueMorning;
    }

    final bool ring = switch (todo.reminder) {
      TodoReminder.followApp => reminderMode == ReminderMode.ring,
      TodoReminder.ring => true,
      TodoReminder.silent => false,
    };
    result[todo.id] = PendingReminder(
      triggerAt: trigger,
      title: todo.title,
      body: _bodyFor(todo, dueMorning: dueMorning, early: trigger.isBefore(dueMorning), now: now),
      ring: ring,
      // Resolved here rather than natively: "follow the app setting" is a Dart
      // concept, and the native side should only ever be handed a decision.
      ringtoneUri: ring ? (todo.ringtoneUri ?? ringtoneUri) : null,
    );
  }
  return result;
}

/// The notification's second line: the notes, plus the deadline when the
/// reminder arrives before it.
///
/// An early reminder without its date is a puzzle — "交房租" a week ahead says
/// nothing about *when* — so the due date travels with it.
String _bodyFor(
  Todo todo, {
  required DateTime dueMorning,
  required bool early,
  required DateTime now,
}) {
  final String notes = todo.notes ?? '';
  if (!early) {
    return notes;
  }
  final String due = AppStrings.reminderDueOn(
    AppDateFormatter.calendarDate(dueMorning, now),
  );
  return notes.isEmpty ? due : '$notes\n$due';
}

/// The reminders that should exist for the personal dates in [days], keyed by
/// their id.
///
/// A birthday entered once has to remind every year without being re-entered,
/// which is why the trigger is computed from [SpecialDay.nextOccurrence] rather
/// than from the stored date. A countdown that has already run out is skipped:
/// there is nothing left to count down to.
///
/// The mode, sound and lead time all come from the app defaults — there is no
/// per-date override, because the point of a birthday reminder is that it
/// happens without being maintained.
Map<String, PendingReminder> desiredSpecialDayReminders({
  required List<SpecialDay> days,
  required ReminderMode reminderMode,
  required DateTime now,
  ReminderLead lead = ReminderLead.onDue,
  String? ringtoneUri,
}) {
  final bool ring = reminderMode == ReminderMode.ring;
  final Map<String, PendingReminder> result = <String, PendingReminder>{};

  for (final SpecialDay day in days) {
    final DateTime occurrence = day.nextOccurrence(now);
    final DateTime morning = DateTime(
      occurrence.year,
      occurrence.month,
      occurrence.day,
      _reminderHour,
      _reminderMinute,
    );
    DateTime trigger = morning.subtract(Duration(days: lead.daysBefore));
    // Same rule as a todo's: a lead time that no longer fits falls back to the
    // morning of the day itself, and anything already past stays quiet.
    if (!trigger.isAfter(now)) {
      if (lead.daysBefore == 0 || !morning.isAfter(now)) {
        continue;
      }
      trigger = morning;
    }

    result[day.id] = PendingReminder(
      triggerAt: trigger,
      title: day.title,
      body: _specialDayBody(day, now: now),
      ring: ring,
      ringtoneUri: ring ? ringtoneUri : null,
    );
  }
  return result;
}

/// What a personal date says when it announces itself.
///
/// "妈妈生日" alone leaves the user to work out which birthday it is; the kind
/// and the number answer that in the notification itself.
String _specialDayBody(SpecialDay day, {required DateTime now}) {
  final int? ordinal = day.ordinal(now);
  final String detail = <String>[
    switch (day.kind) {
      SpecialDayKind.birthday => AppStrings.specialDayBirthday,
      SpecialDayKind.anniversary => AppStrings.specialDayAnniversary,
      SpecialDayKind.countdown => AppStrings.specialDayCountdown,
    },
    if (ordinal != null)
      day.kind == SpecialDayKind.birthday
          ? AppStrings.specialDayAge(ordinal)
          : AppStrings.specialDayYears(ordinal),
  ].join(' · ');

  final String notes = day.notes ?? '';
  return notes.isEmpty ? detail : '$notes\n$detail';
}

/// The app-wide coordinator instance.
final Provider<ReminderCoordinator> reminderCoordinatorProvider =
    Provider<ReminderCoordinator>(
  ReminderCoordinator.new,
  name: 'reminderCoordinator',
);
