import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/timetable/domain/entities/course.dart';
import 'package:m3e_todo/features/timetable/domain/entities/period_time.dart';
import 'package:m3e_todo/features/timetable/domain/entities/term.dart';
import 'package:m3e_todo/features/timetable/presentation/course_widget_sync.dart';

import '../../../support/sample_todo.dart' show testNow;

/// What the home-screen tile is given to draw itself from.
///
/// Worth a test of its own because the tile steps *days* by itself: everything it
/// can ever show has to be in one payload, computed here, and a wrong shape is a
/// wrong shape nothing else would catch — the tile runs in the launcher's
/// process, where no test can follow it.
void main() {
  Term term() => Term(
        name: '大三上',
        startMonday: DateTime(2026, 3, 9),
        totalWeeks: 18,
        periods: kDefaultPeriods,
      );

  Course course(
    String id, {
    String name = '高等数学',
    int weekday = DateTime.tuesday,
    int start = 1,
    int end = 2,
    Set<int>? weeks,
  }) {
    return Course.create(
      id: id,
      name: name,
      slots: <CourseSlot>[
        CourseSlot(weekday: weekday, startPeriod: start, endPeriod: end),
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

  List<Map<String, Object?>> daysOf(Map<String, Object?> payload) =>
      (payload['days']! as List<Object?>).cast<Map<String, Object?>>();

  List<Map<String, Object?>> rowsOf(Map<String, Object?> day) =>
      (day['rows']! as List<Object?>).cast<Map<String, Object?>>();

  /// The day the tile shows when it has not been stepped.
  Map<String, Object?> today(Map<String, Object?> payload) =>
      daysOf(payload)[payload['todayIndex']! as int];

  test('the payload carries the days around today, and where today is', () {
    final Map<String, Object?> data = payload(<Course>[course('c1')]);

    // testNow is 2026-03-10, a Tuesday.
    expect(data['todayIndex'], 7);
    expect(daysOf(data), hasLength(7 + 28 + 1));
    expect(today(data)['date'], '3/10');
    expect(today(data)['weekdayName'], '周二');
    expect(today(data)['relative'], '今天');

    // The two neighbours a thumb reaches for first are named, not numbered.
    expect(daysOf(data)[8]['relative'], '明天');
    expect(daysOf(data)[8]['date'], '3/11');
    expect(daysOf(data)[8]['weekdayName'], '周三');
    expect(daysOf(data)[6]['relative'], '昨天');
    expect(daysOf(data)[6]['date'], '3/9');

    // Further out, the weekday is the useful word.
    expect(daysOf(data)[9]['relative'], '');
    expect(daysOf(data)[9]['weekdayName'], '周四');
  });

  test("today's rows are today's classes, with clock time and room", () {
    final Map<String, Object?> data = payload(<Course>[course('c1')]);

    final Map<String, Object?> day = today(data);
    expect(rowsOf(day), hasLength(1));
    expect(rowsOf(day).single['time'], '08:00');
    expect(rowsOf(day).single['name'], '高等数学');
    expect(rowsOf(day).single['room'], '教三 201');
    expect(day['inTerm'], isTrue);
  });

  test('stepping to a day a course does not run on shows it empty', () {
    final Map<String, Object?> data = payload(<Course>[course('c1')]);

    // Tuesday has it; Wednesday does not. This is the whole point of the tile
    // carrying a window of days: tomorrow's answer is already here.
    expect(rowsOf(daysOf(data)[8]), isEmpty);
  });

  test('a day outside the term says so instead of pretending', () {
    final Map<String, Object?> data = payload(<Course>[course('c1')]);

    // Seven days back is 3/3, before a term that starts on 3/9.
    final Map<String, Object?> before = daysOf(data).first;
    expect(before['inTerm'], isFalse);
    expect(rowsOf(before), isEmpty);
  });

  test('more classes than the tile holds are counted, not silently dropped', () {
    final Map<String, Object?> data = payload(<Course>[
      for (int index = 0; index < 6; index++)
        course('c$index', name: '课$index', start: index + 1, end: index + 2),
    ]);

    final Map<String, Object?> day = today(data);
    expect(rowsOf(day), hasLength(4));
    expect(day['more'], 2);
  });

  test('two courses on one day both arrive', () {
    final Map<String, Object?> data = payload(<Course>[
      course('c1', name: '高等数学', start: 1, end: 2),
      course('c2', name: '英语', start: 5, end: 6),
    ]);

    expect(
      rowsOf(today(data)).map((Map<String, Object?> row) => row['name']),
      <String>['高等数学', '英语'],
    );
  });
}
