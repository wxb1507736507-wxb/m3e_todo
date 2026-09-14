import '../../domain/entities/special_day.dart';

/// Translates between [SpecialDay] and the JSON shape written to disk.
///
/// Enums are stored by name, not by index, so reordering the declarations
/// cannot silently change what an existing file means.
abstract final class SpecialDayModel {
  /// Version 1 is the first shape this document has had.
  static const int schemaVersion = 1;

  static Map<String, Object?> toJson(SpecialDay day) {
    return <String, Object?>{
      'id': day.id,
      'title': day.title,
      'kind': day.kind.name,
      'date': day.date.toIso8601String(),
      if (day.notes != null) 'notes': day.notes,
    };
  }

  /// Rebuilds a special day, or returns `null` when the record is unusable.
  ///
  /// One damaged record is skipped rather than failing the whole load: losing a
  /// single entry beats refusing to show the user's calendar.
  static SpecialDay? fromJson(Map<String, Object?> json) {
    final String? id = _readString(json, 'id');
    final String? title = _readString(json, 'title');
    final DateTime? date = _readDate(json, 'date');
    if (id == null ||
        id.isEmpty ||
        title == null ||
        title.trim().isEmpty ||
        date == null) {
      return null;
    }
    return SpecialDay(
      id: id,
      title: title,
      kind: _readKind(json),
      date: date,
      notes: _readString(json, 'notes'),
    );
  }

  /// An unknown kind is read as an anniversary: it is the yearly kind with the
  /// least specific wording, so a value from a future version shows up on the
  /// right day even if the label is not quite what was meant.
  static SpecialDayKind _readKind(Map<String, Object?> json) {
    final String? raw = _readString(json, 'kind');
    for (final SpecialDayKind kind in SpecialDayKind.values) {
      if (kind.name == raw) {
        return kind;
      }
    }
    return SpecialDayKind.anniversary;
  }

  static String? _readString(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    return value is String ? value : null;
  }

  static DateTime? _readDate(Map<String, Object?> json, String key) {
    final String? raw = _readString(json, key);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
