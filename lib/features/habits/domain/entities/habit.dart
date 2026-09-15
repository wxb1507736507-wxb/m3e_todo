/// A habit the user checks off on a schedule: 吃药, 健身, 喝水, whatever they
/// name it.
///
/// Deliberately not a [Todo]. A todo is one piece of work that ends; a habit is
/// a thing that comes back, and it is judged by whether it happened on the days
/// it was supposed to. Modelling that as a todo with a due date would mean
/// re-creating it every morning, and the check-in history — the whole reason to
/// keep it — would have nowhere to live.
library;

import '../../../../core/utils/calendar.dart';

/// Monday-first weekday mask: bit 0 is Monday, bit 6 is Sunday.
///
/// `DateTime.weekday` is 1 (Monday) through 7 (Sunday), so the bit for a weekday
/// is `1 << (weekday - 1)`.
const int kHabitEveryDay = 0x7F;
const int kHabitWeekdays = 0x1F;
const int kHabitWeekends = 0x60;

/// The bit that stands for [weekday] in a habit's mask.
int habitDayBit(int weekday) => 1 << (weekday - 1);

/// How often a habit can ask to be done, in days.
///
/// A single day of the week is the shortest interval that is not "every day" —
/// and "every day" is spelled as a weekday mask — so 2 is the smallest interval
/// that means anything. A year covers the doctor's "once a year" kind of habit
/// without turning the field into a date picker.
const int kHabitMinIntervalDays = 2;
const int kHabitMaxIntervalDays = 366;

/// Whether [days] is an interval a habit can be set to.
bool isValidHabitInterval(int days) =>
    days >= kHabitMinIntervalDays && days <= kHabitMaxIntervalDays;

/// Weekday names in mask order, Monday first, so index 0 is bit 0.
const List<String> kHabitWeekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

/// The emoji a habit can wear.
///
/// Emoji rather than icon names because the same habit is drawn twice: by Flutter
/// in the app, and by a native `RemoteViews` layout on the home screen, which
/// cannot render a Flutter icon. A character travels through both.
const List<String> kHabitEmoji = <String>[
  '💊', '💧', '🏋️', '🏃', '🧘', '🚶',
  '🥗', '😴', '📖', '✍️', '🦷', '🧹',
];

