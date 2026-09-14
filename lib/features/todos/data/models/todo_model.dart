import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_attachment.dart';
import '../../domain/entities/todo_priority.dart';
import '../../domain/entities/todo_subtask.dart';

/// Translates between [Todo] and the JSON shape written to disk.
///
/// Mapping lives in the data layer so the domain entity carries no
/// serialisation concern, and so an on-disk schema change is confined to this
/// one file.
abstract final class TodoModel {
  /// Bumped whenever the stored shape changes incompatibly.
  ///
  /// Version 2 adds `subtasks`, `attachments`, `accentColor` and
  /// `backgroundImage`; version 3 adds `textColor`. Every one of them is
  /// optional on read, so an older file loads unchanged and a newer one still
  /// opens in an older build — the fields it does not know are ignored.
  static const int schemaVersion = 3;

  static Map<String, Object?> toJson(Todo todo) {
    return <String, Object?>{
      'id': todo.id,
      'title': todo.title,
      'createdAt': todo.createdAt.toIso8601String(),
      'priority': todo.priority.name,
      // Optional fields are omitted rather than written as null, which keeps the
      // file readable and makes "absent" and "null" the same thing on read.
      if (todo.notes != null) 'notes': todo.notes,
      if (todo.dueDate != null) 'dueDate': todo.dueDate!.toIso8601String(),
      if (todo.completedAt != null)
        'completedAt': todo.completedAt!.toIso8601String(),
      if (todo.subtasks.isNotEmpty)
        'subtasks': <Object?>[
          for (final TodoSubtask subtask in todo.subtasks) _subtaskJson(subtask),
        ],
      if (todo.attachments.isNotEmpty)
        'attachments': <Object?>[
          for (final TodoAttachment attachment in todo.attachments)
            _attachmentJson(attachment),
        ],
      if (todo.accentColor != null) 'accentColor': todo.accentColor,
      if (todo.textColor != null) 'textColor': todo.textColor,
      if (todo.backgroundImage != null) 'backgroundImage': todo.backgroundImage,
    };
  }

  /// Rebuilds a todo, or returns `null` when the record cannot be trusted.
  ///
  /// A single damaged record returns `null` instead of throwing so the data
  /// source can skip it. Losing one malformed row is far better than refusing to
  /// load the user's entire list because of it.
  static Todo? fromJson(Map<String, Object?> json) {
    final String? id = _readString(json, 'id');
    final String? title = _readString(json, 'title');
    final DateTime? createdAt = _readDate(json, 'createdAt');

    if (id == null ||
        id.isEmpty ||
        title == null ||
        title.trim().isEmpty ||
        createdAt == null) {
      return null;
    }

    // Constructed directly rather than via Todo.create: the stored values were
    // already normalised on write, and the guard above has re-checked the one
    // invariant that matters.
    return Todo(
      id: id,
      title: title,
      createdAt: createdAt,
      notes: _readString(json, 'notes'),
      priority: _readPriority(json),
      dueDate: _readDate(json, 'dueDate'),
      completedAt: _readDate(json, 'completedAt'),
      subtasks: _readSubtasks(json),
      attachments: _readAttachments(json),
      accentColor: _readInt(json, 'accentColor'),
      textColor: _readInt(json, 'textColor'),
      backgroundImage: _readString(json, 'backgroundImage'),
    );
  }

  static Map<String, Object?> _subtaskJson(TodoSubtask subtask) {
    return <String, Object?>{
      'id': subtask.id,
      'title': subtask.title,
      if (subtask.completedAt != null)
        'completedAt': subtask.completedAt!.toIso8601String(),
    };
  }

  static Map<String, Object?> _attachmentJson(TodoAttachment attachment) {
    return <String, Object?>{
      'id': attachment.id,
      'type': attachment.type.name,
      'path': attachment.path,
      'name': attachment.name,
      if (attachment.mime != null) 'mime': attachment.mime,
    };
  }

  static List<TodoSubtask> _readSubtasks(Map<String, Object?> json) {
    final Object? raw = json['subtasks'];
    if (raw is! List) {
      return const <TodoSubtask>[];
    }
    final List<TodoSubtask> subtasks = <TodoSubtask>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final Map<String, Object?> subtaskJson = Map<String, Object?>.from(entry);
      final String? id = _readString(subtaskJson, 'id');
      final String? title = _readString(subtaskJson, 'title');
      if (id == null || id.isEmpty || title == null || title.trim().isEmpty) {
        continue;
      }
      subtasks.add(TodoSubtask(
        id: id,
        title: title,
        completedAt: _readDate(subtaskJson, 'completedAt'),
      ));
    }
    return subtasks;
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
      final Map<String, Object?> attachmentJson = Map<String, Object?>.from(entry);
      final String? id = _readString(attachmentJson, 'id');
      final String? path = _readString(attachmentJson, 'path');
      if (id == null || id.isEmpty || path == null || path.isEmpty) {
        continue;
      }
      attachments.add(TodoAttachment(
        id: id,
        type: _readAttachmentType(attachmentJson),
        path: path,
        name: _readString(attachmentJson, 'name') ?? path,
        mime: _readString(attachmentJson, 'mime'),
      ));
    }
    return attachments;
  }

  static TodoAttachmentType _readAttachmentType(Map<String, Object?> json) {
    final String? raw = _readString(json, 'type');
    for (final TodoAttachmentType type in TodoAttachmentType.values) {
      if (type.name == raw) {
        return type;
      }
    }
    return TodoAttachmentType.document;
  }

  static String? _readString(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    return value is String ? value : null;
  }

  static int? _readInt(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    return value is int ? value : null;
  }

  static DateTime? _readDate(Map<String, Object?> json, String key) {
    final String? raw = _readString(json, key);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Unknown or missing priority names fall back to [TodoPriority.normal], so a
  /// value written by a future version does not discard the record.
  static TodoPriority _readPriority(Map<String, Object?> json) {
    final String? raw = _readString(json, 'priority');
    if (raw == null) {
      return TodoPriority.normal;
    }
    for (final TodoPriority priority in TodoPriority.values) {
      if (priority.name == raw) {
        return priority;
      }
    }
    return TodoPriority.normal;
  }
}
