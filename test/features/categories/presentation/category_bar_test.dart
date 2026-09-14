import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/categories/domain/entities/category.dart';
import 'package:m3e_todo/features/categories/presentation/providers/category_providers.dart';
import 'package:m3e_todo/features/categories/presentation/widgets/category_bar.dart';
import 'package:m3e_todo/features/categories/presentation/widgets/category_sheet.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/presentation/providers/todo_providers.dart';
import 'package:m3e_todo/features/todos/presentation/widgets/todo_tile.dart';

import '../../../support/fake_category_repository.dart';
import '../../../support/fake_note_repository.dart';
import '../../../support/fake_todo_repository.dart';
import '../../../support/sample_todo.dart';
import '../../../support/test_app.dart';

/// The strip above the list: the whole point of it is that it is *there* — on
/// the same screen as the todos, small enough not to compete with them, and
/// always one tap from narrowing the list.
void main() {
  testWidgets('the strip stays smaller than the tiles it summarises', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[
          sampleTodo(id: 'a', title: '写周报'),
        ]),
        categoryRepository: FakeCategoryRepository(<Category>[
          Category.create(id: 'c1', name: '工作'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final double bar = tester.getSize(find.byType(CategoryBar)).height;
    final double tile = tester.getSize(find.byType(TodoTile).first).height;

    // A ratio, not a magic number: the requirement is that the strip is
    // subordinate to the list, and that has to survive either height changing.
    expect(bar, lessThan(tile));
    expect(bar, CategoryBar.height);
  });

  testWidgets('nothing to summarise means no strip', (WidgetTester tester) async {
    // The empty state explains itself; a row of zeroes above it is noise.
    await tester.pumpWidget(buildTestApp(repository: FakeTodoRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryBar), findsNothing);
  });

  testWidgets('a chip shows how many are in its folder', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[
          sampleTodo(id: 'a', title: '写周报', categoryId: 'c1'),
          sampleTodo(id: 'b', title: '写月报', categoryId: 'c1'),
          sampleTodo(id: 'c', title: '买菜'),
        ]),
        categoryRepository: FakeCategoryRepository(<Category>[
          Category.create(id: 'c1', name: '工作'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final Finder work = find.descendant(
      of: find.byType(CategoryBar),
      matching: find.text('工作'),
    );
    expect(work, findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(of: work, matching: find.byType(InkWell)).first,
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a chip narrows the list to that folder', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[
          sampleTodo(id: 'a', title: '写周报', categoryId: 'c1'),
          sampleTodo(id: 'b', title: '买菜'),
        ]),
        categoryRepository: FakeCategoryRepository(<Category>[
          Category.create(id: 'c1', name: '工作'),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('买菜'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(CategoryBar),
        matching: find.text('工作'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('写周报'), findsOneWidget);
    expect(find.text('买菜'), findsNothing);

    // And back: the strip is a way of reading the list, never a trap.
    await tester.tap(
      find.descendant(
        of: find.byType(CategoryBar),
        matching: find.text(AppStrings.categoryAll),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('买菜'), findsOneWidget);
  });

  testWidgets('a folder can be added from the strip and named there', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeCategoryRepository categories = FakeCategoryRepository();
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[
          sampleTodo(id: 'a', title: '写周报'),
        ]),
        categoryRepository: categories,
      ),
    );
    await tester.pumpAndSettle();

    // Present even with no folders at all: otherwise the feature would be
    // unreachable from the one screen it belongs to.
    await tester.tap(
      find.descendant(
        of: find.byType(CategoryBar),
        matching: find.text(AppStrings.categoryNew),
      ),
    );
    await tester.pumpAndSettle();

    // What deleting does is explained where deleting is offered, and nowhere
    // else: a create sheet has no delete button to explain.
    expect(find.text(AppStrings.categoryDeleteHint), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byType(CategorySheet),
        matching: find.byType(TextFormField),
      ),
      '生活',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(CategorySheet),
        matching: find.text(AppStrings.create),
      ),
    );
    await tester.pumpAndSettle();

    expect((await categories.loadAll()).single.name, '生活');
    expect(
      find.descendant(
        of: find.byType(CategoryBar),
        matching: find.text('生活'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('long-pressing a chip renames its folder', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeCategoryRepository categories = FakeCategoryRepository(<Category>[
      Category.create(id: 'c1', name: '工作'),
    ]);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(<Todo>[sampleTodo(id: 'a', title: '写周报')]),
        categoryRepository: categories,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.descendant(
        of: find.byType(CategoryBar),
        matching: find.text('工作'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CategorySheet), findsOneWidget);
    expect(find.text(AppStrings.categoryDeleteHint), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(CategorySheet),
        matching: find.byType(TextFormField),
      ),
      '工作台',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(CategorySheet),
        matching: find.text(AppStrings.save),
      ),
    );
    await tester.pumpAndSettle();

    expect((await categories.loadAll()).single.name, '工作台');
  });

  testWidgets('deleting a folder unfiles its todos instead of losing them', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
      sampleTodo(id: 'a', title: '写周报', categoryId: 'c1'),
      sampleTodo(id: 'b', title: '买菜'),
    ]);
    final FakeCategoryRepository categories = FakeCategoryRepository(<Category>[
      Category.create(id: 'c1', name: '工作'),
    ]);
    await tester.pumpWidget(
      buildTestApp(
        repository: repository,
        categoryRepository: categories,
        // Deleting a folder also unfiles the notes in it, so the notes have to
        // be a double too: a real repository would put disk I/O between the tap
        // and the assertion, and the test clock does not drive that.
        noteRepository: FakeNoteRepository(),
      ),
    );
    await tester.pumpAndSettle();

    // Filtered to the folder being deleted, which is the case that would leave
    // the list looking broken if the filter were left pointing at it.
    await tester.tap(
      find.descendant(
        of: find.byType(CategoryBar),
        matching: find.text('工作'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.descendant(
        of: find.byType(CategoryBar),
        matching: find.text('工作'),
      ),
    );
    await tester.pumpAndSettle();
    // Scrolled to first: on a phone the sheet's action row sits below the fold,
    // and a tap at a spot the widget does not occupy hits whatever is there.
    final Finder delete = find.descendant(
      of: find.byType(CategorySheet),
      matching: find.text(AppStrings.actionDelete),
    );
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();

    expect(await categories.loadAll(), isEmpty);
    // Unfiled, not deleted: deleting a folder takes the label off, it does not
    // destroy what was labelled.
    final List<Todo> stored = await repository.loadAll();
    expect(stored.map((Todo todo) => todo.title), <String>['写周报', '买菜']);
    expect(stored.every((Todo todo) => todo.categoryId == null), isTrue);
    // And the list is showing everything again rather than the folder.
    expect(find.text('买菜'), findsOneWidget);
  });

  testWidgets('the unfiled chip survives having nothing unfiled', (
    WidgetTester tester,
  ) async {
    // Otherwise filing the last todo away would hide the chip you need in order
    // to come back to the view you are already in.
    final ProviderContainer container = ProviderContainer(
      overrides: [
        todoRepositoryProvider.overrideWithValue(FakeTodoRepository()),
        categoryRepositoryProvider.overrideWithValue(FakeCategoryRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CategoryBar())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.categoryUnfiled), findsNothing);

    container.read(todoFilterProvider.notifier).setCategory(kUnfiledCategoryId);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.categoryUnfiled), findsOneWidget);
  });
}

/// A phone-sized window: narrow enough that the strip has to scroll sideways
/// rather than wrap, which is what keeps it a single compact row.
void _usePhoneWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
