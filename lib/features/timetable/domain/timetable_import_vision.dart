/// Reading a timetable out of a picture with a model's eyes, over the network.
///
/// The phone's own timetable does not recognise anything locally: it hands the
/// photo to the ROM's vision service (vivo's `com.vivo.vtouch`), which has
/// INTERNET and answers with the rows it read. That is the method this copies —
/// a cloud model that *sees* the grid and says what is in it — because the two
/// things a local OCR cannot do are the two a timetable needs: read a small,
/// dense, slightly-angled page, and know that a block of text spanning two rows
/// is one class that runs for two periods.
///
/// What stays here rather than in the data layer is the two decisions that
/// matter for accuracy and that can be tested against text rather than against
/// a network: what is asked for, and what is accepted as an answer. A model's
/// reply is not a schema — it arrives wrapped in prose, in code fences, with
/// Chinese numerals, with a weekday spelled two ways — and every one of those is
/// handled by [parseImportedTimetable], where a test can reach it.
library;

import 'dart:convert';

import 'entities/course.dart';
import 'timetable_import.dart';

/// What is asked of the model, as one instruction.
///
/// Written to make the answer *parsable* rather than conversational: the shape
/// is spelled out, one example is given, and the reply is told to be JSON and
/// nothing else. [periodCount] and [totalWeeks] are the term's own numbers, so
/// the model is asked to fit what it read into the timetable that exists rather
/// than to invent a shape of its own.
String timetableImportPrompt({
  required int periodCount,
  required int totalWeeks,
}) {
  return '''
你是一个课表识别助手。请仔细看这张课程表图片，把里面的课程全部读出来。

要求：
1. 只输出 JSON，不要输出任何解释、不要用 markdown 代码块。
2. 每门课一个对象，同一门课在不同天的多个时段合并成一个对象，放在 slots 数组里。
3. 字段：
   - name：课程名（必填，去掉标记、序号、竖线等符号）
   - room：教室，没有就 null
   - note：老师或备注，没有就 null
   - slots：数组，每项 {weekday, start, end}
     - weekday：1=周一 到 7=周日，用数字
     - start/end：第几节，用数字（1 到 $periodCount）
4. 看不清的字不要编，宁可留空。表头（周一…周日）、节次号、页码、水印都不是课程。
5. 如果一门课跨两节，start 和 end 就写成这两个数字。

输出格式：
{"courses":[{"name":"高等数学","room":"教三201","note":"张老师","slots":[{"weekday":2,"start":1,"end":2}]}]}

学期信息：每天 $periodCount 节课，共 $totalWeeks 周。''';
}

/// Reads a model's reply into courses, or an empty result it cannot.
///
/// Deliberately forgiving, because it is parsing a *sentence* rather than a
/// protocol: the JSON may be fenced, prefixed with an apology, or written with
/// Chinese weekday names. Anything one course gets wrong costs that course, not
/// the import.
ImportedTimetable parseImportedTimetable(
  String reply, {
  required int periodCount,
  required int totalWeeks,
  int minWeekdayColumns = 1,
}) {
  final Object? decoded = _decodeLoose(reply);
  final List<Object?> raw = switch (decoded) {
    final List<Object?> list => list,
    final Map<String, Object?> map when map['courses'] is List =>
      (map['courses']! as List).cast<Object?>(),
    final Map<String, Object?> map when map['data'] is List =>
      (map['data']! as List).cast<Object?>(),
    _ => const <Object?>[],
  };

  final List<ImportedCourse> courses = <ImportedCourse>[];
  int skipped = 0;
  for (final Object? entry in raw) {
    if (entry is! Map) {
      skipped++;
      continue;
    }
    final Map<String, Object?> course = entry.cast<String, Object?>();
    final String? name = _text(course['name'] ?? course['courseName'] ?? course['course']);
    final List<CourseSlot> slots = _slots(course, periodCount: periodCount);
    if (name == null || slots.isEmpty) {
      skipped++;
      continue;
    }
    courses.add(
      ImportedCourse(
        name: name,
        room: _text(course['room'] ?? course['classroom'] ?? course['location']),
        note: _text(course['note'] ?? course['teacher'] ?? course['remark']),
        slots: slots,
      ),
    );
  }

  return ImportedTimetable(
    courses: courses,
    skippedLines: skipped,
    sawGrid: courses.isNotEmpty,
  );
}

