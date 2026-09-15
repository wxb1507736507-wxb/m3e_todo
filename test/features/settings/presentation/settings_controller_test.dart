import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/storage/app_directories.dart';
import 'package:m3e_todo/core/storage/json_file_store.dart';
import 'package:m3e_todo/core/storage/storage_providers.dart';
import 'package:m3e_todo/features/settings/data/settings_repository.dart';
import 'package:m3e_todo/features/settings/domain/app_settings.dart';
import 'package:m3e_todo/features/settings/presentation/settings_controller.dart';

/// Persistence is verified here rather than in a widget test on purpose.
///
/// `testWidgets` runs its body in a zone with faked timers, so a `dart:io`
/// operation started from a tap never has its completion delivered and awaiting
/// it hangs. A plain `test()` runs against the real event loop, so the whole
/// chain &mdash; controller, repository, atomic file write &mdash; can be
/// exercised for real, and far faster.
void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('m3e_todo_settings');
    container = ProviderContainer(
      overrides: [
        documentStoreFactoryProvider.overrideWithValue(
          (String name) => JsonFileStore(tempDir.childFile(name)),
        ),
        initialSettingsProvider.overrideWithValue(const AppSettings()),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File settingsFile() =>
      File('${tempDir.path}${Platform.pathSeparator}$settingsFileName');

  SettingsRepository repository() =>
      SettingsRepository(JsonFileStore(settingsFile()));

  test('starts from the injected initial settings', () {
    expect(container.read(settingsProvider), const AppSettings());
  });

  test('persists a theme mode change', () async {
    final SettingsController controller =
        container.read(settingsProvider.notifier);

    controller.setThemeMode(AppThemeMode.dark);
    await controller.pendingWrite;

    final AppSettings stored = await repository().load();
    expect(stored.themeMode, AppThemeMode.dark);
    // Unrelated fields keep their values.
    expect(stored.colorSeed, AppColorSeed.violet);
  });

  test('persists a seed colour change', () async {
    final SettingsController controller =
        container.read(settingsProvider.notifier);

    controller.setColorSeed(AppColorSeed.rose);
    await controller.pendingWrite;

    final AppSettings stored = await repository().load();
    expect(stored.colorSeed, AppColorSeed.rose);
    expect(stored.themeMode, AppThemeMode.system);
  });

  test('updates in-memory state before the write completes', () {
    final SettingsController controller =
        container.read(settingsProvider.notifier);

    controller.setThemeMode(AppThemeMode.light);

    // The UI must reflect the choice immediately; persistence is deliberately
    // not on the interaction path.
    expect(container.read(settingsProvider).themeMode, AppThemeMode.light);
  });

  test('re-selecting the current value schedules no write', () async {
    final SettingsController controller =
        container.read(settingsProvider.notifier);

    // The initial value is already `system`, so this is a no-op.
    controller.setThemeMode(AppThemeMode.system);
    await controller.pendingWrite;

    expect(settingsFile().existsSync(), isFalse);
  });

  test('round-trips settings through the file', () async {
    final SettingsController controller =
        container.read(settingsProvider.notifier);

    controller.setThemeMode(AppThemeMode.dark);
    controller.setColorSeed(AppColorSeed.teal);
    await controller.pendingWrite;

    final AppSettings stored = await repository().load();
    expect(stored, const AppSettings(
      themeMode: AppThemeMode.dark,
      colorSeed: AppColorSeed.teal,
    ));
  });

  group('application background', () {
    test('persists the image and the scrim strength', () async {
      final SettingsController controller =
          container.read(settingsProvider.notifier);

      await controller.setBackgroundImage('/tmp/background.png');
      controller.setBackgroundDim(0.6);
      await controller.pendingWrite;

      final AppSettings stored = await repository().load();
      expect(stored.backgroundImage, '/tmp/background.png');
      expect(stored.backgroundDim, 0.6);
      expect(stored.hasBackground, isTrue);
    });

    test('clamps the scrim into [0, 1] instead of trusting the caller', () {
      final SettingsController controller =
          container.read(settingsProvider.notifier);

      controller.setBackgroundDim(4);
      expect(container.read(settingsProvider).backgroundDim, 1.0);

      controller.setBackgroundDim(-3);
      expect(container.read(settingsProvider).backgroundDim, 0.0);
    });

    test('removing the background deletes the file it replaced', () async {
      final File image = File('${tempDir.path}${Platform.pathSeparator}bg.png')
        ..writeAsStringSync('not really a png');
      final SettingsController controller =
          container.read(settingsProvider.notifier);

      await controller.setBackgroundImage(image.path);
      expect(image.existsSync(), isTrue);

      await controller.setBackgroundImage(null);
      // The settings write is fire-and-forget by design, so wait for it before
      // the temp directory is torn down: on Windows an in-flight write holds the
      // file open and the cleanup would fail with a sharing violation.
      await controller.pendingWrite;

      expect(container.read(settingsProvider).backgroundImage, isNull);
      // The cropper always writes a fresh file, so a replaced or removed
      // background would otherwise linger in the app directory unreferenced.
      expect(image.existsSync(), isFalse);
    });

    test('a version-2 file still loads, with the new field defaulted', () async {
      // Written by the previous release: no background keys at all.
      settingsFile().writeAsStringSync(
        '{"version":2,"themeMode":"dark","colorSeed":"rose",'
        '"reminderMode":"silent"}',
      );

      final AppSettings stored = await repository().load();

      expect(stored.themeMode, AppThemeMode.dark);
      expect(stored.colorSeed, AppColorSeed.rose);
      expect(stored.backgroundImage, isNull);
      expect(stored.backgroundDim, AppSettings.defaultBackgroundDim);
    });

    test('a nonsense scrim value falls back rather than breaking the app', () async {
      settingsFile().writeAsStringSync(
        '{"version":3,"backgroundDim":"very dim","backgroundImage":17}',
      );

      final AppSettings stored = await repository().load();

      expect(stored.backgroundDim, AppSettings.defaultBackgroundDim);
      expect(stored.backgroundImage, isNull);
    });
  });

  group('widget background', () {
    test('persists the tiles picture and its scrim strength', () async {
      final SettingsController controller =
          container.read(settingsProvider.notifier);

      await controller.setWidgetBackgroundImage('/tmp/tiles.png');
      controller.setWidgetBackgroundDim(0.6);
      await controller.pendingWrite;

      final AppSettings stored = await repository().load();
      expect(stored.widgetBackgroundImage, '/tmp/tiles.png');
      expect(stored.widgetBackgroundDim, 0.6);
      // The app's own background is a different decision and stays untouched.
      expect(stored.backgroundImage, isNull);
    });

    test('clamps the tiles scrim to the slider range', () {
      final SettingsController controller =
          container.read(settingsProvider.notifier);

      // Short of opaque on purpose: at 1.0 the picture is gone and the slider
      // that would bring it back reads as if it were already at the end.
      controller.setWidgetBackgroundDim(4);
      expect(container.read(settingsProvider).widgetBackgroundDim, 0.9);

      controller.setWidgetBackgroundDim(-3);
      expect(container.read(settingsProvider).widgetBackgroundDim, 0.0);
    });

    test('removing the tiles picture deletes the file it replaced', () async {
      final File image = File('${tempDir.path}${Platform.pathSeparator}tiles.png')
        ..writeAsStringSync('not really a png');
      final SettingsController controller =
          container.read(settingsProvider.notifier);

      await controller.setWidgetBackgroundImage(image.path);
      await controller.setWidgetBackgroundImage(null);
      await controller.pendingWrite;

      expect(container.read(settingsProvider).widgetBackgroundImage, isNull);
      expect(image.existsSync(), isFalse);
    });

    test('a version-5 file still loads, with the new fields defaulted', () async {
      settingsFile().writeAsStringSync(
        '{"version":5,"themeMode":"dark","colorSeed":"rose",'
        '"backgroundImage":"/tmp/app.png","backgroundDim":0.4,'
        '"timetableBackgroundImage":"/tmp/grid.png","timetableBackgroundDim":0.5}',
      );

      final AppSettings stored = await repository().load();

      expect(stored.themeMode, AppThemeMode.dark);
      expect(stored.timetableBackgroundImage, '/tmp/grid.png');
      expect(stored.widgetBackgroundImage, isNull);
      expect(stored.widgetBackgroundDim, AppSettings.defaultBackgroundDim);
    });
  });

}
