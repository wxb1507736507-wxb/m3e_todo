import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../datasources/category_local_data_source.dart';

/// [CategoryRepository] backed by the local JSON document, with the same
/// in-memory cache the other repositories keep: every change replaces the whole
/// list, so without it each edit would re-read and re-parse the file.
class LocalCategoryRepository implements CategoryRepository {
  LocalCategoryRepository(this._dataSource);

  final CategoryLocalDataSource _dataSource;

  List<Category>? _cache;

  @override
  Future<List<Category>> loadAll() async {
    final List<Category>? cached = _cache;
    if (cached != null) {
      return List<Category>.unmodifiable(cached);
    }
    final List<Category> loaded = await _dataSource.readAll();
    _cache = loaded;
    return List<Category>.unmodifiable(loaded);
  }

  @override
  Future<void> saveAll(List<Category> categories) async {
    final List<Category> snapshot = List<Category>.unmodifiable(categories);
    await _dataSource.writeAll(snapshot);
    _cache = snapshot;
  }
}
