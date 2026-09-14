import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/calendar/presentation/calendar_page.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';

import '../../../support/fake_todo_repository.dart';
import '../../../support/sample_todo.dart';
import '../../../support/test_app.dart';

/// Opens the app and switches to the calendar destination.
///
/// The test window is 800x600, which is wider than the rail breakpoint, so the
/// destination lives in the [NavigationRail] rather than the bottom bar.
Future<void> openCalendar(
  WidgetTester tester, {
  List<Todo> todos = const <Todo>[],
}) async {
  // A window tall enough for the page to lay out as it does on a phone: the
  // grid reserves six rows so it cannot jump while swiping, which is more than
  // the 600-pixel default the test binding starts with. Wider than the rail
  // breakpoint, so the destinations are still in the NavigationRail.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    buildTestApp(repository: FakeTodoRepository(todos)),
  );
  await tester.pumpAndSettle();

  await tester.tap(
    find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text(AppStrings.navCalendar),
    ),
  );
  await tester.pumpAndSettle();
}

/// A todo due on [day] of March 2026 — the month the fixed test clock is in.
Todo marchTodo({
  required String id,
  required String title,
  required int day,
  DateTime? completedAt,
}) {
  return sampleTodo(
    id: id,
    title: title,
    dueDate: DateTime(2026, 3, day),
    completedAt: completedAt,
  );
}

