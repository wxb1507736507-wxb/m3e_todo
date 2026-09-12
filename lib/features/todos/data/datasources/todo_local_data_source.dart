import '../../../../core/storage/document_store.dart';
import '../../domain/entities/todo.dart';
import '../models/todo_model.dart';

/// Reads and writes the todo collection as a versioned JSON document.
///
/// The document is wrapped in an envelope rather than stored as a bare array so
/// that [TodoModel.schemaVersion] travels with the data. That makes a future
/// migration possible: the loader can inspect the version and upgrade the shape
/// instead of guessing what it is looking at.
class TodoLocalDataSource {
  TodoLocalDataSource(this._store);

  final DocumentStore _store;

  static const String _versionKey = 'version';
  static const String _todosKey = 'todos';

  /// Returns every readable todo. Missing files yield an empty list, and
  /// individual records that fail to parse are skipped rather than failing the
  /// whole load.
  Future<List<Todo>> readAll() async {
    final Map<String, Object?>? document = await _store.read();
    if (document == null) {
      return <Todo>[];
    }

    final Object? raw = document[_todosKey];
    if (raw is! List) {
      return <Todo>[];
    }

    final List<Todo> todos = <Todo>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final Todo? todo = TodoModel.fromJson(Map<String, Object?>.from(entry));
      if (todo != null) {
        todos.add(todo);
      }
    }
    return todos;
  }

  /// Replaces the stored collection with [todos].
  Future<void> writeAll(List<Todo> todos) {
    return _store.write(<String, Object?>{
      _versionKey: TodoModel.schemaVersion,
      _todosKey: <Object?>[
        for (final Todo todo in todos) TodoModel.toJson(todo),
      ],
    });
  }
}
