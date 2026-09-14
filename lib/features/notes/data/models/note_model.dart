import '../../../todos/domain/entities/todo_attachment.dart';
import '../../domain/entities/note.dart';

/// Translates between [Note] and the JSON shape written to disk.
abstract final class NoteModel {
  /// Version 1 is the first shape this document has had.
  static const int schemaVersion = 1;

  static Map<String, Object?> toJson(Note note) {
    return <String, Object?>{
      'id': note.id,
      'date': note.date.toIso8601String(),
      'body': note.body,
      'createdAt': note.createdAt.toIso8601String(),
      if (note.categoryId != null) 'categoryId': note.categoryId,
      if (note.attachments.isNotEmpty)
        'attachments': <Object?>[
          for (final TodoAttachment attachment in note.attachments)
            <String, Object?>{
              'id': attachment.id,
              'type': attachment.type.name,
              'path': attachment.path,
              'name': attachment.name,
              if (attachment.mime != null) 'mime': attachment.mime,
            },
        ],
    };
  }

  /// Rebuilds a note, or returns `null` when the record is unusable.
  static Note? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final DateTime? date = _readDate(json, 'date');
    if (id is! String || id.isEmpty || date == null) {
      return null;
    }
    final Object? body = json['body'];
    final List<TodoAttachment> attachments = _readAttachments(json);
    // A note with neither words nor files is not worth keeping — and would fail
    // the constructor's own invariant anyway.
    if ((body is! String || body.trim().isEmpty) && attachments.isEmpty) {
      return null;
    }
    final Object? categoryId = json['categoryId'];
    return Note(
      id: id,
      date: date,
      body: body is String ? body : '',
      createdAt: _readDate(json, 'createdAt') ?? date,
      categoryId: categoryId is String && categoryId.isNotEmpty ? categoryId : null,
      attachments: attachments,
    );
  }

  static List<TodoAttachment> _readAttachments(Map<String, Object?> json) {
    final Object? raw = json['attachments'];
    if (raw is! List) {
      return const <TodoAttachment>[];
    }
    final List<TodoAttachment> attachments = <TodoAttachment>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final Map<String, Object?> attachment = Map<String, Object?>.from(entry);
      final Object? id = attachment['id'];
      final Object? path = attachment['path'];
      if (id is! String || id.isEmpty || path is! String || path.isEmpty) {
        continue;
      }
      attachments.add(
        TodoAttachment(
          id: id,
          type: _typeOf(attachment['type']),
          path: path,
          name: attachment['name'] is String ? attachment['name']! as String : path,
          mime: attachment['mime'] is String ? attachment['mime']! as String : null,
        ),
      );
    }
    return attachments;
  }

  static TodoAttachmentType _typeOf(Object? raw) {
    for (final TodoAttachmentType type in TodoAttachmentType.values) {
      if (type.name == raw) {
        return type;
      }
    }
    return TodoAttachmentType.document;
  }

  static DateTime? _readDate(Map<String, Object?> json, String key) {
    final Object? raw = json[key];
    return raw is String ? DateTime.tryParse(raw) : null;
  }
}
