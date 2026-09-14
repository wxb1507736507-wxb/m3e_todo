import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/document_store.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../todos/domain/entities/todo_attachment.dart';
import '../../../todos/presentation/providers/todo_providers.dart';
import '../../data/datasources/note_local_data_source.dart';
import '../../data/repositories/local_note_repository.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';

/// File name of the notes document inside the app data directory.
const String noteFileName = 'notes.json';

final Provider<DocumentStore> noteDocumentStoreProvider =
    Provider<DocumentStore>(
  (ref) => ref.watch(documentStoreFactoryProvider)(noteFileName),
  name: 'noteDocumentStore',
);

final Provider<NoteRepository> noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => LocalNoteRepository(
    NoteLocalDataSource(ref.watch(noteDocumentStoreProvider)),
  ),
  name: 'noteRepository',
);

/// Ids for new notes; overridden in tests with a deterministic sequence.
final Provider<IdGenerator> noteIdGeneratorProvider = Provider<IdGenerator>(
  (ref) => generateTodoId,
  name: 'noteIdGenerator',
);

/// The user's notes.
class NotesController extends AsyncNotifier<List<Note>> {
  @override
  Future<List<Note>> build() => ref.watch(noteRepositoryProvider).loadAll();

  Future<void> add({
    required DateTime date,
    required String body,
    required String? categoryId,
    List<TodoAttachment> attachments = const <TodoAttachment>[],
  }) {
    final Note created = Note.create(
      id: ref.read(noteIdGeneratorProvider)(),
      date: date,
      body: body,
      createdAt: ref.read(clockProvider)(),
      categoryId: categoryId,
      attachments: attachments,
    );
    return _replace((List<Note> current) => <Note>[...current, created]);
  }

  Future<void> edit(
    String id, {
    required DateTime date,
    required String body,
    required String? categoryId,
    required List<TodoAttachment> attachments,
  }) {
    return _replace(
      (List<Note> current) => <Note>[
        for (final Note note in current)
          if (note.id == id)
            note.edit(
              date: date,
              body: body,
              categoryId: categoryId,
              attachments: attachments,
            )
          else
            note,
      ],
    );
  }

  /// Removes a note and reports the files it was holding, so the caller can
  /// delete them: nothing else references them once the note is gone.
  Future<List<String>> remove(String id) async {
    final List<Note> current = await future;
    final Note? removed = current.where((Note note) => note.id == id).firstOrNull;
    await _replace(
      (List<Note> notes) => notes.where((Note note) => note.id != id).toList(),
    );
    return <String>[
      for (final TodoAttachment attachment in removed?.attachments ?? const <TodoAttachment>[])
        attachment.path,
    ];
  }

  /// Removes [categoryId] from every note filed under it.
  ///
  /// The same cleanup the todos get when a folder is deleted: a note left
  /// pointing at a folder that no longer exists would be invisible from every
  /// view.
  Future<void> clearCategory(String categoryId) {
    return _replace(
      (List<Note> current) => <Note>[
        for (final Note note in current)
          if (note.categoryId == categoryId)
            note.edit(
              date: note.date,
              body: note.body,
              categoryId: null,
              attachments: note.attachments,
            )
          else
            note,
      ],
    );
  }

  Future<void> _replace(List<Note> Function(List<Note> current) change) async {
    final List<Note> current = await future;
    final List<Note> updated = change(current);
    await ref.read(noteRepositoryProvider).saveAll(updated);
    if (ref.mounted) {
      state = AsyncData<List<Note>>(updated);
    }
  }
}

final AsyncNotifierProvider<NotesController, List<Note>> notesProvider =
    AsyncNotifierProvider<NotesController, List<Note>>(
  NotesController.new,
  name: 'notes',
);

/// The notes belonging to one day, newest first.
///
/// A family keyed by the day key (`year * 10000 + month * 100 + day`), so a
/// day's notes are computed once per day rather than filtered on every rebuild —
/// and the calendar only ever asks for the day it is showing.
final notesOnDayProvider = Provider.family<AsyncValue<List<Note>>, int>(
  (ref, int dayKey) {
    return ref.watch(notesProvider).whenData(
          (List<Note> notes) => <Note>[
            for (final Note note in notes)
              if (note.date.year * 10000 + note.date.month * 100 + note.date.day ==
                  dayKey)
                note,
          ]..sort((Note a, Note b) => b.createdAt.compareTo(a.createdAt)),
        );
  },
  name: 'notesOnDay',
);
