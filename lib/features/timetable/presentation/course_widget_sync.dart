import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/platform/app_platform.dart';
import '../domain/entities/course.dart';
import '../domain/entities/term.dart';
import '../domain/entities/timetable.dart';
import 'providers/timetable_providers.dart';

/// Keeps the course widget's picture of today up to date.
///
/// The same arrangement as the habit tile's: the widget cannot read the app's
/// documents, so the app publishes a payload it can draw, and the widget asks for
/// nothing back — a course is read, not ticked off. Publishes on every change to
/// the timetable and on every launch, which is what makes the tile show today
/// rather than the day the app was last opened.
class CourseWidgetSync {
  CourseWidgetSync(this._ref);

  final Ref _ref;

  bool _running = false;
  bool _queued = false;

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
    final List<CourseMeeting> today =
        meetingsForDateIn(timetable.courses, timetable.term, now);

    final bool placed = await AppPlatform.updateCourseWidget(
      courseWidgetPayload(
        meetings: today,
        term: timetable.term,
        now: now,
        emptyText: AppStrings.courseWidgetEmpty,
        staleText: AppStrings.courseWidgetStale,
      ),
    );
    // Only Android can answer this, and the timetable would otherwise offer to
    // add a tile that is already on the home screen.
    _ref.read(courseWidgetPlacedProvider.notifier).set(placed);
  }
}

/// The payload the course widget draws.
///
/// The rows arrive with their clock times already written out — the widget has
/// no periods to look them up in — and only the four a tile can hold.
Map<String, Object?> courseWidgetPayload({
  required List<CourseMeeting> meetings,
  required Term term,
  required DateTime now,
  required String emptyText,
  required String staleText,
  int maxRows = 4,
}) {
  final List<CourseMeeting> shown = meetings.take(maxRows).toList();
  return <String, Object?>{
    'dayKey': now.year * 10000 + now.month * 100 + now.day,
    'emptyText': emptyText,
    'staleText': staleText,
    'rows': <Object?>[
      for (final CourseMeeting meeting in shown)
        <String, Object?>{
          // When it starts, not the whole range: a row is one line tall, and
          // "08:00" is the part a student reads.
          'time': term.periodAt(meeting.slot.startPeriod)?.startLabel ??
              '第${meeting.slot.startPeriod}节',
          'name': meeting.course.name,
          'room': meeting.course.room,
        },
    ],
  };
}

final Provider<CourseWidgetSync> courseWidgetSyncProvider =
    Provider<CourseWidgetSync>(
  CourseWidgetSync.new,
  name: 'courseWidgetSync',
);
