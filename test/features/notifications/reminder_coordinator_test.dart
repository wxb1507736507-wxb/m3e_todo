import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/notifications/reminder_coordinator.dart';
import 'package:m3e_todo/features/settings/domain/app_settings.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_reminder.dart';

import '../../support/sample_todo.dart';

/// The clock the planner is judged against: 2026-03-10 09:30, i.e. *after*
/// 09:00 on the 10th, which is what makes same-day reminders interesting.
final DateTime now = testNow;

void main() {
  test('a future due date gets a reminder at 09:00 on that day', () {
    final Map<String, PendingReminder> planned = desiredReminders(
      todos: <Todo>[sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 12))],
      reminderMode: ReminderMode.ring,
      now: now,
    );

    expect(planned.keys, <String>['a']);
    expect(planned['a']!.triggerAt, DateTime(2026, 3, 12, 9));
    expect(planned['a']!.ring, isTrue);
  });

  test('silent mode plans the same times but asks for no sound', () {
    final Map<String, PendingReminder> planned = desiredReminders(
      todos: <Todo>[sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 12))],
      reminderMode: ReminderMode.silent,
      now: now,
    );

    expect(planned['a']!.triggerAt, DateTime(2026, 3, 12, 9));
    expect(planned['a']!.ring, isFalse);
  });

  test('a todo with no due date is not planned', () {
    expect(
      desiredReminders(
        todos: <Todo>[sampleTodo(id: 'a')],
        reminderMode: ReminderMode.ring,
        now: now,
      ),
      isEmpty,
    );
  });

  test('a completed todo is not planned', () {
    expect(
      desiredReminders(
        todos: <Todo>[
          sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 12)).completeAt(now),
        ],
        reminderMode: ReminderMode.ring,
        now: now,
      ),
      isEmpty,
    );
  });

  test("today's reminder is dropped once 09:00 has passed", () {
    // It is 09:30, so a 09:00 trigger today would fire immediately.
    expect(
      desiredReminders(
        todos: <Todo>[sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 10))],
        reminderMode: ReminderMode.ring,
        now: now,
      ),
      isEmpty,
    );
  });

  test("today's reminder survives when the hour has not arrived yet", () {
    final Map<String, PendingReminder> planned = desiredReminders(
      todos: <Todo>[sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 10))],
      reminderMode: ReminderMode.ring,
      now: DateTime(2026, 3, 10, 7),
    );

    expect(planned['a']!.triggerAt, DateTime(2026, 3, 10, 9));
  });

  test('an overdue todo is not planned', () {
    expect(
      desiredReminders(
        todos: <Todo>[sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 8))],
        reminderMode: ReminderMode.ring,
        now: now,
      ),
      isEmpty,
    );
  });

  test('the notes become the notification body, empty when there are none', () {
    final Map<String, PendingReminder> planned = desiredReminders(
      todos: <Todo>[
        sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 12), notes: '带上发票'),
        sampleTodo(id: 'b', dueDate: DateTime(2026, 3, 12)),
      ],
      reminderMode: ReminderMode.ring,
      now: now,
    );

    expect(planned['a']!.body, '带上发票');
    expect(planned['b']!.body, '');
    expect(planned['a']!.title, '写周报');
  });

  test('the plan is keyed by todo id, so an edit replaces rather than adds', () {
    final Map<String, PendingReminder> planned = desiredReminders(
      todos: <Todo>[
        sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 12)),
        sampleTodo(id: 'a', title: '改过的', dueDate: DateTime(2026, 3, 13)),
      ],
      reminderMode: ReminderMode.ring,
      now: now,
    );

    expect(planned, hasLength(1));
    expect(planned['a']!.triggerAt, DateTime(2026, 3, 13, 9));
  });

  group('per-todo choices', () {
    /// One dated todo asking for [reminder], judged against an app whose own
    /// default is [defaultMode].
    PendingReminder planned(
      TodoReminder reminder, {
      ReminderMode defaultMode = ReminderMode.silent,
      String? todoRingtone,
      String? defaultRingtone,
    }) {
      final Map<String, PendingReminder> result = desiredReminders(
        todos: <Todo>[
          sampleTodo(
            id: 'a',
            dueDate: DateTime(2026, 3, 12),
            reminder: reminder,
            ringtoneUri: todoRingtone,
          ),
        ],
        reminderMode: defaultMode,
        ringtoneUri: defaultRingtone,
        now: now,
      );
      return result['a']!;
    }

    test('a todo can ring even when the app default is silent', () {
      expect(planned(TodoReminder.ring).ring, isTrue);
    });

    test('a todo can stay quiet even when the app default rings', () {
      expect(
        planned(TodoReminder.silent, defaultMode: ReminderMode.ring).ring,
        isFalse,
      );
    });

    test('following the app default keeps following it', () {
      expect(
        planned(TodoReminder.followApp, defaultMode: ReminderMode.ring).ring,
        isTrue,
      );
      expect(
        planned(TodoReminder.followApp, defaultMode: ReminderMode.silent).ring,
        isFalse,
      );
    });

    test("a todo's own ringtone beats the app-wide one", () {
      expect(
        planned(
          TodoReminder.ring,
          defaultMode: ReminderMode.ring,
          todoRingtone: 'content://todo',
          defaultRingtone: 'content://app',
        ).ringtoneUri,
        'content://todo',
      );
    });

    test('a todo with no ringtone of its own uses the app-wide one', () {
      expect(
        planned(
          TodoReminder.ring,
          defaultMode: ReminderMode.ring,
          defaultRingtone: 'content://app',
        ).ringtoneUri,
        'content://app',
      );
    });

    test('a quiet todo carries no sound, even one it picked earlier', () {
      // Otherwise the native side would be handed a ringtone and a "silent"
      // flag at once, and which one wins would depend on the platform.
      final PendingReminder quiet = planned(
        TodoReminder.silent,
        todoRingtone: 'content://todo',
      );
      expect(quiet.ring, isFalse);
      expect(quiet.ringtoneUri, isNull);
    });

    test('changing a todo from ringing to quiet is a different reminder', () {
      // The coordinator schedules only what differs from the last plan, so a
      // change the planner does not report would leave the device ringing after
      // the user asked for silence.
      final PendingReminder ringing = planned(
        TodoReminder.ring,
        defaultMode: ReminderMode.ring,
      );
      final PendingReminder quiet = planned(
        TodoReminder.silent,
        defaultMode: ReminderMode.ring,
      );
      expect(quiet, isNot(ringing));

      final PendingReminder otherTone = planned(
        TodoReminder.ring,
        defaultMode: ReminderMode.ring,
        todoRingtone: 'content://todo',
      );
      expect(otherTone, isNot(ringing));
    });
  });
}
