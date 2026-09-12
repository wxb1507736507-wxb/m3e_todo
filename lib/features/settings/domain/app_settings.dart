/// Which colour scheme the app should follow.
///
/// Deliberately a plain enum rather than Flutter's [ThemeMode] so the settings
/// layer stays free of Flutter imports and can be unit-tested as pure Dart.
enum AppThemeMode { system, light, dark }

/// Seed colours offered to the user.
///
/// Material's dynamic colour algorithm derives the entire 45-role scheme from a
/// single seed, so these six values are the only colours that need maintaining.
enum AppColorSeed { violet, ocean, teal, forest, amber, rose }

/// User-controlled application preferences.
///
/// Immutable: every change produces a new instance, which is what lets the
/// settings controller rely on `==` to decide whether anything actually
/// changed.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.colorSeed = AppColorSeed.violet,
  });

  final AppThemeMode themeMode;
  final AppColorSeed colorSeed;

  AppSettings copyWith({AppThemeMode? themeMode, AppColorSeed? colorSeed}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      colorSeed: colorSeed ?? this.colorSeed,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppSettings &&
        other.themeMode == themeMode &&
        other.colorSeed == colorSeed;
  }

  @override
  int get hashCode => Object.hash(themeMode, colorSeed);

  @override
  String toString() =>
      'AppSettings(themeMode: $themeMode, colorSeed: $colorSeed)';
}
