import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/todos/data/models/todo_model.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_priority.dart';

import '../../../support/sample_todo.dart';

void main() {
  group('round trip', () {
    test('preserves every field', () {
      final Todo original = Todo(
        id: 'abc',
        title: '评审设计稿',
        createdAt: DateTime(2026, 3, 1, 9, 30),
        notes: '带上原型',
        priority: TodoPriority.high,
        dueDate: DateTime(2026, 3, 12),
        completedAt: DateTime(2026, 3, 11, 16),
      );

      final Todo restored = TodoModel.fromJson(TodoModel.toJson(original))!;

      expect(restored, original);
    });

    test('preserves a todo with no optional fields set', () {
      final Todo original = sampleTodo();
      final Todo restored = TodoModel.fromJson(TodoModel.toJson(original))!;
      expect(restored, original);
      expect(restored.notes, isNull);
      expect(restored.dueDate, isNull);
      expect(restored.completedAt, isNull);
    });

    test('omits absent optional fields rather than writing nulls', () {
      final Map<String, Object?> json = TodoModel.toJson(sampleTodo());
      expect(json.containsKey('notes'), isFalse);
      expect(json.containsKey('dueDate'), isFalse);
      expect(json.containsKey('completedAt'), isFalse);
    });
  });

  group('fromJson resilience', () {
    Map<String, Object?> valid() => <String, Object?>{
          'id': 'a',
          'title': '任务',
          'createdAt': '2026-03-01T10:00:00.000',
        };

    test('rejects a record with no id', () {
      final Map<String, Object?> json = valid()..remove('id');
      expect(TodoModel.fromJson(json), isNull);
    });

    test('rejects a record with a blank title', () {
      final Map<String, Object?> json = valid()..['title'] = '   ';
      expect(TodoModel.fromJson(json), isNull);
    });

    test('rejects a record whose createdAt is unparsable', () {
      final Map<String, Object?> json = valid()..['createdAt'] = 'not-a-date';
      expect(TodoModel.fromJson(json), isNull);
    });

    test('falls back to normal priority for an unknown value', () {
      final Map<String, Object?> json = valid()..['priority'] = 'urgent';
      expect(TodoModel.fromJson(json)?.priority, TodoPriority.normal);
    });

    test('still loads a record whose optional date is corrupt', () {
      final Map<String, Object?> json = valid()..['dueDate'] = 'nonsense';
      final Todo? todo = TodoModel.fromJson(json);
      expect(todo, isNotNull);
      expect(todo!.dueDate, isNull);
    });

    test('ignores fields it does not know about', () {
      final Map<String, Object?> json = valid()..['futureField'] = 42;
      expect(TodoModel.fromJson(json), isNotNull);
    });
  });
}
