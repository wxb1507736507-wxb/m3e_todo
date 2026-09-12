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
}
