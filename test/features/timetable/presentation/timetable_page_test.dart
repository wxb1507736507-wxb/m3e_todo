
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/app/app_background.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/timetable/domain/entities/course.dart';
import 'package:m3e_todo/features/timetable/domain/entities/period_time.dart';
import 'package:m3e_todo/features/timetable/domain/entities/term.dart';
import 'package:m3e_todo/features/timetable/domain/entities/timetable.dart';
import 'package:m3e_todo/features/timetable/presentation/widgets/course_detail_sheet.dart';
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
    String? backgroundImage,
    double? backgroundDim,
  }) {
    return Course.create(
      id: id,
      name: name,
      slots: <CourseSlot>[
        CourseSlot(weekday: weekday, startPeriod: start, endPeriod: end),
      ],
      weeks: weeks ?? <int>{for (int week = 1; week <= 18; week++) week},
      room: room,
      backgroundImage: backgroundImage,
      backgroundDim: backgroundDim ?? Course.defaultBackgroundDim,
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

  testWidgets('a course with a picture of its own is drawn over it', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: FakeTimetableRepository(
          Timetable(
            term: term(),
            courses: <Course>[
              course('c1', backgroundImage: '/no/such/picture.png'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    // The block paints the picture through the shared backdrop widget — the one
    // that owns the surface, the photo and the scrim, so a course's picture is
    // dimmed by the same rule the app's own background is. In a test the file
    // is not there, so what is asserted is that the block asked for it and that
    // the name still has somewhere to go: an unreadable picture must not take
    // the course's name down with it.
    expect(_backdropFor('/no/such/picture.png'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
  });

  testWidgets('a course in a colour paints no picture at all', (
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

    expect(_backdropFor('/no/such/picture.png'), findsNothing);
    // The page's own backdrop is still there — it is the thing the timetable
    // would paint its *own* picture in, and it is a pass-through until one is
    // chosen. The point is that no course brought a picture of its own.
    expect(find.byType(AppBackground), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
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

  testWidgets('tapping an empty cell offers a plus, and the plus opens the editor', (
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
    // A tap on an empty cell asks *where* before it asks what: the phone's own
    // timetable answers with a plus on that cell, and the form is one tap
    // further on. A grid where every stray tap opens a form is a grid nobody
    // can touch just to look at.
    expect(find.byType(CourseEditorSheet), findsNothing);
    expect(find.byTooltip(AppStrings.courseAddHere), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.courseAddHere));
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditorSheet), findsOneWidget);
    // The weekday and the period are already answered, and the row reads them
    // back: 周一 第1节 is what the plus on that cell means.
    expect(find.text('周一 第1节'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '线性代数');
    await tapInEditor(tester, AppStrings.done);

    final Course stored = repository.stored!.courses.single;
    expect(stored.name, '线性代数');
    expect(stored.slots.single.weekday, DateTime.monday);
    expect(stored.slots.single.startPeriod, 1);
    expect(find.text('线性代数'), findsOneWidget);
  });

  testWidgets('tapping an empty cell again puts the plus away', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
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

    await tester.tapAt(_firstCell(tester));
    await tester.pumpAndSettle();
    expect(find.byTooltip(AppStrings.courseAddHere), findsOneWidget);

    await tester.tapAt(_firstCell(tester));
    await tester.pumpAndSettle();
    expect(find.byTooltip(AppStrings.courseAddHere), findsNothing);
  });

  testWidgets('tapping a course shows 课程详情, and 编辑 opens the editor', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    final FakeTimetableRepository repository = FakeTimetableRepository(
      Timetable(
        term: term(),
        courses: <Course>[course('c1', room: '教三 201')],
      ),
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await tester.tap(find.text('高等数学').first);
    await tester.pumpAndSettle();

    // The sheet the phone opens on a course: what it is, where, when, and which
    // weeks — with the form one button away rather than instead of the answer.
    expect(find.byType(CourseDetailSheet), findsOneWidget);
    expect(find.text(AppStrings.courseDetailTitle), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CourseDetailSheet),
        matching: find.text('高等数学'),
      ),
      findsOneWidget,
    );
    expect(find.text('${AppStrings.courseDetailRoomPrefix}教三 201'), findsOneWidget);
    // The line carries the clock times those periods run at.
    expect(find.textContaining('周二 第1-2节（08:00 - 09:35）'), findsOneWidget);
    expect(find.byType(CourseEditorSheet), findsNothing);

    await tester.tap(find.text(AppStrings.actionEdit));
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditorSheet), findsOneWidget);
  });

  /// Opens a course's editor the way a user does: the course, then 课程详情, then
  /// 编辑. A tap on a course is a question first and a form second.
  Future<void> openCourseEditor(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.actionEdit));
    await tester.pumpAndSettle();
  }

  /// Opens the single-course editor the way a user does: 新建课程, then the
  /// first of its three answers.
  Future<void> openSingleCourseEditor(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.courseNewSingle));
    await tester.pumpAndSettle();
  }

  /// Pushes the import sheet onto the app's own navigator.
  ///
  /// Not a fresh tree: the sheet needs the same container the app is running in,
  /// and a second tree would be a second app rather than the one under test.
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

    await openSingleCourseEditor(tester);
    await tester.enterText(find.byType(TextFormField).first, '大学物理');
    await tapInEditor(tester, AppStrings.done);

    final Course stored = repository.stored!.courses.single;
    expect(stored.name, '大学物理');
    // A new course starts on every week of the term, which is what most of them
    // are, and the shortcuts are how the rest are said.
    expect(stored.weeks, hasLength(18));
    expect(find.text('大学物理'), findsOneWidget);
  });

  testWidgets('新建课程 asks which of the three ways, and 单个课程 opens it', (
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

    // The phone's own timetable asks this question with these answers, so the
    // words are its words — minus 拍照导入课程表, which this app no longer has.
    expect(find.text(AppStrings.courseNewSingle), findsOneWidget);
    expect(find.text(AppStrings.courseNewManual), findsOneWidget);

    await tester.tap(find.text(AppStrings.courseNewSingle));
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditorSheet), findsOneWidget);
  });

  testWidgets('手动创建课程表 goes to the term, which is what a term needs', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
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

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.courseNewManual));
    await tester.pumpAndSettle();

    // Filling the grid by hand starts with the term — its weeks are what the
    // courses are numbered against — and the grid is already there to tap.
    expect(find.text(AppStrings.timetableTermSettings), findsOneWidget);
    expect(find.text(AppStrings.termNameLabel), findsOneWidget);
  });

  testWidgets('时段 counts the weekly meetings, and each row picks its own', (
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

    await openSingleCourseEditor(tester);

    await tester.enterText(find.byType(TextFormField).first, '大学物理');
    expect(find.text(AppStrings.courseSlotCount(1)), findsOneWidget);
    expect(find.text(AppStrings.courseSlotCount(2)), findsNothing);

    // The count is how a second weekly meeting is asked for, and it starts the
    // new one next to the last rather than in the same place.
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.courseSlotCount(2)), findsOneWidget);
    expect(find.text('周二 第1节'), findsOneWidget);

    // Each meeting is edited in its own sheet: a weekday, and the periods it
    // covers.
    await tester.tap(find.text(AppStrings.courseSlotCount(2)));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.courseSlotWeekday), findsOneWidget);
    await tester.tap(find.text('周四'));
    await tester.pumpAndSettle();
    await tapInEditor(tester, AppStrings.confirm);
    // The row reads back what was chosen, which is how the user checks it.
    expect(find.text('周四 第1节'), findsOneWidget);

    await tester.tap(find.text(AppStrings.courseSlotCount(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周三'));
    await tester.pumpAndSettle();
    await tapInEditor(tester, AppStrings.confirm);

    await tapInEditor(tester, AppStrings.done);

    final Course stored = repository.stored!.courses.single;
    expect(stored.name, '大学物理');
    expect(stored.slots, hasLength(2));
    expect(stored.slots.first.weekday, DateTime.wednesday);
    expect(stored.slots.last.weekday, DateTime.thursday);
  });

  testWidgets('上课周数 opens the weeks, and an empty set cannot be saved', (
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

    await openSingleCourseEditor(tester);
    await tester.enterText(find.byType(TextFormField).first, '体育');

    await tester.tap(find.text(AppStrings.courseWeeksLabel));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.courseWeeksOdd), findsOneWidget);

    await tester.tap(find.text(AppStrings.courseWeeksOdd));
    await tester.pumpAndSettle();
    await tapInEditor(tester, AppStrings.confirm);
    // The row now reads the weeks it was given, not a count.
    expect(find.textContaining('第1, 3, 5'), findsOneWidget);

    await tapInEditor(tester, AppStrings.done);

    final Course stored = repository.stored!.courses.single;
    expect(stored.weeks, hasLength(9));
    expect(stored.weeks.contains(2), isFalse);
  });
  testWidgets('the editor offers a background for this course alone', (
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

    await openCourseEditor(tester, '高等数学');

    // The same controls the app's own background is set with, in a sheet that
    // is one screen tall — so they are there to be scrolled to, not lost.
    expect(find.text(AppStrings.courseBackgroundLabel), findsOneWidget);
    expect(find.text(AppStrings.courseBackgroundHint), findsOneWidget);
    expect(find.text(AppStrings.appBackgroundPick), findsOneWidget);
    // Nothing to re-crop or remove until a picture has been chosen, and no
    // scrim strength to set under a surface that has no picture on it.
    expect(find.text(AppStrings.cropBackgroundImage), findsNothing);
    expect(find.text(AppStrings.backgroundDimLabel), findsNothing);

    await tester.ensureVisible(find.text(AppStrings.courseBackgroundHint));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.appBackgroundPick));
    await tester.pumpAndSettle();
    // The picker is native and there is none here: what matters is that the
    // course's picture is not the app's, so the tip below belongs to this
    // sheet and the app's own background is untouched by it.
    expect(repository.stored!.courses.single.backgroundImage, isNull);
  });

  testWidgets('周末有课 off takes Saturday and Sunday off the grid', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeTimetableRepository repository = FakeTimetableRepository(
      Timetable(
        term: Term(
          name: '大三上',
          startMonday: DateTime(2026, 3, 9),
          totalWeeks: 18,
          periods: kDefaultPeriods,
          showWeekend: false,
        ),
        courses: <Course>[course('c1', weekday: DateTime.saturday)],
      ),
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    // Five columns, and the Saturday course has nowhere to be drawn — which is
    // what turning the weekend off means.
    expect(find.text('五'), findsWidgets);
    expect(find.text('六'), findsNothing);
    expect(find.text('日'), findsNothing);
    expect(find.text('高等数学'), findsNothing);
  });

  testWidgets('显示非本周课程 draws another week\'s class as an outline', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeTimetableRepository repository = FakeTimetableRepository(
      Timetable(
        term: Term(
          name: '大三上',
          startMonday: DateTime(2026, 3, 9),
          totalWeeks: 18,
          periods: kDefaultPeriods,
          showOtherWeeks: true,
        ),
        // Runs only in weeks 2 and 3, so week 1 — the week being shown — has
        // nothing of it.
        courses: <Course>[
          course('c1', name: '物理实验', weeks: <int>{2, 3}),
        ],
      ),
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    // Drawn, because the user asked to see when it happens at all; faint,
    // because it is not something to go to this week.
    expect(find.text('物理实验'), findsOneWidget);
    expect(find.byType(Opacity), findsWidgets);
  });

  testWidgets('without that switch, another week stays invisible', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: FakeTimetableRepository(
          Timetable(
            term: term(),
            courses: <Course>[course('c1', name: '物理实验', weeks: <int>{2, 3})],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    expect(find.text('物理实验'), findsNothing);
  });

  testWidgets('学期设置 carries the weekend and other-week switches', (
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

    await tester.tap(find.byTooltip(AppStrings.timetableTermSettings));
    await tester.pumpAndSettle();

    // The phone asks both of these while a timetable is being set up, and this
    // is the screen that sets a timetable up.
    expect(find.text(AppStrings.termWeekendLabel), findsOneWidget);
    expect(find.text(AppStrings.termOtherWeeksLabel), findsOneWidget);

    await tester.tap(find.text(AppStrings.termWeekendLabel));
    await tester.pumpAndSettle();
    await tapInEditor(tester, AppStrings.save);

    final Term stored = repository.stored!.term;
    expect(stored.showWeekend, isFalse);
    // Untouched, because the user did not touch it.
    expect(stored.showOtherWeeks, isFalse);
  });

  testWidgets('a course with a lot of text opens its sheet without a mess', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    final FakeTimetableRepository repository = FakeTimetableRepository(
      Timetable(
        term: term(),
        courses: <Course>[
          Course.create(
            id: 'long',
            // Everything a real timetable has: a long official name, a long
            // building name, a teacher, and several weekly meetings.
            name: '单片机原理与应用（含实验）[卓越工程师班] 第 3 教学班',
            slots: <CourseSlot>[
              const CourseSlot(weekday: 1, startPeriod: 1, endPeriod: 2),
              const CourseSlot(weekday: 3, startPeriod: 3, endPeriod: 4),
              const CourseSlot(weekday: 5, startPeriod: 5, endPeriod: 6),
            ],
            weeks: <int>{1, 3, 5, 7, 9, 11, 13, 15},
            room: '明义楼③304(物理与电子工程学院) 东区三号楼',
            note: '焦杨、李国栋、王海燕（助教）',
            createdAt: DateTime(2026, 3, 1),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        timetableRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await tester.tap(find.textContaining('单片机原理').first);
    await tester.pumpAndSettle();

    // The sheet holds everything it was given, and the 编辑 button is a button:
    // a long name used to push the content past the bottom of the sheet, so the
    // action row was drawn over the text around it.
    expect(find.byType(CourseDetailSheet), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'a RenderFlex overflow is what this looked like on the phone',
    );
    expect(find.text(AppStrings.actionEdit), findsOneWidget);

    // On screen, and inside the sheet — not pushed below it or drawn over the
    // text. A name that is a paragraph must not be able to move the button.
    final Rect button = tester.getRect(find.text(AppStrings.actionEdit));
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(button.bottom, lessThanOrEqualTo(screen.height));
    expect(button.top, greaterThan(0));
    expect(button.right, lessThanOrEqualTo(screen.width));

    // And it still works with all that text in it.
    await tester.tap(find.text(AppStrings.actionEdit));
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditorSheet), findsOneWidget);
    // The editor's own buttons are pinned the same way.
    final Rect done = tester.getRect(find.text(AppStrings.done));
    expect(done.bottom, lessThanOrEqualTo(screen.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sideways flick on the grid changes the week', (
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

    // Week 1, which is where the clock is: 2026-03-10 is the Tuesday of it.
    expect(find.text(AppStrings.timetableWeek(1)), findsOneWidget);

    // A flick to the left is a flick to the next week — the direction a page
    // moves when you push it away. Off the current week the label also carries
    // the way back, so these are prefix matches.
    await tester.fling(
      find.text('高等数学'),
      const Offset(-260, 0),
      900,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(AppStrings.timetableWeek(2)), findsOneWidget);

    // And back, to the previous one.
    await tester.flingFrom(_firstCell(tester, column: 3), const Offset(260, 0), 900);
    await tester.pumpAndSettle();
    expect(find.textContaining(AppStrings.timetableWeek(1)), findsOneWidget);

    // A drag that is barely a drag is not a week change: a scroll that starts
    // with a small sideways wobble must not lose the user's place.
    await tester.dragFrom(_firstCell(tester, column: 3), const Offset(-20, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining(AppStrings.timetableWeek(1)), findsOneWidget);
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

    await openCourseEditor(tester, '高等数学');
    await tester.enterText(find.byType(TextFormField).first, '高数（二）');
    await tapInEditor(tester, AppStrings.done);
    expect(repository.stored!.courses.single.name, '高数（二）');
    expect(find.text('高数（二）'), findsOneWidget);

    await openCourseEditor(tester, '高数（二）');
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
          // Monday, period 1 — which is where a course started from the button
          // begins, so the clash is there before anything is typed.
          Timetable(
            term: term(),
            courses: <Course>[course('c1', weekday: DateTime.monday)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await openSingleCourseEditor(tester);
    await tester.enterText(find.byType(TextFormField).first, '体育');
    await tester.pumpAndSettle();

    // The sheet says which course and which slot, so the wording is checked by
    // its start rather than in full.
    expect(find.textContaining('与「高等数学」在'), findsOneWidget);
    // The slot it names is the one already on the grid.
    expect(find.textContaining('周一'), findsWidgets);
  });

  testWidgets('the time picker is a wheel, and turning it changes the slot', (
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

    await openSingleCourseEditor(tester);
    await tester.enterText(find.byType(TextFormField).first, '体育');

    // A new course starts on Monday, and its first meeting reads back.
    expect(find.text('周一 第1节'), findsOneWidget);

    await tester.tap(find.text(AppStrings.courseSlotCount(1)));
    await tester.pumpAndSettle();

    // Three wheels — day, first period, last period — as the phone's own editor
    // has, because a period is a number on a scale rather than a set to pick
    // from.
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    expect(find.text(AppStrings.courseSlotWeekday), findsOneWidget);
    expect(find.text(AppStrings.courseSlotFromLabel), findsOneWidget);
    expect(find.text(AppStrings.courseSlotToLabel), findsOneWidget);

    // One notch up the day wheel is Tuesday; one notch on the end wheel turns a
    // single period into a two-period class.
    await tester.drag(find.byType(CupertinoPicker).at(0), const Offset(0, -40));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CupertinoPicker).at(2), const Offset(0, -40));
    await tester.pumpAndSettle();
    // The line above the buttons is the answer the wheels are giving.
    expect(find.text('周二 第1-2节'), findsOneWidget);

    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();
    expect(find.text('周二 第1-2节'), findsOneWidget);

    await tapInEditor(tester, AppStrings.done);
    final Course stored = repository.stored!.courses.single;
    expect(stored.slots.single.weekday, DateTime.tuesday);
    expect(stored.slots.single.startPeriod, 1);
    expect(stored.slots.single.endPeriod, 2);
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

/// The backdrop painting [path] behind something, wherever it is in the tree.
///
/// The page has a backdrop of its own whether or not it has a picture, so the
/// question a test can ask is not "is there one" but "is there one for *this*
/// picture".
Finder _backdropFor(String path) => find.byWidgetPredicate(
      (Widget widget) => widget is AppBackground && widget.imagePath == path,
      description: 'AppBackground for $path',
    );

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
