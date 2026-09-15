/// The term the timetable belongs to: its name, its first Monday, and how many
/// weeks it runs.
///
/// The first Monday is the whole reason this exists. A course is stored as "week
/// 3, Tuesday, periods 1-2" — not as dates — so that the same timetable works
/// for every year, and the only thing that turns those weeks into the dates of
/// an actual calendar is where week 1 started.
library;

import '../../../../core/utils/calendar.dart';
import 'period_time.dart';

/// A term, with only what the timetable needs to know about it.
class Term {
  const Term({
    required this.name,
    required this.startMonday,
    required this.totalWeeks,
    required this.periods,
  });

  /// What the term is called: 大三上, 2026 秋.
  final String name;

  /// The Monday of week 1, at local midnight.
  final DateTime startMonday;

  /// How many weeks the term runs for; the last week a course may name.
  final int totalWeeks;

  /// The day's periods, in order. Sorted by index on the way in.
  final List<PeriodTime> periods;

  /// The week [day] falls in, or `null` when it is outside the term.
  ///
  /// 1-based: the week containing [startMonday] is week 1. Days before the term
  /// and after its last week answer `null` rather than a negative or oversize
  /// number, because "week -2" is not a week anybody can be shown.
  int? weekOf(DateTime day) {
    final int days = daysBetween(startMonday, day);
    final int week = (days / 7).floor() + 1;
    if (week < 1 || week > totalWeeks) {
      return null;
    }
    return week;
  }

  /// The Monday that starts [week].
  DateTime mondayOfWeek(int week) =>
      startMonday.add(Duration(days: (week - 1) * 7));

  /// The seven days of [week], Monday first.
  List<DateTime> daysOfWeek(int week) => <DateTime>[
        for (int offset = 0; offset < 7; offset++)
          mondayOfWeek(week).add(Duration(days: offset)),
      ];

  /// The period numbered [index], or `null` when the day has no such period.
  PeriodTime? periodAt(int index) {
    for (final PeriodTime period in periods) {
      if (period.index == index) {
        return period;
      }
    }
    return null;
  }

  /// The clock range of the periods [start] to [end], or `null` when neither end
  /// is a period this term knows.
  String? rangeLabel(int start, int end) {
    final PeriodTime? first = periodAt(start);
    final PeriodTime? last = periodAt(end);
    if (first == null || last == null) {
      return null;
    }
    return '${first.startLabel} - ${last.endLabel}';
  }

  Term edited({
    String? name,
    DateTime? startMonday,
    int? totalWeeks,
    List<PeriodTime>? periods,
  }) {
    return Term(
      name: name ?? this.name,
      startMonday: startMonday ?? this.startMonday,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      periods: periods ?? this.periods,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Term &&
      other.name == name &&
      other.startMonday == startMonday &&
      other.totalWeeks == totalWeeks &&
      other.periods.length == periods.length &&
      Iterable<int>.generate(periods.length)
          .every((int i) => other.periods[i] == periods[i]);

  @override
  int get hashCode =>
      Object.hash(name, startMonday, totalWeeks, Object.hashAll(periods));

  @override
  String toString() => 'Term($name, from $startMonday, $totalWeeks weeks)';
}
