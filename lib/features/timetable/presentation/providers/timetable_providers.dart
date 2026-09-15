import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/document_store.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/utils/calendar.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../todos/presentation/providers/todo_providers.dart' show clockProvider;
import '../../data/datasources/timetable_local_data_source.dart';
import '../../data/repositories/local_timetable_repository.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/period_time.dart';
import '../../domain/entities/term.dart';
import '../../domain/entities/timetable.dart';
import '../../domain/repositories/timetable_repository.dart';

export '../../../todos/presentation/providers/todo_providers.dart' show clockProvider;

/// File name of the timetable document.
const String timetableFileName = 'timetable.json';

final Provider<DocumentStore> timetableDocumentStoreProvider =
    Provider<DocumentStore>(
  (ref) => ref.watch(documentStoreFactoryProvider)(timetableFileName),
  name: 'timetableDocumentStore',
);

final Provider<TimetableRepository> timetableRepositoryProvider =
    Provider<TimetableRepository>(
  (ref) => LocalTimetableRepository(
    TimetableLocalDataSource(ref.watch(timetableDocumentStoreProvider)),
  ),
  name: 'timetableRepository',
);

/// Ids for new courses; overridden in tests with a deterministic sequence.
final Provider<IdGenerator> courseIdGeneratorProvider = Provider<IdGenerator>(
  (ref) => generateTodoId,
  name: 'courseIdGenerator',
);

/// The term and the courses in it.
///
/// One controller for both, because every rule worth having — a course's weeks
/// against the term's length, a slot against the number of periods — needs the
/// two together, and splitting them would mean each half reaching for the other
/// to answer a question about itself.
class TimetableController extends AsyncNotifier<Timetable> {
  @override
  Future<Timetable> build() async {
    final TimetableRepository repository = ref.watch(timetableRepositoryProvider);
    final Timetable? stored = await repository.load();
    // A fresh install has no term at all, and a timetable with no term cannot be
    // drawn — so one is made from today, which puts the user in week 1 of a
    // timetable that already looks like a timetable.
    return stored ?? Timetable.fresh(ref.read(clockProvider)());
  }

  /// Saves the term, trimming anything the new term can no longer hold.
  Future<void> setTerm(Term term) {
    return _replace((Timetable current) =>
        Timetable(term: term, courses: current.courses).trimmedToTerm());
  }

  Future<Course> addCourse({
    required String name,
    required List<CourseSlot> slots,
    required Set<int> weeks,
    String? room,
    String? note,
    int? color,
    String? backgroundImage,
    double backgroundDim = Course.defaultBackgroundDim,
  }) async {
    final Course created = Course.create(
      id: ref.read(courseIdGeneratorProvider)(),
      name: name,
      slots: slots,
      weeks: weeks,
      room: room,
      note: note,
      color: color,
      backgroundImage: backgroundImage,
      backgroundDim: backgroundDim,
      createdAt: ref.read(clockProvider)(),
    );
    await _replace((Timetable current) => current.withCourse(created));
    return created;
  }

  Future<void> editCourse(String id, Course Function(Course current) change) {
    return _replace((Timetable current) {
      final Course? existing = current.courseById(id);
      return existing == null ? current : current.withCourse(change(existing));
    });
  }


  Future<void> removeCourse(String id) {
    return _replace((Timetable current) => current.withoutCourse(id));
  }

  Future<void> _replace(Timetable Function(Timetable current) change) async {
    final Timetable current = await future;
    final Timetable updated = change(current);
    await ref.read(timetableRepositoryProvider).save(updated);
    if (ref.mounted) {
      state = AsyncData<Timetable>(updated);
    }
  }
}

final AsyncNotifierProvider<TimetableController, Timetable> timetableProvider =
    AsyncNotifierProvider<TimetableController, Timetable>(
  TimetableController.new,
  name: 'timetable',
);

/// The week the timetable is showing.
///
/// Held apart from the data because it is a view, not a fact: the term number
/// comes from the calendar, and looking at next week must not change what
/// "today" means anywhere else.
class SelectedWeek extends Notifier<int?> {
  @override
  int? build() => null;

  /// Shows [week]; `null` means "follow today".
  void show(int? week) => state = week;

  /// Moves [delta] weeks from wherever the view is now.
  void step(int delta, int currentWeek) {
    final int from = state ?? currentWeek;
    state = (from + delta).clamp(1, 60);
  }
}

final NotifierProvider<SelectedWeek, int?> selectedWeekProvider =
    NotifierProvider<SelectedWeek, int?>(
  SelectedWeek.new,
  name: 'selectedWeek',
);

/// The week the timetable is showing, resolving "follow today" against the term.
final Provider<int> shownWeekProvider = Provider<int>((ref) {
  final Timetable? timetable = ref.watch(timetableProvider).value;
  final DateTime now = ref.watch(clockProvider)();
  final int currentWeek = timetable?.term.weekOf(now) ?? 1;
  final int? selected = ref.watch(selectedWeekProvider);
  return selected ?? currentWeek;
});

/// The week today falls in, clamped into the term when it falls outside it.
final Provider<int> currentWeekProvider = Provider<int>((ref) {
  final Timetable? timetable = ref.watch(timetableProvider).value;
  final DateTime now = ref.watch(clockProvider)();
  final int? week = timetable?.term.weekOf(now);
  if (week != null) {
    return week;
  }
  // Before the term starts, week 1 is the honest answer; after it ends, the last
  // week is — there is no week 19 of an eighteen-week term.
  final int total = timetable?.term.totalWeeks ?? 18;
  return now.isBefore(timetable?.term.startMonday ?? now) ? 1 : total;
});

/// Today's courses, for the habits page's cousin: the widget and the timetable
/// header both ask this.
final Provider<List<CourseMeeting>> todaysCoursesProvider =
    Provider<List<CourseMeeting>>((ref) {
  final Timetable? timetable = ref.watch(timetableProvider).value;
  if (timetable == null) {
    return const <CourseMeeting>[];
  }
  return meetingsForDateIn(
    timetable.courses,
    timetable.term,
    startOfDay(ref.watch(clockProvider)()),
  );
});

/// Every collision between courses, for the warning the editor shows.
final Provider<List<CourseClash>> courseClashesProvider =
    Provider<List<CourseClash>>((ref) {
  final Timetable? timetable = ref.watch(timetableProvider).value;
  if (timetable == null) {
    return const <CourseClash>[];
  }
  return findCourseClashes(timetable.courses);
});

/// The periods a new course can be given, in order.
final Provider<List<PeriodTime>> periodsProvider = Provider<List<PeriodTime>>(
  (ref) => ref.watch(timetableProvider).value?.term.periods ?? kDefaultPeriods,
  name: 'timetablePeriods',
);

/// Whether the course widget is on one of the home screens.
///
/// Read from the platform after the first sync, because only Android knows; the
/// timetable page shows the answer rather than guessing, so it never offers to
/// add a tile that is already there.
class CourseWidgetPlaced extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool placed) => state = placed;
}

final NotifierProvider<CourseWidgetPlaced, bool> courseWidgetPlacedProvider =
    NotifierProvider<CourseWidgetPlaced, bool>(
  CourseWidgetPlaced.new,
  name: 'courseWidgetPlaced',
);
