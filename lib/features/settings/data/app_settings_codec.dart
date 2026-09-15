import '../../notifications/domain/reminder.dart';
import '../domain/app_settings.dart';

/// Translates [AppSettings] to and from the JSON shape written to disk.
///
/// Enums are stored by *name* rather than by index, so reordering the enum
/// declarations for readability cannot silently change what an existing file
/// means.
abstract final class AppSettingsCodec {
  /// Version 3 adds `backgroundImage` and `backgroundDim`.
  ///
  /// Both are optional on read, so a version-2 file loads unchanged and a
  /// version-3 file still opens in an older build, where the extra fields are
  /// simply ignored.
  /// Version 5 adds the timetable's own `timetableBackgroundImage` and
  /// `timetableBackgroundDim`, and version 6 the home-screen tiles'
  /// `widgetBackgroundImage` and `widgetBackgroundDim` — both optional on read:
  /// an older file loads with the app's defaults, and a newer one still opens in
  /// an older build.
  ///
  /// Version 7 held the photo-import reader's settings. That feature is gone,
  /// and the fields with it: a file written by it still loads, because writing
  /// extra keys is what a tolerant reader is for.
  static const int schemaVersion = 7;

  static Map<String, Object?> toJson(AppSettings settings) {
    return <String, Object?>{
      'version': schemaVersion,
      'themeMode': settings.themeMode.name,
      'colorSeed': settings.colorSeed.name,
      'reminderMode': settings.reminderMode.name,
      'reminderLead': settings.reminderLead.name,
      // Absent rather than null on disk: absent means "follow the system".
      if (settings.ringtoneUri != null) 'ringtoneUri': settings.ringtoneUri,
      // Same rule: absent means "no background, use the theme surface".
      if (settings.backgroundImage != null)
        'backgroundImage': settings.backgroundImage,
      'backgroundDim': settings.backgroundDim,
      if (settings.timetableBackgroundImage != null)
        'timetableBackgroundImage': settings.timetableBackgroundImage,
      'timetableBackgroundDim': settings.timetableBackgroundDim,
      if (settings.widgetBackgroundImage != null)
        'widgetBackgroundImage': settings.widgetBackgroundImage,
      'widgetBackgroundDim': settings.widgetBackgroundDim,
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
      reminderMode: _enumByName(
        ReminderMode.values,
        json['reminderMode'],
        ReminderMode.ring,
      ),
      reminderLead: _enumByName(
        ReminderLead.values,
        json['reminderLead'],
        ReminderLead.onDue,
      ),
      ringtoneUri: json['ringtoneUri'] is String ? json['ringtoneUri'] as String : null,
      backgroundImage:
          json['backgroundImage'] is String ? json['backgroundImage'] as String : null,
      backgroundDim: _unitInterval(
        json['backgroundDim'],
        AppSettings.defaultBackgroundDim,
      ),
      timetableBackgroundImage: json['timetableBackgroundImage'] is String
          ? json['timetableBackgroundImage'] as String
          : null,
      timetableBackgroundDim: _unitInterval(
        json['timetableBackgroundDim'],
        AppSettings.defaultBackgroundDim,
      ),
      widgetBackgroundImage: json['widgetBackgroundImage'] is String
          ? json['widgetBackgroundImage'] as String
          : null,
      widgetBackgroundDim: _unitInterval(
        json['widgetBackgroundDim'],
        AppSettings.defaultBackgroundDim,
      ),
    );
  }

  /// Reads a `[0, 1]` fraction, clamping rather than rejecting.
  ///
  /// A hand-edited or truncated value should not be able to paint the app's
  /// surface fully transparent (dim above 1) or fully occluded (below 0).
  static double _unitInterval(Object? raw, double fallback) {
    if (raw is! num) {
      return fallback;
    }
    final double value = raw.toDouble();
    if (value.isNaN) {
      return fallback;
    }
    return value.clamp(0.0, 1.0);
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