void main() {
  // The clock is pinned to 2026-03-10 09:30 by buildTestApp, so "today" is the
  // 10th and the grid always opens on March 2026.
  testWidgets('the destination opens the month grid on the current month', (
    WidgetTester tester,
  ) async {
    await openCalendar(tester);

    expect(find.byType(CalendarPage), findsOneWidget);
    expect(find.text(AppStrings.calendarMonthLabel(2026, 3)), findsOneWidget);
    // The title follows the destination instead of still claiming to be the
    // todo list.
    expect(find.text(AppStrings.calendarTitle), findsOneWidget);
  });

  testWidgets('the selected day defaults to today and lists its todos', (
    WidgetTester tester,
  ) async {
    await openCalendar(
      tester,
      todos: <Todo>[
        marchTodo(id: 'a', title: '交周报', day: 10),
        marchTodo(id: 'b', title: '买咖啡', day: 12),
      ],
    );

    expect(find.text('交周报'), findsOneWidget);
    expect(find.text('买咖啡'), findsNothing);
  });

  testWidgets('choosing another day shows that day only', (
    WidgetTester tester,
  ) async {
    await openCalendar(
      tester,
      todos: <Todo>[
        marchTodo(id: 'a', title: '交周报', day: 10),
        marchTodo(id: 'b', title: '买咖啡', day: 12),
      ],
    );

    // Day cells are addressed by their number; March 2026 has a single "12".
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();

    expect(find.text('买咖啡'), findsOneWidget);
    expect(find.text('交周报'), findsNothing);
  });

  testWidgets('a day with no history says so instead of showing an empty list', (
    WidgetTester tester,
  ) async {
    await openCalendar(
      tester,
      todos: <Todo>[marchTodo(id: 'a', title: '交周报', day: 10)],
    );

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.calendarNoTodos), findsOneWidget);
  });

  testWidgets('completions are grouped under the day they were finished', (
    WidgetTester tester,
  ) async {
    await openCalendar(
      tester,
      todos: <Todo>[
        sampleTodo(
          id: 'a',
          title: '已完成的旧事',
          completedAt: DateTime(2026, 3, 8, 15),
        ),
      ],
    );

    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.calendarCompletedLegend), findsOneWidget);
    expect(find.text('已完成的旧事'), findsOneWidget);
  });

  testWidgets('month navigation moves the grid in both directions', (
    WidgetTester tester,
  ) async {
    await openCalendar(tester);

    await tester.tap(find.byTooltip(AppStrings.calendarNextMonth));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.calendarMonthLabel(2026, 4)), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.calendarPreviousMonth));
    await tester.tap(find.byTooltip(AppStrings.calendarPreviousMonth));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.calendarMonthLabel(2026, 2)), findsOneWidget);
  });

  testWidgets('the grid can be swiped from month to month', (
    WidgetTester tester,
  ) async {
    await openCalendar(tester);

    // A calendar you cannot flick through is a calendar nobody uses: the arrows
    // are for precision, the swipe is for browsing.
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.calendarMonthLabel(2026, 4)), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.calendarMonthLabel(2026, 3)), findsOneWidget);

    // Two flicks back, each landing a month away.
    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.calendarMonthLabel(2026, 1)), findsOneWidget);
  });

  testWidgets('the today action comes back after wandering off', (
    WidgetTester tester,
  ) async {
    await openCalendar(tester);

    await tester.tap(find.byTooltip(AppStrings.calendarNextMonth));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.calendarToday));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.calendarMonthLabel(2026, 3)), findsOneWidget);
  });

  testWidgets('searching finds a todo from another day', (
    WidgetTester tester,
  ) async {
    await openCalendar(
      tester,
      todos: <Todo>[
        marchTodo(id: 'a', title: '交周报', day: 10),
        marchTodo(id: 'b', title: '买咖啡', day: 12),
      ],
    );

    await tester.enterText(find.byType(TextField), '咖啡');
    await tester.pumpAndSettle();

    expect(find.text('买咖啡'), findsOneWidget);
    // The row is no longer under a single day, so it states its own date.
    expect(find.text('3月12日'), findsOneWidget);
    expect(find.text('交周报'), findsNothing);
  });

  testWidgets('tapping a search hit lands the grid on its day', (
    WidgetTester tester,
  ) async {
    await openCalendar(
      tester,
      todos: <Todo>[
        marchTodo(id: 'a', title: '交周报', day: 10),
        marchTodo(id: 'b', title: '买咖啡', day: 12),
      ],
    );

    await tester.enterText(find.byType(TextField), '咖啡');
    await tester.pumpAndSettle();
    await tester.tap(find.text('买咖啡'));
    await tester.pumpAndSettle();

    // Search is cleared and the 12th is selected, so the day view is back.
    expect(find.text('3月12日'), findsNothing);
    expect(find.text('买咖啡'), findsOneWidget);
    expect(find.text('交周报'), findsNothing);
  });

  testWidgets('an empty search result explains itself', (
    WidgetTester tester,
  ) async {
    await openCalendar(
      tester,
      todos: <Todo>[marchTodo(id: 'a', title: '交周报', day: 10)],
    );

    await tester.enterText(find.byType(TextField), '不存在的关键词');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.emptySearchTitle), findsOneWidget);
  });

  testWidgets('the date-jump control opens the platform picker', (
    WidgetTester tester,
  ) async {
    await openCalendar(tester);

    await tester.tap(find.byTooltip(AppStrings.calendarJumpToDate));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  // Alignment is the one property of a month grid that a screenshot cannot
  // confirm but a wrong weekday silently ruins: every todo would appear under
  // the wrong day name. The grid is Monday-first, and the header row carries
  // the day names, so a cell and its column header must share a centre.
  testWidgets('the 1st sits under its real weekday column', (
    WidgetTester tester,
  ) async {
    // March 2026 starts on a Sunday, so the 1st belongs in the last column.
    await openCalendar(tester);

    final double firstDx = tester.getCenter(find.text('1')).dx;
    expect(firstDx, tester.getCenter(find.text('日')).dx);
  });

  testWidgets('a month starting mid-week aligns the same way', (
    WidgetTester tester,
  ) async {
    // September 2026 starts on a Tuesday, which exercises the leading-offset
    // arithmetic on a value other than "0 or 6".
    await openCalendar(tester);

    for (int i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip(AppStrings.calendarNextMonth));
      await tester.pumpAndSettle();
    }
    expect(find.text(AppStrings.calendarMonthLabel(2026, 9)), findsOneWidget);

    expect(tester.getCenter(find.text('1')).dx, tester.getCenter(find.text('二')).dx);
    // ...and the 1st is the only cell in its row, so the 2nd follows it.
    expect(
      tester.getCenter(find.text('2')).dx,
      tester.getCenter(find.text('三')).dx,
    );
  });
}
