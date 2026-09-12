import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_filter.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_priority.dart';

import '../../../support/sample_todo.dart';

void main() {
  group('status filtering', () {
    final List<Todo> todos = <Todo>[
      sampleTodo(id: 'open'),
      sampleTodo(id: 'done').completeAt(testNow),
    ];

    test('all keeps everything', () {
      const TodoFilter filter = TodoFilter();
      expect(filter.apply(todos).length, 2);
    });

    test('active keeps only open todos', () {
      const TodoFilter filter =
          TodoFilter(status: TodoStatusFilter.active);
      expect(filter.apply(todos).map((Todo t) => t.id), <String>['open']);
    });

    test('completed keeps only finished todos', () {
      const TodoFilter filter =
          TodoFilter(status: TodoStatusFilter.completed);
      expect(filter.apply(todos).map((Todo t) => t.id), <String>['done']);
    });
  });

  group('query filtering', () {
    final List<Todo> todos = <Todo>[
      sampleTodo(id: 'title', title: 'Review design doc'),
      sampleTodo(id: 'notes', title: '呼叫客户', notes: '提到 design 评审'),
      sampleTodo(id: 'other', title: '买咖啡'),
    ];

    test('matches the title case-insensitively', () {
      const TodoFilter filter = TodoFilter(query: 'DESIGN');
      expect(
        filter.apply(todos).map((Todo t) => t.id),
        <String>['title', 'notes'],
      );
    });

    test('matches notes as well as titles', () {
      const TodoFilter filter = TodoFilter(query: '评审');
      expect(filter.apply(todos).map((Todo t) => t.id), <String>['notes']);
    });

    test('ignores surrounding whitespace', () {
      const TodoFilter filter = TodoFilter(query: '  咖啡  ');
      expect(filter.apply(todos).map((Todo t) => t.id), <String>['other']);
    });

    test('hasQuery reflects whether anything was typed', () {
      expect(const TodoFilter(query: '   ').hasQuery, isFalse);
      expect(const TodoFilter(query: 'x').hasQuery, isTrue);
    });
  });

  group('sorting', () {
    test('manual keeps the order it was given', () {
      final List<Todo> todos = <Todo>[
        sampleTodo(id: 'b', createdAt: DateTime(2026, 1, 1)),
        sampleTodo(id: 'a', createdAt: DateTime(2026, 5, 1)),
      ];
      const TodoFilter filter = TodoFilter();
      expect(filter.apply(todos).map((Todo t) => t.id), <String>['b', 'a']);
    });

    test('createdNewest puts the most recent first', () {
      final List<Todo> todos = <Todo>[
        sampleTodo(id: 'old', createdAt: DateTime(2026, 1, 1)),
        sampleTodo(id: 'new', createdAt: DateTime(2026, 5, 1)),
      ];
      const TodoFilter filter = TodoFilter(sort: TodoSortOrder.createdNewest);
      expect(filter.apply(todos).map((Todo t) => t.id), <String>['new', 'old']);
    });

    test('dueSoonest orders by date and sinks undated todos to the bottom', () {
      final List<Todo> todos = <Todo>[
        sampleTodo(id: 'none'),
        sampleTodo(id: 'later', dueDate: DateTime(2026, 4, 1)),
        sampleTodo(id: 'soon', dueDate: DateTime(2026, 3, 20)),
      ];
      const TodoFilter filter = TodoFilter(sort: TodoSortOrder.dueSoonest);
      expect(
        filter.apply(todos).map((Todo t) => t.id),
        <String>['soon', 'later', 'none'],
      );
    });

    test('priorityFirst orders by rank then recency', () {
      final List<Todo> todos = <Todo>[
        sampleTodo(id: 'low', priority: TodoPriority.low),
        sampleTodo(id: 'high-old', priority: TodoPriority.high, createdAt: DateTime(2026, 1, 1)),
        sampleTodo(id: 'high-new', priority: TodoPriority.high, createdAt: DateTime(2026, 5, 1)),
      ];
      const TodoFilter filter = TodoFilter(sort: TodoSortOrder.priorityFirst);
      expect(
        filter.apply(todos).map((Todo t) => t.id),
        <String>['high-new', 'high-old', 'low'],
      );
    });
  });

  test('apply leaves the source list untouched', () {
    final List<Todo> todos = <Todo>[
      sampleTodo(id: 'a', createdAt: DateTime(2026, 1, 1)),
      sampleTodo(id: 'b', createdAt: DateTime(2026, 5, 1)),
    ];
    const TodoFilter filter = TodoFilter(sort: TodoSortOrder.createdNewest);

    filter.apply(todos);

    expect(todos.map((Todo t) => t.id), <String>['a', 'b']);
  });

  test('allowsManualReorder follows the sort order', () {
    expect(const TodoFilter().allowsManualReorder, isTrue);
    expect(
      const TodoFilter(sort: TodoSortOrder.dueSoonest).allowsManualReorder,
      isFalse,
    );
  });

  test('isPristine only when nothing has been narrowed', () {
    expect(const TodoFilter().isPristine, isTrue);
    expect(const TodoFilter(query: 'x').isPristine, isFalse);
    expect(
      const TodoFilter(status: TodoStatusFilter.active).isPristine,
      isFalse,
    );
  });

  test('equality is by value so Riverpod can skip redundant rebuilds', () {
    expect(const TodoFilter(), const TodoFilter());
    expect(
      const TodoFilter(query: 'a') == const TodoFilter(query: 'b'),
      isFalse,
    );
  });
}
