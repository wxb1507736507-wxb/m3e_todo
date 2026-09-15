import '../../../../core/storage/document_store.dart';
import '../../domain/entities/timetable.dart';
import '../models/timetable_model.dart';

/// Reads and writes the timetable as a versioned JSON document.
class TimetableLocalDataSource {
  TimetableLocalDataSource(this._store);

  final DocumentStore _store;

  Future<Timetable?> read() async {
    final Map<String, Object?>? document = await _store.read();
    if (document == null) {
      return null;
    }
    return TimetableModel.fromJson(document);
  }

  Future<void> write(Timetable timetable) =>
      _store.write(TimetableModel.toJson(timetable));
}
