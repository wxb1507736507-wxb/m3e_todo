import '../entities/todo.dart';

/// Persistence boundary for todos.
///
/// The domain depends only on this interface, so storage can be swapped (a JSON
/// file today, SQLite or a remote API later, an in-memory fake in tests) without
/// touching a single use case.
///
/// The collection is read and written as a whole. For a single-user todo list
/// that is the honest model: the manual ordering *is* part of the data, and
/// replacing the document atomically means a crash can never leave the list
/// half-updated.
abstract interface class TodoRepository {
  /// Every stored todo, in the user's manual order.
  Future<List<Todo>> loadAll();

  /// Replaces the stored collection with [todos], preserving list order.
  Future<void> saveAll(List<Todo> todos);
}
