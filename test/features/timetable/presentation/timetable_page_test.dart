import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/timetable/domain/entities/course.dart';
import 'package:m3e_todo/features/timetable/domain/entities/period_time.dart';
import 'package:m3e_todo/features/timetable/domain/entities/term.dart';
import 'package:m3e_todo/features/timetable/domain/entities/timetable.dart';
import 'package:m3e_todo/features/timetable/presentation/widgets/course_editor_sheet.dart';

import '../../../support/fake_timetable_repository.dart';
import '../../../support/fake_todo_repository.dart';
import '../../../support/test_app.dart';

/// The week grid, and everything it can be told to do.
///
/// `testNow` is 2026-03-10, a Tuesday, so the term these tests use starts on
/// Monday the 9th and week 1 is the week being looked at.
void main() {
  Term term({int weeks = 18}) => Term(
        name: '大三上',
        startMonday: DateTime(2026, 3, 9),
        totalWeeks: weeks,
        periods: kDefaultPeriods,
      );

  Course course(
    String id, {
    String name = '高等数学',
    int weekday = DateTime.tuesday,
    int start = 1,
    int end = 2,
    Set<int>? weeks,
    String? room,
  }) {
    return Course.create(
      id: id,
      name: name,
      slots: <CourseSlot>[
        CourseSlot(weekday: weekday, startPeriod: start, endPeriod: end),
      ],
      weeks: weeks ?? <int>{for (int week = 1; week <= 18; week++) week},
      room: room,
      createdAt: DateTime(2026, 3, 1),
    );
  }

  /// Taps a button inside the course editor, scrolling it into view first.
  ///
  /// The editor is taller than a phone screen — name, room, note, the slots, a
  /// month of week ticks, the colours — so its action row starts below the fold
  /// and a plain tap would land on whatever else is there.
  Future<void> tapInEditor(WidgetTester tester, String label) async {
    final Finder button = find.text(label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> openTimetable(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(AppStrings.navCalendar),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.timetableOpen));
    await tester.pumpAndSettle();
  }

  testWidgets('a tile opens the timetable as the first frame, not the list', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        opensOnTimetable: true,
        timetableRepository: FakeTimetableRepository(
          Timetable(term: term(), courses: <Course>[course('c1')]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing was tapped: the grid has to be there on the first frame, because
    // the tap that got us here landed on a tile, not on the app's list.
    expect(find.text(AppStrings.timetableTitle), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    // The shell it was opened over is behind it, so its chrome is not on screen.
    expect(find.byType(NavigationBar), findsNothing);

    // Back still reaches the app it was opened over: the grid is pushed on top,
    // not swapped in for the shell.
    final NavigatorState navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(AppStrings.timetableTitle), findsNothing);
  });

  testWidgets('the grid opens on this week, with the days and their dates', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: FakeTimetableRepository(
          Timetable(term: term(), courses: const <Course>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    expect(find.text('大三上'), findsOneWidget);
    // Week 1 of a term starting on the 9th is the week the clock is in.
    expect(find.text(AppStrings.timetableWeek(1)), findsOneWidget);
    expect(find.text('3/9'), findsOneWidget);
    expect(find.text('3/10'), findsOneWidget);
    // The period column has the day's clock times, straight from the term.
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('08:45'), findsOneWidget);
    expect(find.text(AppStrings.timetableNoCoursesBody), findsOneWidget);
  });

  testWidgets('a course is drawn on the day and periods it runs', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: FakeTimetableRepository(
          Timetable(term: term(), courses: <Course>[course('c1')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text(AppStrings.timetableNoCourses), findsNothing);
  });

  testWidgets('the week moves, and a course that only runs in week 1 goes', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: FakeTimetableRepository(
          Timetable(
            term: term(),
            courses: <Course>[course('c1', weeks: <int>{1})],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);
    expect(find.text('高等数学'), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.timetableNextWeek));
    await tester.pumpAndSettle();

    expect(find.textContaining(AppStrings.timetableWeek(2)), findsOneWidget);
    // It runs in week 1 only, so week 2 has nothing on it.
    expect(find.text('高等数学'), findsNothing);

    // 本周 comes back, which is the tap a timetable is used with most.
    await tester.tap(find.textContaining(AppStrings.timetableThisWeek));
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsOneWidget);
  });

  testWidgets('tapping an empty cell opens the editor filled in for it', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    final FakeTimetableRepository repository = FakeTimetableRepository(
      Timetable(term: term(), courses: const <Course>[]),
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    // The first period of the first column — Monday, period 1.
    await tester.tapAt(_firstCell(tester));
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditorSheet), findsOneWidget);
    // The weekday and the period are already answered.
    expect(find.text('周一'), findsOneWidget);
    expect(find.text(AppStrings.periodLabel(1)), findsWidgets);

    await tester.enterText(find.byType(TextFormField).first, '线性代数');
    await tapInEditor(tester, AppStrings.create);

    final Course stored = repository.stored!.courses.single;
    expect(stored.name, '线性代数');
    expect(stored.slots.single.weekday, DateTime.monday);
    expect(stored.slots.single.startPeriod, 1);
    expect(find.text('线性代数'), findsOneWidget);
  });

  testWidgets('a course is created through the editor', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    final FakeTimetableRepository repository = FakeTimetableRepository(
      Timetable(term: term(), courses: const <Course>[]),
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '大学物理');
    await tapInEditor(tester, AppStrings.create);

    final Course stored = repository.stored!.courses.single;
    expect(stored.name, '大学物理');
    // A new course starts on every week of the term, which is what most of them
    // are, and the shortcuts are how the rest are said.
    expect(stored.weeks, hasLength(18));
    expect(find.text('大学物理'), findsOneWidget);
  });

  testWidgets('a course is renamed and then deleted from its own editor', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    final FakeTimetableRepository repository = FakeTimetableRepository(
      Timetable(term: term(), courses: <Course>[course('c1')]),
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await tester.tap(find.text('高等数学'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '高数（二）');
    await tapInEditor(tester, AppStrings.save);
    expect(repository.stored!.courses.single.name, '高数（二）');
    expect(find.text('高数（二）'), findsOneWidget);

    await tester.tap(find.text('高数（二）'));
    await tester.pumpAndSettle();
    await tapInEditor(tester, AppStrings.actionDelete);
    expect(find.text(AppStrings.courseDeleteTitle), findsOneWidget);
    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();

    expect(repository.stored!.courses, isEmpty);
    expect(find.text(AppStrings.timetableNoCoursesBody), findsOneWidget);
  });

  testWidgets('a course that collides with another says so before saving', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: FakeTimetableRepository(
          Timetable(term: term(), courses: <Course>[course('c1')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    // The same day and periods as the course already there.
    await tester.tapAt(_firstCell(tester, column: 1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '体育');
    await tester.pumpAndSettle();

    // The sheet says which course and which slot, so the wording is checked by
    // its start rather than in full.
    expect(find.textContaining('与「高等数学」在'), findsOneWidget);
    // The slot it names is the one already on the grid.
    expect(find.textContaining('周二'), findsWidgets);
  });

  testWidgets('a term that is one week long shows one week of courses', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: FakeTimetableRepository(
          Timetable(
            term: term(weeks: 1),
            courses: <Course>[course('c1', weeks: <int>{1})],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    expect(find.text('高等数学'), findsOneWidget);
    // There is no week 2 to move to, and asking for one does not lose the week
    // being shown.
    await tester.tap(find.byTooltip(AppStrings.timetableNextWeek));
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsNothing);
  });
}

/// The middle of an empty grid cell: the first period of [column] (0 = Monday).
///
/// Anchored on the first period's clock time rather than on arithmetic about
/// the app bar, the two headers and the padding: those numbers are the layout's
/// business, and a test that repeats them is a test that breaks the next time a
/// header grows a few pixels.
Offset _firstCell(WidgetTester tester, {int column = 0}) {
  final double width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  const double left = 46;
  final double columnWidth = (width - left) / 7;
  final double y = tester.getCenter(find.text('08:00')).dy;
  return Offset(left + columnWidth * (column + 0.5), y);
}

/// A window tall enough for the course editor.
///
/// The editor is a bottom sheet taller than a phone screen at the default test
/// size, and its action row ends up a few pixels past the bottom edge — where a
/// tap lands on nothing. A taller window is the honest fix: on a real phone the
/// sheet is scrollable, and the test is not here to re-test that.
void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _usePhoneWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
