import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

/// Shared plumbing for use cases that change the collection.
///
/// Every mutation follows the same shape: read the current collection, compute
/// the next one, persist it atomically, and hand the result back so the
/// controller can publish it without a second read. Expressing that once keeps
/// the individual use cases down to the one thing that actually differs &mdash;
/// the change itself.
///
/// The change callback must be pure: it receives the current list and returns
/// the new one. That makes each use case trivially unit-testable with an
/// in-memory repository.
abstract base class TodoMutation {
  const TodoMutation(this.repository);

  final TodoRepository repository;

  /// Applies [change] to the stored collection and persists the result.
  Future<List<Todo>> mutate(
    List<Todo> Function(List<Todo> current) change,
  ) async {
    final List<Todo> current = await repository.loadAll();
    final List<Todo> updated = change(current);
    await repository.saveAll(updated);
    return updated;
  }
}
