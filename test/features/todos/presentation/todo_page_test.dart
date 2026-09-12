import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/presentation/widgets/todo_editor_sheet.dart';

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
