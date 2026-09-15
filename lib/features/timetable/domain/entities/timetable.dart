/// The whole timetable: one term, and the courses taught in it.
///
/// One document rather than two because they are never edited apart — a course's
/// weeks only mean anything against the term's first Monday — and because the
/// timetable is read whole every time it is drawn.
library;

import 'course.dart';
import 'period_time.dart';
import 'term.dart';

class Timetable {
  const Timetable({required this.term, required this.courses});

  /// A timetable for a term that has just been created: today's week is week 1,
  /// eighteen weeks, and the nine periods the phone's own timetable uses.
  ///
  /// Nobody has to fill anything in before the screen is worth looking at, which
  /// is the difference between a feature and a form.
  factory Timetable.fresh(DateTime today) {
    final DateTime monday = today.subtract(Duration(days: today.weekday - 1));
    return Timetable(
      term: Term(
        name: '我的课程表',
        startMonday: DateTime(monday.year, monday.month, monday.day),
        totalWeeks: 18,
        periods: kDefaultPeriods,
      ),
      courses: const <Course>[],
    );
  }

  final Term term;
  final List<Course> courses;

  bool get isEmpty => courses.isEmpty;

  /// The course with [id], or `null` when it has been deleted.
  Course? courseById(String id) {
    for (final Course course in courses) {
      if (course.id == id) {
        return course;
      }
    }
    return null;
  }

  /// The courses that run in [week], in the order they were created.
  List<Course> coursesInWeek(int week) => <Course>[
        for (final Course course in courses)
          if (course.runsInWeek(week)) course,
      ];

  /// The courses that meet on [weekday] in [week].
  List<CourseMeeting> meetingsOnDay(int week, int weekday) => <CourseMeeting>[
        for (final Course course in coursesInWeek(week))
          for (final CourseSlot slot in course.slotsOnDay(weekday))
            CourseMeeting(course: course, slot: slot),
      ]..sort((CourseMeeting a, CourseMeeting b) =>
          a.slot.startPeriod.compareTo(b.slot.startPeriod));

  /// What is on today, for the widget: it has no week selector to offer.
  List<CourseMeeting> meetingsForDate(DateTime day) =>
      meetingsForDateIn(courses, term, day);

  /// The course that collides with [course] — the same day and periods in a week
  /// they both run — or `null` when it fits.
  ///
  /// Used before saving, because a clash is invisible until the term starts.
  CourseClash? clashWith(Course candidate) {
    for (final CourseClash clash in findCourseClashes(<Course>[...courses, candidate])) {
      if (clash.first.id == candidate.id || clash.second.id == candidate.id) {
        return clash;
      }
    }
    return null;
  }

  Timetable withCourse(Course course) {
    final int index = courses.indexWhere((Course other) => other.id == course.id);
    final List<Course> next = List<Course>.of(courses);
    if (index >= 0) {
      next[index] = course;
    } else {
      next.add(course);
    }
    return Timetable(term: term, courses: next);
  }

  Timetable withoutCourse(String id) => Timetable(
        term: term,
        courses: <Course>[
          for (final Course course in courses)
            if (course.id != id) course,
        ],
      );

  /// Drops every course that no longer fits the term.
  ///
  /// Shortening a term to twelve weeks has to mean something for a course
  /// written for week 17: it is trimmed to the weeks that still exist, and a
  /// course with none left is removed rather than left as a block nothing can
  /// ever draw.
  Timetable trimmedToTerm() {
    final List<Course> kept = <Course>[];
    for (final Course course in courses) {
      final Set<int> weeks = <int>{
        for (final int week in course.weeks)
          if (week >= 1 && week <= term.totalWeeks) week,
      };
      if (weeks.isEmpty) {
        continue;
      }
      final List<CourseSlot> slots = <CourseSlot>[
        for (final CourseSlot slot in course.slots)
          if (slot.endPeriod <= term.periods.length) slot,
      ];
      if (slots.isEmpty) {
        continue;
      }
      kept.add(course.edited(weeks: weeks, slots: slots));
    }
    return Timetable(term: term, courses: kept);
  }

  @override
  String toString() => 'Timetable(${term.name}, ${courses.length} courses)';
}
