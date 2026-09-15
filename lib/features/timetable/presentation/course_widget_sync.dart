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
/// A window of *days*, not of weeks: the tile steps one day at a time, so
/// "what have I got tomorrow" is answered on the home screen without opening
/// anything. Every day in the window arrives with its rows already written out —
/// a widget has no periods to look them up in, and no term to know which week a
/// date falls in — so stepping is a matter of picking an index.
///
/// The window is lopsided on purpose: a week back to catch up on what was
/// missed, four weeks forward, which is as far as anyone plans a timetable.
Map<String, Object?> courseWidgetPayload({
  required List<Course> courses,
  required Term term,
  required DateTime now,
  required String emptyText,
  required String staleText,
  int maxRows = 4,
  int daysBack = 7,
  int daysForward = 28,
}) {
  final DateTime today = startOfDay(now);
  final List<Map<String, Object?>> days = <Map<String, Object?>>[
    for (int offset = -daysBack; offset <= daysForward; offset++)
      _dayPayload(
        courses: courses,
        term: term,
        day: today.add(Duration(days: offset)),
        offset: offset,
        today: today,
        maxRows: maxRows,
      ),
  ];

  return <String, Object?>{
    'dayKey': now.year * 10000 + now.month * 100 + now.day,
    'emptyText': emptyText,
    'staleText': staleText,
    // Where "today" sits in the window, so the tile's offset from it is a plain
    // index sum — and so the tile can say 今天/明天 without a clock of its own.
    'todayIndex': daysBack,
    'days': days,
  };
}

Map<String, Object?> _dayPayload({
  required List<Course> courses,
  required Term term,
  required DateTime day,
  required int offset,
  required DateTime today,
  required int maxRows,
}) {
  final List<CourseMeeting> meetings = meetingsForDateIn(courses, term, day);
  return <String, Object?>{
    'date': '${day.month}/${day.day}',
    'weekdayName': '周${kCourseWeekdayNames[day.weekday - 1]}',
    // 今天/明天/昨天 where they apply, the weekday otherwise: a relative word is
    // how a person reads a date they are standing in.
    'relative': switch (offset) {
      0 => AppStrings.courseWidgetToday,
      1 => AppStrings.courseWidgetTomorrow,
      -1 => AppStrings.courseWidgetYesterday,
      _ => '',
    },
    'inTerm': term.weekOf(day) != null,
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
