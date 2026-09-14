import '../../../../core/storage/document_store.dart';
import '../../domain/entities/special_day.dart';
import '../models/special_day_model.dart';

/// Reads and writes the personal dates as a versioned JSON document.
///
/// Mirrors the todo data source, envelope and all: the version travels with the
/// data so a future shape change can be migrated rather than guessed at, and a
/// record that fails to parse is skipped instead of failing the load.
class SpecialDayLocalDataSource {
  SpecialDayLocalDataSource(this._store);

  final DocumentStore _store;

  static const String _versionKey = 'version';
  static const String _daysKey = 'days';

  Future<List<SpecialDay>> readAll() async {
    final Map<String, Object?>? document = await _store.read();
    if (document == null) {
      return <SpecialDay>[];
    }
    final Object? raw = document[_daysKey];
    if (raw is! List) {
      return <SpecialDay>[];
    }

    final List<SpecialDay> days = <SpecialDay>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final SpecialDay? day = SpecialDayModel.fromJson(
        Map<String, Object?>.from(entry),
      );
      if (day != null) {
        days.add(day);
      }
    }
    return days;
  }

  Future<void> writeAll(List<SpecialDay> days) {
    return _store.write(<String, Object?>{
      _versionKey: SpecialDayModel.schemaVersion,
      _daysKey: <Object?>[
        for (final SpecialDay day in days) SpecialDayModel.toJson(day),
      ],
    });
  }
}
