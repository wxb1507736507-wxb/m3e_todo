import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/calendar.dart';
import '../domain/entities/course.dart';
import '../domain/entities/term.dart';
import '../domain/entities/timetable.dart';
import 'providers/timetable_providers.dart';

/// Keeps the course tile on the home screen up to date.
///
/// One direction only — the app publishes, the tile draws — except for the week
/// the tile is showing, which the tile changes by itself: stepping weeks on a
/// home screen must not need the app to open, so the payload carries every week
/// of the term and the tile picks one. That is why the rows are computed for a
/// *weekday* across all weeks rather than for today alone.
class CourseWidgetSync {
  CourseWidgetSync(this._ref);

  final Ref _ref;

  /// Whether the widget asked for the timetable since the last check.
  bool _selfChecked = false;

  Future<void> _selfCheckOnce() async {
    if (_selfChecked) {
      return;
    }
    _selfChecked = true;
    final Map<String, Object?> report = await AppPlatform.selfCheckCourseWidget();
    debugPrint('course-widget-self-check: $report');
  }

  Future<void> sync() async {
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      do {
        _queued = false;
        await _syncOnce();
      } while (_queued);
    } finally {
      _running = false;
    }
  }

  bool _running = false;
  bool _queued = false;

  Future<void> _syncOnce() async {
    // Awaited rather than read: on a cold start the timetable is still loading,
    // and a payload built from "still loading" would tell the widget there are no
    // classes today — which is a lie the tile would wear until the next publish.
    final Timetable timetable;
    try {
      timetable = await _ref.read(timetableProvider.future);
    } on Object catch (error) {
      debugPrint('course widget sync skipped: $error');
      return;
    }

    final DateTime now = _ref.read(clockProvider)();
    final bool placed = await AppPlatform.updateCourseWidget(
      courseWidgetPayload(
        courses: timetable.courses,
        term: timetable.term,
        now: now,
        emptyText: AppStrings.courseWidgetEmpty,
        staleText: AppStrings.courseWidgetStale,
      ),
    );
    // Only Android can answer this, and the timetable would otherwise offer to
    // add a tile that is already on the home screen.
    _ref.read(courseWidgetPlacedProvider.notifier).set(placed);

    if (kDebugMode) {
      await _selfCheckOnce();
    }
  }
}

/// The payload the course tile draws.
///
/// Every week of the term, for the weekday today falls on: enough for the tile
/// to step through the whole term by itself, which it must be able to do without
/// the app running. The rows arrive with their clock times already written out —
/// a widget has no periods to look them up in — and only the four a tile can
/// hold.
Map<String, Object?> courseWidgetPayload({
  required List<Course> courses,
  required Term term,
  required DateTime now,
  required String emptyText,
  required String staleText,
  int maxRows = 4,
}) {
  final int weekday = now.weekday;
  return <String, Object?>{
    'dayKey': now.year * 10000 + now.month * 100 + now.day,
    'emptyText': emptyText,
    'staleText': staleText,
    // Which week the clock is in, so the tile can say 本周 — and 0 when today is
    // outside the term, in which case no week is "this week".
    'currentWeek': term.weekOf(now) ?? 0,
    'weekday': weekday,
    'weekdayName': '周${kCourseWeekdayNames[weekday - 1]}',
    'weeks': <Object?>[
      for (int week = 1; week <= term.totalWeeks; week++)
        _weekPayload(
          courses: courses,
          term: term,
          weekday: weekday,
          week: week,
          maxRows: maxRows,
        ),
    ],
  };
}

Map<String, Object?> _weekPayload({
  required List<Course> courses,
  required Term term,
  required int weekday,
  required int week,
  required int maxRows,
}) {
  final DateTime monday = term.mondayOfWeek(week);
  final DateTime day = monday.add(Duration(days: weekday - 1));
  final List<CourseMeeting> meetings = meetingsOn(courses, week, startOfDay(day));
  return <String, Object?>{
    'week': week,
    'date': '${day.month}/${day.day}',
    'rows': <Object?>[
      for (final CourseMeeting meeting in meetings.take(maxRows))
        <String, Object?>{
          // When it starts, not the whole range: a row is one line tall, and
          // "08:00" is the part a student reads.
          'time': term.periodAt(meeting.slot.startPeriod)?.startLabel ??
              '第${meeting.slot.startPeriod}节',
          'name': meeting.course.name,
          'room': meeting.course.room,
        },
    ],
    // Whether the tile has more to say than it can hold, said rather than
    // silently dropped.
    'more': meetings.length > maxRows ? meetings.length - maxRows : 0,
  };
}

final Provider<CourseWidgetSync> courseWidgetSyncProvider =
    Provider<CourseWidgetSync>(
  CourseWidgetSync.new,
  name: 'courseWidgetSync',
);
