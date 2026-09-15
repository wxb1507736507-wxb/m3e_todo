import '../../domain/entities/course.dart';
import '../../domain/entities/period_time.dart';
import '../../domain/entities/term.dart';
import '../../domain/entities/timetable.dart';

/// Translates the timetable to and from the JSON document on disk.
///
/// Tolerant on the way in and explicit on the way out: a course that cannot be
/// read is dropped rather than crashing the timetable, and a term that cannot be
/// read at all answers `null`, which the controller turns into a fresh term.
abstract final class TimetableModel {
  /// Version 1 is the first shape this document has had.
  ///
  /// Version 2 adds a course's own `backgroundImage` and `backgroundDim`, both
  /// optional on read: a version-1 file loads with every course in its colour,
  /// and a version-2 file still opens in an older build, which ignores them.
  static const int schemaVersion = 2;

  static Map<String, Object?> toJson(Timetable timetable) {
    final Term term = timetable.term;
    return <String, Object?>{
      'version': schemaVersion,
      'term': <String, Object?>{
        'name': term.name,
        'startMonday': term.startMonday.toIso8601String(),
        'totalWeeks': term.totalWeeks,
        'periods': <Object?>[
          for (final PeriodTime period in term.periods)
            <String, Object?>{
              'index': period.index,
              'start': period.startMinutes,
              'end': period.endMinutes,
            },
        ],
      },
      'courses': <Object?>[
        for (final Course course in timetable.courses) courseToJson(course),
      ],
    };
  }

  static Map<String, Object?> courseToJson(Course course) {
    return <String, Object?>{
      'id': course.id,
      'name': course.name,
      'createdAt': course.createdAt.toIso8601String(),
      if (course.room != null) 'room': course.room,
      if (course.note != null) 'note': course.note,
      if (course.color != null) 'color': course.color,
      // Absent rather than null, like every other optional field here: absent
      // means "no picture, use the colour".
      if (course.backgroundImage != null)
        'backgroundImage': course.backgroundImage,
      if (course.backgroundImage != null)
        'backgroundDim': course.backgroundDim,
      'slots': <Object?>[
        for (final CourseSlot slot in course.slots)
          <String, Object?>{
            'weekday': slot.weekday,
            'start': slot.startPeriod,
            'end': slot.endPeriod,
          },
      ],
      // Sorted so the file reads the way the weeks do, and so a diff of two
      // saves is about the timetable rather than about set iteration order.
      'weeks': (course.weeks.toList()..sort()),
    };
  }

  static Timetable? fromJson(Map<String, Object?> json) {
    final Object? rawTerm = json['term'];
    if (rawTerm is! Map) {
      return null;
    }
    final Term? term = termFromJson(Map<String, Object?>.from(rawTerm));
    if (term == null) {
      return null;
    }

    final List<Course> courses = <Course>[];
    final Object? rawCourses = json['courses'];
    if (rawCourses is List) {
      for (final Object? entry in rawCourses) {
        if (entry is! Map) {
          continue;
        }
        final Course? course = courseFromJson(Map<String, Object?>.from(entry));
        if (course != null) {
          courses.add(course);
        }
      }
    }
    return Timetable(term: term, courses: courses);
  }

  static Term? termFromJson(Map<String, Object?> json) {
    final Object? start = json['startMonday'];
    final DateTime? startMonday = start is String ? DateTime.tryParse(start) : null;
    if (startMonday == null) {
      return null;
    }
    final Object? weeks = json['totalWeeks'];
    final int totalWeeks = weeks is int && weeks > 0 && weeks <= 60 ? weeks : 18;

    final List<PeriodTime> periods = <PeriodTime>[];
    final Object? rawPeriods = json['periods'];
    if (rawPeriods is List) {
      for (final Object? entry in rawPeriods) {
        if (entry is! Map) {
          continue;
        }
        final Object? index = entry['index'];
        final Object? from = entry['start'];
        final Object? to = entry['end'];
        if (index is! int || from is! int || to is! int) {
          continue;
        }
        if (index < 1 || from < 0 || to > 24 * 60 || to <= from) {
          continue;
        }
        periods.add(
          PeriodTime(index: index, startMinutes: from, endMinutes: to),
        );
      }
    }
    periods.sort((PeriodTime a, PeriodTime b) => a.index.compareTo(b.index));

    return Term(
      name: json['name'] is String && (json['name']! as String).trim().isNotEmpty
          ? (json['name']! as String).trim()
          : '我的课程表',
      startMonday: DateTime(startMonday.year, startMonday.month, startMonday.day),
      totalWeeks: totalWeeks,
      // A term with no periods cannot be drawn; the default day is a better
      // answer than a timetable with no rows.
      periods: periods.isEmpty ? kDefaultPeriods : periods,
    );
  }

  static Course? courseFromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }

    final List<CourseSlot> slots = <CourseSlot>[];
    final Object? rawSlots = json['slots'];
    if (rawSlots is List) {
      for (final Object? entry in rawSlots) {
        if (entry is! Map) {
          continue;
        }
        final Object? weekday = entry['weekday'];
        final Object? from = entry['start'];
        final Object? to = entry['end'];
        if (weekday is! int || from is! int || to is! int) {
          continue;
        }
        if (weekday < 1 || weekday > 7 || from < 1 || to < from || to > 20) {
          continue;
        }
        slots.add(
          CourseSlot(weekday: weekday, startPeriod: from, endPeriod: to),
        );
      }
    }
    if (slots.isEmpty) {
      return null;
    }

    final Set<int> weeks = <int>{};
    final Object? rawWeeks = json['weeks'];
    if (rawWeeks is List) {
      for (final Object? week in rawWeeks) {
        if (week is int && week >= 1 && week <= 60) {
          weeks.add(week);
        }
      }
    }
    if (weeks.isEmpty) {
      return null;
    }

    final Object? createdAt = json['createdAt'];
    return Course(
      id: id,
      name: name.trim(),
      slots: List<CourseSlot>.unmodifiable(slots),
      weeks: Set<int>.unmodifiable(weeks),
      room: json['room'] is String ? json['room']! as String : null,
      note: json['note'] is String ? json['note']! as String : null,
      color: json['color'] is int ? json['color']! as int : null,
      backgroundImage:
          json['backgroundImage'] is String ? json['backgroundImage']! as String : null,
      backgroundDim: _dim(json['backgroundDim']),
      createdAt: createdAt is String
          ? (DateTime.tryParse(createdAt) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  /// Reads a scrim strength, clamped rather than rejected.
  ///
  /// A truncated or hand-edited value must not be able to paint the picture
  /// fully opaque (dim above the slider's ceiling) or fully absent.
  static double _dim(Object? raw) {
    if (raw is! num || raw.toDouble().isNaN) {
      return Course.defaultBackgroundDim;
    }
    return raw.toDouble().clamp(0.0, 0.9);
  }
}
