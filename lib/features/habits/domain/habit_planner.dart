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
/// One widget shows one habit: a 2×2 tile is big enough for a name, a state
/// and one large target to hit, and small enough that a handful of habits can
/// sit on a home screen without any of them being a list. Several habits
/// therefore mean several widgets, each configured to its own habit.
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

/// The payload the home-screen widgets draw themselves from.
///
/// A plain map because it crosses the method channel into a Kotlin
/// `RemoteViews`; the shape is fixed and mirrored in `HabitWidgetProvider`, so
/// both sides must be changed together.
///
/// Every habit travels, not only today's: each widget is configured to *one*
/// habit, and a habit that is not due today still owns its tile — it has to be
/// able to say "今天不用打卡" rather than looking like a habit that was deleted.
/// The words are resolved here as well, so the widget never has to know how to
/// phrase anything; it draws `sub` and `state` and nothing else.
Map<String, Object?> habitWidgetPayload({
  required List<Habit> habits,
  required List<HabitLog> logs,
  required DateTime now,
  required String todoSub,
  required String doneSub,
  required String offSub,
  required String emptyTitle,
  required String emptyBody,
  required String staleText,
  required String unconfiguredText,
  required String missingText,
}) {
  final DateTime today = startOfDay(now);
  final Map<String, Set<int>> doneByHabit = <String, Set<int>>{};
  for (final HabitLog log in logs) {
    (doneByHabit[log.habitId] ??= <int>{}).add(log.dayKey);
  }
  final int todayKey = habitDayKey(today);
  final Map<String, HabitLog> todayLogs = <String, HabitLog>{
    for (final HabitLog log in logs)
      if (log.dayKey == todayKey) log.habitId: log,
  };

  final Map<String, Object?> tiles = <String, Object?>{};
  for (final Habit habit in habits) {
    final Set<int> doneDays = doneByHabit[habit.id] ?? const <int>{};
    final bool due = habit.isDueOn(today);
    final bool done = todayLogs.containsKey(habit.id);
    final int streak = habitStreak(habit: habit, doneDays: doneDays, today: today);
    final String? time = habit.reminderLabel;

    tiles[habit.id] = <String, Object?>{
      'emoji': habit.emoji,
      'name': habit.name,
      'due': due,
      'done': done,
      // The facts, not the sentence: the widget has to be able to re-word the
      // line when a tap changes `done` with the app closed, and it can only do
      // that if the words and the facts arrive separately.
      'details': <String>[
        ?time,
        if (streak > 0) '$streak 天',
      ].join(' · '),
      // Only habits that accept a note get the widget's ＋: an offer to write
      // something the habit does not keep would be a lie.
      'note': habit.allowNote,
    };
  }

  return <String, Object?>{
    'dayKey': todayKey,
    'empty': habits.isEmpty,
    'tiles': tiles,
    // The habits in the order the app lists them. `tiles` is a map, and a map
    // has no order a widget could rely on — a tile that draws "everything, in
    // order" needs the order written down.
    'order': <Object?>[for (final Habit habit in habits) habit.id],
    'subTodo': todoSub,
    'subDone': doneSub,
    'subOff': offSub,
    'emptyTitle': emptyTitle,
    'emptyBody': emptyBody,
    'staleText': staleText,
    'unconfiguredText': unconfiguredText,
    'missingText': missingText,
  };
}
