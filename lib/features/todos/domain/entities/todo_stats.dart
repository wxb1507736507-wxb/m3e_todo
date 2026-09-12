import 'todo.dart';

/// Derived counts for the summary header.
///
/// Computed from the collection rather than stored alongside it, so there is no
/// second copy of the truth that could drift out of sync after an edit.
class TodoStats {
  const TodoStats({
    required this.total,
    required this.completed,
    required this.overdue,
  });

  /// Counts [todos] as of [now]. Overdue is evaluated against [now] rather than
  /// the wall clock so the result is deterministic in tests.
  factory TodoStats.fromTodos(List<Todo> todos, DateTime now) {
    int completed = 0;
    int overdue = 0;
    for (final Todo todo in todos) {
      if (todo.isCompleted) {
        completed++;
      } else if (todo.isOverdue(now)) {
        overdue++;
      }
    }
    return TodoStats(
      total: todos.length,
      completed: completed,
      overdue: overdue,
    );
  }

  final int total;
  final int completed;
  final int overdue;

  int get active => total - completed;

  bool get isEmpty => total == 0;

  /// Whether there is at least one todo and all of them are done.
  bool get isAllDone => total > 0 && completed == total;

  /// Completion ratio in `[0, 1]`; `0` when there is nothing to complete.
  double get progress => total == 0 ? 0 : completed / total;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TodoStats &&
        other.total == total &&
        other.completed == completed &&
        other.overdue == overdue;
  }

  @override
  int get hashCode => Object.hash(total, completed, overdue);

  @override
  String toString() =>
      'TodoStats(total: $total, completed: $completed, overdue: $overdue)';
}
