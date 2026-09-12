import 'dart:convert';

import 'package:web/web.dart' as web;

import 'document_store.dart';

/// Web implementation backed by `localStorage`.
///
/// Uses `localStorage` rather than IndexedDB because the documents here are a
/// few kilobytes of JSON and are read once at startup: a synchronous key/value
/// store is a better fit than an async transactional database, and it needs no
/// extra dependency.
///
/// Writes are synchronous, so unlike the file-backed store there is nothing to
/// serialise &mdash; `setItem` either happens or throws.
class LocalStorageDocumentStore implements DocumentStore {
  LocalStorageDocumentStore(this.name);

  /// Logical document name, e.g. `todos.json`.
  final String name;

  /// Namespaced so several apps served from the same origin cannot collide.
  String get _key => 'm3e_todo.$name';

  @override
  Future<Map<String, Object?>?> read() async {
    final String? raw = web.window.localStorage.getItem(_key);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      // Fall through to the discard below.
    }
    // Same contract as the file-backed store: a document that cannot be parsed
    // is removed rather than allowed to break every later launch.
    _remove();
    return null;
  }

  @override
  Future<void> write(Map<String, Object?> document) async {
    web.window.localStorage.setItem(_key, jsonEncode(document));
  }

  @override
  Future<void> delete() async => _remove();

  void _remove() => web.window.localStorage.removeItem(_key);
}

/// Web needs no preparation: `localStorage` requires neither discovery nor a
/// permission, so the factory is known up front.
Future<DocumentStoreFactory> prepareDocumentStoreFactory() async =>
    (String name) => LocalStorageDocumentStore(name);
