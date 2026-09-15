/// The rules a habit follows, as pure functions.
///
/// Kept out of the widgets and the controllers for the same reason the reminder
/// rules are: "is this due today", "how long is the streak" and "when does the
/// next alarm go" are the parts that can be wrong, and as pure functions they can
/// be tested without a device, a clock or a channel.
library;

import '../../../core/utils/calendar.dart';
import 'entities/habit.dart';
import 'entities/habit_log.dart';

/// How many habits the home-screen widget can show at once.
///
/// The widget's layout has this many fixed rows: a `RemoteViews` cannot inflate
/// a variable-length list without a collection service, and four is what fits a
/// 4×2 cell without scrolling. Anything beyond it is reported as a count rather
/// than silently dropped.
const int kHabitWidgetRows = 4;

/// One habit as it stands on a particular day.
class HabitDayStatus {
  const HabitDayStatus({required this.habit, this.log});

  final Habit habit;

  /// The check-in for that day, or `null` when it has not happened.
  final HabitLog? log;

  bool get done => log != null;

  String? get note => log?.note;

  @override
  bool operator ==(Object other) =>
      other is HabitDayStatus && other.habit == habit && other.log == log;

  @override
  int get hashCode => Object.hash(habit, log);
}

/// The habits due on [day], each paired with that day's check-in.
///
/// Ordered by reminder time and then by name, because a habit is a thing you do
/// at a time of day: 早上吃药 belongs above 晚上健身, and a habit with no reminder
/// sorts last rather than first, where a `null` would otherwise land.
List<HabitDayStatus> habitsDueOn(
  List<Habit> habits,
  List<HabitLog> logs,
  DateTime day,
) {
  final int key = habitDayKey(day);
  final Map<String, HabitLog> byHabit = <String, HabitLog>{
    for (final HabitLog log in logs)
      if (log.dayKey == key) log.habitId: log,
  };

  final List<Habit> due = <Habit>[
    for (final Habit habit in habits)
      if (habit.isDueOn(day)) habit,
  ]..sort((Habit a, Habit b) {
      final int? left = a.reminderMinutes;
      final int? right = b.reminderMinutes;
      if (left != right) {
        if (left == null) {
          return 1;
        }
        if (right == null) {
          return -1;
        }
        return left.compareTo(right);
      }
      return a.name.compareTo(b.name);
    });

  return <HabitDayStatus>[
    for (final Habit habit in due)
      HabitDayStatus(habit: habit, log: byHabit[habit.id]),
  ];
}

/// The day keys on which [habitId] was checked off.
Set<int> doneDaysFor(List<HabitLog> logs, String habitId) => <int>{
      for (final HabitLog log in logs)
        if (log.habitId == habitId) log.dayKey,
    };

