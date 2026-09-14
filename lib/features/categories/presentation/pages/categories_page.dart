import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../todos/domain/entities/todo.dart';
import '../../../todos/presentation/providers/todo_providers.dart';
import '../../domain/entities/category.dart';
import '../providers/category_providers.dart';
import '../widgets/category_sheet.dart';
import 'category_detail_page.dart';

/// The folders: one row each, with how many todos are filed inside.
///
/// One level, like the contact groups it is modelled on. Tapping a row opens
/// that folder, where the search box looks only inside it — which is the whole
/// point of filing things away.
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<Category> categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final List<Todo> todos = ref.watch(todoListProvider).value ?? const <Todo>[];

    // Counted in one pass here rather than kept as derived state: the numbers
    // are only ever needed on this screen, and a todo whose folder was deleted
    // counts as unfiled rather than disappearing from every folder at once.
    final Set<String> known = <String>{
      for (final Category category in categories) category.id,
    };
    final Map<String, int> counts = <String, int>{};
    int unfiled = 0;
    for (final Todo todo in todos) {
      final String? id = todo.categoryId;
      if (id == null || !known.contains(id)) {
        unfiled++;
      } else {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }

    if (categories.isEmpty && todos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            AppStrings.categoriesEmpty,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        if (categories.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              AppStrings.categoriesEmpty,
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        for (final Category category in categories)
          _FolderRow(
            name: category.name,
            color: category.color,
            count: counts[category.id] ?? 0,
            onOpen: () => _open(context, category),
            onEdit: () => unawaited(showCategorySheet(context, existing: category)),
          ),
        _FolderRow(
          name: AppStrings.categoryUnfiled,
          color: null,
          count: unfiled,
          onOpen: () => _open(context, null),
          onEdit: null,
        ),
      ],
    );
  }

  void _open(BuildContext context, Category? category) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CategoryDetailPage(category: category),
        ),
      ),
    );
  }
}

/// One folder: its colour, its name, how much is inside, and a way in.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.color,
    required this.count,
    required this.onOpen,
    required this.onEdit,
  });

  final String name;
  final int? color;
  final int count;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = color == null ? colors.outline : Color(color!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: AppShapes.radius(AppShapes.large),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: AppShapes.radius(AppShapes.small),
                  ),
                  child: Icon(Icons.folder_outlined, size: 20, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium,
                  ),
                ),
                Text(
                  '$count',
                  style: text.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: AppStrings.categoryEdit,
                    onPressed: onEdit,
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
