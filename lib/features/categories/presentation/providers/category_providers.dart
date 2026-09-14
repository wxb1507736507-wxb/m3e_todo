import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/document_store.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/utils/id_generator.dart';
import '../../data/datasources/category_local_data_source.dart';
import '../../data/repositories/local_category_repository.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';

/// File name of the folders document inside the app data directory.
const String categoryFileName = 'categories.json';

final Provider<DocumentStore> categoryDocumentStoreProvider =
    Provider<DocumentStore>(
  (ref) => ref.watch(documentStoreFactoryProvider)(categoryFileName),
  name: 'categoryDocumentStore',
);

final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>(
  (ref) => LocalCategoryRepository(
    CategoryLocalDataSource(ref.watch(categoryDocumentStoreProvider)),
  ),
  name: 'categoryRepository',
);

/// Ids for new folders; overridden in tests with a deterministic sequence.
final Provider<IdGenerator> categoryIdGeneratorProvider = Provider<IdGenerator>(
  (ref) => generateTodoId,
  name: 'categoryIdGenerator',
);

/// The user's folders.
class CategoriesController extends AsyncNotifier<List<Category>> {
  @override
  Future<List<Category>> build() =>
      ref.watch(categoryRepositoryProvider).loadAll();

  Future<Category> add({required String name, int? color}) async {
    final Category created = Category.create(
      id: ref.read(categoryIdGeneratorProvider)(),
      name: name,
      color: color,
    );
    await _replace((List<Category> current) => <Category>[...current, created]);
    return created;
  }

  Future<void> edit(String id, {required String name, required int? color}) {
    return _replace(
      (List<Category> current) => <Category>[
        for (final Category category in current)
          if (category.id == id)
            category.edited(name: name, color: color)
          else
            category,
      ],
    );
  }

  /// Removes a folder. Entries that were filed under it are not deleted — they
  /// fall back to "unfiled", because losing a todo because its folder was tidied
  /// away would be the worst possible reading of "delete this group".
  Future<void> remove(String id) {
    return _replace(
      (List<Category> current) =>
          current.where((Category category) => category.id != id).toList(),
    );
  }

  Future<void> _replace(
    List<Category> Function(List<Category> current) change,
  ) async {
    final List<Category> current = await future;
    final List<Category> updated = change(current);
    await ref.read(categoryRepositoryProvider).saveAll(updated);
    if (ref.mounted) {
      state = AsyncData<List<Category>>(updated);
    }
  }
}

final AsyncNotifierProvider<CategoriesController, List<Category>>
    categoriesProvider =
    AsyncNotifierProvider<CategoriesController, List<Category>>(
  CategoriesController.new,
  name: 'categories',
);

/// The folders by id, for name and colour lookups while building the list.
final Provider<Map<String, Category>> categoriesByIdProvider =
    Provider<Map<String, Category>>(
  (ref) => <String, Category>{
    for (final Category category in
        ref.watch(categoriesProvider).value ?? const <Category>[])
      category.id: category,
  },
  name: 'categoriesById',
);
