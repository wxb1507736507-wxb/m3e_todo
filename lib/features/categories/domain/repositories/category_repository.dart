import '../entities/category.dart';

/// Persistence boundary for the user's folders.
abstract interface class CategoryRepository {
  /// Every stored category, in the order the user created them.
  Future<List<Category>> loadAll();

  /// Replaces the stored collection with [categories].
  Future<void> saveAll(List<Category> categories);
}
