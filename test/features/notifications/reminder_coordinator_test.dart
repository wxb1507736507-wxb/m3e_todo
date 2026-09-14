import 'package:m3e_todo/features/calendar/domain/entities/special_day.dart';
import 'package:m3e_todo/features/notifications/domain/reminder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/notifications/reminder_coordinator.dart';
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

  group('advance notice', () {
    /// One todo due on the 20th, judged from the 10th.
    PendingReminder planned(ReminderLead lead, {ReminderLead? todoLead}) {
      final Map<String, PendingReminder> result = desiredReminders(
        todos: <Todo>[
          sampleTodo(
            id: 'a',
            dueDate: DateTime(2026, 3, 20),
            reminderLead: todoLead,
          ),
        ],
        reminderMode: ReminderMode.ring,
        lead: lead,
        now: now,
      );
      return result['a']!;
    }

    test('a week of notice fires at 09:00 seven days before the deadline', () {
      expect(planned(ReminderLead.oneWeek).triggerAt, DateTime(2026, 3, 13, 9));
    });

    test('three days, one day and same-day land on the right mornings', () {
      expect(planned(ReminderLead.threeDays).triggerAt, DateTime(2026, 3, 17, 9));
      expect(planned(ReminderLead.oneDay).triggerAt, DateTime(2026, 3, 19, 9));
      expect(planned(ReminderLead.onDue).triggerAt, DateTime(2026, 3, 20, 9));
    });

    test("a todo's own lead beats the app-wide one", () {
      expect(
        planned(ReminderLead.onDue, todoLead: ReminderLead.oneWeek).triggerAt,
        DateTime(2026, 3, 13, 9),
      );
      expect(
        planned(ReminderLead.oneWeek, todoLead: ReminderLead.onDue).triggerAt,
        DateTime(2026, 3, 20, 9),
      );
    });

    test('a lead that no longer fits falls back to the deadline morning', () {
      // Due in two days, asked for a week's notice: the requested moment is
      // already gone. Being reminded late beats not being reminded at all.
      final Map<String, PendingReminder> result = desiredReminders(
        todos: <Todo>[sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 12))],
        reminderMode: ReminderMode.ring,
        lead: ReminderLead.oneWeek,
        now: now,
      );

      expect(result['a']!.triggerAt, DateTime(2026, 3, 12, 9));
    });

    test('a deadline that has also passed is dropped', () {
      final Map<String, PendingReminder> result = desiredReminders(
        todos: <Todo>[sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 10))],
        reminderMode: ReminderMode.ring,
        lead: ReminderLead.oneWeek,
        now: now,
      );

      expect(result, isEmpty);
    });

    test('an early reminder says when the deadline is', () {
      // A week's warning without the date is a puzzle: the title alone says
      // nothing about when.
      expect(planned(ReminderLead.oneWeek).body, contains('3月20日'));
      expect(planned(ReminderLead.onDue).body, '');
    });

    test('the notes survive alongside the deadline', () {
      final Map<String, PendingReminder> result = desiredReminders(
        todos: <Todo>[
          sampleTodo(id: 'a', dueDate: DateTime(2026, 3, 20), notes: '带上合同'),
        ],
        reminderMode: ReminderMode.ring,
        lead: ReminderLead.threeDays,
        now: now,
      );

      expect(result['a']!.body, startsWith('带上合同'));
      expect(result['a']!.body, contains('3月20日'));
    });

    test('a changed lead time is a different reminder', () {
      // The coordinator only schedules what differs from the last plan.
      expect(planned(ReminderLead.oneWeek), isNot(planned(ReminderLead.onDue)));
    });
  });

  group('personal dates', () {
    /// A birthday on 3 October, judged from 10 March.
    SpecialDay birthday({SpecialDayKind kind = SpecialDayKind.birthday}) {
      return SpecialDay.create(
        id: 'd1',
        title: '妈妈生日',
        kind: kind,
        date: DateTime(1996, 10, 3),
      );
    }

    Map<String, PendingReminder> planned({
      List<SpecialDay>? days,
      ReminderLead lead = ReminderLead.onDue,
    }) {
      return desiredSpecialDayReminders(
        days: days ?? <SpecialDay>[birthday()],
        reminderMode: ReminderMode.ring,
        lead: lead,
        now: now,
      );
    }

    test('a birthday reminds on the day itself, every year', () {
      final PendingReminder reminder = planned()['d1']!;
      // Mid-March, so this year's 3 October is still ahead.
      expect(reminder.triggerAt, DateTime(2026, 10, 3, 9));
      expect(reminder.ring, isTrue);
    });

    test('the lead time applies to a birthday too', () {
      // A week's notice is exactly what a birthday wants: time to buy something.
      expect(
        planned(lead: ReminderLead.oneWeek)['d1']!.triggerAt,
        DateTime(2026, 9, 26, 9),
      );
    });

    test('a birthday already past this year waits for the next one', () {
      final SpecialDay passed = SpecialDay.create(
        id: 'd2',
        title: '爸爸生日',
        kind: SpecialDayKind.birthday,
        date: DateTime(1970, 2, 1),
      );
      expect(planned(days: <SpecialDay>[passed])['d2']!.triggerAt,
          DateTime(2027, 2, 1, 9));
    });

    test('a countdown reminds on its target, and stops once it is past', () {
      final SpecialDay upcoming = SpecialDay.create(
        id: 'd3',
        title: '考试',
        kind: SpecialDayKind.countdown,
        date: DateTime(2026, 3, 20),
      );
      expect(planned(days: <SpecialDay>[upcoming])['d3']!.triggerAt,
          DateTime(2026, 3, 20, 9));

      final SpecialDay gone = SpecialDay.create(
        id: 'd4',
        title: '交房租',
        kind: SpecialDayKind.countdown,
        date: DateTime(2026, 3, 7),
      );
      expect(planned(days: <SpecialDay>[gone]), isEmpty);
    });

    test('silent mode keeps birthdays quiet too', () {
      final Map<String, PendingReminder> quiet = desiredSpecialDayReminders(
        days: <SpecialDay>[birthday()],
        reminderMode: ReminderMode.silent,
        now: now,
      );
      expect(quiet['d1']!.ring, isFalse);
      expect(quiet['d1']!.ringtoneUri, isNull);
    });

    test('the notification says which birthday it is', () {
      // "妈妈生日" alone leaves the user to work out which one.
      expect(planned()['d1']!.body, contains('生日'));
      expect(planned()['d1']!.body, contains('30 岁'));
    });
  });
}
