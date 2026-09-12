import '../entities/todo.dart';
import 'todo_mutation.dart';

/// Result of a bulk clear: the remaining collection plus how many were removed,
/// so the UI can report "cleared 3 todos" without recomputing the difference.
typedef ClearCompletedResult = ({List<Todo> todos, int removedCount});

/// Removes every completed todo in one operation.
///
/// Done as a single read-modify-write rather than a delete per item, so the
/// whole clear either lands on disk or does not, and the file is rewritten once
/// instead of once per removed todo.
final class ClearCompletedTodos extends TodoMutation {
  const ClearCompletedTodos(super.repository);

  Future<ClearCompletedResult> call() async {
    final List<Todo> current = await repository.loadAll();
    final List<Todo> remaining = current
        .where((Todo todo) => !todo.isCompleted)
        .toList();
    final int removedCount = current.length - remaining.length;

    if (removedCount == 0) {
      return (todos: current, removedCount: 0);
    }

    await repository.saveAll(remaining);
    return (todos: remaining, removedCount: removedCount);
  }
}
