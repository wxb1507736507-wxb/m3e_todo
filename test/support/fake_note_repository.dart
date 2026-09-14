import 'package:m3e_todo/features/notes/domain/entities/note.dart';
import 'package:m3e_todo/features/notes/domain/repositories/note_repository.dart';

/// In-memory [NoteRepository] for tests.
class FakeNoteRepository implements NoteRepository {
  FakeNoteRepository([List<Note>? initial])
      : _notes = List<Note>.of(initial ?? const <Note>[]);

  List<Note> _notes;
  int saveCount = 0;

  @override
  Future<List<Note>> loadAll() async => List<Note>.unmodifiable(_notes);

  @override
  Future<void> saveAll(List<Note> notes) async {
    saveCount++;
    _notes = List<Note>.of(notes);
  }
}
