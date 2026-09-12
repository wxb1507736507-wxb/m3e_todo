import '../entities/todo.dart';
import 'todo_mutation.dart';

/// Puts a previously deleted todo back into the collection, undoing a delete.
final class RestoreTodo extends TodoMutation {
  const RestoreTodo(super.repository);

  /// Re-inserts [todo] at [index], clamping the position into range so a stale
  /// index (for example if other items were removed in the meantime) cannot
  /// throw.
  Future<List<Todo>> call(Todo todo, int index) {
    return mutate((List<Todo> current) {
      final List<Todo> restored = List<Todo>.of(current);
      final int at = index < 0
          ? 0
          : (index > restored.length ? restored.length : index);
      restored.insert(at, todo);
      return restored;
    });
  }
}
