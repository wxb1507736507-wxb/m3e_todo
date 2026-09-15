/// Turning a picture of a timetable into courses.
///
/// The recogniser's only job is to say what text it saw and where; this is the
/// part that decides what that *means*, and it lives in the domain — free of
/// Flutter, free of the channel — so it can be tested against a page of made-up
/// boxes instead of against a photograph.
///
/// The shape of the problem is always the same: a timetable is a grid with the
/// weekdays along the top and the periods down the left, and every other piece
/// of text belongs to the cell it sits in. So the plan is:
///
///  1. find the weekday row, which fixes the columns;
///  2. find the period numbers, which fix the rows — or divide the area evenly
///     when the picture has none, because a screenshot of a timetable has rows
///     of equal height and that is the only assumption available;
///  3. drop every line into the cell it is standing in;
///  4. read each cell as a course: the first line is its name, and the lines
///     under it are the room and the teacher;
///  5. give the cells that name the same course to one course with several
///     weekly meetings, which is what a timetable actually means by a course
///     that appears on Tuesday and again on Thursday.
library;

import 'entities/course.dart';

/// One line of text the recogniser read, and the box it sat in.
class TextBox {
  const TextBox({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;

  /// Pixels in the recogniser's own coordinate space, top-left origin.
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;

  @override
  String toString() => 'TextBox($text @${centerX.round()},${centerY.round()})';
}

/// A course read out of a picture, before the user has agreed to it.
class ImportedCourse {
  const ImportedCourse({
    required this.name,
    required this.slots,
    this.room,
    this.note,
  });

  final String name;
  final String? room;
  final String? note;
  final List<CourseSlot> slots;

  ImportedCourse edited({String? name, String? room, bool clearRoom = false}) {
    return ImportedCourse(
      name: name ?? this.name,
      slots: slots,
      room: clearRoom ? null : (room ?? this.room),
      note: note,
    );
  }

  /// `周二 第1-2节 / 周四 第3节`.
  String get slotsLabel => slots.map((CourseSlot slot) => slot.label).join(' / ');

  @override
  String toString() => 'ImportedCourse($name, $slotsLabel)';
}

/// What a picture turned out to hold.
class ImportedTimetable {
  const ImportedTimetable({
    required this.courses,
    this.skippedLines = 0,
    this.sawGrid = false,
  });

  const ImportedTimetable.nothing()
      : courses = const <ImportedCourse>[],
        skippedLines = 0,
        sawGrid = false;

  final List<ImportedCourse> courses;

  /// Text that was read but did not land in a cell — a title, a legend, a
  /// watermark. Reported rather than ignored: "18 lines skipped" is how a user
  /// learns that the picture was half cut off.
  final int skippedLines;

  /// Whether a weekday row was found at all. Without one, nothing here is
  /// trustworthy, and the difference matters to what the user is told.
  final bool sawGrid;

  bool get isEmpty => courses.isEmpty;

  int get courseCount => courses.length;
}

/// Reads a timetable out of the lines a recogniser found in a picture.
///
/// [periodCount] is the term's own number of periods, used only when the
/// picture has no period numbers to read; [minWeekdayColumns] is how many
/// weekdays have to be recognised before the page counts as a timetable at all.
ImportedTimetable readTimetable(
  List<TextBox> lines, {
  required int periodCount,
  int minWeekdayColumns = 3,
}) {
  if (lines.isEmpty) {
    return const ImportedTimetable.nothing();
  }

  final _DayHeader? header = _findDayHeader(lines, minWeekdayColumns);
  if (header == null) {
    return ImportedTimetable(courses: const <ImportedCourse>[], skippedLines: lines.length);
  }

  final List<_Column> columns = header.columns;
  final List<_Row> rows = _findRows(
    lines,
    columns: columns,
    below: header.bottom,
    periodCount: periodCount,
  );
  if (rows.isEmpty) {
    return ImportedTimetable(
      courses: const <ImportedCourse>[],
      skippedLines: lines.length,
      sawGrid: true,
    );
  }

  // 3. Every other line goes into the cell it is standing in — and a course
  // that runs for two periods is *one* cell with its name centred across both,
  // which is why the lines of a column are grouped into blocks first and the
  // block, not each line, is what gets a period range.
  final double rowHeight = rows
          .map((_Row row) => row.bottom - row.top)
          .reduce((double a, double b) => a + b) /
      rows.length;

  final Map<String, ImportedCourse> byName = <String, ImportedCourse>{};
  final List<String> order = <String>[];
  int skipped = 0;

  // Anything that is neither the grid nor inside it: a title, a legend, the
  // watermark of whoever shared the screenshot. Counted rather than ignored,
  // because "18 lines skipped" is how a user learns their picture was half cut
  // off — and the header and the period column are the grid, so they are not
  // leftovers and are not counted.
  for (final TextBox line in lines) {
    if (weekdayOf(line.text) != null || _periodNumber(line) != null) {
      continue;
    }
    if (line.centerY <= header.bottom) {
      skipped++;
    }
  }

  for (int column = 0; column < columns.length; column++) {
    final List<TextBox> inColumn = <TextBox>[
      for (final TextBox line in lines)
        if (_inGrid(line, header.bottom) && _columnOf(columns, line) == column)
          line,
    ]..sort((TextBox a, TextBox b) => a.centerY.compareTo(b.centerY));

    for (final List<TextBox> block in _blocks(inColumn, rowHeight)) {
      final _Span? span = _spanOf(rows, block);
      if (span == null) {
        skipped += block.length;
        continue;
      }
      final _Cell cell = _readCell(block);
      if (cell.name.isEmpty) {
        skipped += block.length;
        continue;
      }
      final CourseSlot slot = CourseSlot(
        weekday: columns[column].weekday,
        startPeriod: span.start,
        endPeriod: span.end,
      );
      final String key = _normalize(cell.name);
      final ImportedCourse? existing = byName[key];
      if (existing == null) {
        byName[key] = ImportedCourse(
          name: cell.name,
          room: cell.room,
          note: cell.note,
          slots: <CourseSlot>[slot],
        );
        order.add(key);
      } else {
        byName[key] = ImportedCourse(
          name: existing.name,
          // The first room wins: a course that moves rooms between days is
          // rare, and one room the user can fix beats two the app cannot
          // choose between.
          room: existing.room ?? cell.room,
          note: existing.note ?? cell.note,
          slots: <CourseSlot>[
            ...existing.slots,
            if (!existing.slots.contains(slot)) slot,
          ]..sort(_byDayThenPeriod),
        );
      }
    }
  }

  return ImportedTimetable(
    courses: <ImportedCourse>[for (final String key in order) byName[key]!],
    skippedLines: skipped,
    sawGrid: true,
  );
}

/// Whether a line is something a cell could hold — that is, below the weekday
/// row and not one of the period numbers down the left.
bool _inGrid(TextBox line, double headerBottom) =>
    line.centerY > headerBottom && _periodNumber(line) == null;

/// Groups a column's lines into the cells they were written in.///
/// Two courses stacked in one column are separated by the row boundary between
/// them, so a gap of a third of a row is already more than the space between
/// the lines of one course — and much less than the space between two.
List<List<TextBox>> _blocks(List<TextBox> lines, double rowHeight) {
  final List<List<TextBox>> blocks = <List<TextBox>>[];
  for (final TextBox line in lines) {
    final List<TextBox>? last = blocks.isEmpty ? null : blocks.last;
    final double gap = last == null ? 0 : line.top - last.last.bottom;
    if (last == null || gap > rowHeight * 0.35) {
      blocks.add(<TextBox>[line]);
    } else {
      last.add(line);
    }
  }
  return blocks;
}

/// Which periods a block of text covers: the rows it overlaps.
///
/// A name centred in a two-period cell crosses the boundary between the two
/// rows and so claims both — which is exactly the answer wanted, and the reason
/// this is done by overlap rather than by asking which row the text is "in".
_Span? _spanOf(List<_Row> rows, List<TextBox> block) {
  final double top = block.first.top;
  final double bottom = block.last.bottom;
  int? start;
  int? end;
  for (final _Row row in rows) {
    final double tolerance = (row.bottom - row.top) * 0.02;
    final bool overlaps =
        top < row.bottom - tolerance && bottom > row.top + tolerance;
    if (!overlaps) {
      continue;
    }
    start = start == null || row.start < start ? row.start : start;
    end = end == null || row.end > end ? row.end : end;
  }
  if (start == null || end == null) {
    // Nothing overlapped: the text sits outside the grid the numbers describe,
    // which means the rows are not what this picture has. Better to say nothing
    // about this cell than to invent a time for it.
    return null;
  }
  return _Span(start: start, end: end < start ? start : end);
}

/// The weekday a header cell names, 1 (Monday) through 7, or `null`.
///
/// Both ways of writing it, and both short forms: a timetable on a phone may
/// say 周一, 星期一, or just 一 under a column that is too narrow for more.
int? weekdayOf(String text) {
  final String clean = text.replaceAll(RegExp(r'\s+'), '');
  if (clean.isEmpty) {
    return null;
  }
  const List<String> names = <String>['一', '二', '三', '四', '五', '六', '日'];
  for (int index = 0; index < names.length; index++) {
    final String name = names[index];
    // `$name曜日` would read the Chinese characters as part of the identifier,
    // which is why the day-character is appended as its own piece.
    final String youbi = '曜日';
    if (clean == name ||
        clean == '周$name' ||
        clean == '星期$name' ||
        clean == '礼拜$name' ||
        clean == '$name$youbi') {
      return index + 1;
    }
  }
  if (clean == '周天' || clean == '星期天' || clean == '礼拜天' || clean == '天') {
    return 7;
  }
  return null;
}

/// The period number a line is, or `null` when it is not one.
int? _periodNumber(TextBox line) {
  final String clean = line.text.trim();
  if (clean.length > 2) {
    return null;
  }
  final int? value = int.tryParse(clean);
  if (value == null || value < 1 || value > 20) {
    return null;
  }
  return value;
}

/// The weekday row, with the columns it implies.
_DayHeader? _findDayHeader(List<TextBox> lines, int minColumns) {
  final List<TextBox> found = <TextBox>[
    for (final TextBox line in lines)
      if (weekdayOf(line.text) != null) line,
  ];
  if (found.length < minColumns) {
    return null;
  }

  // The weekdays of one timetable share a row, so the group to keep is the
  // widest set of them that sits at the same height. A second row of weekday
  // names — a legend, or the next week's header — must not be mixed in.
  final List<List<TextBox>> bands = <List<TextBox>>[];
  for (final TextBox line in found..sort((TextBox a, TextBox b) => a.centerY.compareTo(b.centerY))) {
    final List<TextBox>? band = bands.isEmpty ? null : bands.last;
    if (band != null && (line.centerY - band.first.centerY).abs() <= line.height * 0.8) {
      band.add(line);
    } else {
      bands.add(<TextBox>[line]);
    }
  }
  bands.sort((List<TextBox> a, List<TextBox> b) => b.length.compareTo(a.length));
  final List<TextBox> row = bands.first;
  if (row.length < minColumns) {
    return null;
  }
  row.sort((TextBox a, TextBox b) => a.centerX.compareTo(b.centerX));

  final Map<int, double> centres = <int, double>{};
  for (final TextBox line in row) {
    final int? weekday = weekdayOf(line.text);
    if (weekday != null) {
      centres[weekday] = line.centerX;
    }
  }
  if (centres.length < minColumns) {
    return null;
  }

  // A column that was not recognised still has a position: the days are evenly
  // spaced, so a missing one is between its neighbours.
  final List<int> known = centres.keys.toList()..sort();
  final List<double> gaps = <double>[
    for (int i = 1; i < known.length; i++)
      (centres[known[i]]! - centres[known[i - 1]]!) / (known[i] - known[i - 1]),
  ]..sort();
  final double gap = gaps.isEmpty ? 1 : gaps[gaps.length ~/ 2];
  for (int weekday = known.first; weekday <= known.last; weekday++) {
    if (!centres.containsKey(weekday)) {
      centres[weekday] = centres[weekday - 1]! + gap;
    }
  }

  final double bottom = row
      .map((TextBox line) => line.bottom)
      .reduce((double a, double b) => a > b ? a : b);
  return _DayHeader(
    columns: <_Column>[
      for (final int weekday in centres.keys.toList()..sort())
        _Column(weekday: weekday, centerX: centres[weekday]!),
    ],
    bottom: bottom,
  );
}

/// The period rows, read from the numbers down the left or laid out evenly.
List<_Row> _findRows(
  List<TextBox> lines, {
  required List<_Column> columns,
  required double below,
  required int periodCount,
}) {
  final double leftEdge = columns.first.centerX -
      (columns.length > 1 ? (columns[1].centerX - columns[0].centerX) / 2 : 0);

  final List<TextBox> numbers = <TextBox>[
    for (final TextBox line in lines)
      if (_periodNumber(line) != null && line.centerX < leftEdge) line,
  ]..sort((TextBox a, TextBox b) => a.centerY.compareTo(b.centerY));

  if (numbers.length >= 2) {
    final List<double> gaps = <double>[
      for (int i = 1; i < numbers.length; i++) numbers[i].centerY - numbers[i - 1].centerY,
    ]..sort();
    final double gap = gaps[gaps.length ~/ 2];

    // A row for every period from the first one the picture showed down to the
    // last one the term has — not one row per number that was read. Numbers go
    // missing in practice: a period with nothing written beside it, a shadow
    // along the bottom edge, a digit the recogniser folded into the text next
    // to it. The rows themselves do not go missing, and a timetable missing its
    // eighth row is a timetable that silently drops every eighth-period class.
    final int firstPeriod = _periodNumber(numbers.first)!;
    final int lastPeriod = <int>[
      _periodNumber(numbers.last)!,
      periodCount,
    ].reduce((int a, int b) => a > b ? a : b);
    final double first = numbers.first.centerY - gap / 2;
    return <_Row>[
      for (int index = 0; index <= lastPeriod - firstPeriod; index++)
        _Row(
          start: firstPeriod + index,
          end: firstPeriod + index,
          top: first + index * gap,
          bottom: first + (index + 1) * gap,
        ),
    ];
  }

  // No numbers to read: the rows are assumed to be equal, which is what every
  // timetable — on a wall, on a phone, in this app — actually looks like. The
  // area runs from under the header to the lowest line that could be a course.
  final List<TextBox> body = <TextBox>[
    for (final TextBox line in lines)
      if (line.centerY > below && weekdayOf(line.text) == null) line,
  ];
  if (body.isEmpty || periodCount < 1) {
    return const <_Row>[];
  }
  final double bottom = body
      .map((TextBox line) => line.bottom)
      .reduce((double a, double b) => a > b ? a : b);
  final double height = bottom - below;
  if (height <= 0) {
    return const <_Row>[];
  }
  final double rowHeight = height / periodCount;
  return <_Row>[
    for (int index = 0; index < periodCount; index++)
      _Row(
        start: index + 1,
        end: index + 1,
        top: below + rowHeight * index,
        bottom: below + rowHeight * (index + 1),
      ),
  ];
}

/// Which column a line stands in, or `null` when it stands outside them all.
int? _columnOf(List<_Column> columns, TextBox line) {
  int? best;
  double bestDistance = double.infinity;
  for (int index = 0; index < columns.length; index++) {
    final double distance = (columns[index].centerX - line.centerX).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = index;
    }
  }
  if (best == null) {
    return null;
  }
  // Half a column either side of the centre, so a line about the next column
  // over is not claimed by this one — and a line that belongs to no column at
  // all, such as a title along the top, is refused rather than misplaced.
  final double half = columns.length > 1
      ? (columns[1].centerX - columns[0].centerX).abs() / 2
      : double.infinity;
  return bestDistance <= half * 1.1 ? best : null;
}

/// The periods a cell covers.
class _Span {
  const _Span({required this.start, required this.end});