/// How many days in a row the habit has been kept, counting back from [today].
///
/// Only days the habit was actually due are counted, so a Monday/Wednesday habit
/// is not punished for Tuesday. Today itself does not break a streak that is
/// still winnable: at 08:00, before the day's check-in, yesterday's run is still
/// intact — it is only lost once the day is over.
int habitStreak({
  required Habit habit,
  required Set<int> doneDays,
  required DateTime today,
}) {
  DateTime cursor = startOfDay(today);
  if (habit.isDueOn(cursor) && !doneDays.contains(habitDayKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }

  int streak = 0;
  // Ten years is not a limit anyone will meet; it is a stop for a habit whose
  // mask is empty or whose clock is wrong, so this can never spin forever.
  for (int guard = 0; guard < 3660; guard++) {
    if (habit.isDueOn(cursor)) {
      if (!doneDays.contains(habitDayKey(cursor))) {
        break;
      }
      streak++;
    }
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// How many times the habit has been checked off in total, including days it was
/// not due on — a check-in made on an off day still happened.
int habitTotal(Set<int> doneDays) => doneDays.length;

/// How a recent day looks for a habit.
enum HabitDayMark {
  /// The habit was not due that day; it asks nothing of anyone.
  notDue,

  /// Due and checked off.
  done,

  /// Due and missed.
  missed,
}

/// The last [count] days for [habit], oldest first, for the little row of marks
/// under a habit in the list.
///
/// Today counts as neither done nor missed until it is over: showing a red mark
/// for this morning's un-checked habit would be a scolding rather than a record.
List<HabitDayMark> habitRecentDays({
  required Habit habit,
  required Set<int> doneDays,
  required DateTime today,
  int count = 7,
}) {
  final DateTime end = startOfDay(today);
  return <HabitDayMark>[
    for (int offset = count - 1; offset >= 0; offset--)
      () {
        final DateTime day = end.subtract(Duration(days: offset));
        if (!habit.isDueOn(day)) {
          return HabitDayMark.notDue;
        }
        if (doneDays.contains(habitDayKey(day))) {
          return HabitDayMark.done;
        }
        // Not yet due (today, before the fact) is reported as "not due" for the
        // mark's purposes: nothing has been missed.
        return offset == 0 ? HabitDayMark.notDue : HabitDayMark.missed;
      }(),
  ];
}

/// When this habit's reminder should next fire, or `null` when it has none or
/// none of its days are ahead.
///
/// [skipToday] is the case that matters after a check-in: the alarm for today
/// would otherwise still go off at 20:00 for a habit already ticked at 07:00.
DateTime? nextHabitTrigger({
  required Habit habit,
  required DateTime now,
  bool skipToday = false,
}) {
  final int? minutes = habit.reminderMinutes;
  if (minutes == null) {
    return null;
  }
  final DateTime start = startOfDay(now);
  for (int offset = 0; offset <= 7; offset++) {
    if (offset == 0 && skipToday) {
      continue;
    }
    final DateTime day = start.add(Duration(days: offset));
    if (!habit.isDueOn(day)) {
      continue;
    }
    final DateTime at = day.add(Duration(minutes: minutes));
    if (at.isAfter(now)) {
      return at;
    }
  }
  return null;
}

/// The payload the home-screen widget draws itself from.
///
/// A plain map because it crosses the method channel into a Kotlin
/// `RemoteViews`; the shape is fixed and mirrored in `HabitWidgetProvider`, so
/// both sides must be changed together.
Map<String, Object?> habitWidgetSnapshot({
  required List<HabitDayStatus> today,
  required DateTime now,
  required String dateLabel,
  required String countLabel,
  required String countSuffix,
  required String emptyTitle,
  required String emptyBody,
}) {
  final List<HabitDayStatus> rows = today.take(kHabitWidgetRows).toList();
  final int done = today.where((HabitDayStatus status) => status.done).length;

  return <String, Object?>{
    'dateLabel': dateLabel,
    'countLabel': countLabel,
    // The numbers and the words are sent apart as well as together: the widget
    // recounts on its own when a row is ticked with the app closed, and it can
    // only rebuild the line if it knows which part of it is a number.
    'countSuffix': countSuffix,
    'done': done,
    'total': today.length,
    'empty': today.isEmpty,
    'emptyTitle': emptyTitle,
    'emptyBody': emptyBody,
    'overflow': today.length - rows.length,
    'rows': <Object?>[
      for (final HabitDayStatus status in rows)
        <String, Object?>{
          'id': status.habit.id,
          'emoji': status.habit.emoji,
          'name': status.habit.name,
          'done': status.done,
          // Only habits that allow a note get the widget's ＋ affordance: an
          // offer to write something the habit does not accept is worse than no
          // offer at all.
          'note': status.habit.allowNote,
          'time': status.habit.reminderLabel,
        },
    ],
    // Sent along because the widget can log a check-in without the app ever
    // running: it needs the day it is counting for, not the day it happens to be
    // rendering at midnight.
    'dayKey': habitDayKey(now),
  };
}
