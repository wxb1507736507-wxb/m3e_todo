import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';
import '../datasources/note_local_data_source.dart';

/// [NoteRepository] backed by the local JSON document, with the same in-memory
/// cache the other repositories keep.
class LocalNoteRepository implements NoteRepository {
  LocalNoteRepository(this._dataSource);

  final NoteLocalDataSource _dataSource;

  List<Note>? _cache;

  @override
  Future<List<Note>> loadAll() async {
    final List<Note>? cached = _cache;
    if (cached != null) {
      return List<Note>.unmodifiable(cached);
    }
    final List<Note> loaded = await _dataSource.readAll();
    _cache = loaded;
    return List<Note>.unmodifiable(loaded);
  }

  @override
  Future<void> saveAll(List<Note> notes) async {
    final List<Note> snapshot = List<Note>.unmodifiable(notes);
    await _dataSource.writeAll(snapshot);
    _cache = snapshot;
  }
}
