import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/timetable/domain/entities/course.dart';
import 'package:m3e_todo/features/timetable/domain/entities/period_time.dart';
import 'package:m3e_todo/features/timetable/domain/entities/term.dart';
import 'package:m3e_todo/features/timetable/domain/entities/timetable.dart';
import 'package:m3e_todo/features/timetable/domain/timetable_import.dart';
import 'package:m3e_todo/features/timetable/presentation/providers/timetable_providers.dart';

import '../../../support/fake_timetable_repository.dart';
import '../../../support/sample_todo.dart' show testNow;

/// Importing a picture into the timetable, at the level where the counts live.
void main() {
  late FakeTimetableRepository repository;
  late ProviderContainer container;

  Term term() => Term(
        name: '大三上',
        startMonday: DateTime(2026, 3, 9),
        totalWeeks: 18,
        periods: kDefaultPeriods,
      );

  setUp(() {
    repository = FakeTimetableRepository(
      Timetable(term: term(), courses: const <Course>[]),
    );
    container = ProviderContainer(
      overrides: [
        timetableRepositoryProvider.overrideWithValue(repository),
        clockProvider.overrideWithValue(() => testNow),
      ],
    );
  });

  tearDown(() => container.dispose());

  ImportedCourse imported(
    String name, {
    String? room,
    List<CourseSlot>? slots,
  }) {
    return ImportedCourse(
      name: name,
      room: room,
      slots: slots ??
          const <CourseSlot>[
            CourseSlot(weekday: DateTime.tuesday, startPeriod: 1, endPeriod: 2),
          ],
    );
  }

  Future<({int imported, int alreadyThere})> import(List<ImportedCourse> courses) async {
    await container.read(timetableProvider.future);
    return container.read(timetableProvider.notifier).importCourses(courses);
  }

  group('识图导课', () {
    test('the courses a picture held land in the timetable', () async {
      final ({int imported, int alreadyThere}) result = await import(<ImportedCourse>[
        imported('高等数学', room: '教三 201'),
        imported('大学物理'),
      ]);

      expect(result.imported, 2);
      expect(result.alreadyThere, 0);
      final Timetable stored = repository.stored!;
      expect(stored.courses, hasLength(2));
      final Course maths = stored.courses.firstWhere((Course c) => c.name == '高等数学');
      expect(maths.room, '教三 201');
      expect(maths.slots.single.weekday, DateTime.tuesday);
      // A photograph cannot say which weeks a course runs, so the whole term is
      // the answer — and the only one that cannot silently lose a class.
      expect(maths.weeks, hasLength(18));
    });

    test('one write, not one per course', () async {
      await import(<ImportedCourse>[imported('A'), imported('B'), imported('C')]);

      // Three courses, one save: an import interrupted half way through would
      // otherwise leave a timetable that is neither the old one nor the new one.
      expect(repository.saveCount, 1);
    });

    test('the same picture twice does not double the timetable', () async {
      await import(<ImportedCourse>[imported('高等数学'), imported('大学物理')]);

      final ({int imported, int alreadyThere}) second =
          await import(<ImportedCourse>[imported('高等数学'), imported('大学物理')]);

      expect(second.imported, 0);
      expect(second.alreadyThere, 2);
      expect(repository.stored!.courses, hasLength(2));
    });

    test('a name already in the timetable is matched however it is spaced', () async {
      await import(<ImportedCourse>[imported('高等数学')]);

      // A screenshot and a person disagree about spaces more than about
      // anything else, and a course that appears twice is worse than one that
      // appears once with a space in it.
      final ({int imported, int alreadyThere}) second =
          await import(<ImportedCourse>[imported('高等 数学')]);

      expect(second.imported, 0);
      expect(second.alreadyThere, 1);
      expect(repository.stored!.courses, hasLength(1));
    });

    test('the new courses are added to what the term already had', () async {
      await import(<ImportedCourse>[imported('高等数学')]);

      final ({int imported, int alreadyThere}) second =
          await import(<ImportedCourse>[imported('大学物理')]);

      expect(second.imported, 1);
      expect(
        repository.stored!.courses.map((Course course) => course.name),
        containsAll(<String>['高等数学', '大学物理']),
      );
    });

    test('a course with nothing to place it is dropped, not fatal', () async {
      final ({int imported, int alreadyThere}) result =
          await import(<ImportedCourse>[
        imported('没有时间的课', slots: const <CourseSlot>[]),
        imported('高等数学'),
      ]);

      expect(result.imported, 1);
      expect(repository.stored!.courses.single.name, '高等数学');
    });

    test('importing nothing writes nothing', () async {
      final ({int imported, int alreadyThere}) result =
          await import(const <ImportedCourse>[]);

      expect(result.imported, 0);
      expect(repository.saveCount, 0);
      expect(repository.stored!.courses, isEmpty);
    });
  });
}
