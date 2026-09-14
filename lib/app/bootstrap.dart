import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/diagnostics/frame_log.dart';
import '../core/storage/document_store.dart';
import '../core/storage/document_store_factory.dart';
import '../core/storage/storage_providers.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_controller.dart';
import 'app.dart';

/// Prepares the app and starts it.
///
/// Two things happen here, both before the first frame, because both are
/// platform questions that the widget tree must never have to ask:
///
///  * storage is located. On Android that means asking the host for the app's
///    private directory over a method channel; elsewhere it is derived from the
///    environment, or is `localStorage` on web.
///  * settings are read, so the theme is correct immediately instead of
///    flashing the default colours and then correcting itself.
///
/// The results are injected as provider overrides, which leaves the widget tree
/// free of platform I/O and lets every widget be tested without a filesystem.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No-op unless the build passed --dart-define=M3E_FRAME_LOG=true.
  installFrameLogger();
  _boundImageCache();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  // Errors raised outside the widget pipeline (a failed background write, for
  // instance) would otherwise disappear into the void.
  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stackTrace) {
    debugPrint('Uncaught error: $error\n$stackTrace');
    return true;
  };

  final DocumentStoreFactory storeFactory = await prepareDocumentStoreFactory();
  final AppSettings settings = await SettingsRepository(
    storeFactory(settingsFileName),
  ).load();

  runApp(
    ProviderScope(
      overrides: [
        documentStoreFactoryProvider.overrideWithValue(storeFactory),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const M3eTodoApp(),
    ),
  );
}

/// Caps how much decoded image data the app will hold on to.
///
/// Flutter's defaults (1000 images / 100MB) are tuned for galleries that show
/// hundreds of photos. This app keeps at most a handful on screen — an
/// application background, tile backgrounds, attachment thumbnails — and the
/// ceiling is not academic: measured on the Android 13 device after scrolling a
/// list of 60 todos that each carry their own background image, the defaults
/// left the process at **297MB PSS / 166MB of graphics memory**, against
/// **196MB / 68MB** with this bound. Nearly 100MB of textures were being kept
/// alive for rows that had long since scrolled away.
///
/// It is a ceiling, not a reservation: with a few images the cache never
/// approaches it, and a smaller bound can only cost a re-decode of a row the
/// user scrolls back to.
void _boundImageCache() {
  final ImageCache cache = PaintingBinding.instance.imageCache;
  cache.maximumSizeBytes = 32 << 20; // 32MB
  cache.maximumSize = 120; // entries
}
