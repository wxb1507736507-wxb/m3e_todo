import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_priority.dart';

/// Builds a [Todo] with sensible defaults so a test only states the fields it
/// actually cares about.
Todo sampleTodo({
  String id = 'todo-1',
  String title = '写周报',
  String? notes,
  TodoPriority priority = TodoPriority.normal,
  DateTime? dueDate,
  DateTime? createdAt,
  DateTime? completedAt,
}) {
  return Todo(
    id: id,
    title: title,
    createdAt: createdAt ?? DateTime(2026, 3, 1, 10),
    notes: notes,
    priority: priority,
    dueDate: dueDate,
    completedAt: completedAt,
  );
}

/// A fixed "now" used by tests that involve due dates.
final DateTime testNow = DateTime(2026, 3, 10, 9, 30);
