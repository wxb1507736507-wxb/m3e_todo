import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'document_store.dart';

/// Builds a [DocumentStore] for a named document.
///
/// Declared with no usable default on purpose. Resolving "where does data live"
/// needs a platform step that cannot happen inside a synchronous provider:
/// Android has to be asked over a method channel. So `bootstrap()` awaits
/// `prepareDocumentStoreFactory()` before the first frame and injects the result
/// here, which keeps platform I/O in exactly one place and lets tests point the
/// whole app at a temporary directory with a single override.
///
/// A silently wrong default would be worse than none: on Android the
/// environment-derived path resolves to the filesystem root, where writes fail.
final Provider<DocumentStoreFactory> documentStoreFactoryProvider =
    Provider<DocumentStoreFactory>(
  (ref) => throw UnimplementedError(
    'documentStoreFactoryProvider must be overridden in ProviderScope.',
  ),
  name: 'documentStoreFactory',
);
