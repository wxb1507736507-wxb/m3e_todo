import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_platform.dart';
import '../../../core/storage/document_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';
import '../../notifications/domain/reminder.dart';

/// File name of the settings document inside the app data directory.
const String settingsFileName = 'settings.json';

final Provider<DocumentStore> settingsDocumentStoreProvider =
    Provider<DocumentStore>(
  (ref) => ref.watch(documentStoreFactoryProvider)(settingsFileName),
  name: 'settingsDocumentStore',
);

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(settingsDocumentStoreProvider)),
  name: 'settingsRepository',
);

/// Initial settings, injected by `bootstrap()` after reading them from disk.
///
/// Settings are loaded *before* the first frame rather than through an async
/// notifier, because a theme that arrives a frame late would flash the wrong
/// colours on every launch.
final Provider<AppSettings> initialSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError(
    'initialSettingsProvider must be overridden in ProviderScope.',
  ),
  name: 'initialSettings',
);

/// Current appearance settings, and the only place they are mutated.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  void setThemeMode(AppThemeMode mode) {
    if (state.themeMode == mode) {
      return;
    }
    _apply(state.copyWith(themeMode: mode));
  }

  void setColorSeed(AppColorSeed seed) {
    if (state.colorSeed == seed) {
      return;
    }
    _apply(state.copyWith(colorSeed: seed));
  }

  /// Switches between ringing and silent reminders, and re-points the native
  /// notification channel so the change takes effect for future alarms.
  Future<void> setReminderMode(ReminderMode mode) async {
    if (state.reminderMode == mode) {
      return;
    }
    _apply(state.copyWith(reminderMode: mode));
  }

  /// Sets how early reminders arrive by default.
  void setReminderLead(ReminderLead lead) {
    if (state.reminderLead == lead) {
      return;
    }
    _apply(state.copyWith(reminderLead: lead));
  }

  /// Sets the ringtone reminders sound with by default, or back to the system
  /// default when `null`.
  ///
  /// No native call: the sound travels with each alarm now, and the native side
  /// keeps one notification channel per distinct ringtone — so changing this
  /// only has to reach the scheduler, which [AppShell] re-runs when the settings
  /// change. Todos that carry their own ringtone are unaffected.
  Future<void> setRingtone(String? uri) async {
    _apply(state.copyWith(ringtoneUri: uri, clearRingtone: uri == null));
  }

  /// Previews the given ringtone (or the system default) once.
  Future<void> previewRingtone(String? uri) async {
    await AppPlatform.playRingtone(uri);
  }

  Future<void> stopPreview() => AppPlatform.stopRingtone();

  /// Sets the application-wide background image, or clears it when [path] is
  /// null.
  ///
  /// The previous file is deleted: the cropper always writes a *new* file, so
  /// replacing a background (or removing one) would otherwise leave the old copy
  /// in the app directory with nothing referencing it.
  Future<void> setBackgroundImage(String? path) async {
    final String? previous = state.backgroundImage;
    _apply(
      state.copyWith(
        backgroundImage: path,
        clearBackgroundImage: path == null,
      ),
    );
    if (previous != null && previous != path) {
      await _deleteQuietly(previous);
    }
  }

  /// Sets how strongly the theme surface covers the background image.
  void setBackgroundDim(double dim) {
    final double clamped = dim.clamp(0.0, 1.0);
    if (state.backgroundDim == clamped) {
      return;
    }
    _apply(state.copyWith(backgroundDim: clamped));
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on Object {
      // Already gone, or not ours to delete.
    }
  }

  Future<void>? _pendingWrite;

  /// The most recent write to disk.
  ///
  /// The UI never waits on this: applying the preference straight away is what
  /// keeps the interaction instant. Exposing it anyway means anything that does
  /// need durability &mdash; a shutdown hook, or a test asserting the preference
  /// really reached the file &mdash; can await it rather than guessing at a
  /// delay long enough to cover the write.
  Future<void> get pendingWrite => _pendingWrite ?? Future<void>.value();

  void _apply(AppSettings settings) {
    state = settings;
    // Persisting is deliberately fire-and-forget: the new value is already
    // applied to the UI, and a preference write is not worth making the user
    // wait for. The failure path still reports rather than swallowing.
    final Future<void> write = _persist(settings);
    _pendingWrite = write;
    unawaited(write);
  }

  Future<void> _persist(AppSettings settings) async {
    try {
      await ref.read(settingsRepositoryProvider).save(settings);
    } on Object catch (error, stackTrace) {
      debugPrint('Could not persist settings: $error\n$stackTrace');
    }
  }
}

final NotifierProvider<SettingsController, AppSettings> settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
  name: 'settings',
);
