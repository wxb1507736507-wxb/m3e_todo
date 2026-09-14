import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../todos/domain/entities/todo.dart';
import '../../../todos/presentation/providers/todo_providers.dart';
import '../../../todos/presentation/widgets/todo_editor_sheet.dart';
import '../../../todos/presentation/widgets/todo_list_view.dart';
import '../../domain/entities/category.dart';
import '../providers/category_providers.dart';

/// Everything filed inside one folder, with a search box that looks only here.
///
/// A separate screen rather than a filter on the main list: the point of a
/// folder is that opening it narrows what you are looking at, and a filter that
/// can be forgotten about somewhere else does not do that.
class CategoryDetailPage extends ConsumerStatefulWidget {
  const CategoryDetailPage({required this.category, super.key});

  /// The folder being shown, or `null` for the unfiled pile.
  final Category? category;

  @override
  ConsumerState<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends ConsumerState<CategoryDetailPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Todo> todos = ref.watch(todoListProvider).value ?? const <Todo>[];
    final DateTime now = ref.read(clockProvider)();
    final String? categoryId = widget.category?.id;

    // One pass: the folder test and the query test together, and the same rule
    // the folders screen counts by — an id whose folder no longer exists counts
    // as unfiled.
    final Set<String> known = <String>{
      for (final Category category
          in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id,
    };
    final String needle = _query.trim().toLowerCase();
    final List<Todo> visible = <Todo>[
      for (final Todo todo in todos)
        if (_belongs(todo, categoryId, known) && _matches(todo, needle)) todo,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category?.name ?? AppStrings.categoryUnfiled),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            unawaited(showTodoEditor(context, initialCategoryId: categoryId)),
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.newTodo),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _searchController,
              onChanged: (String value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: AppStrings.categorySearchHint,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: AppStrings.clearSearch,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? AppStrings.categoryFolderEmpty
                            : AppStrings.emptySearchTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    )
                  : TodoListView(
                      todos: visible,
                      now: now,
                      // Inside a folder the order is still the manual one, so
                      // dragging works the same way it does on the main list.
                      allowReorder: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _belongs(Todo todo, String? categoryId, Set<String> known) {
    final String? id = todo.categoryId;
    final bool unfiled = id == null || !known.contains(id);
    return categoryId == null ? unfiled : id == categoryId;
  }

  static bool _matches(Todo todo, String needle) {
    if (needle.isEmpty) {
      return true;
    }
    return todo.title.toLowerCase().contains(needle) ||
        (todo.notes?.toLowerCase().contains(needle) ?? false);
  }
}
