import '../entities/todo.dart';
import '../repositories/todo_repository.dart';

/// Reads every stored todo in the user's manual order.
final class LoadTodos {
  const LoadTodos(this._repository);

  final TodoRepository _repository;

  Future<List<Todo>> call() => _repository.loadAll();
}
