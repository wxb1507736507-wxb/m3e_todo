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
  }) {
    return Habit.create(
      id: id,
      name: name,
      emoji: '💊',
      days: days,
      createdAt: DateTime(2026, 9, 1),
      reminderMinutes: reminderMinutes,
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

  group('widget snapshot', () {
    test("carries today's habits, counts and the day it is counting for", () {
      final DateTime now = DateTime(2026, 9, 16, 7);
      final List<HabitDayStatus> today = <HabitDayStatus>[
        HabitDayStatus(habit: habit('a', reminderMinutes: 480)),
        HabitDayStatus(
          habit: habit('b', name: '健身'),
          log: log('b', now, note: '练了 40 分钟'),
        ),
      ];
      final Map<String, Object?> snapshot = habitWidgetSnapshot(
        today: today,
        now: now,
        dateLabel: '9月16日 周三',
        countLabel: '1/2 已完成',
        countSuffix: '已完成',
        emptyTitle: '今天没有要打卡的项目',
        emptyBody: '在应用里添加打卡项',
      );

      expect(snapshot['done'], 1);
      expect(snapshot['total'], 2);
      expect(snapshot['empty'], false);
      expect(snapshot['dayKey'], habitDayKey(now));
      expect(snapshot['dateLabel'], '9月16日 周三');
      // The words travel apart from the numbers, because the widget recounts on
      // its own when a row is ticked with the app closed.
      expect(snapshot['countSuffix'], '已完成');
      final List<Object?> rows = snapshot['rows']! as List<Object?>;
      expect(rows, hasLength(2));
      final Map<String, Object?> first = rows.first! as Map<String, Object?>;
      expect(first['id'], 'a');
      expect(first['time'], '08:00');
      expect(first['note'], isTrue);
    });

    test('shows at most the rows the widget has, and counts the rest', () {
      final List<HabitDayStatus> today = <HabitDayStatus>[
        for (int i = 0; i < kHabitWidgetRows + 2; i++)
          HabitDayStatus(habit: habit('h$i')),
      ];
      final Map<String, Object?> snapshot = habitWidgetSnapshot(
        today: today,
        now: DateTime(2026, 9, 16),
        dateLabel: '9月16日 周三',
        countLabel: '0/6 已完成',
        countSuffix: '已完成',
        emptyTitle: 't',
        emptyBody: 'b',
      );
      expect((snapshot['rows']! as List<Object?>), hasLength(kHabitWidgetRows));
      // Dropped rows are reported, never silently lost.
      expect(snapshot['overflow'], 2);
    });

    test('an empty day says so instead of showing nothing', () {
      final Map<String, Object?> snapshot = habitWidgetSnapshot(
        today: const <HabitDayStatus>[],
        now: DateTime(2026, 9, 16),
        dateLabel: '9月16日 周三',
        countLabel: '0/0 已完成',
        countSuffix: '已完成',
        emptyTitle: '今天没有要打卡的项目',
        emptyBody: '在应用里添加打卡项',
      );
      expect(snapshot['empty'], isTrue);
      expect(snapshot['emptyTitle'], '今天没有要打卡的项目');
    });
  });
}
