import 'package:flutter/material.dart';

import '../../features/settings/domain/app_settings.dart';

/// Builds Material colour schemes from the user's chosen seed.
///
/// Every scheme uses [DynamicSchemeVariant.expressive], the tonal-palette
/// variant Material added for Expressive. Compared with the default
/// `tonalSpot`, it shifts the primary hue away from the seed and raises chroma,
/// which produces the richer, more contrasted palettes Expressive designs rely
/// on.
abstract final class AppColorSchemes {
  /// Used when a seed cannot be resolved, preserving the Material baseline.
  static const Color fallbackSeed = Color(0xFF6750A4);

  /// Generating a scheme runs the HCT tonal-palette algorithm, which is far from
  /// free. Results depend only on the seed and brightness, so they are cached:
  /// the appearance picker alone previews six seeds, and the app rebuilds both
  /// themes whenever a preference changes.
  static final Map<(AppColorSeed, Brightness), ColorScheme> _cache =
      <(AppColorSeed, Brightness), ColorScheme>{};

  /// The vivid seed colour behind each [AppColorSeed].
  static Color seedOf(AppColorSeed seed) {
    return switch (seed) {
      AppColorSeed.violet => const Color(0xFF6750A4),
      AppColorSeed.ocean => const Color(0xFF00639B),
      AppColorSeed.teal => const Color(0xFF00696D),
      AppColorSeed.forest => const Color(0xFF3F6837),
      AppColorSeed.amber => const Color(0xFF8A5100),
      AppColorSeed.rose => const Color(0xFF984061),
    };
  }

  /// Light scheme generated from [seed].
  static ColorScheme light(AppColorSeed seed) =>
      _schemeFor(seed, Brightness.light);

  /// Dark scheme generated from [seed].
  static ColorScheme dark(AppColorSeed seed) =>
      _schemeFor(seed, Brightness.dark);

  static ColorScheme _schemeFor(AppColorSeed seed, Brightness brightness) {
    return _cache.putIfAbsent(
      (seed, brightness),
      () => ColorScheme.fromSeed(
        seedColor: seedOf(seed),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.expressive,
      ),
    );
  }

  /// Maps the Flutter-free [AppThemeMode] onto Flutter's [ThemeMode].
  static ThemeMode themeModeOf(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }
}