/// Pulls JSON out of whatever the model wrapped it in.
Object? _decodeLoose(String reply) {
  final String trimmed = reply.trim();
  for (final String candidate in <String>[
    trimmed,
    _between(trimmed, '```json', '```'),
    _between(trimmed, '```', '```'),
    // Outermost braces, not the first pair: the answer nests an object per
    // meeting, so stopping at the first `}` would cut the JSON in half.
    _outermost(trimmed, '{', '}'),
    _outermost(trimmed, '[', ']'),
  ]) {
    if (candidate.isEmpty) {
      continue;
    }
    try {
      return jsonDecode(candidate);
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// From the first [open] to the last [close], which is the whole document.
String _outermost(String text, String open, String close) {
  final int from = text.indexOf(open);
  final int to = text.lastIndexOf(close);
  if (from < 0 || to <= from) {
    return '';
  }
  return text.substring(from, to + 1).trim();
}

String _between(String text, String open, String close) {
  final int from = text.indexOf(open);
  if (from < 0) {
    return '';
  }
  final int start = from + open.length;
  final int to = text.indexOf(close, start);
  return text.substring(start, to < 0 ? text.length : to).trim();
}

List<CourseSlot> _slots(Map<String, Object?> course, {required int periodCount}) {
  final Object? raw = course['slots'] ?? course['times'] ?? course['time'];
  final List<Object?> entries = raw is List
      ? raw
      : raw == null
          ? const <Object?>[]
          : <Object?>[raw];
  final List<CourseSlot> slots = <CourseSlot>[];
  for (final Object? entry in entries) {
    final CourseSlot? slot = _slot(entry, periodCount: periodCount);
    if (slot != null && !slots.contains(slot)) {
      slots.add(slot);
    }
  }
  slots.sort((CourseSlot a, CourseSlot b) {
    final int byDay = a.weekday.compareTo(b.weekday);
    return byDay != 0 ? byDay : a.startPeriod.compareTo(b.startPeriod);
  });
  return slots;
}

/// One weekly meeting, from a map or from a sentence like `周二 第1-2节`.
CourseSlot? _slot(Object? entry, {required int periodCount}) {
  if (entry is Map) {
    final Map<String, Object?> slot = entry.cast<String, Object?>();
    final int? weekday = weekdayNumber(slot['weekday'] ?? slot['day']);
    final int? start = _period(slot['start'] ?? slot['startPeriod'] ?? slot['from']);
    final int? end = _period(slot['end'] ?? slot['endPeriod'] ?? slot['to']) ?? start;
    if (weekday == null || start == null || end == null) {
      return null;
    }
    return CourseSlot(
      weekday: weekday,
      startPeriod: start.clamp(1, periodCount < 1 ? start : periodCount),
      endPeriod: (end < start ? start : end).clamp(1, periodCount < 1 ? end : periodCount),
    );
  }
  if (entry is String) {
    return _slotFromText(entry, periodCount: periodCount);
  }
  return null;
}

/// A meeting written the way a person writes one: `周二 第1-2节`.
CourseSlot? _slotFromText(String text, {required int periodCount}) {
  final int? weekday = weekdayNumber(text);
  if (weekday == null) {
    return null;
  }
  final List<int> periods = <int>[
    for (final RegExpMatch match in RegExp(r'\d+').allMatches(text))
      int.parse(match.group(0)!),
  ];
  if (periods.isEmpty) {
    return null;
  }
  final int start = periods.first;
  final int end = periods.length > 1 ? periods[1] : start;
  return CourseSlot(
    weekday: weekday,
    startPeriod: start.clamp(1, periodCount),
    endPeriod: (end < start ? start : end).clamp(1, periodCount),
  );
}

/// The weekday a number, a digit or a name stands for, or `null`.
int? weekdayNumber(Object? raw) {
  if (raw is num) {
    final int value = raw.toInt();
    return value >= 1 && value <= 7 ? value : null;
  }
  if (raw is! String) {
    return null;
  }
  final int? asNumber = int.tryParse(raw.trim());
  if (asNumber != null) {
    return asNumber >= 1 && asNumber <= 7 ? asNumber : null;
  }
  final String text = raw.trim();
  final int? named = weekdayOf(text);
  if (named != null) {
    return named;
  }
  // A weekday inside a longer phrase, which is how a sentence like
  // `周三 第1-2节` carries one.
  final RegExpMatch? inside =
      RegExp('(?:周|星期|礼拜)[一二三四五六日天]').firstMatch(text);
  return inside == null ? null : weekdayOf(inside.group(0)!);
}

/// A period number from a number or from `第3节` / `3`.
int? _period(Object? raw) {
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is! String) {
    return null;
  }
  final RegExpMatch? match = RegExp(r'\d+').firstMatch(raw);
  return match == null ? null : int.parse(match.group(0)!);
}

/// A field of a course, cleaned of the punctuation a model likes to add.
String? _text(Object? raw) {
  if (raw is! String) {
    return null;
  }
  String value = raw.trim();
  const String edges = '|｜·•・,，.。:：;；-—_=+*#「」『』[]【】()（）<>《》“”"\'';
  while (value.isNotEmpty && edges.contains(value[0])) {
    value = value.substring(1).trimLeft();
  }
  while (value.isNotEmpty && edges.contains(value[value.length - 1])) {
    value = value.substring(0, value.length - 1).trimRight();
  }
  // A model asked for null sometimes answers with the word for it.
  if (value.isEmpty ||
      value == 'null' ||
      value == 'NULL' ||
      value == '无' ||
      value == '暂无' ||
      value == '未填写') {
    return null;
  }
  return value;
}
