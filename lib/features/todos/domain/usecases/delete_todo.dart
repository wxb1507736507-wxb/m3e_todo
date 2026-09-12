import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

/// The outcome of deleting a todo, carrying everything needed to undo it.
///
/// Undo has to restore the item *at the position it occupied*, otherwise
/// undoing a delete in manual order would silently reshuffle the list.
class TodoDeletion {
  const TodoDeletion({
    required this.todos,
    required this.removed,
    required this.index,
  });

  /// The collection after the removal.
  final List<Todo> todos;

  /// The removed todo, or `null` when [id] matched nothing.
  final Todo? removed;

  /// Where the todo sat before it was removed, or `-1` when nothing matched.
  final int index;

  bool get removedSomething => removed != null;
}

/// Removes the todo with [id].
///
/// Implemented directly rather than through `TodoMutation` because it has to
/// report *what* it removed and *where it was*, which the shared
/// read-change-persist shape has no way to express.
final class DeleteTodo {
  const DeleteTodo(this.repository);

  final TodoRepository repository;

  Future<TodoDeletion> call(String id) async {
    final List<Todo> current = await repository.loadAll();
    final int index = current.indexWhere((Todo todo) => todo.id == id);

    if (index < 0) {
      return TodoDeletion(todos: current, removed: null, index: -1);
    }

    final Todo removed = current[index];
    final List<Todo> remaining = List<Todo>.of(current)..removeAt(index);
    await repository.saveAll(remaining);

    return TodoDeletion(todos: remaining, removed: removed, index: index);
  }
}
