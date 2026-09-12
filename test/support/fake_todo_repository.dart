import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/repositories/todo_repository.dart';

/// In-memory [TodoRepository] for tests.
///
/// Also counts writes, so a test can assert that an operation really did (or
/// deliberately did not) touch storage &mdash; which is the part of each use case
/// that a pure in-memory check would otherwise miss.
class FakeTodoRepository implements TodoRepository {
  FakeTodoRepository([List<Todo>? initial])
      : _todos = List<Todo>.of(initial ?? const <Todo>[]);

  List<Todo> _todos;
  int saveCount = 0;

  @override
  Future<List<Todo>> loadAll() async => List<Todo>.unmodifiable(_todos);

  @override
  Future<void> saveAll(List<Todo> todos) async {
    saveCount++;
    _todos = List<Todo>.of(todos);
  }
}
