import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../domain/entities/todo_filter.dart';
import '../providers/todo_providers.dart';

/// The search field that lives in the app bar.
///
/// It used to sit in its own row under the summary card, which cost a row of
/// height for something used a few times a day, and left the top of the screen
/// to a progress dashboard. Search and sort are the two things done *to* the
/// list, so they belong on the line the user's eyes already go to — the app bar,
/// next to the settings button.
///
/// Sized to the bar rather than to the list: a dense, filled pill that reads as
/// a field without pretending to be a full-width one.
class TodoSearchField extends ConsumerStatefulWidget {
  const TodoSearchField({super.key});

  @override
  ConsumerState<TodoSearchField> createState() => _TodoSearchFieldState();
}

class _TodoSearchFieldState extends ConsumerState<TodoSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    ref.read(todoFilterProvider.notifier).clearQuery();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TodoFilter filter = ref.watch(todoFilterProvider);
    // Watched, not created here: the Ctrl+F shortcut lives above this widget
    // and has to be able to focus the same node.
    final FocusNode focusNode = ref.watch(searchFocusNodeProvider);

    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surfaceContainerHighest,
          hintText: AppStrings.searchHint,
          hintStyle: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: colors.onSurfaceVariant,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: filter.hasQuery
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: AppStrings.clearSearch,
                  visualDensity: VisualDensity.compact,
                  onPressed: _clear,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 40),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: AppShapes.radius(AppShapes.full),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: ref.read(todoFilterProvider.notifier).setQuery,
      ),
    );
  }
}

/// Menu button that chooses the list's ordering.
///
/// Labelled rather than a bare icon: which order is in force is not decoration —
/// dragging a tile only reorders the list while "手动排序" is the one selected —
/// so the name of the current order stays on screen.
class TodoSortButton extends StatelessWidget {
  const TodoSortButton({super.key});

  static String _labelOf(TodoSortOrder order) {
    return switch (order) {
      TodoSortOrder.manual => AppStrings.sortManual,
      TodoSortOrder.createdNewest => AppStrings.sortCreatedNewest,
      TodoSortOrder.dueSoonest => AppStrings.sortDueSoonest,
      TodoSortOrder.priorityFirst => AppStrings.sortPriorityFirst,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final TodoSortOrder selected = ref.watch(
          todoFilterProvider.select((TodoFilter filter) => filter.sort),
        );
        return MenuAnchor(
          menuChildren: <Widget>[
            for (final TodoSortOrder order in TodoSortOrder.values)
              MenuItemButton(
                // A placeholder keeps every row's text aligned whether or not it
                // is the selected one.
                leadingIcon: order == selected
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                onPressed: () =>
                    ref.read(todoFilterProvider.notifier).setSort(order),
                child: Text(_labelOf(order)),
              ),
          ],
          builder: (
            BuildContext context,
            MenuController controller,
            Widget? child,
          ) {
            return Tooltip(
              message: AppStrings.sortTooltip,
              child: TextButton(
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 40),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: Text(
                  _labelOf(selected),
                  style: theme.textTheme.labelLarge,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
