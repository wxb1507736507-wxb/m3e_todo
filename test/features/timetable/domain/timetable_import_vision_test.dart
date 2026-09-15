import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/timetable/domain/timetable_import.dart';
import 'package:m3e_todo/features/timetable/domain/timetable_import_vision.dart';

/// Reading a model's answer.
///
/// The replies here are the shapes models actually produce — fenced, wrapped in
/// an apology, with `null` written as 无, with a weekday named rather than
/// numbered, with one meeting written as a sentence — because that is the whole
/// difficulty of asking a model rather than a parser.
void main() {
  String reply(Object json) => json is String ? json : jsonEncode(json);

  List<ImportedCourse> parse(String text) => parseImportedTimetable(
        text,
        periodCount: 9,
        totalWeeks: 18,
      ).courses;

  group('a clean answer', () {
    test('one course, one meeting', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'name': '高等数学',
              'room': '教三201',
              'note': '张老师',
              'slots': <Object?>[
                <String, Object?>{'weekday': 2, 'start': 1, 'end': 2},
              ],
            },
          ],
        }),
      );

      expect(courses, hasLength(1));
      expect(courses.single.name, '高等数学');
      expect(courses.single.room, '教三201');
      expect(courses.single.note, '张老师');
      expect(courses.single.slots.single.weekday, DateTime.tuesday);
      expect(courses.single.slots.single.startPeriod, 1);
      expect(courses.single.slots.single.endPeriod, 2);
    });

    test('a course that meets twice keeps both meetings, in day order', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'name': '英语',
              'slots': <Object?>[
                <String, Object?>{'weekday': 4, 'start': 3, 'end': 4},
                <String, Object?>{'weekday': 1, 'start': 5, 'end': 5},
              ],
            },
          ],
        }),
      );

      expect(courses.single.slots, hasLength(2));
      expect(courses.single.slots.first.weekday, DateTime.monday);
      expect(courses.single.slots.last.weekday, DateTime.thursday);
    });
  });

  group('the ways a model wraps its answer', () {
    test('inside a code fence', () {
      final List<ImportedCourse> courses = parse(
        '好的，我识别到了以下课程：\n```json\n'
        '{"courses":[{"name":"大学物理","slots":[{"weekday":4,"start":3,"end":4}]}]}\n'
        '```\n希望对你有帮助。',
      );

      expect(courses.single.name, '大学物理');
    });

    test('as a bare array', () {
      final List<ImportedCourse> courses = parse(
        '[{"name":"体育","slots":[{"weekday":5,"start":7,"end":7}]}]',
      );

      expect(courses.single.name, '体育');
      expect(courses.single.slots.single.startPeriod, 7);
    });

    test('with prose before it and no fence', () {
      final List<ImportedCourse> courses = parse(
        '这是识别结果：{"courses":[{"name":"数据库","slots":[{"weekday":3,"start":6,"end":6}]}]} 以上。',
      );

      expect(courses.single.name, '数据库');
    });

    test('a reply that is not JSON at all is empty, not an exception', () {
      expect(parse('抱歉，我看不清这张图片。'), isEmpty);
    });

    test('an empty answer is empty', () {
      expect(parse('{}'), isEmpty);
      expect(parse(''), isEmpty);
    });
  });

  group('the ways a model writes a field', () {
    test('a weekday as a name rather than a number', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'name': '体育',
              'slots': <Object?>[
                <String, Object?>{'weekday': '周二', 'start': 1, 'end': 1},
              ],
            },
          ],
        }),
      );

      expect(courses.single.slots.single.weekday, DateTime.tuesday);
    });

    test('a meeting written as a sentence', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{'name': '化学', 'slots': <Object?>['周三 第1-2节']},
          ],
        }),
      );

      expect(courses.single.slots.single.weekday, DateTime.wednesday);
      expect(courses.single.slots.single.startPeriod, 1);
      expect(courses.single.slots.single.endPeriod, 2);
    });

    test('periods under other names', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'courseName': '物理',
              'classroom': '实验楼A404',
              'teacher': '李老师',
              'slots': <Object?>[
                <String, Object?>{'day': 4, 'startPeriod': 3, 'endPeriod': 4},
              ],
            },
          ],
        }),
      );

      expect(courses.single.name, '物理');
      expect(courses.single.room, '实验楼A404');
      expect(courses.single.note, '李老师');
      expect(courses.single.slots.single.endPeriod, 4);
    });

    test('a missing end is one period, as the phone draws a single class', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'name': '毛概',
              'slots': <Object?>[
                <String, Object?>{'weekday': 5, 'start': 5},
              ],
            },
          ],
        }),
      );

      expect(courses.single.slots.single.startPeriod, 5);
      expect(courses.single.slots.single.endPeriod, 5);
    });

    test('an end before the start is pulled back to the start', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'name': '制图',
              'slots': <Object?>[
                <String, Object?>{'weekday': 1, 'start': 3, 'end': 1},
              ],
            },
          ],
        }),
      );

      expect(courses.single.slots.single.startPeriod, 3);
      expect(courses.single.slots.single.endPeriod, 3);
    });

    test('a period past the end of the day is clamped to the day', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'name': '晚课',
              'slots': <Object?>[
                <String, Object?>{'weekday': 1, 'start': 8, 'end': 14},
              ],
            },
          ],
        }),
      );

      expect(courses.single.slots.single.startPeriod, 8);
      expect(courses.single.slots.single.endPeriod, 9);
    });

    test('the word for empty is empty', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'name': '| 大学物理 ',
              'room': '无',
              'note': '暂无',
              'slots': <Object?>[
                <String, Object?>{'weekday': 4, 'start': 3, 'end': 4},
              ],
            },
          ],
        }),
      );

      // The rule the recogniser read as part of the name is gone, and "无" is
      // not a room.
      expect(courses.single.name, '大学物理');
      expect(courses.single.room, isNull);
      expect(courses.single.note, isNull);
    });
  });

  group('what is refused', () {
    test('a course with no name or no time is dropped, not fatal', () {
      final ImportedTimetable read = parseImportedTimetable(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{'name': '', 'slots': <Object?>[<String, Object?>{'weekday': 1, 'start': 1, 'end': 1}]},
            <String, Object?>{'name': '没有时间的课'},
            <String, Object?>{'name': '高等数学', 'slots': <Object?>[<String, Object?>{'weekday': 2, 'start': 1, 'end': 2}]},
          ],
        }),
        periodCount: 9,
        totalWeeks: 18,
      );

      expect(read.courses, hasLength(1));
      expect(read.courses.single.name, '高等数学');
      expect(read.skippedLines, 2);
    });

    test('the same meeting twice is one meeting', () {
      final List<ImportedCourse> courses = parse(
        reply(<String, Object?>{
          'courses': <Object?>[
            <String, Object?>{
              'name': '英语',
              'slots': <Object?>[
                <String, Object?>{'weekday': 1, 'start': 5, 'end': 6},
                <String, Object?>{'weekday': 1, 'start': 5, 'end': 6},
              ],
            },
          ],
        }),
      );

      expect(courses.single.slots, hasLength(1));
    });
  });

  group('the instruction', () {
    test('names the term it is asking about, and the shape it wants', () {
      final String prompt =
          timetableImportPrompt(periodCount: 9, totalWeeks: 18);

      expect(prompt, contains('9'));
      expect(prompt, contains('18'));
      // The two things a model gets wrong without being told: using a code
      // fence, and inventing a shape instead of the one asked for.
      expect(prompt, contains('只输出 JSON'));
      expect(prompt, contains('"slots"'));
      expect(prompt, contains('weekday'));
    });
  });
}
