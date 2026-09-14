import '../../../../core/storage/document_store.dart';
import '../../domain/entities/note.dart';
import '../models/note_model.dart';

/// Reads and writes the notes as a versioned JSON document.
class NoteLocalDataSource {
  NoteLocalDataSource(this._store);

  final DocumentStore _store;

  static const String _versionKey = 'version';
  static const String _notesKey = 'notes';

  Future<List<Note>> readAll() async {
    final Map<String, Object?>? document = await _store.read();
    if (document == null) {
      return <Note>[];
    }
    final Object? raw = document[_notesKey];
    if (raw is! List) {
      return <Note>[];
    }

    final List<Note> notes = <Note>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final Note? note = NoteModel.fromJson(Map<String, Object?>.from(entry));
      if (note != null) {
        notes.add(note);
      }
    }
    return notes;
  }

  Future<void> writeAll(List<Note> notes) {
    return _store.write(<String, Object?>{
      _versionKey: NoteModel.schemaVersion,
      _notesKey: <Object?>[
        for (final Note note in notes) NoteModel.toJson(note),
      ],
    });
  }
}
