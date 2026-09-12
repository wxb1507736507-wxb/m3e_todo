import 'dart:io';

import 'package:flutter/services.dart';

import 'app_directories.dart';
import 'document_store.dart';
import 'json_file_store.dart';

/// Channel the Android/iOS host answers on. The name is namespaced by the
/// application id so it cannot clash with a plugin's channels.
const MethodChannel _storageChannel = MethodChannel('dev.m3e.m3e_todo/storage');

/// Native implementation: one JSON file per document.
Future<DocumentStoreFactory> prepareDocumentStoreFactory() async {
  final String directory = await _resolveDataDirectory();
  return (String name) => JsonFileStore(Directory(directory).childFile(name));
}

Future<String> _resolveDataDirectory() async {
  // On Android and iOS the app's private directory is handed out by the host,
  // never present in the environment. Note that `Platform.environment` on
  // Android contains only a handful of system variables, so the desktop logic
  // below would otherwise fall through to `Directory.current` — which resolves
  // to the filesystem root there, and is not writable.
  if (Platform.isAndroid || Platform.isIOS) {
    final String? fromHost = await _askHostForDataDirectory();
    if (fromHost != null && fromHost.isNotEmpty) {
      return '$fromHost${Platform.pathSeparator}${AppDirectories.appFolderName}';
    }
  }
  return AppDirectories.dataDirectoryPath();
}

/// Asks the host for the app's private files directory.
///
/// Returns `null` rather than throwing when the channel is unavailable. That
/// happens when Dart runs without the Android shell — a plain Dart VM or a unit
/// test — and in those cases falling back to the environment-derived path is the
/// more useful behaviour than refusing to start.
Future<String?> _askHostForDataDirectory() async {
  try {
    return await _storageChannel.invokeMethod<String>('getDataDirectory');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
