import 'package:m3e_todo/features/categories/domain/entities/category.dart';
import 'package:m3e_todo/features/categories/domain/repositories/category_repository.dart';

/// In-memory [CategoryRepository] for tests.
///
/// The real one reads a file, and a widget test that waits for the disk is a
/// widget test that fails on a slow machine; a fake keeps the folders
/// deterministic and the assertions about the UI.
class FakeCategoryRepository implements CategoryRepository {
  FakeCategoryRepository([List<Category>? initial])
      : _categories = List<Category>.of(initial ?? const <Category>[]);

  List<Category> _categories;
  int saveCount = 0;

  @override
  Future<List<Category>> loadAll() async =>
      List<Category>.unmodifiable(_categories);

  @override
  Future<void> saveAll(List<Category> categories) async {
    saveCount++;
    _categories = List<Category>.of(categories);
  }
}
