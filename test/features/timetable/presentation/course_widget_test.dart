import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/timetable/domain/entities/course.dart';
import 'package:m3e_todo/features/timetable/domain/entities/period_time.dart';
import 'package:m3e_todo/features/timetable/domain/entities/term.dart';
import 'package:m3e_todo/features/timetable/presentation/course_widget_sync.dart';

import '../../../support/sample_todo.dart' show testNow;

/// What the home-screen tile is given to draw itself from.
///
/// Worth a test of its own because the tile steps weeks *by itself*: everything
/// it can ever show has to be in one payload, computed here, and a wrong shape is
/// a wrong shape nothing else would catch — the tile runs in the launcher's
/// process, where no test can follow it.
void main() {
  Term term() => Term(
        name: '大三上',
        startMonday: DateTime(2026, 3, 9),
        totalWeeks: 18,
        periods: kDefaultPeriods,
      );

  Course course(String id, {String name = '高等数学', Set<int>? weeks}) {
    return Course.create(
      id: id,
      name: name,
      slots: <CourseSlot>[
        const CourseSlot(weekday: DateTime.tuesday, startPeriod: 1, endPeriod: 2),
      ],
      weeks: weeks ?? <int>{for (int week = 1; week <= 18; week++) week},
      room: '教三 201',
      createdAt: DateTime(2026, 3, 1),
    );
  }

  Map<String, Object?> payload(List<Course> courses) => courseWidgetPayload(
        courses: courses,
        term: term(),
        now: testNow,
        emptyText: '今天没有课',
        staleText: '刷新',
      );

  List<Map<String, Object?>> weeksOf(Map<String, Object?> payload) =>
      (payload['weeks']! as List<Object?>).cast<Map<String, Object?>>();

  List<Map<String, Object?>> rowsOf(Map<String, Object?> week) =>
      (week['rows']! as List<Object?>).cast<Map<String, Object?>>();

  test('the payload carries every week, not just this one', () {
    final Map<String, Object?> data = payload(<Course>[course('c1')]);

    expect(weeksOf(data), hasLength(18));
    expect(weeksOf(data).first['week'], 1);
    expect(weeksOf(data).last['week'], 18);
    // testNow is 2026-03-10, the Tuesday of week 1, so the tile draws Tuesdays.
    expect(data['currentWeek'], 1);
    expect(data['weekdayName'], '周二');
    expect(weeksOf(data).first['date'], '3/10');
    // Week 18 is seventeen weeks after the first, which lands on 7/7.
    expect(weeksOf(data).last['date'], '7/7');
  });

  test('a week with a class lists it, with its clock time and room', () {
    final Map<String, Object?> data = payload(<Course>[course('c1')]);

    final Map<String, Object?> first = weeksOf(data).first;
    expect(rowsOf(first), hasLength(1));
    expect(rowsOf(first).single['time'], '08:00');
    expect(rowsOf(first).single['name'], '高等数学');
    expect(rowsOf(first).single['room'], '教三 201');
  });

  test('stepping to a week a course does not run in shows it empty', () {
    final Map<String, Object?> data =
        payload(<Course>[course('c1', weeks: <int>{2})]);

    // Week 1 has nothing; week 2 has the class. This is the whole point of the
    // tile carrying every week: the answer for week 2 is already here.
    expect(rowsOf(weeksOf(data)[0]), isEmpty);
    expect(rowsOf(weeksOf(data)[1]), hasLength(1));
  });

  test('more classes than the tile holds are counted, not silently dropped', () {
    final Map<String, Object?> data = payload(<Course>[
      for (int index = 0; index < 6; index++)
        Course.create(
          id: 'c$index',
          name: '课$index',
          slots: <CourseSlot>[
            CourseSlot(
              weekday: DateTime.tuesday,
              startPeriod: index + 1,
              endPeriod: index + 2,
            ),
          ],
          weeks: <int>{1},
          createdAt: DateTime(2026, 3, 1),
        ),
    ]);

    final Map<String, Object?> first = weeksOf(data).first;
    expect(rowsOf(first), hasLength(4));
    expect(first['more'], 2);
  });

  test('a day outside the term has no week to be in', () {
    final Map<String, Object?> data = courseWidgetPayload(
      courses: <Course>[course('c1')],
      term: term(),
      // A month after the term ends.
      now: DateTime(2026, 8, 10),
      emptyText: '今天没有课',
      staleText: '刷新',
    );

    // 0 rather than a week number: nothing here is "this week", and the tile
    // says so instead of claiming one.
    expect(data['currentWeek'], 0);
    expect(weeksOf(data), hasLength(18));
  });
}
