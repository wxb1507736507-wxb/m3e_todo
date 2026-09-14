import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../todos/domain/entities/todo.dart';
import '../../../todos/domain/entities/todo_filter.dart';
import '../../../todos/presentation/providers/todo_providers.dart';
import '../../domain/entities/category.dart';
import '../providers/category_providers.dart';
import 'category_sheet.dart';

/// The category strip above the list: one small chip per folder, tap to narrow.
///
/// Deliberately a *strip* and not a screen. Keeping this beside the todos rather
/// than behind a destination is what makes it usable — you are looking at the
/// list, you wonder "where are the work ones?", and the answer is one tap away
/// without losing your place.
///
/// It is also deliberately smaller than the todo tiles it sits above: this is a
/// way of reading the list, not a second thing to read. Chips are compact, the
/// text is small, and the row scrolls sideways rather than wrapping, so it never
/// grows into the content it is meant to summarise.
class CategoryBar extends ConsumerWidget {
  const CategoryBar({super.key});

  /// Height of the strip. The tiles below it are twice this.
  static const double height = 34;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<Category> categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final List<Todo> todos = ref.watch(todoListProvider).value ?? const <Todo>[];
    final String? selected =
        ref.watch(todoFilterProvider.select((TodoFilter filter) => filter.categoryId));

    // Counted here in one pass: the strip is the only reader, and a count is
    // what makes it a summary rather than a row of decorative labels.
    final Map<String, int> counts = <String, int>{};
    for (final Todo todo in todos) {
      final String key = todo.categoryId ?? kUnfiledCategoryId;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    void select(String? scope) {
      ref.read(todoFilterProvider.notifier).setCategory(scope);
    }

    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: <Widget>[
          _Chip(
            label: AppStrings.categoryAll,
            count: todos.length,
            color: colors.primary,
            selected: selected == null,
            onTap: () => select(null),
          ),
          for (final Category category in categories)
            _Chip(
              label: category.name,
              count: counts[category.id] ?? 0,
              color: category.color == null ? colors.primary : Color(category.color!),
              selected: selected == category.id,
              onTap: () => select(category.id),
              // Long press renames: a strip this small has no room for a menu,
              // and editing a folder is rare next to filtering by one.
              onLongPress: () =>
                  unawaited(showCategorySheet(context, existing: category)),
            ),
          // Shown once there is something unfiled — or whenever it is the
          // active choice, so that filing the last one away cannot hide the
          // chip you would need in order to switch back.
          if (counts[kUnfiledCategoryId] != null ||
              selected == kUnfiledCategoryId)
            _Chip(
              label: AppStrings.categoryUnfiled,
              count: counts[kUnfiledCategoryId] ?? 0,
              color: colors.outline,
              selected: selected == kUnfiledCategoryId,
              onTap: () => select(kUnfiledCategoryId),
            ),
          _Chip(
            label: AppStrings.categoryNew,
            count: null,
            color: colors.primary,
            selected: false,
            icon: Icons.add,
            onTap: () => unawaited(showCategorySheet(context)),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// One chip of the strip: name, how many are in it, and that is all.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.icon,
  });

  final String label;
  final int? count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Center(
        child: Material(
          color: selected ? color.withValues(alpha: 0.16) : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null)
                    Icon(icon, size: 13, color: colors.onSurfaceVariant)
                  else
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: selected ? color : color.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: text.labelMedium?.copyWith(
                      color: selected ? colors.onSurface : colors.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                  if (count != null) ...<Widget>[
                    const SizedBox(width: 5),
                    Text(
                      '$count',
                      style: text.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
