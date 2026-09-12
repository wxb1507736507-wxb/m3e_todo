/// A single named JSON document.
///
/// This is the seam that keeps storage portable. On native platforms
/// `JsonFileStore` backs it with an atomically-replaced file; on Flutter web,
/// where `dart:io` does not exist at all, a `localStorage`-backed
/// implementation takes its place. Nothing above this interface — repository,
/// data source, use cases or UI — knows or cares which one is in use.
///
/// Only three operations are needed, and they are deliberately coarse: every
/// caller in this app replaces a whole document rather than patching parts of
/// one, which is what makes atomic replacement possible.
abstract interface class DocumentStore {
  /// Reads the document, or returns `null` when there is nothing valid to read.
  ///
  /// Implementations must not throw on corrupt content; quarantine or discard it
  /// and return `null` so a damaged document cannot stop the app from starting.
  Future<Map<String, Object?>?> read();

  /// Replaces the document, durably enough that a crash cannot leave a
  /// half-written mixture behind.
  Future<void> write(Map<String, Object?> document);

  /// Removes the document and any leftover temporary data.
  Future<void> delete();
}

/// Builds a [DocumentStore] for a named document, e.g. `todos.json`.
///
/// A factory rather than a directory path, because web has no directory at all:
/// asking for a document by name is the only thing every platform can honour.
typedef DocumentStoreFactory = DocumentStore Function(String name);
