import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/notes/data/models/note_model.dart';
import 'package:m3e_todo/features/notes/domain/entities/note.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_attachment.dart';

void main() {
  group('round trip', () {
    test('preserves words, day, folder and attachments', () {
      final Note original = Note.create(
        id: 'n1',
        date: DateTime(2026, 3, 10),
        body: '今天拍到了猫',
        createdAt: DateTime(2026, 3, 10, 21),
        categoryId: 'c1',
        attachments: <TodoAttachment>[
          TodoAttachment(
            id: 'a1',
            type: TodoAttachmentType.image,
            path: '/data/cat.jpg',
            name: 'cat.jpg',
            mime: 'image/jpeg',
          ),
        ],
      );

      final Map<String, Object?> json = NoteModel.toJson(original);

      expect(json['date'], startsWith('2026-03-10'));
      expect(NoteModel.fromJson(json), original);
    });

    test('a note with only an attachment survives the file', () {
      final Note original = Note.create(
        id: 'n1',
        date: DateTime(2026, 3, 10),
        body: '',
        createdAt: DateTime(2026, 3, 10, 21),
        attachments: <TodoAttachment>[
          TodoAttachment(
            id: 'a1',
            type: TodoAttachmentType.audio,
            path: '/data/memo.m4a',
            name: '语音备忘',
          ),
        ],
      );

      expect(NoteModel.fromJson(NoteModel.toJson(original)), original);
    });
  });

  group('resilience', () {
    test('rejects a record with no id', () {
      expect(
        NoteModel.fromJson(<String, Object?>{
          'date': '2026-03-10T00:00:00.000',
          'body': '写点什么',
        }),
        isNull,
      );
    });

    test('rejects an unparsable date', () {
      expect(
        NoteModel.fromJson(<String, Object?>{
          'id': 'n1',
          'date': 'not-a-date',
          'body': '写点什么',
        }),
        isNull,
      );
    });

    test('rejects a record with neither words nor attachments', () {
      // Otherwise the record could not be turned back into a Note at all.
      expect(
        NoteModel.fromJson(<String, Object?>{
          'id': 'n1',
          'date': '2026-03-10T00:00:00.000',
          'body': '   ',
        }),
        isNull,
      );
    });

    test('skips an attachment with no path but keeps the note', () {
      final Note? note = NoteModel.fromJson(<String, Object?>{
        'id': 'n1',
        'date': '2026-03-10T00:00:00.000',
        'body': '有文字的随笔',
        'attachments': <Object?>[
          <String, Object?>{'id': 'a1', 'name': 'broken'},
          <String, Object?>{
            'id': 'a2',
            'type': 'video',
            'path': '/data/clip.mp4',
            'name': 'clip.mp4',
          },
        ],
      });

      expect(note, isNotNull);
      expect(note!.attachments, hasLength(1));
      expect(note.attachments.single.type, TodoAttachmentType.video);
    });

    test('an unknown attachment type is read as a document', () {
      final Note? note = NoteModel.fromJson(<String, Object?>{
        'id': 'n1',
        'date': '2026-03-10T00:00:00.000',
        'body': 'x',
        'attachments': <Object?>[
          <String, Object?>{
            'id': 'a1',
            'type': 'hologram',
            'path': '/data/x.bin',
            'name': 'x.bin',
          },
        ],
      });

      expect(note!.attachments.single.type, TodoAttachmentType.document);
    });
  });
}
