/// One course: what it is called, where it is, and when it happens.
///
/// A course is *not* one appointment. The same lecture runs on two weekdays and
/// every other week, so it carries a list of slots (weekday + periods) and a set
/// of weeks — which covers both the "weeks 1 to 16" a form offers and the
/// irregular "1, 3, 5, 7, 17, 18" the phone this feature imitates shows, without
/// a second concept for odd weeks.
library;

import '../../../../core/utils/calendar.dart';
import 'term.dart';

/// One weekly meeting of a course: a weekday and a range of periods.
class CourseSlot {
  const CourseSlot({
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
  });

  /// 1 (Monday) through 7 (Sunday), as `DateTime.weekday` numbers them.
  final int weekday;

  /// 1-based period numbers, inclusive.
  final int startPeriod;
  final int endPeriod;

  int get periodCount => endPeriod - startPeriod + 1;

  bool overlaps(CourseSlot other) =>
      weekday == other.weekday &&
      startPeriod <= other.endPeriod &&
      endPeriod >= other.startPeriod;

  /// `周二 第1-2节`, or `周二 第1节` for a single period.
  String get label => periodCount == 1
      ? '周${kCourseWeekdayNames[weekday - 1]} 第$startPeriod节'
      : '周${kCourseWeekdayNames[weekday - 1]} 第$startPeriod-$endPeriod节';

  CourseSlot edited({int? weekday, int? startPeriod, int? endPeriod}) =>
      CourseSlot(
        weekday: weekday ?? this.weekday,
        startPeriod: startPeriod ?? this.startPeriod,
        endPeriod: endPeriod ?? this.endPeriod,
      );

  @override
  bool operator ==(Object other) =>
      other is CourseSlot &&
      other.weekday == weekday &&
      other.startPeriod == startPeriod &&
      other.endPeriod == endPeriod;

  @override
  int get hashCode => Object.hash(weekday, startPeriod, endPeriod);

  @override
  String toString() => label;
}

/// Monday-first weekday names, the same order `DateTime.weekday` uses.
const List<String> kCourseWeekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

/// A course could not be saved because it is not usable as written.
class CourseValidationException implements Exception {
  const CourseValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Course {
  const Course({
    required this.id,
    required this.name,
    required this.slots,
    required this.weeks,
    this.room,
    this.note,
    this.color,
    required this.createdAt,
  });

  /// Builds a course, rejecting the shapes that would leave a block on the
  /// timetable with nothing to draw or nowhere to draw it.
  factory Course.create({
    required String id,
    required String name,
    required List<CourseSlot> slots,
    required Set<int> weeks,
    String? room,
    String? note,
    int? color,
    required DateTime createdAt,
  }) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const CourseValidationException('课程名不能为空');
    }
    if (slots.isEmpty) {
      throw const CourseValidationException('至少要有一个上课时间');
    }
    for (final CourseSlot slot in slots) {
      if (slot.startPeriod > slot.endPeriod) {
        throw const CourseValidationException('节次范围不对');
      }
    }
    if (weeks.isEmpty) {
      throw const CourseValidationException('至少要选一周');
    }
    return Course(
      id: id,
      name: trimmed,
      slots: List<CourseSlot>.unmodifiable(slots),
      weeks: Set<int>.unmodifiable(weeks),
      room: _blankToNull(room),
      note: _blankToNull(note),
      color: color,
      createdAt: createdAt,
    );
  }

  final String id;
  final String name;

  /// Where it is taught, when the user wrote it down.
  final String? room;

  /// The free line under the room: the teacher, usually.
  final String? note;

  /// Every weekly meeting of this course.
  final List<CourseSlot> slots;

  /// The weeks it runs, 1-based and absolute within the term.
  final Set<int> weeks;

  /// Background colour (ARGB32), or `null` to take one from the palette by name.
  final int? color;

  final DateTime createdAt;

  /// Whether this course happens in [week].
  bool runsInWeek(int week) => weeks.contains(week);

  /// Whether this course meets on [weekday] during any of [periods].
  bool meetsOn(int weekday, Set<int> periods) {
    for (final CourseSlot slot in slots) {
      if (slot.weekday != weekday) {
        continue;
      }
      for (final int period in periods) {
        if (period >= slot.startPeriod && period <= slot.endPeriod) {
          return true;
        }
      }
    }
    return false;
  }

  /// Whether this course meets on [weekday] at all.
  bool meetsOnDay(int weekday) =>
      slots.any((CourseSlot slot) => slot.weekday == weekday);

  /// The slots that fall on [weekday], in period order.
  List<CourseSlot> slotsOnDay(int weekday) => <CourseSlot>[
        for (final CourseSlot slot in slots)
          if (slot.weekday == weekday) slot,
      ]..sort((CourseSlot a, CourseSlot b) => a.startPeriod.compareTo(b.startPeriod));

  /// The first period this course starts at, for sorting a day's list.
  int get firstPeriod =>
      slots.map((CourseSlot slot) => slot.startPeriod).reduce((int a, int b) => a < b ? a : b);

  /// `每周` when it runs every week of the term, otherwise the weeks it names.
  String weeksLabel(int totalWeeks) {
    if (weeks.length == totalWeeks && weeks.contains(1) && weeks.contains(totalWeeks)) {
      return '每周';
    }
    final List<int> sorted = weeks.toList()..sort();
    // Runs of consecutive weeks read better than a list: 1-16周 beats sixteen
    // numbers, while 1, 3, 5 stays as it is because that *is* the pattern.
    final List<String> parts = <String>[];
    int start = sorted.first;
    int previous = sorted.first;
    for (final int week in sorted.skip(1)) {
      if (week == previous + 1) {
        previous = week;
        continue;
      }
      parts.add(start == previous ? '$start' : '$start-$previous');
      start = week;
      previous = week;
    }
    parts.add(start == previous ? '$start' : '$start-$previous');
    return '第${parts.join(', ')}周';
  }

  /// `周一 第1-2节 / 周三 第3-4节`.
  String get slotsLabel => slots.map((CourseSlot slot) => slot.label).join(' / ');

  Course edited({
    String? name,
    List<CourseSlot>? slots,
    Set<int>? weeks,
    String? room,
    bool clearRoom = false,
    String? note,
    bool clearNote = false,
    int? color,
    bool clearColor = false,
  }) {
    return Course.create(
      id: id,
      name: name ?? this.name,
      slots: slots ?? this.slots,
      weeks: weeks ?? this.weeks,
      room: clearRoom ? null : (room ?? this.room),
      note: clearNote ? null : (note ?? this.note),
      color: clearColor ? null : (color ?? this.color),
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Course &&
      other.id == id &&
      other.name == name &&
      other.room == room &&
      other.note == note &&
      other.color == color &&
      other.slots.length == slots.length &&
      Iterable<int>.generate(slots.length).every((int i) => other.slots[i] == slots[i]) &&
      other.weeks.length == weeks.length &&
      other.weeks.containsAll(weeks) &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        room,
        note,
        color,
        Object.hashAll(slots),
        Object.hashAllUnordered(weeks),
        createdAt,
      );

  @override
  String toString() => 'Course($name, $slotsLabel)';
}

