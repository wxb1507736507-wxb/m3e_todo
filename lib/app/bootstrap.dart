import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
