import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/categories/domain/entities/category.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_reminder.dart';
import 'package:m3e_todo/features/todos/presentation/widgets/todo_editor_sheet.dart';

import '../../../support/fake_category_repository.dart';
import '../../../support/fake_todo_repository.dart';
import '../../../support/sample_todo.dart';
import '../../../support/test_app.dart';

void main() {
  testWidgets('shows the empty state when nothing is stored', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildTestApp(repository: FakeTodoRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.emptyAllTitle), findsOneWidget);
  });

  testWidgets('renders the todos it loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[
          sampleTodo(id: 'a', title: '写周报'),
          sampleTodo(id: 'b', title: '买咖啡'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('写周报'), findsOneWidget);
    expect(find.text('买咖啡'), findsOneWidget);
    expect(find.text(AppStrings.emptyAllTitle), findsNothing);
  });

  testWidgets('ticking a todo persists the change', (
    WidgetTester tester,
  ) async {
    final FakeTodoRepository repository =
        FakeTodoRepository(<Todo>[sampleTodo(id: 'a', title: '写周报')]);

    await tester.pumpWidget(buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    final List<Todo> stored = await repository.loadAll();
    expect(stored.single.isCompleted, isTrue);
    expect(repository.saveCount, 1);
  });

  testWidgets('searching narrows the visible list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[
          sampleTodo(id: 'a', title: '写周报'),
          sampleTodo(id: 'b', title: '买咖啡'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '咖啡');
    await tester.pumpAndSettle();

    expect(find.text('买咖啡'), findsOneWidget);
    expect(find.text('写周报'), findsNothing);
  });

  testWidgets('the completed destination shows only finished todos', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[
          sampleTodo(id: 'a', title: '进行中的事'),
          sampleTodo(id: 'b', title: '已完成的事').completeAt(testNow),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(AppStrings.navCompleted),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已完成的事'), findsOneWidget);
    expect(find.text('进行中的事'), findsNothing);
  });

  testWidgets('the new-todo action opens the editor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildTestApp(repository: FakeTodoRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(TodoEditorSheet), findsOneWidget);
  });

  testWidgets('creating a todo through the editor stores it', (
    WidgetTester tester,
  ) async {
    final FakeTodoRepository repository = FakeTodoRepository();

    await tester.pumpWidget(buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // The first field is the title; the second is the notes.
    await tester.enterText(find.byType(TextFormField).first, '写周报');
    await tester.tap(find.text(AppStrings.create));
    await tester.pumpAndSettle();

    final List<Todo> stored = await repository.loadAll();
    expect(stored.single.title, '写周报');
    expect(find.text('写周报'), findsOneWidget);
    expect(find.byType(TodoEditorSheet), findsNothing);
  });

  testWidgets('the editor stores the card and text colours it was given', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    final FakeTodoRepository repository = FakeTodoRepository();

    await tester.pumpWidget(buildTestApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '写周报');

    await _chooseColor(tester, '靛蓝');
    await _chooseColor(tester, '浅黄');

    await tester.tap(find.text(AppStrings.create));
    await tester.pumpAndSettle();

    final Todo stored = (await repository.loadAll()).single;
    expect(stored.accentColor, 0xFF3949AB);
    expect(stored.textColor, 0xFFFFF9C4);
  });

  testWidgets('the editor warns about a text colour it cannot be read on', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    await tester.pumpWidget(buildTestApp(repository: FakeTodoRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '写周报');

    // Yellow text on a yellow card: legible to nobody, so the editor says so.
    await _chooseColor(tester, '黄');
    await _chooseColor(tester, '浅黄');
    expect(find.text(AppStrings.colorContrastWarning), findsOneWidget);

    // A colour that can be read takes the warning away again.
    await _chooseColor(tester, '近黑');
    expect(find.text(AppStrings.colorContrastWarning), findsNothing);
  });

  testWidgets('the editor fits its background-image buttons on a phone', (
    WidgetTester tester,
  ) async {
    // A phone window rather than the 800×600 the test binding defaults to: this
    // row only runs out of room on a narrow screen, and running out of room
    // paints Flutter's striped overflow banner over the last button instead of
    // failing loudly — which is exactly what was reported from the device.
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[
          // A file that is not there: the layout is the same either way, and
          // the preview falls back to its placeholder.
          sampleTodo(id: 'a', backgroundImage: '/no/such/picture.png'),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('写周报'));
    await tester.pumpAndSettle();

    // A picture in the editor brings two more buttons with it, and three do not
    // fit beside the label. Every one of them has to stay on screen.
    for (final String label in <String>[
      AppStrings.pickBackgroundImage,
      AppStrings.cropBackgroundImage,
      AppStrings.clearBackgroundImage,
    ]) {
      final Rect rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(360), reason: label);
    }
  });

  testWidgets('the editor stores a reminder choice made for one todo', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
      // A due date is what brings the reminder controls into the editor.
      sampleTodo(id: 'a', dueDate: DateTime(2026, 4, 1)),
    ]);

    await tester.pumpWidget(buildTestApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写周报'));
    await tester.pumpAndSettle();

    // Quiet for this one, whatever the app-wide default happens to be.
    final Finder quiet = find.text(AppStrings.reminderModeSilent);
    await tester.dragUntilVisible(
      quiet,
      find.byType(SingleChildScrollView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(quiet);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.save));
    await tester.pumpAndSettle();

    expect((await repository.loadAll()).single.reminder, TodoReminder.silent);
  });

  testWidgets('dragging a row reorders what is stored, filtered or not', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    // The middle todo is completed, so the "进行中" tab hides it: the visible
    // rows are then a *subset* of the stored ones, which is the case that used
    // to move the wrong row or appear to do nothing.
    final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
      sampleTodo(id: 'a', title: '第一件'),
      sampleTodo(id: 'b', title: '已完成的事').completeAt(testNow),
      sampleTodo(id: 'c', title: '第三件'),
    ]);

    await tester.pumpWidget(buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(AppStrings.navActive),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已完成的事'), findsNothing);

    // Long-press the last row and drag it above the first.
    final Offset from = tester.getCenter(find.text('第三件'));
    final TestGesture drag = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await drag.moveBy(const Offset(0, -200));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(
      (await repository.loadAll()).map((Todo todo) => todo.id),
      <String>['c', 'a', 'b'],
      reason: 'the hidden completed row must keep its place',
    );
    // And the list on screen follows: '第三件' is above '第一件' now.
    expect(
      tester.getCenter(find.text('第三件')).dy,
      lessThan(tester.getCenter(find.text('第一件')).dy),
    );
  });

  testWidgets('a drop shows its new order before the write finishes', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
      sampleTodo(id: 'a', title: '第一件'),
      sampleTodo(id: 'b', title: '第二件'),
    ]);

    await tester.pumpWidget(buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    // Hold the write open: with the order shown only after it lands, the row
    // would animate back to where it started and then jump — the flicker.
    repository.holdWrites();
    final TestGesture drag =
        await tester.startGesture(tester.getCenter(find.text('第二件')));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await drag.moveBy(const Offset(0, -200));
    await tester.pump();
    await drag.up();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester.getCenter(find.text('第二件')).dy,
      lessThan(tester.getCenter(find.text('第一件')).dy),
      reason: 'the drop must land immediately, not after the disk',
    );

    repository.releaseWrite();
    await tester.pumpAndSettle();
    expect(
      (await repository.loadAll()).map((Todo todo) => todo.id),
      <String>['b', 'a'],
    );
  });

  testWidgets('the editor files a todo under a folder', (
    WidgetTester tester,
  ) async {
    _useTallWindow(tester);
    // A folder to file under: the editor only offers the picker when there is
    // something to choose.
    final FakeTodoRepository repository = FakeTodoRepository();
    await tester.pumpWidget(
      buildTestApp(
        repository: repository,
        categoryRepository: FakeCategoryRepository(<Category>[
          Category.create(id: 'c1', name: '工作'),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '写周报');

    // Scrolled into view rather than dragged there: `ensureVisible` asks the
    // sheet's own scrollable, so the test does not have to guess which of the
    // several scrollables in the tree is the right one.
    final Finder folder = find.text('工作');
    await tester.ensureVisible(folder);
    await tester.pumpAndSettle();
    await tester.tap(folder);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.create));
    await tester.pumpAndSettle();

    expect((await repository.loadAll()).single.categoryId, 'c1');
  });

  testWidgets('deleting a todo removes it from the list and offers undo', (
    WidgetTester tester,
  ) async {
    final FakeTodoRepository repository =
        FakeTodoRepository(<Todo>[sampleTodo(id: 'a', title: '写周报')]);

    await tester.pumpWidget(buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.actionDelete));
    await tester.pumpAndSettle();

    expect(await repository.loadAll(), isEmpty);
    expect(find.text(AppStrings.undo), findsOneWidget);

    await tester.tap(find.text(AppStrings.undo));
    await tester.pumpAndSettle();

    expect((await repository.loadAll()).single.id, 'a');
  });
}

/// Scrolls the editor down to the swatch named [label] and taps it.
///
/// The colour section sits well below the fold in the test window, so the
/// swatches have to be brought into view before they can be tapped — a tap on an
/// off-screen swatch silently hits nothing.
Future<void> _chooseColor(WidgetTester tester, String label) async {
  final Finder swatch = find.byTooltip(label);
  await tester.dragUntilVisible(
    swatch,
    find.byType(SingleChildScrollView).first,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
  await tester.tap(swatch);
  await tester.pumpAndSettle();
}


/// A phone-sized window: narrow enough for the bottom navigation bar and for the
/// row heights a thumb actually drags.
void _usePhoneWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Gives the editor a window tall enough for a swatch to be tapped once it has
/// been scrolled to.
///
/// The default 800×600 test window is shorter than the sheet's own content, so
/// the swatch a test has just scrolled to can still land half under the sheet's
/// action bar — and a tap there hits the bar instead.
void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
