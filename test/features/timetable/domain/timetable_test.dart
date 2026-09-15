import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/timetable/data/models/timetable_model.dart';
import 'package:m3e_todo/features/timetable/domain/entities/course.dart';
import 'package:m3e_todo/features/timetable/domain/entities/period_time.dart';
import 'package:m3e_todo/features/timetable/domain/entities/term.dart';
import 'package:m3e_todo/features/timetable/domain/entities/timetable.dart';

void main() {
  /// A term starting on the Monday of 2026-08-31, eighteen weeks long.
  Term term({int weeks = 18, List<PeriodTime>? periods}) => Term(
        name: '大三上',
        startMonday: DateTime(2026, 8, 31),
        totalWeeks: weeks,
        periods: periods ?? kDefaultPeriods,
      );

  Course course(
    String id, {
    String name = '高等数学',
    List<CourseSlot>? slots,
    Set<int>? weeks,
    String? room,
    String? note,
    String? backgroundImage,
    double? backgroundDim,
  }) {
    return Course.create(
      id: id,
      name: name,
      slots: slots ??
          <CourseSlot>[
            const CourseSlot(weekday: DateTime.tuesday, startPeriod: 1, endPeriod: 2),
          ],
      weeks: weeks ?? <int>{1, 2, 3},
      room: room,
      note: note,
      backgroundImage: backgroundImage,
      backgroundDim: backgroundDim ?? Course.defaultBackgroundDim,
      createdAt: DateTime(2026, 8, 20),
    );
  }

  group('term weeks', () {
    test('the term\'s own Monday is week 1', () {
      expect(term().weekOf(DateTime(2026, 8, 31)), 1);
    });

    test('the Sunday of that week is still week 1', () {
      expect(term().weekOf(DateTime(2026, 9, 6)), 1);
    });

    test('the next Monday starts week 2', () {
      expect(term().weekOf(DateTime(2026, 9, 7)), 2);
    });

    test('a day before the term has no week rather than a negative one', () {
      expect(term().weekOf(DateTime(2026, 8, 30)), isNull);
    });

    test('a day after the last week has no week either', () {
      expect(term(weeks: 3).weekOf(DateTime(2026, 9, 21)), isNull);
      expect(term(weeks: 3).weekOf(DateTime(2026, 9, 20)), 3);
    });

    test('a week can be turned back into its Monday', () {
      expect(term().mondayOfWeek(3), DateTime(2026, 9, 14));
      expect(term().daysOfWeek(3).last, DateTime(2026, 9, 20));
    });

    test('a period range prints the clock times of its ends', () {
      expect(term().rangeLabel(1, 2), '08:00 - 09:35');
      expect(term().rangeLabel(1, 99), isNull);
    });
  });

  group('course', () {
    test('a course needs a name, a slot and a week', () {
      expect(
        () => Course.create(
          id: 'c',
          name: '  ',
          slots: <CourseSlot>[
            const CourseSlot(weekday: 1, startPeriod: 1, endPeriod: 1),
          ],
          weeks: <int>{1},
          createdAt: DateTime(2026, 8, 20),
        ),
        throwsA(isA<CourseValidationException>()),
      );
      expect(
        () => Course.create(
          id: 'c',
          name: '高数',
          slots: const <CourseSlot>[],
          weeks: <int>{1},
          createdAt: DateTime(2026, 8, 20),
        ),
        throwsA(isA<CourseValidationException>()),
      );
      expect(
        () => Course.create(
          id: 'c',
          name: '高数',
          slots: <CourseSlot>[
            const CourseSlot(weekday: 1, startPeriod: 1, endPeriod: 1),
          ],
          weeks: const <int>{},
          createdAt: DateTime(2026, 8, 20),
        ),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('a course background is set, changed and cleared', () {
      final Course plain = course('a');
      expect(plain.backgroundImage, isNull);

      final Course withPicture = plain.edited(
        backgroundImage: '/files/attachments/first.png',
        backgroundDim: 0.5,
      );
      expect(withPicture.backgroundImage, '/files/attachments/first.png');
      expect(withPicture.backgroundDim, 0.5);

      // Editing the room is not editing the picture: the two decisions are
      // independent, and losing one while making the other would be a bug the
      // user only sees on the grid.
      final Course renamed = withPicture.edited(name: '高数(下)', room: '教三 201');
      expect(renamed.backgroundImage, '/files/attachments/first.png');
      expect(renamed.backgroundDim, 0.5);

      expect(renamed.edited(clearBackgroundImage: true).backgroundImage, isNull);
    });

    test('a scrim outside the slider range is clamped on the way in', () {
      expect(course('a', backgroundDim: 3).backgroundDim, 0.9);
      expect(course('a', backgroundDim: -1).backgroundDim, 0.0);
      expect(course('a', backgroundDim: 0.4).backgroundDim, 0.4);
    });

    test('a slot reads as a weekday and a period range', () {
      expect(
        const CourseSlot(weekday: 2, startPeriod: 1, endPeriod: 2).label,
        '周二 第1-2节',
      );
      expect(
        const CourseSlot(weekday: 7, startPeriod: 3, endPeriod: 3).label,
        '周日 第3节',
      );
    });

    test('every week of the term is spelled 每周', () {
      expect(
        course('c', weeks: <int>{for (int w = 1; w <= 18; w++) w}).weeksLabel(18),
        '每周',
      );
    });

    test('runs of weeks are collapsed but a pattern is kept', () {
      expect(course('c', weeks: <int>{1, 2, 3, 4}).weeksLabel(18), '第1-4周');
      expect(
        course('c', weeks: <int>{1, 3, 5, 7}).weeksLabel(18),
        '第1, 3, 5, 7周',
      );
      expect(
        course('c', weeks: <int>{1, 2, 3, 9, 10}).weeksLabel(18),
        '第1-3, 9-10周',
      );
    });

    test('a course can meet on two weekdays', () {
      final Course two = course(
        'c',
        slots: <CourseSlot>[
          const CourseSlot(weekday: 1, startPeriod: 1, endPeriod: 2),
          const CourseSlot(weekday: 3, startPeriod: 3, endPeriod: 4),
        ],
      );
      expect(two.slotsLabel, '周一 第1-2节 / 周三 第3-4节');
      expect(two.meetsOnDay(3), isTrue);
      expect(two.meetsOnDay(2), isFalse);
      expect(two.meetsOn(3, <int>{4}), isTrue);
      expect(two.meetsOn(3, <int>{1}), isFalse);
    });
  });

  group('what a week holds', () {
    test('only the courses that run that week are listed', () {
      final List<Course> courses = <Course>[
        course('a', weeks: <int>{1}),
        course('b', name: '线性代数', weeks: <int>{2, 3}),
      ];
      // The course meets on Tuesdays: week 1's Tuesday is 2026-09-01.
      expect(
        meetingsOn(courses, 1, DateTime(2026, 9, 1)).map((CourseMeeting m) => m.course.id),
        <String>['a'],
      );
      // Week 2's Tuesday is the 8th, and by then only the second course runs.
      expect(
        meetingsOn(courses, 2, DateTime(2026, 9, 8)).map((CourseMeeting m) => m.course.id),
        <String>['b'],
      );
    });

    test('the day is looked up by its weekday', () {
      final List<Course> courses = <Course>[course('a', weeks: <int>{1})];
      expect(meetingsOn(courses, 1, DateTime(2026, 9, 1)), hasLength(1));
      expect(meetingsOn(courses, 1, DateTime(2026, 9, 2)), isEmpty);
    });

    test('a day outside the term has nothing on it', () {
      final List<Course> courses = <Course>[course('a', weeks: <int>{1})];
      expect(meetingsForDateIn(courses, term(), DateTime(2026, 8, 24)), isEmpty);
    });

    test('meetings come back in period order', () {
      final List<Course> courses = <Course>[
        course(
          'late',
          slots: <CourseSlot>[
            const CourseSlot(weekday: 2, startPeriod: 5, endPeriod: 6),
          ],
          weeks: <int>{1},
        ),
        course(
          'early',
          slots: <CourseSlot>[
            const CourseSlot(weekday: 2, startPeriod: 1, endPeriod: 2),
          ],
          weeks: <int>{1},
        ),
      ];
      expect(
        meetingsOn(courses, 1, DateTime(2026, 9, 1)).map((CourseMeeting m) => m.course.id),
        <String>['early', 'late'],
      );
    });
  });

  group('clashes', () {
    test('two courses in the same slot clash only in shared weeks', () {
      final List<Course> courses = <Course>[
        course('a', weeks: <int>{1, 2}),
        course('b', name: '大学物理', weeks: <int>{3, 4}),
      ];
      expect(findCourseClashes(courses), isEmpty);

      final List<Course> overlapping = <Course>[
        course('a', weeks: <int>{1, 2}),
        course('b', name: '大学物理', weeks: <int>{2, 3}),
      ];
      final List<CourseClash> clashes = findCourseClashes(overlapping);
      expect(clashes, hasLength(1));
      expect(clashes.single.weeks, <int>{2});
      expect(clashes.single.label, '周二 第1-2节');
    });

    test('different days never clash', () {
      final List<Course> courses = <Course>[
        course('a'),
        course(
          'b',
          name: '大学物理',
          slots: <CourseSlot>[
            const CourseSlot(weekday: 4, startPeriod: 1, endPeriod: 2),
          ],
        ),
      ];
      expect(findCourseClashes(courses), isEmpty);
    });

    test('a partial period overlap is still a clash', () {
      final List<Course> courses = <Course>[
        course('a'),
        course(
          'b',
          name: '大学物理',
          slots: <CourseSlot>[
            const CourseSlot(weekday: 2, startPeriod: 2, endPeriod: 3),
          ],
        ),
      ];
      expect(findCourseClashes(courses), hasLength(1));
    });
  });

  group('timetable', () {
    test('a fresh timetable starts this week with a usable day', () {
      final Timetable fresh = Timetable.fresh(DateTime(2026, 9, 16));
      expect(fresh.term.startMonday, DateTime(2026, 9, 14));
      expect(fresh.term.weekOf(DateTime(2026, 9, 16)), 1);
      expect(fresh.term.periods, isNotEmpty);
      expect(fresh.isEmpty, isTrue);
    });

    test('a course is added, edited and removed', () {
      final Timetable base = Timetable(term: term(), courses: const <Course>[]);
      final Timetable withOne = base.withCourse(course('a'));
      expect(withOne.courses, hasLength(1));
      expect(withOne.courseById('a')?.name, '高等数学');

      final Timetable edited = withOne.withCourse(
        withOne.courseById('a')!.edited(name: '高数（二）'),
      );
      expect(edited.courses, hasLength(1));
      expect(edited.courseById('a')?.name, '高数（二）');

      expect(edited.withoutCourse('a').courses, isEmpty);
    });

    test('shortening the term trims the courses that no longer fit', () {
      final Timetable longer = Timetable(
        term: term(),
        courses: <Course>[
          course('keeps', weeks: <int>{1, 2, 17}),
          course('drops', name: '体育', weeks: <int>{19}),
        ],
      );
      final Timetable trimmed = Timetable(
        term: longer.term.edited(totalWeeks: 12),
        courses: longer.courses,
      ).trimmedToTerm();

      expect(trimmed.courses.map((Course c) => c.id), <String>['keeps']);
      expect(trimmed.courseById('keeps')!.weeks, <int>{1, 2});
    });

    test('a course whose periods no longer exist is dropped', () {
      final Timetable fivePeriodDays = Timetable(
        term: term(periods: kDefaultPeriods.take(4).toList()),
        courses: <Course>[
          course(
            'late',
            slots: <CourseSlot>[
              const CourseSlot(weekday: 1, startPeriod: 8, endPeriod: 9),
            ],
          ),
        ],
      ).trimmedToTerm();
      expect(fivePeriodDays.courses, isEmpty);
    });
  });

  group('the file', () {
    test('a timetable survives the round trip', () {
      final Timetable original = Timetable(
        term: term(weeks: 16),
        courses: <Course>[
          course('a', room: '教三 201', note: '张老师'),
          course(
            'b',
            name: '大学物理',
            slots: <CourseSlot>[
              const CourseSlot(weekday: 4, startPeriod: 3, endPeriod: 5),
            ],
            weeks: <int>{1, 3, 5},
          ),
        ],
      );
      final Timetable restored = TimetableModel.fromJson(
        TimetableModel.toJson(original),
      )!;
      expect(restored.term, original.term);
      expect(restored.courses, original.courses);
    });

    test('weeks are written in order so two saves compare cleanly', () {
      final Map<String, Object?> json =
          TimetableModel.courseToJson(course('a', weeks: <int>{9, 1, 5}));
      expect(json['weeks'], <int>[1, 5, 9]);
    });

    test("a course's own picture and scrim survive the round trip", () {
      final Course withPicture = course(
        'a',
        backgroundImage: '/files/attachments/course.png',
        backgroundDim: 0.55,
      );
      final Course restored = TimetableModel.courseFromJson(
        TimetableModel.courseToJson(withPicture),
      )!;
      expect(restored.backgroundImage, '/files/attachments/course.png');
      expect(restored.backgroundDim, 0.55);
      expect(restored, withPicture);
    });

    test('a course in a colour only carries no picture keys', () {
      final Map<String, Object?> json = TimetableModel.courseToJson(course('a'));
      expect(json.containsKey('backgroundImage'), isFalse);
      expect(json.containsKey('backgroundDim'), isFalse);
      expect(
        TimetableModel.courseFromJson(json)!.backgroundImage,
        isNull,
      );
    });

    test('a scrim nobody could have chosen is clamped, not kept', () {
      Map<String, Object?> withDim(Object? raw) => <String, Object?>{
            'id': 'a',
            'name': '高数',
            'backgroundImage': '/files/attachments/course.png',
            'backgroundDim': raw,
            'slots': <Object?>[
              <String, Object?>{'weekday': 1, 'start': 1, 'end': 2},
            ],
            'weeks': <int>[1],
          };
      // Above the slider's ceiling the picture would be gone; below zero it
      // would be at full strength over the text. Neither is reachable from the
      // UI, which is exactly why a hand-edited file has to be clamped.
      expect(TimetableModel.courseFromJson(withDim(4))!.backgroundDim, 0.9);
      expect(TimetableModel.courseFromJson(withDim(-2))!.backgroundDim, 0.0);
      expect(
        TimetableModel.courseFromJson(withDim('very dim'))!.backgroundDim,
        Course.defaultBackgroundDim,
      );
    });

    test('an older file without pictures loads in colour', () {
      final Course restored = TimetableModel.courseFromJson(<String, Object?>{
        'id': 'a',
        'name': '高数',
        'color': 0xFFE53935,
        'slots': <Object?>[
          <String, Object?>{'weekday': 1, 'start': 1, 'end': 2},
        ],
        'weeks': <int>[1],
      })!;
      expect(restored.backgroundImage, isNull);
      expect(restored.backgroundDim, Course.defaultBackgroundDim);
      expect(restored.color, 0xFFE53935);
    });

    test('the term remembers its weekend and its other weeks', () {
      final Timetable original = Timetable(
        term: term().edited(showWeekend: false, showOtherWeeks: true),
        courses: const <Course>[],
      );

      final Timetable restored =
          TimetableModel.fromJson(TimetableModel.toJson(original))!;

      expect(restored.term.showWeekend, isFalse);
      expect(restored.term.showOtherWeeks, isTrue);
      expect(restored.term, original.term);
    });

    test('a file written before those two existed gets the grid it had', () {
      final Timetable restored = TimetableModel.fromJson(<String, Object?>{
        'version': 1,
        'term': <String, Object?>{
          'name': '大三上',
          'startMonday': '2026-08-31T00:00:00.000',
          'totalWeeks': 18,
        },
        'courses': <Object?>[],
      })!;

      // Seven columns and nothing from other weeks: the way that file was
      // drawn when it was written.
      expect(restored.term.showWeekend, isTrue);
      expect(restored.term.showOtherWeeks, isFalse);
      expect(restored.term.shownWeekdays, hasLength(7));
    });

    test('a term without the weekend shows five days', () {
      expect(term().shownWeekdays, <int>[1, 2, 3, 4, 5, 6, 7]);
      expect(
        term().edited(showWeekend: false).shownWeekdays,
        <int>[1, 2, 3, 4, 5],
      );
    });

    test('a document with no term is not a timetable', () {
      expect(TimetableModel.fromJson(<String, Object?>{'courses': <Object?>[]}), isNull);
    });

    test('courses outlive a term that cannot be read', () {
      // A term is what the grid hangs on, so an unreadable one costs the term —
      // but not the afternoon the user spent typing courses in. Reading the term
      // first, as this used to, threw the courses away with it, and the next save
      // wrote that loss to disk: a whole timetable gone without a warning.
      final Map<String, Object?> document = <String, Object?>{
        'version': 3,
        'term': <String, Object?>{'name': '大三上', 'totalWeeks': 18},
        'courses': <Object?>[TimetableModel.courseToJson(course('c1'))],
      };

      expect(TimetableModel.fromJson(document), isNull);

      final Timetable restored = TimetableModel.fromJson(
        document,
        today: DateTime(2026, 9, 15),
      )!;
      expect(restored.courses.map((Course c) => c.id), <String>['c1']);
      expect(restored.term.name, '我的课程表');
      expect(restored.term.startMonday, DateTime(2026, 9, 14));
    });

    test('a course with no slots or no weeks is dropped, not fatal', () {
      expect(
        TimetableModel.courseFromJson(<String, Object?>{
          'id': 'a',
          'name': '高数',
          'weeks': <int>[1],
        }),
        isNull,
      );
      expect(
        TimetableModel.courseFromJson(<String, Object?>{
          'id': 'a',
          'name': '高数',
          'slots': <Object?>[
            <String, Object?>{'weekday': 1, 'start': 1, 'end': 2},
          ],
        }),
        isNull,
      );
    });

    test('a broken period list falls back to the default day', () {
      final Term restored = TimetableModel.termFromJson(<String, Object?>{
        'name': '大三上',
        'startMonday': '2026-08-31T00:00:00.000',
        'totalWeeks': 18,
        'periods': <Object?>[
          <String, Object?>{'index': 1, 'start': 500, 'end': 100},
        ],
      })!;
      expect(restored.periods, kDefaultPeriods);
    });
  });
}
