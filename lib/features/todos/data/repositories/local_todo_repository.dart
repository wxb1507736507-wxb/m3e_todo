import '../../domain/entities/todo.dart';
import '../../domain/repositories/todo_repository.dart';
import '../datasources/todo_local_data_source.dart';

/// [TodoRepository] backed by the local JSON document.
///
/// Holds the loaded collection in memory. Every mutation in this app is
/// expressed as "replace the whole list", so without a cache a single checkbox
/// tap would re-read and re-parse the file; with it, reads after the first cost
/// nothing, while the file on disk remains the source of truth.
///
/// Both directions hand out unmodifiable snapshots. That means a caller cannot
/// accidentally mutate the cache by sorting or removing from the list it was
/// given &mdash; a subtle bug that would make the UI disagree with the disk.
class LocalTodoRepository implements TodoRepository {
  LocalTodoRepository(this._dataSource);

  final TodoLocalDataSource _dataSource;

  List<Todo>? _cache;

  @override
  Future<List<Todo>> loadAll() async {
    final List<Todo>? cached = _cache;
    if (cached != null) {
      return List<Todo>.unmodifiable(cached);
    }

    final List<Todo> loaded = await _dataSource.readAll();
    _cache = loaded;
    return List<Todo>.unmodifiable(loaded);
  }

  @override
  Future<void> saveAll(List<Todo> todos) async {
    final List<Todo> snapshot = List<Todo>.unmodifiable(todos);
    await _dataSource.writeAll(snapshot);
    // Only update the cache once the write has actually succeeded, so a failed
    // save cannot leave the app believing data is persisted when it is not.
    _cache = snapshot;
  }
}