  final int start;
  final int end;
}

/// What one cell's lines say: a name, and whatever is under it.
_Cell _readCell(List<TextBox> lines) {
  final List<String> texts = <String>[
    for (final TextBox line in lines)
      if (_tidy(line.text).isNotEmpty) _tidy(line.text),
  ];
  if (texts.isEmpty) {
    return const _Cell(name: '');
  }
  final String name = texts.first;
  String? room;
  final List<String> rest = <String>[];
  for (final String text in texts.skip(1)) {
    if (room == null && _looksLikeRoom(text)) {
      room = text;
    } else {
      rest.add(text);
    }
  }
  return _Cell(
    name: name,
    room: room,
    note: rest.isEmpty ? null : rest.join(' '),
  );
}

/// Strips what a recogniser picks up from the lines of the grid itself.
///
/// A vertical rule drawn beside a course name comes back as a leading `|`, and
/// text that touches a cell's border can collect a stray dash or bracket. None
/// of it is part of what the timetable says, and all of it ends up in the
/// course's name if it is not removed — a name the user then has to fix by
/// hand, in a feature whose whole point is not having to type.
String _tidy(String text) {
  const String edges = '|｜·•・,，.。:：;；!！?？~～-—_=+*#「」『』[]【】()（）<>《》“”"\'';
  String result = text.trim();
  while (result.isNotEmpty && edges.contains(result[0])) {
    result = result.substring(1).trimLeft();
  }
  while (result.isNotEmpty && edges.contains(result[result.length - 1])) {
    result = result.substring(0, result.length - 1).trimRight();
  }
  return result;
}

/// Whether a line reads like a room rather than a person or a note.
///
/// Deliberately loose: the cost of calling a room a note is one line in the
/// wrong field of a card the user is about to check anyway, while the cost of
/// demanding a perfect match is a room that never gets imported at all.
bool _looksLikeRoom(String text) {
  if (RegExp(r'\d').hasMatch(text)) {
    return true;
  }
  const List<String> words = <String>['楼', '教', '室', '馆', '区', '号', '栋', '厅'];
  return words.any(text.contains);
}

String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

int _byDayThenPeriod(CourseSlot a, CourseSlot b) {
  final int byDay = a.weekday.compareTo(b.weekday);
  return byDay != 0 ? byDay : a.startPeriod.compareTo(b.startPeriod);
}

class _DayHeader {
  const _DayHeader({required this.columns, required this.bottom});

  final List<_Column> columns;

  /// The bottom of the weekday row, which is where the grid starts.
  final double bottom;
}

class _Column {
  const _Column({required this.weekday, required this.centerX});

  final int weekday;
  final double centerX;
}

class _Row {
  const _Row({
    required this.start,
    required this.end,
    required this.top,
    required this.bottom,
  });

  final int start;
  final int end;
  final double top;
  final double bottom;
}

class _Cell {
  const _Cell({required this.name, this.room, this.note});

  final String name;
  final String? room;
  final String? note;
}
