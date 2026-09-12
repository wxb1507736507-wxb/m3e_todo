import '../domain/app_settings.dart';

/// Translates [AppSettings] to and from the JSON shape written to disk.
///
/// Enums are stored by *name* rather than by index, so reordering the enum
/// declarations for readability cannot silently change what an existing file
/// means.
abstract final class AppSettingsCodec {
  static const int schemaVersion = 1;

  static Map<String, Object?> toJson(AppSettings settings) {
    return <String, Object?>{
      'version': schemaVersion,
      'themeMode': settings.themeMode.name,
      'colorSeed': settings.colorSeed.name,
    };
  }

  /// Rebuilds settings from [json], falling back per-field.
  ///
  /// An unreadable document should never stop the app from starting, so every
  /// field degrades to its default independently instead of the whole object
  /// being rejected.
  static AppSettings fromJson(Map<String, Object?>? json) {
    if (json == null) {
      return const AppSettings();
    }
    return AppSettings(
      themeMode: _enumByName(
        AppThemeMode.values,
        json['themeMode'],
        AppThemeMode.system,
      ),
      colorSeed: _enumByName(
        AppColorSeed.values,
        json['colorSeed'],
        AppColorSeed.violet,
      ),
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    if (raw is! String) {
      return fallback;
    }
    for (final T value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    return fallback;
  }
}
