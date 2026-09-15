import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/habits/data/models/habit_model.dart';
import 'package:m3e_todo/features/habits/domain/entities/habit.dart';
import 'package:m3e_todo/features/habits/domain/entities/habit_log.dart';

void main() {
  group('habit json', () {
    test('writes the defaults by leaving them out', () {
      final Habit habit = Habit.create(
        id: 'h1',
        name: '喝水',
        emoji: '💧',
        days: kHabitEveryDay,
        createdAt: DateTime(2026, 9, 1),
      );
      final Map<String, Object?> json = HabitModel.toJson(habit);
      // A record that spells out "every day, no reminder, notes allowed" on
      // every line buries the fields that actually differ.
      expect(json.containsKey('reminderMinutes'), isFalse);
      expect(json.containsKey('allowNote'), isFalse);
      expect(json.containsKey('color'), isFalse);
      expect(json['days'], kHabitEveryDay);
    });

    test('writes the choices that are not the default', () {
      final Habit habit = Habit.create(
        id: 'h1',
        name: '吃药',
        emoji: '💊',
        days: kHabitWeekdays,
        createdAt: DateTime(2026, 9, 1),
        reminderMinutes: 8 * 60,
        allowNote: false,
        color: 0xFFE53935,
      );
      final Map<String, Object?> json = HabitModel.toJson(habit);
      expect(json['reminderMinutes'], 480);
      expect(json['allowNote'], false);
      expect(json['color'], 0xFFE53935);
      expect(json['days'], kHabitWeekdays);
    });

    test('round-trips through the file with everything intact', () {
      final Habit habit = Habit.create(
        id: 'h1',
        name: '健身',
        emoji: '🏋️',
        days: habitDayBit(DateTime.tuesday),
        createdAt: DateTime(2026, 9, 1, 10, 30),
        reminderMinutes: 20 * 60 + 15,
        allowNote: false,
      );
      final Habit restored = HabitModel.fromJson(HabitModel.toJson(habit))!;
      expect(restored, habit);
    });

    test('drops a record with no id or no name', () {
      expect(HabitModel.fromJson(<String, Object?>{'name': '吃药'}), isNull);
      expect(HabitModel.fromJson(<String, Object?>{'id': 'h1'}), isNull);
      expect(
        HabitModel.fromJson(<String, Object?>{'id': 'h1', 'name': '  '}),
        isNull,
      );
    });

    test('a mask with no days in it falls back to every day', () {
      // Otherwise the habit would exist but never be due: invisible in every
      // list, and impossible to fix from the UI.
      final Habit restored = HabitModel.fromJson(<String, Object?>{
        'id': 'h1',
        'name': '吃药',
        'days': 0,
      })!;
      expect(restored.days, kHabitEveryDay);
    });

    test('an impossible reminder time is dropped rather than trusted', () {
      final Habit restored = HabitModel.fromJson(<String, Object?>{
        'id': 'h1',
        'name': '吃药',
        'reminderMinutes': 5000,
      })!;
      expect(restored.reminderMinutes, isNull);
    });

    test('a missing emoji still leaves a usable habit', () {
      final Habit restored = HabitModel.fromJson(<String, Object?>{
        'id': 'h1',
        'name': '吃药',
      })!;
      expect(restored.emoji, isNotEmpty);
    });
  });

  group('habit log json', () {
    test('round-trips a check-in with its note', () {
      final HabitLog log = HabitLog(
        habitId: 'h1',
        dayKey: 20260915,
        at: DateTime(2026, 9, 15, 7, 30),
        note: '早上吃的',
      );
      expect(HabitLogModel.fromJson(HabitLogModel.toJson(log)), log);
    });

    test('a check-in without a note omits the key entirely', () {
      final HabitLog log = HabitLog(
        habitId: 'h1',
        dayKey: 20260915,
        at: DateTime(2026, 9, 15, 7, 30),
      );
      expect(HabitLogModel.toJson(log).containsKey('note'), isFalse);
      expect(HabitLogModel.fromJson(HabitLogModel.toJson(log))!.hasNote, isFalse);
    });

    test('blank notes are treated as no note at all', () {
      expect(
        HabitLogModel.fromJson(<String, Object?>{
          'habitId': 'h1',
          'dayKey': 20260915,
          'note': '   ',
        })!
            .hasNote,
        isFalse,
      );
    });

    test('drops a record that does not name a habit or a day', () {
      expect(HabitLogModel.fromJson(<String, Object?>{'dayKey': 1}), isNull);
      expect(HabitLogModel.fromJson(<String, Object?>{'habitId': 'h1'}), isNull);
    });

    test('the day key survives the round trip', () {
      final DateTime day = DateTime(2026, 12, 31);
      expect(habitDayFromKey(habitDayKey(day)), DateTime(2026, 12, 31));
    });
  });
}
