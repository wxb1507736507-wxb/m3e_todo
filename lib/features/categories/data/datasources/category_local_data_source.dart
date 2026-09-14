import '../../../../core/storage/document_store.dart';
import '../../domain/entities/category.dart';
import '../models/category_model.dart';

/// Reads and writes the folders as a versioned JSON document.
class CategoryLocalDataSource {
  CategoryLocalDataSource(this._store);

  final DocumentStore _store;

  static const String _versionKey = 'version';
  static const String _categoriesKey = 'categories';

  Future<List<Category>> readAll() async {
    final Map<String, Object?>? document = await _store.read();
    if (document == null) {
      return <Category>[];
    }
    final Object? raw = document[_categoriesKey];
    if (raw is! List) {
      return <Category>[];
    }

    final List<Category> categories = <Category>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final Category? category =
          CategoryModel.fromJson(Map<String, Object?>.from(entry));
      if (category != null) {
        categories.add(category);
      }
    }
    return categories;
  }

  Future<void> writeAll(List<Category> categories) {
    return _store.write(<String, Object?>{
      _versionKey: CategoryModel.schemaVersion,
      _categoriesKey: <Object?>[
        for (final Category category in categories) CategoryModel.toJson(category),
      ],
    });
  }
}
