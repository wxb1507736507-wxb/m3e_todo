import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';

/// Translates between [Habit] and the JSON shape written to disk.
abstract final class HabitModel {
  /// Version 1 is the first shape this document has had.
  static const int schemaVersion = 1;

  static Map<String, Object?> toJson(Habit habit) {
    return <String, Object?>{
      'id': habit.id,
      'name': habit.name,
      'emoji': habit.emoji,
      'days': habit.days,
      'createdAt': habit.createdAt.toIso8601String(),
      // Absent rather than null, and absent rather than `false`: the common
      // habit is "every day, no reminder, notes allowed", and spelling out the
      // defaults on every record would bury the fields that differ.
      if (habit.intervalDays != null) 'intervalDays': habit.intervalDays,
      if (habit.reminderMinutes != null) 'reminderMinutes': habit.reminderMinutes,
      if (!habit.allowNote) 'allowNote': false,
      if (habit.color != null) 'color': habit.color,
    };
  }

  /// Rebuilds a habit, or returns `null` when the record is unusable.
  static Habit? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    final Object? days = json['days'];
    // A mask with no days in it would be a habit that is never due — invisible
    // in every list and impossible to fix from the UI. Falling back to every day
    // keeps a record that was written by something else usable instead of
    // silently dropping the user's habit.
    final int mask = days is int && days & kHabitEveryDay != 0
        ? days & kHabitEveryDay
        : kHabitEveryDay;

    final Object? interval = json['intervalDays'];
    final Object? minutes = json['reminderMinutes'];
    final Object? createdAt = json['createdAt'];
    final Object? color = json['color'];
    return Habit(
      id: id,
      name: name,
      emoji: json['emoji'] is String ? json['emoji']! as String : '✅',
      days: mask,
      createdAt: createdAt is String
          ? (DateTime.tryParse(createdAt) ?? DateTime.now())
          : DateTime.now(),
      // An interval outside what the editor can produce is dropped rather than
      // trusted: the weekday mask is then the schedule, which is always valid.
      intervalDays: interval is int && isValidHabitInterval(interval)
          ? interval
          : null,
      reminderMinutes:
          minutes is int && minutes >= 0 && minutes < 24 * 60 ? minutes : null,
      allowNote: json['allowNote'] is bool ? json['allowNote']! as bool : true,
      color: color is int ? color : null,
    );
  }
}

/// Translates between [HabitLog] and the JSON shape written to disk.
abstract final class HabitLogModel {
  /// Version 1 is the first shape this document has had.
  static const int schemaVersion = 1;

  static Map<String, Object?> toJson(HabitLog log) {
    return <String, Object?>{
      'habitId': log.habitId,
      'dayKey': log.dayKey,
      'at': log.at.toIso8601String(),
      if (log.note != null) 'note': log.note,
    };
  }

  /// Rebuilds a check-in, or returns `null` when the record is unusable.
  static HabitLog? fromJson(Map<String, Object?> json) {
    final Object? habitId = json['habitId'];
    final Object? dayKey = json['dayKey'];
    if (habitId is! String || habitId.isEmpty || dayKey is! int) {
      return null;
    }
    final Object? at = json['at'];
    final Object? note = json['note'];
    return HabitLog(
      habitId: habitId,
      dayKey: dayKey,
      at: at is String ? (DateTime.tryParse(at) ?? DateTime.now()) : DateTime.now(),
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
    );
  }
}
