import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_draft.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_priority.dart';
import 'package:m3e_todo/features/todos/domain/usecases/add_todo.dart';
import 'package:m3e_todo/features/todos/domain/usecases/clear_completed_todos.dart';
import 'package:m3e_todo/features/todos/domain/usecases/delete_todo.dart';
import 'package:m3e_todo/features/todos/domain/usecases/load_todos.dart';
import 'package:m3e_todo/features/todos/domain/usecases/reorder_todos.dart';
import 'package:m3e_todo/features/todos/domain/usecases/restore_todo.dart';
import 'package:m3e_todo/features/todos/domain/usecases/toggle_todo.dart';
import 'package:m3e_todo/features/todos/domain/usecases/update_todo.dart';

import '../../../support/fake_todo_repository.dart';
import '../../../support/sample_todo.dart';

void main() {
  group('LoadTodos', () {
    test('returns what the repository holds', () async {
      final FakeTodoRepository repository =
          FakeTodoRepository(<Todo>[sampleTodo(title: '任务')]);
      final List<Todo> todos = await LoadTodos(repository)();
      expect(todos.single.title, '任务');
    });
  });

  group('AddTodo', () {
    test('prepends the new todo so it is immediately visible', () async {
      final FakeTodoRepository repository =
          FakeTodoRepository(<Todo>[sampleTodo(id: 'existing')]);
      final AddTodo addTodo = AddTodo(
        repository,
        idGenerator: () => 'generated-id',
        clock: () => testNow,
      );

      final List<Todo> result = await addTodo(
        const TodoDraft(title: '  新任务  ', priority: TodoPriority.high),
      );

      expect(result.length, 2);
      expect(result.first.id, 'generated-id');
      expect(result.first.title, '新任务');
      expect(result.first.priority, TodoPriority.high);
      expect(result.first.createdAt, testNow);
      expect(repository.saveCount, 1);
    });

    test('normalises a due date to midnight', () async {
      final FakeTodoRepository repository = FakeTodoRepository();
      final AddTodo addTodo = AddTodo(
        repository,
        idGenerator: () => 'id',
        clock: () => testNow,
      );

      final List<Todo> result = await addTodo(
        TodoDraft(title: '任务', dueDate: DateTime(2026, 4, 2, 18, 30)),
      );

      expect(result.single.dueDate, DateTime(2026, 4, 2));
    });

    test('propagates a blank-title rejection without writing', () async {
      final FakeTodoRepository repository = FakeTodoRepository();
      final AddTodo addTodo = AddTodo(
        repository,
        idGenerator: () => 'id',
        clock: () => testNow,
      );

      await expectLater(
        addTodo(const TodoDraft(title: '   ')),
        throwsA(isA<TodoValidationException>()),
      );
      expect(repository.saveCount, 0);
    });
  });

  group('UpdateTodo', () {
    test('edits the matching todo and leaves the others alone', () async {
      final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
        sampleTodo(id: 'a', title: '旧'),
        sampleTodo(id: 'b', title: '不变'),
      ]);

      final List<Todo> result = await UpdateTodo(repository)(
        'a',
        const TodoDraft(title: '新', notes: '备注'),
      );

      expect(result.first.title, '新');
      expect(result.first.notes, '备注');
      expect(result.last.title, '不变');
    });

    test('is a no-op for an unknown id', () async {
      final FakeTodoRepository repository =
          FakeTodoRepository(<Todo>[sampleTodo(id: 'a')]);

      final List<Todo> result = await UpdateTodo(repository)(
        'missing',
        const TodoDraft(title: '新'),
      );

      expect(result.single.id, 'a');
    });
  });

  group('ToggleTodo', () {
    test('completes an open todo using the injected clock', () async {
      final FakeTodoRepository repository =
          FakeTodoRepository(<Todo>[sampleTodo(id: 'a')]);
      final ToggleTodo toggle = ToggleTodo(repository, clock: () => testNow);

      final List<Todo> result = await toggle('a');

      expect(result.single.completedAt, testNow);
      expect(repository.saveCount, 1);
    });

    test('reopens a completed todo', () async {
      final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
        sampleTodo(id: 'a').completeAt(DateTime(2026, 1, 1)),
      ]);
      final ToggleTodo toggle = ToggleTodo(repository, clock: () => testNow);

      final List<Todo> result = await toggle('a');

      expect(result.single.isCompleted, isFalse);
    });
  });

  group('DeleteTodo', () {
    test('reports what was removed and where it sat', () async {
      final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
        sampleTodo(id: 'a'),
        sampleTodo(id: 'b'),
        sampleTodo(id: 'c'),
      ]);

      final TodoDeletion deletion = await DeleteTodo(repository)('b');

      expect(deletion.removed?.id, 'b');
      expect(deletion.index, 1);
      expect(deletion.todos.map((Todo t) => t.id), <String>['a', 'c']);
      expect(repository.saveCount, 1);
    });

    test('reports nothing removed for an unknown id and does not write', () async {
      final FakeTodoRepository repository =
          FakeTodoRepository(<Todo>[sampleTodo(id: 'a')]);

      final TodoDeletion deletion = await DeleteTodo(repository)('missing');

      expect(deletion.removedSomething, isFalse);
      expect(repository.saveCount, 0);
    });
  });

  group('RestoreTodo', () {
    test('puts the todo back at its original index', () async {
      final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
        sampleTodo(id: 'a'),
        sampleTodo(id: 'c'),
      ]);

      final List<Todo> result = await RestoreTodo(repository)(
        sampleTodo(id: 'b'),
        1,
      );

      expect(result.map((Todo t) => t.id), <String>['a', 'b', 'c']);
    });

    test('clamps an out-of-range index instead of throwing', () async {
      final FakeTodoRepository repository =
          FakeTodoRepository(<Todo>[sampleTodo(id: 'a')]);

      final List<Todo> result = await RestoreTodo(repository)(
        sampleTodo(id: 'b'),
        99,
      );

      expect(result.map((Todo t) => t.id), <String>['a', 'b']);
    });
  });

  group('ReorderTodos', () {
    List<Todo> three() => <Todo>[
          sampleTodo(id: 'a'),
          sampleTodo(id: 'b'),
          sampleTodo(id: 'c'),
        ];

    test('moves an item down using the list\'s already-adjusted index', () async {
      // `onReorderItem` reports newIndex after the dragged item has been lifted
      // out, so dragging a below b arrives here as (0, 1).
      final List<Todo> result =
          await ReorderTodos(FakeTodoRepository(three()))(0, 1);
      expect(result.map((Todo t) => t.id), <String>['b', 'a', 'c']);
    });

    test('moves an item to the end of the list', () async {
      final List<Todo> result =
          await ReorderTodos(FakeTodoRepository(three()))(0, 2);
      expect(result.map((Todo t) => t.id), <String>['b', 'c', 'a']);
    });

    test('moves an item up', () async {
      final List<Todo> result =
          await ReorderTodos(FakeTodoRepository(three()))(2, 0);
      expect(result.map((Todo t) => t.id), <String>['c', 'a', 'b']);
    });

    test('clamps a target index past the end instead of throwing', () async {
      final List<Todo> result =
          await ReorderTodos(FakeTodoRepository(three()))(1, 99);
      expect(result.map((Todo t) => t.id), <String>['a', 'c', 'b']);
    });

    test('ignores an out-of-range source index', () async {
      final List<Todo> result =
          await ReorderTodos(FakeTodoRepository(three()))(9, 0);
      expect(result.map((Todo t) => t.id), <String>['a', 'b', 'c']);
    });
  });

  group('ClearCompletedTodos', () {
    test('removes only completed todos and reports the count', () async {
      final FakeTodoRepository repository = FakeTodoRepository(<Todo>[
        sampleTodo(id: 'open'),
        sampleTodo(id: 'done-1').completeAt(testNow),
        sampleTodo(id: 'done-2').completeAt(testNow),
      ]);

      final ClearCompletedResult result =
          await ClearCompletedTodos(repository)();

      expect(result.removedCount, 2);
      expect(result.todos.map((Todo t) => t.id), <String>['open']);
      expect(repository.saveCount, 1);
    });

    test('writes nothing when there is nothing to clear', () async {
      final FakeTodoRepository repository =
          FakeTodoRepository(<Todo>[sampleTodo(id: 'open')]);

      final ClearCompletedResult result =
          await ClearCompletedTodos(repository)();

      expect(result.removedCount, 0);
      expect(repository.saveCount, 0);
    });
  });
}
