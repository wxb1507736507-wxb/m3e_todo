import '../entities/todo.dart';
import 'todo_mutation.dart';

/// Moves a todo within the manual ordering.
final class ReorderTodos extends TodoMutation {
  const ReorderTodos(super.repository);

  /// Moves the item at [oldIndex] to [newIndex].
  ///
  /// Both indices come straight from `ReorderableListView.onReorderItem`, which
  /// reports [newIndex] **after** accounting for the dragged item having been
  /// lifted out. So this is a plain "remove then insert", with no off-by-one
  /// correction: adding one here would reintroduce the very bug the callback
  /// exists to prevent.
  Future<List<Todo>> call(int oldIndex, int newIndex) {
    return mutate((List<Todo> current) {
      if (oldIndex < 0 || oldIndex >= current.length) {
        return current;
      }

      final List<Todo> reordered = List<Todo>.of(current);
      final Todo moved = reordered.removeAt(oldIndex);

      // Clamp rather than throw: a stale index from an animation that finished
      // against a list that has since shrunk should not take the app down.
      final int target =
          newIndex < 0 ? 0 : (newIndex > reordered.length ? reordered.length : newIndex);

      reordered.insert(target, moved);
      return reordered;
    });
  }
}
