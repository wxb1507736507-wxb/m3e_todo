/// One teaching period of the day: which number it is, and when it runs.
///
/// The times are the user's own, not a fixed bell: the timetable on the phone
/// this feature imitates has nine periods with a gap over lunch and another over
/// dinner, and every school cuts its day differently. Storing the start and end
/// as minutes past midnight keeps them comparable and printable without a
/// `DateTime` for a thing that never happens on a date.
library;

/// A period's clock time, as minutes after local midnight.
class PeriodTime {
  const PeriodTime({
    required this.index,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// 1-based, and the number shown in the timetable's left column.
  final int index;

  final int startMinutes;
  final int endMinutes;

  /// `08:00`.
  String get startLabel => _clock(startMinutes);

  /// `08:45`.
  String get endLabel => _clock(endMinutes);

  /// `08:00 - 08:45`.
  String get label => '$startLabel - $endLabel';

  bool overlaps(int start, int end) =>
      startMinutes < end && endMinutes > start;

  PeriodTime edited({int? startMinutes, int? endMinutes}) => PeriodTime(
        index: index,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );

  @override
  bool operator ==(Object other) =>
      other is PeriodTime &&
      other.index == index &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(index, startMinutes, endMinutes);

  @override
  String toString() => 'PeriodTime($index, $label)';
}

String _clock(int minutes) {
  final int hours = (minutes ~/ 60) % 24;
  final int rest = minutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

/// The nine periods the phone's own timetable starts from: morning, afternoon,
/// evening, with the gaps a school day actually has.
///
/// A default rather than a rule — every one of them can be retimed — but a
/// timetable with no periods at all cannot be drawn, and asking for nine times
/// before showing anything would be a poor hello.
const List<PeriodTime> kDefaultPeriods = <PeriodTime>[
  PeriodTime(index: 1, startMinutes: 8 * 60, endMinutes: 8 * 60 + 45),
  PeriodTime(index: 2, startMinutes: 8 * 60 + 50, endMinutes: 9 * 60 + 35),
  PeriodTime(index: 3, startMinutes: 9 * 60 + 55, endMinutes: 10 * 60 + 40),
  PeriodTime(index: 4, startMinutes: 10 * 60 + 45, endMinutes: 11 * 60 + 30),
  PeriodTime(index: 5, startMinutes: 14 * 60, endMinutes: 14 * 60 + 45),
  PeriodTime(index: 6, startMinutes: 14 * 60 + 50, endMinutes: 15 * 60 + 35),
  PeriodTime(index: 7, startMinutes: 15 * 60 + 45, endMinutes: 16 * 60 + 30),
  PeriodTime(index: 8, startMinutes: 16 * 60 + 35, endMinutes: 17 * 60 + 20),
  PeriodTime(index: 9, startMinutes: 19 * 60 + 20, endMinutes: 20 * 60 + 5),
];
