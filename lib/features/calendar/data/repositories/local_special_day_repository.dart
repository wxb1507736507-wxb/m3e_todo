import '../../domain/entities/special_day.dart';
import '../../domain/repositories/special_day_repository.dart';
import '../datasources/special_day_local_data_source.dart';

/// [SpecialDayRepository] backed by the local JSON document.
///
/// Caches the loaded collection in memory for the same reason the todo
/// repository does: every change replaces the whole list, so without a cache
/// each edit would re-read and re-parse the file.
class LocalSpecialDayRepository implements SpecialDayRepository {
  LocalSpecialDayRepository(this._dataSource);

  final SpecialDayLocalDataSource _dataSource;

  List<SpecialDay>? _cache;

  @override
  Future<List<SpecialDay>> loadAll() async {
    final List<SpecialDay>? cached = _cache;
    if (cached != null) {
      return List<SpecialDay>.unmodifiable(cached);
    }
    final List<SpecialDay> loaded = await _dataSource.readAll();
    _cache = loaded;
    return List<SpecialDay>.unmodifiable(loaded);
  }

  @override
  Future<void> saveAll(List<SpecialDay> days) async {
    final List<SpecialDay> snapshot = List<SpecialDay>.unmodifiable(days);
    await _dataSource.writeAll(snapshot);
    _cache = snapshot;
  }
}
