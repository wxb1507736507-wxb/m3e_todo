import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/habits/domain/entities/habit.dart';
import 'package:m3e_todo/features/habits/domain/entities/habit_log.dart';
import 'package:m3e_todo/features/habits/domain/habit_planner.dart';

void main() {
  /// A habit due every day, with the given id and reminder.
  Habit habit(
    String id, {
    String name = '吃药',
    int days = kHabitEveryDay,
    int? reminderMinutes,
    bool allowNote = true,
  }) {
    return Habit.create(
      id: id,
      name: name,
      emoji: '💊',
      days: days,
      createdAt: DateTime(2026, 9, 1),
      reminderMinutes: reminderMinutes,
      allowNote: allowNote,
    );
  }

  HabitLog log(String habitId, DateTime day, {String? note}) => HabitLog(
        habitId: habitId,
        dayKey: habitDayKey(day),
        at: day,
        note: note,
      );

  group('habitsDueOn', () {
    test('keeps only the habits whose own days include this one', () {
      final List<Habit> habits = <Habit>[
        habit('daily'),
        habit('weekends', days: kHabitWeekends),
        habit('mondays', days: habitDayBit(DateTime.monday)),
      ];
      // 2026-09-16 is a Wednesday.
      final List<HabitDayStatus> due =
          habitsDueOn(habits, const <HabitLog>[], DateTime(2026, 9, 16));
      expect(due.map((HabitDayStatus s) => s.habit.id), <String>['daily']);
    });

    test("pairs each habit with that day's check-in, and no other day's", () {
      final List<Habit> habits = <Habit>[habit('daily')];
      final List<HabitLog> logs = <HabitLog>[
        log('daily', DateTime(2026, 9, 16), note: '早上吃的'),
        log('daily', DateTime(2026, 9, 15)),
      ];
      final List<HabitDayStatus> due =
          habitsDueOn(habits, logs, DateTime(2026, 9, 16));
      expect(due.single.done, isTrue);
      expect(due.single.note, '早上吃的');
    });

    test('orders by reminder time, with the untimed ones last', () {
      final List<Habit> habits = <Habit>[
        habit('anytime', name: '喝水'),
        habit('evening', name: '健身', reminderMinutes: 20 * 60),
        habit('morning', name: '吃药', reminderMinutes: 8 * 60),
      ];
      final List<HabitDayStatus> due =
          habitsDueOn(habits, const <HabitLog>[], DateTime(2026, 9, 16));
      expect(
        due.map((HabitDayStatus s) => s.habit.id),
        <String>['morning', 'evening', 'anytime'],
      );
    });
  });

  group('streak', () {
    final DateTime today = DateTime(2026, 9, 16);

    test('counts back over consecutive due days', () {
      final Habit daily = habit('h');
      final Set<int> days = <int>{
        habitDayKey(today),
        habitDayKey(today.subtract(const Duration(days: 1))),
        habitDayKey(today.subtract(const Duration(days: 2))),
      };
      expect(habitStreak(habit: daily, doneDays: days, today: today), 3);
    });

    test("today being unchecked does not break yesterday's run", () {
      final Habit daily = habit('h');
      final Set<int> days = <int>{
        habitDayKey(today.subtract(const Duration(days: 1))),
        habitDayKey(today.subtract(const Duration(days: 2))),
      };
      // It is not "lost" until the day is over.
      expect(habitStreak(habit: daily, doneDays: days, today: today), 2);
    });

    test('a missed due day ends the streak', () {
      final Habit daily = habit('h');
      final Set<int> days = <int>{
        habitDayKey(today),
        habitDayKey(today.subtract(const Duration(days: 1))),
        // Nothing two days ago, but something three days ago.
        habitDayKey(today.subtract(const Duration(days: 3))),
      };
      expect(habitStreak(habit: daily, doneDays: days, today: today), 2);
    });

    test('days the habit is not due are skipped, not counted as misses', () {
      // 2026-09-16 is a Wednesday; a Monday-only habit due on the 14th.
      final Habit mondays = habit('h', days: habitDayBit(DateTime.monday));
      final Set<int> days = <int>{
        habitDayKey(DateTime(2026, 9, 14)),
        habitDayKey(DateTime(2026, 9, 7)),
      };
      expect(
        habitStreak(habit: mondays, doneDays: days, today: DateTime(2026, 9, 16)),
        2,
      );
    });

    test('a habit never checked off has no streak and cannot hang the loop', () {
      expect(
        habitStreak(habit: habit('h'), doneDays: const <int>{}, today: today),
        0,
      );
    });
  });

  group('recent days', () {
    test('marks kept, missed and not-due days, oldest first', () {
      final DateTime today = DateTime(2026, 9, 16); // Wednesday
      final Habit daily = habit('h');
      final List<HabitDayMark> marks = habitRecentDays(
        habit: daily,
        doneDays: <int>{habitDayKey(today)},
        today: today,
      );
      expect(marks, hasLength(7));
      expect(marks.last, HabitDayMark.done);
      // The days before were due and missed.
      expect(marks.first, HabitDayMark.missed);
    });

    test('today is not marked as missed before it is over', () {
      final DateTime today = DateTime(2026, 9, 16);
      final List<HabitDayMark> marks = habitRecentDays(
        habit: habit('h'),
        doneDays: const <int>{},
        today: today,
      );
      expect(marks.last, HabitDayMark.notDue);
    });

    test('a day the habit is not due reads as neither kept nor missed', () {
      final DateTime today = DateTime(2026, 9, 16);
      final Habit sundays = habit('h', days: habitDayBit(DateTime.sunday));
      final List<HabitDayMark> marks = habitRecentDays(
        habit: sundays,
        doneDays: const <int>{},
        today: today,
      );
      // The window runs from the 10th to the 16th, so it holds exactly one
      // Sunday — which was due and went unchecked, and is therefore missed. The
      // other six days ask nothing of this habit and are not held against it.
      expect(
        marks.where((HabitDayMark m) => m == HabitDayMark.missed),
        hasLength(1),
      );
      expect(
        marks.where((HabitDayMark m) => m == HabitDayMark.notDue),
        hasLength(6),
      );
    });
  });

  group('next trigger', () {
    test('no reminder time means no trigger at all', () {
      expect(
        nextHabitTrigger(habit: habit('h'), now: DateTime(2026, 9, 16, 7)),
        isNull,
      );
    });

    test('today still ahead is today', () {
      final DateTime trigger = nextHabitTrigger(
        habit: habit('h', reminderMinutes: 8 * 60),
        now: DateTime(2026, 9, 16, 7),
      )!;
      expect(trigger, DateTime(2026, 9, 16, 8));
    });

    test('a time already past rolls to the next due day', () {
      final DateTime trigger = nextHabitTrigger(
        habit: habit('h', reminderMinutes: 8 * 60),
        now: DateTime(2026, 9, 16, 9),
      )!;
      expect(trigger, DateTime(2026, 9, 17, 8));
    });

    test('skipToday is how a checked-off habit stops nagging', () {
      final DateTime trigger = nextHabitTrigger(
        habit: habit('h', reminderMinutes: 8 * 60),
        now: DateTime(2026, 9, 16, 7),
        skipToday: true,
      )!;
      expect(trigger, DateTime(2026, 9, 17, 8));
    });

    test('a weekly habit skips the days it is not due', () {
      // Wednesday 2026-09-16, asking for the next Monday.
      final DateTime trigger = nextHabitTrigger(
        habit: habit('h', days: habitDayBit(DateTime.monday), reminderMinutes: 8 * 60),
        now: DateTime(2026, 9, 16, 9),
      )!;
      expect(trigger, DateTime(2026, 9, 21, 8));
    });
  });

  group('interval habits', () {
    Habit everyOtherDay() => Habit.create(
          id: 'h',
          name: '浇花',
          emoji: '💧',
          days: kHabitEveryDay,
          createdAt: DateTime(2026, 9, 16),
          intervalDays: 2,
        );

    test('are listed only on their own days', () {
      final List<Habit> habits = <Habit>[everyOtherDay()];
      expect(
        habitsDueOn(habits, const <HabitLog>[], DateTime(2026, 9, 16)),
        hasLength(1),
      );
      expect(
        habitsDueOn(habits, const <HabitLog>[], DateTime(2026, 9, 17)),
        isEmpty,
      );
      expect(
        habitsDueOn(habits, const <HabitLog>[], DateTime(2026, 9, 18)),
        hasLength(1),
      );
    });

    test('a streak counts their days and ignores the days between', () {
      final Habit habit = everyOtherDay();
      // 16th, 18th and 20th are its days; the 18th is today.
      final Set<int> days = <int>{
        habitDayKey(DateTime(2026, 9, 16)),
        habitDayKey(DateTime(2026, 9, 18)),
      };
      expect(
        habitStreak(habit: habit, doneDays: days, today: DateTime(2026, 9, 18)),
        2,
      );
    });

    test('their next reminder lands on the next due day, not tomorrow', () {
      final Habit habit = Habit.create(
        id: 'h',
        name: '浇花',
        emoji: '💧',
        days: kHabitEveryDay,
        createdAt: DateTime(2026, 9, 16),
        intervalDays: 3,
        reminderMinutes: 8 * 60,
      );
      final DateTime? trigger = nextHabitTrigger(
        habit: habit,
        now: DateTime(2026, 9, 16, 9),
      );
      expect(trigger, DateTime(2026, 9, 19, 8));
    });
  });

  group('widget payload', () {
    Map<String, Object?> payload({
      required List<Habit> habits,
      List<HabitLog> logs = const <HabitLog>[],
      DateTime? now,
    }) {
      return habitWidgetPayload(
        habits: habits,
        logs: logs,
        now: now ?? DateTime(2026, 9, 16, 7),
        todoSub: '今天还没打卡',
        doneSub: '已完成',
        offSub: '今天不用打卡',
        emptyTitle: '还没有打卡项',
        emptyBody: '在应用里添加打卡项',
        staleText: '新的一天了，打开应用刷新',
        unconfiguredText: '还没选择打卡项',
        missingText: '这个打卡项已删除',
      );
    }

    Map<String, Object?> tile(Map<String, Object?> payload, String id) =>
        (payload['tiles']! as Map<String, Object?>)[id]! as Map<String, Object?>;

    test('carries every habit, not only the ones due today', () {
      // Each widget is configured to one habit, so a habit that is not due today
      // still has to be able to say so rather than looking deleted.
      final Map<String, Object?> result = payload(
        habits: <Habit>[
          habit('a', reminderMinutes: 480),
          habit('b', name: '周一瑜伽', days: habitDayBit(DateTime.monday)),
        ],
      );

      expect(result['dayKey'], habitDayKey(DateTime(2026, 9, 16)));
      expect(result['empty'], isFalse);
      expect((result['tiles']! as Map<String, Object?>).keys, containsAll(<String>['a', 'b']));
      expect(tile(result, 'a')['due'], isTrue);
      expect(tile(result, 'b')['due'], isFalse);
      // The words travel once per payload, the facts once per habit: the widget
      // re-words the line itself when a tap flips done with the app closed.
      expect(result['subOff'], '今天不用打卡');
      expect(tile(result, 'b')['details'], '');
    });

    test('a ticked habit reads as done, with its time and streak', () {
      final DateTime now = DateTime(2026, 9, 16, 7);
      final Map<String, Object?> result = payload(
        habits: <Habit>[habit('a', reminderMinutes: 480)],
        logs: <HabitLog>[log('a', now, note: '早上吃的')],
        now: now,
      );
      final Map<String, Object?> first = tile(result, 'a');
      expect(first['done'], isTrue);
      expect(first['details'], '08:00 · 1 天');
      expect(first['emoji'], '💊');
      expect(first['name'], '吃药');
      expect(result['subDone'], '已完成');
    });

    test('an un-ticked habit with a reminder shows the time', () {
      final Map<String, Object?> result = payload(
        habits: <Habit>[habit('a', reminderMinutes: 480)],
      );
      expect(tile(result, 'a')['details'], '08:00');
      expect(tile(result, 'a')['done'], isFalse);
    });

    test('a habit with nothing to say has no details to show', () {
      final Map<String, Object?> result = payload(habits: <Habit>[habit('a')]);
      expect(tile(result, 'a')['details'], '');
      expect(result['subTodo'], '今天还没打卡');
    });

    test('the ＋ is only offered where a note would be kept', () {
      final Map<String, Object?> result = payload(
        habits: <Habit>[
          habit('a'),
          habit('b', name: '健身', allowNote: false),
        ],
      );
      expect(tile(result, 'a')['note'], isTrue);
      expect(tile(result, 'b')['note'], isFalse);
    });

    test('no habits at all says so instead of drawing an empty tile', () {
      final Map<String, Object?> result = payload(habits: const <Habit>[]);
      expect(result['empty'], isTrue);
      expect(result['emptyTitle'], '还没有打卡项');
      expect(result['tiles'], isEmpty);
    });
  });
}
