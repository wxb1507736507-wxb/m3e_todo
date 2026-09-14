import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../settings/domain/app_settings.dart';
import '../settings/presentation/settings_controller.dart';
import '../todos/domain/entities/todo.dart';
import '../todos/domain/entities/todo_reminder.dart';
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

  /// Applies the difference between [todos] and the last scheduled set.
  Future<void> sync(List<Todo> todos) async {
    final AppSettings settings = _ref.read(settingsProvider);
    final Map<String, PendingReminder> desired = _desiredReminders(todos, settings);

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

    await AppPlatform.cancelAlarms(toCancel);
    await AppPlatform.scheduleAlarms(toSchedule);

    _scheduled
      ..clear()
      ..addAll(desired);
  }

  /// Recomputes the schedule from the current collection; used when only the
  /// defaults changed (ring vs silent, or the default ringtone), which does not
  /// touch the todo list itself.
  ///
  /// Todos that carry their own choice are unaffected by construction: their
  /// planned reminder is identical before and after, so the diff leaves them
  /// alone.
  Future<void> resync() async {
    final List<Todo>? todos = _ref.read(todoListProvider).value;
    if (todos != null) {
      await sync(todos);
    }
  }

  Map<String, PendingReminder> _desiredReminders(
    List<Todo> todos,
    AppSettings settings,
  ) {
    return desiredReminders(
      todos: todos,
      reminderMode: settings.reminderMode,
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
/// [reminderMode] and [ringtoneUri] are the *app-wide defaults*: a todo that
/// carries its own choice wins, and one that does not keeps following the
/// defaults — including when they change later.
Map<String, PendingReminder> desiredReminders({
  required List<Todo> todos,
  required ReminderMode reminderMode,
  required DateTime now,
  String? ringtoneUri,
}) {
  final Map<String, PendingReminder> result = <String, PendingReminder>{};

  for (final Todo todo in todos) {
    final DateTime? due = todo.dueDate;
    // Finished work and undated work both have nothing to remind about.
    if (todo.isCompleted || due == null) {
      continue;
    }
    final DateTime trigger = DateTime(
      due.year,
      due.month,
      due.day,
      _reminderHour,
      _reminderMinute,
    );
    // A trigger already in the past would fire the instant it was scheduled,
    // which is worse than staying quiet: the list already marks such todos
    // overdue, so the user is not left uninformed.
    if (!trigger.isAfter(now)) {
      continue;
    }
    final bool ring = switch (todo.reminder) {
      TodoReminder.followApp => reminderMode == ReminderMode.ring,
      TodoReminder.ring => true,
      TodoReminder.silent => false,
    };
    result[todo.id] = PendingReminder(
      triggerAt: trigger,
      title: todo.title,
      body: todo.notes ?? '',
      ring: ring,
      // Resolved here rather than natively: "follow the app setting" is a Dart
      // concept, and the native side should only ever be handed a decision.
      ringtoneUri: ring ? (todo.ringtoneUri ?? ringtoneUri) : null,
    );
  }
  return result;
}

/// The app-wide coordinator instance.
final Provider<ReminderCoordinator> reminderCoordinatorProvider =
    Provider<ReminderCoordinator>(
  ReminderCoordinator.new,
  name: 'reminderCoordinator',
);
