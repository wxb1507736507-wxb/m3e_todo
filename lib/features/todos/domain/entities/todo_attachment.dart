/// What kind of content an attachment holds.
///
/// Drives the icon, the thumbnail logic and the picker filter; it is derived
/// from the MIME type at pick time rather than stored as user input, so the
/// enum stays consistent with the actual file.
enum TodoAttachmentType { image, video, audio, document }

/// A file attached to a todo — an image, a video, a document or a voice memo.
///
/// The file itself lives in the app's attachments directory (the native picker
/// copies it in at pick time); [path] is an absolute path into that directory.
/// Copying rather than linking is what makes the todo self-contained: deleting
/// the original from Downloads must not break the todo.
class TodoAttachment {
  const TodoAttachment({
    required this.id,
    required this.type,
    required this.path,
    required this.name,
    this.mime,
  });

  final String id;
  final TodoAttachmentType type;

  /// Absolute path of the private copy of the file.
  final String path;

  /// The name the file had when the user picked it; shown in the UI.
  final String name;

  /// Original MIME type as reported by the system picker; used when handing
  /// the file to an external viewer. `null` when the system did not say.
  final String? mime;

  /// Classifies a picked file from the metadata the system reported.
  ///
  /// The picker filter already constrains what arrives, but a generic
  /// `*/*` pick can still yield anything, so the fallback is [TodoAttachmentType.document].
  static TodoAttachmentType typeOf(String? mime, String name) {
    final String lowerMime = (mime ?? '').toLowerCase();
    if (lowerMime.startsWith('image/')) {
      return TodoAttachmentType.image;
    }
    if (lowerMime.startsWith('video/')) {
      return TodoAttachmentType.video;
    }
    if (lowerMime.startsWith('audio/')) {
      return TodoAttachmentType.audio;
    }
    final String extension = name.toLowerCase().split('.').last;
    const Set<String> imageExtensions = <String>{
      'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic',
    };
    const Set<String> videoExtensions = <String>{'mp4', 'mov', 'webm', 'mkv', 'avi'};
    const Set<String> audioExtensions = <String>{'m4a', 'mp3', 'aac', 'wav', 'ogg', 'flac'};
    if (imageExtensions.contains(extension)) {
      return TodoAttachmentType.image;
    }
    if (videoExtensions.contains(extension)) {
      return TodoAttachmentType.video;
    }
    if (audioExtensions.contains(extension)) {
      return TodoAttachmentType.audio;
    }
    return TodoAttachmentType.document;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TodoAttachment &&
        other.id == id &&
        other.type == type &&
        other.path == path &&
        other.name == name &&
        other.mime == mime;
  }

  @override
  int get hashCode => Object.hash(id, type, path, name, mime);

  @override
  String toString() => 'TodoAttachment($id, $type, "$name")';
}

/// Drops attachments pointing nowhere, and dedupes by path.
List<TodoAttachment> normalizeAttachments(Iterable<TodoAttachment> attachments) {
  final List<TodoAttachment> result = <TodoAttachment>[];
  final Set<String> seen = <String>{};
  for (final TodoAttachment attachment in attachments) {
    if (attachment.path.isEmpty || !seen.add(attachment.path)) {
      continue;
    }
    result.add(attachment);
  }
  return List<TodoAttachment>.unmodifiable(result);
}
