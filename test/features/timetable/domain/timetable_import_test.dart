import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/timetable/domain/entities/course.dart';
import 'package:m3e_todo/features/timetable/domain/timetable_import.dart';

/// What a picture of a timetable turns into.
///
/// The pages here are built rather than photographed on purpose: a recogniser's
/// answer is a list of lines and rectangles, and that is a thing that can be
/// written down exactly. A test that needed a real photo would be a test that
/// could not say which part of the reading is wrong.
void main() {
  /// A page laid out like a timetable: seven day columns from [left], nine
  /// period rows of [rowHeight] starting at [top].
  const double left = 100;
  const double columnWidth = 100;
  const double rowHeight = 60;
  const double top = 80;

  /// A line of text in the cell for [weekday] and [period], [line] rows down
  /// inside that cell.
  TextBox cell(
    int weekday,
    int period,
    String text, {
    int line = 0,
    double? width,
    double? leftOffset,
  }) {
    final double x = left + (weekday - 1) * columnWidth;
    final double y = top + (period - 1) * rowHeight + 6 + line * 18;
    final double w = width ?? columnWidth - 10;
    return TextBox(
      text: text,
      left: leftOffset ?? x + 5,
      top: y,
      right: (leftOffset ?? x + 5) + w,
      bottom: y + 16,
    );
  }

  /// The weekday header row, and the period numbers down the left.
  List<TextBox> grid() => <TextBox>[
        for (int weekday = 1; weekday <= 7; weekday++)
          TextBox(
            text: '周${kCourseWeekdayNames[weekday - 1]}',
            left: left + (weekday - 1) * columnWidth + 20,
            top: 40,
            right: left + (weekday - 1) * columnWidth + 80,
            bottom: 70,
          ),
        for (int period = 1; period <= 9; period++)
          TextBox(
            text: '$period',
            left: 30,
            top: top + (period - 1) * rowHeight + 20,
            right: 50,
            bottom: top + (period - 1) * rowHeight + 40,
          ),
      ];

  group('reading a page', () {
    test('a course is placed on the day and period it was written in', () {
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          ...grid(),
          cell(2, 1, '高等数学'),
          cell(2, 1, '教三 201', line: 1),
          cell(4, 3, '大学物理'),
        ],
        periodCount: 9,
      );

      expect(read.sawGrid, isTrue);
      expect(read.courses, hasLength(2));

      final ImportedCourse maths = read.courses.first;
      expect(maths.name, '高等数学');
      expect(maths.room, '教三 201');
      expect(maths.slots.single.weekday, DateTime.tuesday);
      expect(maths.slots.single.startPeriod, 1);
      expect(maths.slots.single.endPeriod, 1);

      final ImportedCourse physics = read.courses.last;
      expect(physics.name, '大学物理');
      expect(physics.slots.single.weekday, DateTime.thursday);
      expect(physics.slots.single.startPeriod, 3);
    });

    test('a name centred over two periods becomes a two-period course', () {
      // A merged cell: the name sits across the boundary between periods 1 and
      // 2, because that is where a timetable draws it.
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          ...grid(),
          TextBox(
            text: '高等数学',
            left: left + columnWidth + 5,
            top: top + rowHeight - 20,
            right: left + columnWidth * 2 - 5,
            bottom: top + rowHeight + 20,
          ),
        ],
        periodCount: 9,
      );

      expect(read.courses, hasLength(1));
      expect(read.courses.single.slots.single.startPeriod, 1);
      expect(read.courses.single.slots.single.endPeriod, 2);
    });

    test('the same course on two days is one course with two meetings', () {
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          ...grid(),
          cell(1, 1, '英语'),
          cell(3, 5, '英语'),
          cell(3, 5, '外语楼 302', line: 1),
        ],
        periodCount: 9,
      );

      expect(read.courses, hasLength(1));
      expect(read.courses.single.slots, hasLength(2));
      expect(read.courses.single.slots.first.weekday, DateTime.monday);
      expect(read.courses.single.slots.last.weekday, DateTime.wednesday);
      expect(read.courses.single.slots.last.startPeriod, 5);
      // The room came from the one cell that had one.
      expect(read.courses.single.room, '外语楼 302');
    });

    test('a third line becomes the note rather than the room', () {
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          ...grid(),
          cell(5, 2, '数据库'),
          cell(5, 2, '实验楼 A404', line: 1),
          cell(5, 2, '王老师', line: 2),
        ],
        periodCount: 9,
      );

      expect(read.courses.single.room, '实验楼 A404');
      expect(read.courses.single.note, '王老师');
    });

    test('text with no weekday row above it is not a timetable', () {
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          cell(2, 1, '高等数学'),
          cell(3, 2, '大学物理'),
        ],
        periodCount: 9,
      );

      expect(read.sawGrid, isFalse);
      expect(read.isEmpty, isTrue);
    });

    test('the title above the grid is skipped, and counted', () {
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          TextBox(text: '2026 秋季学期课表', left: 200, top: 4, right: 600, bottom: 30),
          ...grid(),
          cell(2, 1, '高等数学'),
        ],
        periodCount: 9,
      );

      expect(read.courses, hasLength(1));
      expect(read.skippedLines, 1);
    });

    test('a page with no period numbers still gets its rows from the grid', () {
      // Rows of equal height are what a timetable always has, so the numbers
      // are a convenience rather than a requirement.
      final List<TextBox> page = <TextBox>[
        for (int weekday = 1; weekday <= 7; weekday++)
          TextBox(
            text: '周${kCourseWeekdayNames[weekday - 1]}',
            left: left + (weekday - 1) * columnWidth + 20,
            top: 40,
            right: left + (weekday - 1) * columnWidth + 80,
            bottom: 70,
          ),
        for (int period = 1; period <= 9; period++)
          cell(3, period, '第$period 门课', line: 0),
      ];

      final ImportedTimetable read = readTimetable(page, periodCount: 9);

      expect(read.courses, hasLength(9));
      expect(read.courses.first.slots.single.startPeriod, 1);
      expect(read.courses.last.slots.single.startPeriod, 9);
    });

    test('a bare weekday letter is a column', () {
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          for (int weekday = 1; weekday <= 7; weekday++)
            TextBox(
              text: kCourseWeekdayNames[weekday - 1],
              left: left + (weekday - 1) * columnWidth + 40,
              top: 40,
              right: left + (weekday - 1) * columnWidth + 60,
              bottom: 70,
            ),
          for (int period = 1; period <= 9; period++)
            TextBox(
              text: '$period',
              left: 30,
              top: top + (period - 1) * rowHeight + 20,
              right: 50,
              bottom: top + (period - 1) * rowHeight + 40,
            ),
          cell(7, 4, '体育'),
        ],
        periodCount: 9,
      );

      expect(read.courses.single.slots.single.weekday, DateTime.sunday);
      expect(read.courses.single.slots.single.startPeriod, 4);
    });

    test('a missing column is filled in from its neighbours', () {
      // A narrow screenshot can lose a header or two; the days are evenly
      // spaced, so where they were is still known.
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          for (final int weekday in <int>[1, 2, 4, 5])
            TextBox(
              text: '周${kCourseWeekdayNames[weekday - 1]}',
              left: left + (weekday - 1) * columnWidth + 20,
              top: 40,
              right: left + (weekday - 1) * columnWidth + 80,
              bottom: 70,
            ),
          for (int period = 1; period <= 9; period++)
            TextBox(
              text: '$period',
              left: 30,
              top: top + (period - 1) * rowHeight + 20,
              right: 50,
              bottom: top + (period - 1) * rowHeight + 40,
            ),
          cell(3, 2, '大学物理'),
        ],
        periodCount: 9,
      );

      // The third column was interpolated between Tuesday and Thursday, so a
      // course written there is still Wednesday's.
      expect(read.courses.single.slots.single.weekday, DateTime.wednesday);
    });

    test('a course below the last period number still gets its row', () {
      // Found on a real photo: the recogniser read the period numbers 1 to 7 and
      // stopped, because the rows below had nothing written in their number
      // column. The grid does not stop there, and a class in period 8 must not
      // be dropped for it.
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          for (int weekday = 1; weekday <= 7; weekday++)
            TextBox(
              text: '周${kCourseWeekdayNames[weekday - 1]}',
              left: left + (weekday - 1) * columnWidth + 20,
              top: 40,
              right: left + (weekday - 1) * columnWidth + 80,
              bottom: 70,
            ),
          for (int period = 1; period <= 7; period++)
            TextBox(
              text: '$period',
              left: 30,
              top: top + (period - 1) * rowHeight + 20,
              right: 50,
              bottom: top + (period - 1) * rowHeight + 40,
            ),
          // A two-period class below the last number that was read, drawn the
          // way a timetable draws one: the name centred across both rows.
          TextBox(
            text: '程序设计',
            left: left + 5 * columnWidth + 5,
            top: top + 8 * rowHeight - 20,
            right: left + 6 * columnWidth - 5,
            bottom: top + 8 * rowHeight + 20,
          ),
          TextBox(
            text: '机房 302',
            left: left + 5 * columnWidth + 5,
            top: top + 8 * rowHeight + 24,
            right: left + 6 * columnWidth - 5,
            bottom: top + 8 * rowHeight + 42,
          ),
        ],
        periodCount: 9,
      );

      expect(read.courses, hasLength(1));
      expect(read.courses.single.slots.single.weekday, DateTime.saturday);
      expect(read.courses.single.slots.single.startPeriod, 8);
      expect(read.courses.single.slots.single.endPeriod, 9);
    });

    test('a rule the recogniser read as text is not part of a name', () {
      // Also from a real photo: the vertical line beside a cell came back as a
      // leading `|`, and the name arrived as `|大学物理`.
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          ...grid(),
          cell(4, 3, '|大学物理'),
          cell(4, 3, '实验楼 A404', line: 1),
          cell(4, 3, '李老师', line: 2),
        ],
        periodCount: 9,
      );

      expect(read.courses.single.name, '大学物理');
      expect(read.courses.single.room, '实验楼 A404');
      expect(read.courses.single.note, '李老师');
    });

    test('an empty page is not an error', () {
      expect(readTimetable(const <TextBox>[], periodCount: 9).isEmpty, isTrue);
      expect(
        readTimetable(const <TextBox>[], periodCount: 9).sawGrid,
        isFalse,
      );
    });
  });

  group('weekday names', () {
    test('every way a phone writes a weekday is understood', () {
      expect(weekdayOf('周一'), 1);
      expect(weekdayOf('星期一'), 1);
      expect(weekdayOf('礼拜一'), 1);
      expect(weekdayOf('一'), 1);
      expect(weekdayOf('周日'), 7);
      expect(weekdayOf('星期天'), 7);
      expect(weekdayOf('日'), 7);
      expect(weekdayOf(' 周 三 '), 3);
    });

    test('anything else is not a weekday', () {
      expect(weekdayOf('高数'), isNull);
      expect(weekdayOf(''), isNull);
      expect(weekdayOf('第1节'), isNull);
    });
  });
}
