import '../../../../core/storage/document_store.dart';
import '../../domain/entities/timetable.dart';
import '../models/timetable_model.dart';

/// Reads and writes the timetable as a versioned JSON document.
class TimetableLocalDataSource {
  TimetableLocalDataSource(this._store, {required this.now});

  final DocumentStore _store;

  /// The clock, in the app's own sense of "now" rather than the platform's.
  ///
  /// Injected rather than read inside, because the app keeps one clock for the
  /// whole of its idea of "today", and a second one here would answer differently
  /// across midnight. Only needed for the one case where a document has courses
  /// but no term it can read; see [TimetableModel.fromJson].
  final DateTime Function() now;

  Future<Timetable?> read() async {
    final Map<String, Object?>? document = await _store.read();
    if (document == null) {
      return null;
    }
    return TimetableModel.fromJson(document, today: now());
  }

  Future<void> write(Timetable timetable) =>
      _store.write(TimetableModel.toJson(timetable));
}
