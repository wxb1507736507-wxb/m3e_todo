import '../entities/todo.dart';
import 'todo_mutation.dart';

/// The collection with [movedId] placed directly before [beforeId].
///
/// Expressed as "put this one in front of that one" rather than as two indices,
/// because the indices a drag reports belong to the list *on screen*: with the
/// "进行中" tab selected, or a search typed, the visible list is a subset of the
/// stored one, and moving items around by visible index silently rearranged the
/// wrong rows — or appeared to do nothing at all. Naming the neighbours instead
/// makes the gesture mean the same thing whichever rows happen to be hidden,
/// and the visible list is always a subsequence of the stored one, so the
/// reference is always a real element.
///
/// Pure, so the controller can apply it to what it has in memory and show the
/// result before the disk has agreed — which is what keeps a drop from
/// flickering back to where it started.
List<Todo> reorderTodos(List<Todo> todos, String movedId, String? beforeId) {
  final int from = todos.indexWhere((Todo todo) => todo.id == movedId);
  if (from < 0) {
    return todos;
  }

  final List<Todo> reordered = List<Todo>.of(todos);
  final Todo moved = reordered.removeAt(from);

  if (beforeId == null) {
    // Dropped past the last row on screen: last in the collection.
    reordered.add(moved);
    return reordered;
  }
  final int at = reordered.indexWhere((Todo todo) => todo.id == beforeId);
  reordered.insert(at < 0 ? reordered.length : at, moved);
  return reordered;
}

/// Moves a todo within the manual ordering.
final class ReorderTodos extends TodoMutation {
  const ReorderTodos(super.repository);

  /// Moves [movedId] to sit directly before [beforeId], or to the end of the
  /// collection when [beforeId] is `null`.
  Future<List<Todo>> call(String movedId, String? beforeId) {
    return mutate(
      (List<Todo> current) => reorderTodos(current, movedId, beforeId),
    );
  }
}