/// A habit that could not be saved because it is not usable as written.
class HabitValidationException implements Exception {
  const HabitValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One habit: what it is called, how it looks, and when it is due.
class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.days,
    required this.createdAt,
    this.intervalDays,
    this.reminderMinutes,
    this.allowNote = true,
    this.color,
  });

  /// Builds a new habit, rejecting the shapes that would leave a dangling entry
  /// in the list: no name, or no day to be due on.
  factory Habit.create({
    required String id,
    required String name,
    required String emoji,
    required int days,
    required DateTime createdAt,
    int? intervalDays,
    int? reminderMinutes,
    bool allowNote = true,
    int? color,
  }) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const HabitValidationException('打卡项需要一个名字');
    }
    final int mask = days & kHabitEveryDay;
    if (intervalDays == null && mask == 0) {
      throw const HabitValidationException('至少要选一天');
    }
    if (intervalDays != null && !isValidHabitInterval(intervalDays)) {
      throw const HabitValidationException('间隔天数不合适');
    }
    return Habit(
      id: id,
      name: trimmed,
      emoji: emoji,
      days: mask,
      createdAt: createdAt,
      intervalDays: intervalDays,
      reminderMinutes: reminderMinutes,
      allowNote: allowNote,
      color: color,
    );
  }

  final String id;
  final String name;

  /// A single emoji, shown in the app list and in the home-screen widget.
  final String emoji;

  /// Which weekdays this habit is due, as a [kHabitEveryDay]-style mask.
  ///
  /// Only consulted when [intervalDays] is `null`: a habit counts its days one
  /// way or the other, never both.
  final int days;

  /// How many days apart this habit comes back, or `null` for a habit that
  /// follows the week instead.
  ///
  /// Counted from [createdAt]'s day, so "每隔 3 天" means today, then the third
  /// day after, and does not drift when the app is not opened.
  final int? intervalDays;

  final DateTime createdAt;

  /// Minutes after local midnight at which to remind, or `null` for a habit that
  /// should stay quiet — "也可选择不提醒" is a first-class choice, not a missing
  /// value to be filled in with a default.
  final int? reminderMinutes;

  /// Whether a check-in may carry a written note. Off means one tap is the whole
  /// interaction, which is what makes a widget check-in worth having.
  final bool allowNote;

  /// Accent colour (ARGB32), or `null` to follow the theme.
  final int? color;

  bool get reminds => reminderMinutes != null;

  /// Whether this habit counts its days by interval rather than by weekday.
  bool get repeatsEveryFewDays => intervalDays != null;

  /// Whether this habit is due on [day]. Only the date is looked at.
  ///
  /// The interval case is a subtraction, not a counter: there is no stored
  /// "next due" date to fall out of step with the calendar, so a habit set up
  /// on a phone that is then left alone for a month is still due on the right
  /// days when it comes back.
  bool isDueOn(DateTime day) {
    final int? interval = intervalDays;
    if (interval != null) {
      final int elapsed = daysBetween(startOfDay(createdAt), day);
      return elapsed >= 0 && elapsed % interval == 0;
    }
    return days & habitDayBit(day.weekday) != 0;
  }

  /// The reminder time as `08:30`, or `null` when there is no reminder.
  String? get reminderLabel {
    final int? minutes = reminderMinutes;
    if (minutes == null) {
      return null;
    }
    final String hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final String minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// How the schedule reads in a list: 每天, 工作日, 周末, 每隔 N 天, or the days
  /// themselves.
  ///
  /// The three common masks get their own words because they are what almost
  /// every habit is, and "一二三四五" makes the reader decode something they
  /// already knew.
  String get scheduleLabel {
    final int? interval = intervalDays;
    if (interval != null) {
      return '每隔 $interval 天';
    }
    if (days == kHabitEveryDay) {
      return '每天';
    }
    if (days == kHabitWeekdays) {
      return '工作日';
    }
    if (days == kHabitWeekends) {
      return '周末';
    }
    final List<String> names = <String>[
      for (int bit = 0; bit < 7; bit++)
        if (days & (1 << bit) != 0) '周${kHabitWeekdayNames[bit]}',
    ];
    return names.join('、');
  }

  Habit edited({
    String? name,
    String? emoji,
    int? days,
    DateTime? createdAt,
    int? intervalDays,
    bool clearInterval = false,
    int? reminderMinutes,
    bool clearReminder = false,
    bool? allowNote,
    int? color,
    bool clearColor = false,
  }) {
    final String nextName = (name ?? this.name).trim();
    if (nextName.isEmpty) {
      throw const HabitValidationException('打卡项需要一个名字');
    }
    final int nextDays = (days ?? this.days) & kHabitEveryDay;
    final int? nextInterval =
        clearInterval ? null : (intervalDays ?? this.intervalDays);
    if (nextInterval == null && nextDays == 0) {
      throw const HabitValidationException('至少要选一天');
    }
    if (nextInterval != null && !isValidHabitInterval(nextInterval)) {
      throw const HabitValidationException('间隔天数不合适');
    }
    return Habit(
      id: id,
      name: nextName,
      emoji: emoji ?? this.emoji,
      days: nextDays,
      createdAt: createdAt ?? this.createdAt,
      intervalDays: nextInterval,
      reminderMinutes:
          clearReminder ? null : (reminderMinutes ?? this.reminderMinutes),
      allowNote: allowNote ?? this.allowNote,
      color: clearColor ? null : (color ?? this.color),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Habit &&
      other.id == id &&
      other.name == name &&
      other.emoji == emoji &&
      other.days == days &&
      other.intervalDays == intervalDays &&
      other.createdAt == createdAt &&
      other.reminderMinutes == reminderMinutes &&
      other.allowNote == allowNote &&
      other.color == color;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        emoji,
        days,
        intervalDays,
        createdAt,
        reminderMinutes,
        allowNote,
        color,
      );

  @override
  String toString() => 'Habit($id, "$name", $scheduleLabel)';
}
