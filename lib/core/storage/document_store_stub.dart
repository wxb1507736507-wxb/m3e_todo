import 'document_store.dart';

/// Fallback for platforms that are neither native nor web.
///
/// Failing loudly beats silently pretending to persist: a store that accepted
/// writes and dropped them would look like data loss much later, in a place far
/// from the cause.
Future<DocumentStoreFactory> prepareDocumentStoreFactory() async {
  throw UnsupportedError('No document store is available for this platform.');
}
