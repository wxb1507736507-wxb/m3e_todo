import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/notes/domain/entities/note.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_attachment.dart';

final DateTime createdAt = DateTime(2026, 3, 10, 21, 5);

TodoAttachment attachment(String id, String name) => TodoAttachment(
      id: id,
      type: TodoAttachmentType.image,
      path: '/tmp/$name',
      name: name,
    );

Note note({
  String body = '今天写完了周报',
  DateTime? date,
  String? categoryId,
  List<TodoAttachment> attachments = const <TodoAttachment>[],
}) {
  return Note.create(
    id: 'n1',
    date: date ?? DateTime(2026, 3, 10),
    body: body,
    createdAt: createdAt,
    categoryId: categoryId,
    attachments: attachments,
  );
}

void main() {
  group('creation', () {
    test('trims the body and reduces the date to midnight', () {
      final Note created = note(
        body: '  今天写完了周报  ',
        date: DateTime(2026, 3, 10, 22, 30),
      );
      expect(created.body, '今天写完了周报');
      expect(created.date, DateTime(2026, 3, 10));
    });

    test('a picture on its own is a note', () {
      // Something seen on the day is worth keeping without a sentence about it.
      final Note created = note(body: '', attachments: <TodoAttachment>[
        attachment('a1', 'cat.jpg'),
      ]);
      expect(created.body, '');
      expect(created.hasAttachments, isTrue);
    });

    test('nothing at all is rejected', () {
      expect(
        () => note(body: '   '),
        throwsA(isA<NoteValidationException>()),
      );
    });
  });

  group('preview', () {
    test('is the first line, or the attachment when there are no words', () {
      expect(note(body: '第一行\n第二行').preview, '第一行');
      expect(
        note(body: '', attachments: <TodoAttachment>[attachment('a1', 'cat.jpg')])
            .preview,
        'cat.jpg',
      );
    });
  });

  group('editing', () {
    test('keeps identity and creation time', () {
      final Note edited = note().edit(
        date: DateTime(2026, 3, 12),
        body: '改过的内容',
        categoryId: 'c1',
        attachments: <TodoAttachment>[attachment('a1', 'cat.jpg')],
      );

      expect(edited.id, 'n1');
      expect(edited.createdAt, createdAt);
      expect(edited.date, DateTime(2026, 3, 12));
      expect(edited.body, '改过的内容');
      expect(edited.categoryId, 'c1');
      expect(edited.attachments, hasLength(1));
    });

    test('emptying it completely is rejected', () {
      expect(
        () => note().edit(
          date: DateTime(2026, 3, 10),
          body: '  ',
          categoryId: null,
          attachments: const <TodoAttachment>[],
        ),
        throwsA(isA<NoteValidationException>()),
      );
    });
  });

  test('value equality covers attachments as well as text', () {
    expect(note(), note());
    expect(note(), isNot(note(body: '别的')));
    expect(
      note(attachments: <TodoAttachment>[attachment('a1', 'cat.jpg')]),
      isNot(note(attachments: <TodoAttachment>[attachment('a1', 'dog.jpg')])),
    );
  });
}
