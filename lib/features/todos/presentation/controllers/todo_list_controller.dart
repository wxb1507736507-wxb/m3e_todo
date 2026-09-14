import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_draft.dart';
import '../../domain/usecases/clear_completed_todos.dart';
import '../../domain/usecases/delete_todo.dart';
import '../../domain/usecases/reorder_todos.dart';
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

  /// Moves a todo to sit in front of [beforeId], or last when it is `null`.
  ///
  /// The one *optimistic* write in this controller, and deliberately so: the
  /// drag animation has already shown the user where the row landed, so waiting
  /// for the disk before the list agrees is exactly the flicker this method
  /// exists to remove — the dropped row animates back to its old slot and then
  /// jumps to the new one. The order in memory is updated at once, the write
  /// happens behind it, and a failed write puts the old order back.
  Future<void> reorder(String movedId, String? beforeId) async {
    final List<Todo>? current = state.value;
    if (current == null) {
      return;
    }
    final List<Todo> optimistic = reorderTodos(current, movedId, beforeId);
    if (_sameOrder(optimistic, current)) {
      return;
    }

    state = AsyncData<List<Todo>>(optimistic);
    try {
      final List<Todo> stored =
          await ref.read(reorderTodosProvider)(movedId, beforeId);
      if (ref.mounted) {
        state = AsyncData<List<Todo>>(stored);
      }
    } on Object {
      if (ref.mounted) {
        state = AsyncData<List<Todo>>(current);
      }
      rethrow;
    }
  }

  static bool _sameOrder(List<Todo> a, List<Todo> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) {
        return false;
      }
    }
    return true;
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

  /// Removes [categoryId] from every todo filed under it.
  ///
  /// Called when a folder is deleted. Clearing the folder here rather than
  /// teaching every view to treat an unknown id as unfiled keeps the data
  /// honest: nothing is left pointing at something that no longer exists, and
  /// "unfiled" stays a single, unambiguous state.
  Future<void> clearCategory(String categoryId) {
    final List<Todo>? current = state.value;
    if (current == null ||
        !current.any((Todo todo) => todo.categoryId == categoryId)) {
      return Future<void>.value();
    }
    return _publish(
      () => ref.read(clearCategoryProvider)(categoryId),
    );
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
