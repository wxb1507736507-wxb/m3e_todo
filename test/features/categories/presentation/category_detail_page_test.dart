import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/categories/domain/entities/category.dart';
import 'package:m3e_todo/features/notes/domain/entities/note.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';

import '../../../support/fake_category_repository.dart';
import '../../../support/fake_note_repository.dart';
import '../../../support/fake_todo_repository.dart';
import '../../../support/sample_todo.dart';
import '../../../support/test_app.dart';

/// Opens the app on a phone-sized window and walks into the `工作` folder.
Future<void> openFolder(WidgetTester tester) async {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    buildTestApp(
      repository: FakeTodoRepository(<Todo>[
        sampleTodo(id: 't1', title: '写周报', categoryId: 'c1'),
        sampleTodo(id: 't2', title: '买咖啡豆'),
      ]),
      categoryRepository: FakeCategoryRepository(<Category>[
        Category.create(id: 'c1', name: '工作'),
      ]),
      noteRepository: FakeNoteRepository(<Note>[
        note(id: 'n1', body: '季度复盘的想法', categoryId: 'c1'),
        note(id: 'n2', body: '周末爬山'),
      ]),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(AppStrings.navCategories),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('工作'));
  await tester.pumpAndSettle();
}

Note note({required String id, required String body, String? categoryId}) {
  return Note.create(
    id: id,
    date: DateTime(2026, 3, 10),
    body: body,
    createdAt: DateTime(2026, 3, 10, 20),
    categoryId: categoryId,
  );
}

void main() {
  testWidgets('a folder shows its own todos and hides the rest', (
    WidgetTester tester,
  ) async {
    await openFolder(tester);

    expect(find.text('写周报'), findsOneWidget);
    expect(find.text('买咖啡豆'), findsNothing);
  });

  testWidgets('a folder browses its own notes too', (WidgetTester tester) async {
    await openFolder(tester);

    // The same switch the calendar uses, so there is one way to move between
    // what is left to do and what was written about it.
    await tester.tap(find.text(AppStrings.noteSection));
    await tester.pumpAndSettle();

    expect(find.text('季度复盘的想法'), findsOneWidget);
    expect(find.text('周末爬山'), findsNothing);
  });

  testWidgets('the search inside a folder stays inside the folder', (
    WidgetTester tester,
  ) async {
    await openFolder(tester);
    await tester.tap(find.text(AppStrings.noteSection));
    await tester.pumpAndSettle();

    // A query that only matches the note filed *outside* this folder: finding it
    // here would mean the folder was not really narrowing anything.
    await tester.enterText(find.byType(TextField).first, '爬山');
    await tester.pumpAndSettle();

    expect(find.text('周末爬山'), findsNothing);
    expect(find.text(AppStrings.noteSearchEmpty), findsOneWidget);
  });
}
