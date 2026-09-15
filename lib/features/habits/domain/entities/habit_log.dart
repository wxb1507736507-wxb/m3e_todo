/// One check-in: the fact that [habitId] happened on a day.
///
/// Identity is `(habitId, dayKey)` rather than a generated id. A habit can only
/// be done once a day — pressing the widget button twice is the same fact, not
/// two facts — so making the pair the key is what stops a double tap from
/// creating a duplicate, and what makes "undo" a delete of one known row.
library;

/// A calendar day as a single integer: `20260915`.
///
/// The same packing the calendar's own `dayKey` uses, and for the same reason:
/// a set of ints is what a log needs to be compared and grouped cheaply.
int habitDayKey(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

/// The day `key` stands for, at local midnight.
DateTime habitDayFromKey(int key) =>
    DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);

class HabitLog {
  const HabitLog({
    required this.habitId,
    required this.dayKey,
    required this.at,
    this.note,
  });

  final String habitId;

  /// The day this check-in counts for, as [habitDayKey].
  final int dayKey;

  /// When the check-in was actually made.
  ///
  /// Kept apart from [dayKey] on purpose: checking off yesterday's habit at
  /// 00:10 still belongs to yesterday, and the widget can log a check-in for
  /// today before the app has ever been opened.
  final DateTime at;

  /// What the user wrote, when the habit allows it and they chose to. `null` is
  /// the normal case — "打卡内容可以选择增加文字记录，也可以选择不增加".
  final String? note;

  DateTime get day => habitDayFromKey(dayKey);

  bool get hasNote => note != null && note!.trim().isNotEmpty;

  HabitLog withNote(String? note) {
    final String? trimmed = note?.trim();
    return HabitLog(
      habitId: habitId,
      dayKey: dayKey,
      at: at,
      note: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HabitLog &&
      other.habitId == habitId &&
      other.dayKey == dayKey &&
      other.at == at &&
      other.note == note;

  @override
  int get hashCode => Object.hash(habitId, dayKey, at, note);

  @override
  String toString() => 'HabitLog($habitId, $dayKey${hasNote ? ", note" : ""})';
}
