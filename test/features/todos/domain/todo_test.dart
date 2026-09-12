import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_priority.dart';

import '../../../support/sample_todo.dart';

void main() {
  group('Todo.create', () {
    test('trims the title', () {
      final Todo todo = Todo.create(
        id: 'a',
        title: '  写周报  ',
        createdAt: testNow,
      );
      expect(todo.title, '写周报');
    });

    test('rejects a blank title', () {
      expect(
        () => Todo.create(id: 'a', title: '   ', createdAt: testNow),
        throwsA(isA<TodoValidationException>()),
      );
    });

    test('collapses empty notes to null rather than an empty string', () {
      final Todo todo = Todo.create(
        id: 'a',
        title: '任务',
        notes: '   ',
        createdAt: testNow,
      );
      expect(todo.notes, isNull);
      expect(todo.hasNotes, isFalse);
    });

    test('reduces a due date to midnight so comparisons are day-granular', () {
      final Todo todo = Todo.create(
        id: 'a',
        title: '任务',
        createdAt: testNow,
        dueDate: DateTime(2026, 3, 12, 17, 45),
      );
      expect(todo.dueDate, DateTime(2026, 3, 12));
    });
  });

  group('completion', () {
    test('completeAt records the moment', () {
      final Todo todo = sampleTodo().completeAt(testNow);
      expect(todo.isCompleted, isTrue);
      expect(todo.completedAt, testNow);
    });

    test('completeAt is idempotent so a double click cannot rewrite history', () {
      final DateTime first = DateTime(2026, 3, 1);
      final Todo todo = sampleTodo().completeAt(first).completeAt(testNow);
      expect(todo.completedAt, first);
    });

    test('reopen clears the completion timestamp', () {
      final Todo todo = sampleTodo().completeAt(testNow).reopen();
      expect(todo.isCompleted, isFalse);
      expect(todo.completedAt, isNull);
    });

    test('toggledAt flips in both directions', () {
      final Todo open = sampleTodo();
      final Todo done = open.toggledAt(testNow);
      expect(done.isCompleted, isTrue);
      expect(done.toggledAt(testNow).isCompleted, isFalse);
    });
  });

  group('edit', () {
    test('replaces editable fields but preserves identity and history', () {
      final Todo original = sampleTodo(id: 'keep-me', title: '旧标题');
      final Todo edited = original.edit(
        title: '新标题',
        notes: '备注',
        priority: TodoPriority.high,
        dueDate: DateTime(2026, 4, 1, 23, 59),
      );

      expect(edited.id, 'keep-me');
      expect(edited.createdAt, original.createdAt);
      expect(edited.title, '新标题');
      expect(edited.notes, '备注');
      expect(edited.priority, TodoPriority.high);
      expect(edited.dueDate, DateTime(2026, 4, 1));
    });

    test('keeps a completed todo completed', () {
      final Todo done = sampleTodo().completeAt(testNow);
      final Todo edited = done.edit(
        title: '改过的标题',
        notes: null,
        priority: TodoPriority.low,
        dueDate: null,
      );
      expect(edited.isCompleted, isTrue);
      expect(edited.completedAt, testNow);
    });

    test('rejects a blank title', () {
      expect(
        () => sampleTodo().edit(
          title: ' ',
          notes: null,
          priority: TodoPriority.normal,
          dueDate: null,
        ),
        throwsA(isA<TodoValidationException>()),
      );
    });
  });

  group('due date judgements', () {
    test('a past deadline on an open todo is overdue', () {
      final Todo todo = sampleTodo(dueDate: DateTime(2026, 3, 9));
      expect(todo.isOverdue(testNow), isTrue);
    });

    test('a deadline later today is not overdue', () {
      final Todo todo = sampleTodo(dueDate: DateTime(2026, 3, 10));
      expect(todo.isOverdue(testNow), isFalse);
      expect(todo.isDueToday(testNow), isTrue);
    });

    test('a completed todo is never overdue', () {
      final Todo todo =
          sampleTodo(dueDate: DateTime(2026, 3, 1)).completeAt(testNow);
      expect(todo.isOverdue(testNow), isFalse);
    });

    test('daysUntilDue counts calendar days', () {
      expect(sampleTodo(dueDate: DateTime(2026, 3, 13)).daysUntilDue(testNow), 3);
      expect(sampleTodo(dueDate: DateTime(2026, 3, 8)).daysUntilDue(testNow), -2);
      expect(sampleTodo().daysUntilDue(testNow), isNull);
    });
  });

  test('equality covers every field', () {
    expect(sampleTodo(), sampleTodo());
    expect(sampleTodo().hashCode, sampleTodo().hashCode);
    expect(sampleTodo(title: 'a') == sampleTodo(title: 'b'), isFalse);
  });
}
