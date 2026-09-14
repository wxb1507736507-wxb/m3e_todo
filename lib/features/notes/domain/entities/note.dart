import '../../../../core/utils/calendar.dart';
import '../../../todos/domain/entities/todo_attachment.dart';

/// A dated jotting: what happened, what you thought, what you saw.
///
/// Distinct from a todo in the way that matters: nothing here is ever finished.
/// A note belongs to a *day* rather than to a deadline, which is why it shows up
/// under the calendar next to that day rather than in the list of things to do.
///
/// The body may be empty when there is something attached — a photo taken on the
/// day is a note in its own right — so the rule is "a body or an attachment",
/// not "a body".
class Note {
  const Note({
    required this.id,
    required this.date,
    required this.body,
    required this.createdAt,
    this.categoryId,
    this.attachments = const <TodoAttachment>[],
  });

  factory Note.create({
    required String id,
    required DateTime date,
    required String body,
    required DateTime createdAt,
    String? categoryId,
    List<TodoAttachment> attachments = const <TodoAttachment>[],
  }) {
    final String trimmed = body.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      throw const NoteValidationException('A note needs words or an attachment.');
    }
    return Note(
      id: id,
      date: startOfDay(date),
      body: trimmed,
      createdAt: createdAt,
      categoryId: categoryId,
      attachments: List<TodoAttachment>.unmodifiable(attachments),
    );
  }

  final String id;

  /// The day this note belongs to, at midnight. What the calendar files it under.
  final DateTime date;

  /// The words. Never null; empty when the note is only an attachment.
  final String body;

  final DateTime createdAt;

  /// The folder this note is filed under, or `null` for unfiled — the same
  /// folders the todos use, so "work" means one thing in this app.
  final String? categoryId;

  final List<TodoAttachment> attachments;

  bool get hasAttachments => attachments.isNotEmpty;

  /// The first line, for a one-line summary.
  String get preview {
    if (body.isEmpty) {
      return attachments.isEmpty ? '' : attachments.first.name;
    }
    final int newline = body.indexOf('\n');
    return newline < 0 ? body : body.substring(0, newline);
  }

  Note edit({
    required DateTime date,
    required String body,
    required String? categoryId,
    required List<TodoAttachment> attachments,
  }) {
    final String trimmed = body.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      throw const NoteValidationException('A note needs words or an attachment.');
    }
    return Note(
      id: id,
      date: startOfDay(date),
      body: trimmed,
      createdAt: createdAt,
      categoryId: categoryId,
      attachments: List<TodoAttachment>.unmodifiable(attachments),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.date == date &&
      other.body == body &&
      other.createdAt == createdAt &&
      other.categoryId == categoryId &&
      _sameAttachments(other.attachments, attachments);

  @override
  int get hashCode => Object.hash(
        id,
        date,
        body,
        createdAt,
        categoryId,
        Object.hashAll(attachments),
      );

  @override
  String toString() => 'Note($id, $date, ${body.length} chars)';

  static bool _sameAttachments(
    List<TodoAttachment> a,
    List<TodoAttachment> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Thrown when a note would be saved with neither words nor an attachment.
class NoteValidationException implements Exception {
  const NoteValidationException(this.message);

  final String message;

  @override
  String toString() => 'NoteValidationException: $message';
}
