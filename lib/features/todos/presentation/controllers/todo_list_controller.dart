import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_draft.dart';
import '../../domain/usecases/clear_completed_todos.dart';
import '../../domain/usecases/delete_todo.dart';
import '../providers/todo_providers.dart';

/// Owns the todo collection and exposes one method per user intention.
///
/// The controller holds no business rules of its own: each method reads the
/// matching use case from the container and publishes whatever collection comes
/// back. That keeps the rules testable without a `ProviderContainer` and keeps
/// this class small enough to read in one sitting.
///
/// State is only replaced *after* a use case succeeds. Deliberately no
/// intermediate loading state: flashing a spinner on every checkbox tap would
/// be both distracting and wrong, since the previous list is still perfectly
/// valid while the write is in flight. If a write fails the old state is kept
/// and the error is rethrown, so the UI can report it and stay consistent with
/// what is actually on disk.
class TodoListController extends AsyncNotifier<List<Todo>> {
  @override
  Future<List<Todo>> build() => ref.watch(loadTodosProvider)();

  Future<void> add(TodoDraft draft) {
    return _publish(() => ref.read(addTodoProvider)(draft));
  }

  /// Applies edited values to an existing todo.
  ///
  /// Named `edit` rather than `update` because [AsyncNotifier] already declares
  /// an `update` for transforming the current value, and shadowing it with a
  /// different signature is not a legal override.
  Future<void> edit(String id, TodoDraft draft) {
    return _publish(() => ref.read(updateTodoProvider)(id, draft));
  }

  Future<void> toggle(String id) {
    return _publish(() => ref.read(toggleTodoProvider)(id));
  }

  /// Flips one checklist step of the todo with [id].
  Future<void> toggleSubtask(String todoId, String subtaskId) {
    return _publish(
      () => ref.read(toggleSubtaskProvider)(todoId, subtaskId),
    );
  }

  Future<void> reorder(int oldIndex, int newIndex) {
    return _publish(() => ref.read(reorderTodosProvider)(oldIndex, newIndex));
  }

  /// Deletes a todo and reports what was removed, so the caller can offer undo.
  Future<TodoDeletion> delete(String id) async {
    final TodoDeletion deletion = await ref.read(deleteTodoProvider)(id);
    if (deletion.removedSomething) {
      state = AsyncData<List<Todo>>(deletion.todos);
    }
    return deletion;
  }

  /// Puts a deleted todo back where it was.
  Future<void> restore(Todo todo, int index) {
    return _publish(() => ref.read(restoreTodoProvider)(todo, index));
  }

  /// Removes every completed todo and returns how many were removed.
  Future<int> clearCompleted() async {
    final ClearCompletedResult result =
        await ref.read(clearCompletedTodosProvider)();
    if (result.removedCount > 0) {
      state = AsyncData<List<Todo>>(result.todos);
    }
    return result.removedCount;
  }

  /// Re-reads everything from storage, used by the retry affordance after a
  /// failed load.
  void reload() => ref.invalidateSelf();

  Future<void> _publish(Future<List<Todo>> Function() operation) async {
    final List<Todo> updated = await operation();
    if (ref.mounted) {
      state = AsyncData<List<Todo>>(updated);
    }
  }
}
