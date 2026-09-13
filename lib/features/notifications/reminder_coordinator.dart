import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../settings/domain/app_settings.dart';
import '../settings/presentation/settings_controller.dart';
import '../todos/domain/entities/todo.dart';
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
  });

  final DateTime triggerAt;
  final String title;
  final String body;
  final bool ring;

  @override
  bool operator ==(Object other) =>
      other is PendingReminder &&
      other.triggerAt == triggerAt &&
      other.title == title &&
      other.body == body &&
      other.ring == ring;

  @override
  int get hashCode => Object.hash(triggerAt, title, body, ring);
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
    final Map<String, PendingReminder> desired =
        _desiredReminders(todos, _ref.read(settingsProvider).reminderMode);

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
  /// settings changed (ring vs silent), which does not touch the todo list.
  Future<void> resync() async {
    final List<Todo>? todos = _ref.read(todoListProvider).value;
    if (todos != null) {
      await sync(todos);
    }
  }

  Map<String, PendingReminder> _desiredReminders(
    List<Todo> todos,
    ReminderMode reminderMode,
  ) {
    return desiredReminders(
      todos: todos,
      reminderMode: reminderMode,
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
/// a reminder, and when it fires), and a pure function can be tested without an
/// Android device or a mocked method channel — which is exactly what the rest of
/// the coordinator cannot be.
Map<String, PendingReminder> desiredReminders({
  required List<Todo> todos,
  required ReminderMode reminderMode,
  required DateTime now,
}) {
  final bool ring = reminderMode == ReminderMode.ring;
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
    result[todo.id] = PendingReminder(
      triggerAt: trigger,
      title: todo.title,
      body: todo.notes ?? '',
      ring: ring,
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
