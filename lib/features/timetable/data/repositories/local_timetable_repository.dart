import '../../domain/entities/timetable.dart';
import '../../domain/repositories/timetable_repository.dart';
import '../datasources/timetable_local_data_source.dart';

/// A [TimetableRepository] over the app's own JSON document.
class LocalTimetableRepository implements TimetableRepository {
  LocalTimetableRepository(this._source);

  final TimetableLocalDataSource _source;

  @override
  Future<Timetable?> load() => _source.read();

  @override
  Future<void> save(Timetable timetable) => _source.write(timetable);
}