String? _blankToNull(String? value) {
  final String? trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Two courses that want the same period of the same day, in overlapping weeks.
class CourseClash {
  const CourseClash({
    required this.first,
    required this.second,
    required this.slot,
    required this.weeks,
  });

  final Course first;
  final Course second;

  /// The day and periods they fight over.
  final CourseSlot slot;

  /// The weeks both of them run in.
  final Set<int> weeks;

  String get label => slot.label;
}

/// Every pair of courses that collide, so the editor can say so before saving.
///
/// A timetable is the one place where a mistake is invisible until the term has
/// started — two lectures in the same slot look fine on separate cards — so this
/// is checked as a rule rather than left to the user to notice.
List<CourseClash> findCourseClashes(List<Course> courses) {
  final List<CourseClash> clashes = <CourseClash>[];
  for (int i = 0; i < courses.length; i++) {
    for (int j = i + 1; j < courses.length; j++) {
      final Course first = courses[i];
      final Course second = courses[j];
      final Set<int> shared = first.weeks.intersection(second.weeks);
      if (shared.isEmpty) {
        continue;
      }
      for (final CourseSlot a in first.slots) {
        for (final CourseSlot b in second.slots) {
          if (a.overlaps(b)) {
            clashes.add(
              CourseClash(
                first: first,
                second: second,
                slot: a,
                weeks: shared,
              ),
            );
          }
        }
      }
    }
  }
  return clashes;
}

/// The courses that meet on [day] in [week], with the slots that do.
class CourseMeeting {
  const CourseMeeting({required this.course, required this.slot});

  final Course course;
  final CourseSlot slot;

  /// The clock range, when the term knows these periods.
  String? timeLabel(Term term) => term.rangeLabel(slot.startPeriod, slot.endPeriod);
}

/// What [week] holds on [day], in period order.
List<CourseMeeting> meetingsOn(
  List<Course> courses,
  int week,
  DateTime day,
) {
  final List<CourseMeeting> meetings = <CourseMeeting>[];
  for (final Course course in courses) {
    if (!course.runsInWeek(week)) {
      continue;
    }
    for (final CourseSlot slot in course.slotsOnDay(day.weekday)) {
      meetings.add(CourseMeeting(course: course, slot: slot));
    }
  }
  meetings.sort((CourseMeeting a, CourseMeeting b) =>
      a.slot.startPeriod.compareTo(b.slot.startPeriod));
  return meetings;
}

/// The courses that meet [day], whichever week of the term it is.
///
/// Used by the widget, which has no week selector: it shows what is on today,
/// and a day outside the term simply has nothing.
List<CourseMeeting> meetingsForDateIn(
  List<Course> courses,
  Term term,
  DateTime day,
) {
  final int? week = term.weekOf(day);
  if (week == null) {
    return const <CourseMeeting>[];
  }
  return meetingsOn(courses, week, startOfDay(day));
}
