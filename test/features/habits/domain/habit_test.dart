import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/habits/domain/entities/habit.dart';

void main() {
  Habit build({
    String name = '吃药',
    int days = kHabitEveryDay,
    int? reminderMinutes,
    bool allowNote = true,
  }) {
    return Habit.create(
      id: 'h1',
      name: name,
      emoji: '💊',
      days: days,
      createdAt: DateTime(2026, 9, 1),
      reminderMinutes: reminderMinutes,
      allowNote: allowNote,
    );
  }

  group('creation', () {
    test('refuses a habit with no name', () {
      expect(
        () => build(name: '   '),
        throwsA(isA<HabitValidationException>()),
      );
    });

    test('refuses a habit with no day to be due on', () {
      // A habit due on no day would sit in the list forever asking for nothing.
      expect(() => build(days: 0), throwsA(isA<HabitValidationException>()));
    });

    test('trims the name it is given', () {
      expect(build(name: '  吃药  ').name, '吃药');
    });
  });

  group('schedule', () {
    test('a weekday mask decides which days are due', () {
      final Habit weekdays = build(days: kHabitWeekdays);
      // 2026-09-14 is a Monday, 2026-09-19 a Saturday.
      expect(weekdays.isDueOn(DateTime(2026, 9, 14)), isTrue);
      expect(weekdays.isDueOn(DateTime(2026, 9, 19)), isFalse);
      expect(weekdays.isDueOn(DateTime(2026, 9, 20)), isFalse);
    });

    test('a single day is due once a week', () {
      final Habit wednesdays = build(days: habitDayBit(DateTime.wednesday));
      expect(wednesdays.isDueOn(DateTime(2026, 9, 16)), isTrue);
      expect(wednesdays.isDueOn(DateTime(2026, 9, 17)), isFalse);
    });

    test('the three common masks get their own words', () {
      expect(build(days: kHabitEveryDay).scheduleLabel, '每天');
      expect(build(days: kHabitWeekdays).scheduleLabel, '工作日');
      expect(build(days: kHabitWeekends).scheduleLabel, '周末');
    });

    test('anything else lists its days, Monday first', () {
      final Habit custom = build(
        days: habitDayBit(DateTime.monday) | habitDayBit(DateTime.wednesday),
      );
      expect(custom.scheduleLabel, '周一、周三');
    });
  });

  group('reminder', () {
    test('no reminder time means no reminder at all', () {
      final Habit quiet = build();
      expect(quiet.reminds, isFalse);
      expect(quiet.reminderLabel, isNull);
    });

    test('a reminder time is shown as a clock time', () {
      expect(build(reminderMinutes: 8 * 60).reminderLabel, '08:00');
      expect(build(reminderMinutes: 21 * 60 + 5).reminderLabel, '21:05');
    });
  });

  group('editing', () {
    test('keeps the id and the creation date', () {
      final Habit original = build();
      final Habit edited = original.edited(name: '健身', emoji: '🏋️');
      expect(edited.id, original.id);
      expect(edited.createdAt, original.createdAt);
      expect(edited.name, '健身');
      expect(edited.emoji, '🏋️');
    });

    test('a reminder can be cleared without touching the rest', () {
      final Habit withTime = build(reminderMinutes: 480);
      final Habit cleared = withTime.edited(clearReminder: true);
      expect(cleared.reminderMinutes, isNull);
      expect(cleared.name, withTime.name);
    });

    test('an edit that would empty the name is refused', () {
      expect(
        () => build().edited(name: ' '),
        throwsA(isA<HabitValidationException>()),
      );
    });

    test('an edit that would leave no days is refused', () {
      expect(
        () => build().edited(days: 0),
        throwsA(isA<HabitValidationException>()),
      );
    });
  });

  test('equality is by value, so providers can skip a rebuild', () {
    expect(build(), build());
    expect(build(name: '健身') == build(), isFalse);
    expect(build(reminderMinutes: 480) == build(), isFalse);
  });
}
