import 'dart:convert';
import 'dart:io';

import 'document_store.dart';

/// Reads and writes a single JSON document as an atomically-replaced file.
///
/// Writes go to a sibling `.tmp` file that is then renamed over the target. A
/// rename is atomic on both NTFS and POSIX filesystems, so a crash or power loss
/// mid-write can never leave a half-written document behind: a reader sees
/// either the previous complete file or the new complete one, never a truncated
/// mixture.
///
/// Native-only; see [DocumentStore] for the platform-neutral interface and the
/// `localStorage` implementation used on web.
class JsonFileStore implements DocumentStore {
  JsonFileStore(this.file);

  /// The document this store owns.
  final File file;

  String get _tempPath => '${file.path}.tmp';

  /// Reads the document, or returns `null` when there is nothing valid to read.
  ///
  /// Corrupt JSON is quarantined rather than silently discarded: the bad file is
  /// renamed to `<name>.corrupt-<timestamp>` so it can be recovered by hand,
  /// and `null` is returned so the app starts from a clean state instead of
  /// crashing on every launch.
  @override
  Future<Map<String, Object?>?> read() async {
    if (!await file.exists()) {
      return null;
    }
    try {
      final String raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
      await _quarantine();
      return null;
    } on FormatException {
      await _quarantine();
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Tail of the write chain; see [write].
  Future<void> _pending = Future<void>.value();

  /// Atomically replaces the document with [document].
  ///
  /// Writes are serialised because every one of them shares the same temporary
  /// file. Two overlapping calls would fight over it: on Windows the loser gets
  /// a sharing violation when it tries to rename (`errno 32`), and the final file
  /// could even end up holding the *older* value. Chaining also makes "last write
  /// wins" true by construction, which is exactly the guarantee a
  /// fire-and-forget caller such as the settings controller depends on.
  @override
  Future<void> write(Map<String, Object?> document) {
    final Future<void> result = _pending.then((_) => _writeNow(document));
    // Swallow the error on the chain only, so a single failed write cannot
    // poison every later one. The caller still sees it through [result].
    _pending = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _writeNow(Map<String, Object?> document) async {
    final Directory parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final File temp = File(_tempPath);
    // Pretty-printed so the on-disk file stays diffable and hand-editable.
    final String encoded =
        const JsonEncoder.withIndent('  ').convert(document);
    await temp.writeAsString(encoded, flush: true);
    await temp.rename(file.path);
  }

  /// Removes the document and any leftover temporary file.
  @override
  Future<void> delete() async {
    if (await file.exists()) {
      await file.delete();
    }
    final File temp = File(_tempPath);
    if (await temp.exists()) {
      await temp.delete();
    }
  }

  Future<void> _quarantine() async {
    try {
      final String stamp =
          DateTime.now().toIso8601String().replaceAll(':', '-');
      await file.rename('${file.path}.corrupt-$stamp');
    } on FileSystemException {
      // Nothing useful left to do; the next successful write replaces the file.
    }
  }
}
