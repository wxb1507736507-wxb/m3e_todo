import '../../domain/entities/note.dart';

/// Persistence boundary for notes.
abstract interface class NoteRepository {
  /// Every stored note, newest first as written.
  Future<List<Note>> loadAll();

  /// Replaces the stored collection with [notes].
  Future<void> saveAll(List<Note> notes);
}
