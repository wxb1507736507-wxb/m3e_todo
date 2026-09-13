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

/// How a due-date reminder makes itself noticed.
enum ReminderMode {
  /// Full sound + vibration through the "ring" notification channel.
  ring,

  /// A quiet notification through the "silent" channel.
  silent,
}

/// User-controlled application preferences.
///
/// Immutable: every change produces a new instance, which is what lets the
/// settings controller rely on `==` to decide whether anything actually
/// changed.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.colorSeed = AppColorSeed.violet,
    this.reminderMode = ReminderMode.ring,
    this.ringtoneUri,
    this.backgroundImage,
    this.backgroundDim = defaultBackgroundDim,
  });

  /// Default strength of the scrim drawn over an application background.
  ///
  /// Chosen so a photo is clearly visible while body text stays legible: at 0
  /// the photo competes with the text, above ~0.6 it stops being recognisable.
  static const double defaultBackgroundDim = 0.35;

  final AppThemeMode themeMode;
  final AppColorSeed colorSeed;

  /// Whether due reminders ring or arrive silently.
  final ReminderMode reminderMode;

  /// Chosen ringtone as a system `content://` URI, or `null` to follow the
  /// system default notification sound.
  final String? ringtoneUri;

  /// Application-wide background image, as a path to a private copy, or `null`
  /// for the plain theme surface.
  final String? backgroundImage;

  /// How strongly the theme surface is laid over [backgroundImage], in `[0, 1]`.
  final double backgroundDim;

  bool get hasBackground => backgroundImage != null;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppColorSeed? colorSeed,
    ReminderMode? reminderMode,
    String? ringtoneUri,
    bool clearRingtone = false,
    String? backgroundImage,
    bool clearBackgroundImage = false,
    double? backgroundDim,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      colorSeed: colorSeed ?? this.colorSeed,
      reminderMode: reminderMode ?? this.reminderMode,
      // The sentinel flag separates "clear" from "leave it alone", which a
      // plain nullable parameter cannot express.
      ringtoneUri: clearRingtone ? null : (ringtoneUri ?? this.ringtoneUri),
      backgroundImage: clearBackgroundImage
          ? null
          : (backgroundImage ?? this.backgroundImage),
      backgroundDim: backgroundDim ?? this.backgroundDim,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppSettings &&
        other.themeMode == themeMode &&
        other.colorSeed == colorSeed &&
        other.reminderMode == reminderMode &&
        other.ringtoneUri == ringtoneUri &&
        other.backgroundImage == backgroundImage &&
        other.backgroundDim == backgroundDim;
  }

  @override
  int get hashCode => Object.hash(
        themeMode,
        colorSeed,
        reminderMode,
        ringtoneUri,
        backgroundImage,
        backgroundDim,
      );

  @override
  String toString() =>
      'AppSettings(themeMode: $themeMode, colorSeed: $colorSeed, '
      'reminderMode: $reminderMode, ringtone: $ringtoneUri, '
      'background: $backgroundImage @$backgroundDim)';
}
