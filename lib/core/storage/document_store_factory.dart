import 'document_store.dart';
import 'document_store_stub.dart'
    if (dart.library.io) 'document_store_io.dart'
    if (dart.library.js_interop) 'document_store_web.dart' as platform;

/// Prepares storage for the current platform and returns the factory to use.
///
/// This is the single place where "where does data live?" is answered, and the
/// answer differs enough per platform that it cannot be a constant:
///
///  * **web** needs no preparation — `localStorage` is always available.
///  * **desktop native** derives the directory from the environment
///    (`%APPDATA%` on Windows, `XDG_DATA_HOME`/`HOME` elsewhere).
///  * **Android and iOS** cannot derive it at all. Each app gets a private
///    directory whose path is only known to the host process, so it has to be
///    asked for over a method channel.
///
/// The implementation is chosen at compile time by conditional import, so
/// `dart:io` is never referenced on web and `package:web` is never referenced on
/// native.
///
/// It is async because of the channel case, and `bootstrap()` awaits it before
/// the first frame — which is exactly where platform I/O belongs.
Future<DocumentStoreFactory> prepareDocumentStoreFactory() =>
    platform.prepareDocumentStoreFactory();
