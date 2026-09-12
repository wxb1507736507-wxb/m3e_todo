import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../domain/entities/todo_filter.dart';
import '../providers/todo_providers.dart';

/// Search field plus sort control, sitting directly under the summary.
class TodoToolbar extends ConsumerStatefulWidget {
  const TodoToolbar({super.key});

  @override
  ConsumerState<TodoToolbar> createState() => _TodoToolbarState();
}

class _TodoToolbarState extends ConsumerState<TodoToolbar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(todoFilterProvider.notifier).clearQuery();
  }

  @override
  Widget build(BuildContext context) {
    final TodoFilter filter = ref.watch(todoFilterProvider);
    // Watched, not created here: the Ctrl+F shortcut lives above this widget
    // and has to be able to focus the same node.
    final FocusNode searchFocusNode = ref.watch(searchFocusNodeProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: searchFocusNode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: AppStrings.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filter.hasQuery
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: AppStrings.clearSearch,
                      onPressed: _clearSearch,
                    )
                  : null,
            ),
            onChanged: ref.read(todoFilterProvider.notifier).setQuery,
          ),
        ),
        const SizedBox(width: 12),
        _SortMenu(
          selected: filter.sort,
          onSelected: ref.read(todoFilterProvider.notifier).setSort,
        ),
      ],
    );
  }
}

/// Menu button that chooses the list's ordering.
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.selected, required this.onSelected});

  final TodoSortOrder selected;
  final ValueChanged<TodoSortOrder> onSelected;

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
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final TodoSortOrder order in TodoSortOrder.values)
          MenuItemButton(
            // A placeholder keeps every row's text aligned whether or not it is
            // the selected one.
            leadingIcon: order == selected
                ? const Icon(Icons.check)
                : const SizedBox(width: 24),
            onPressed: () => onSelected(order),
            child: Text(_labelOf(order)),
          ),
      ],
      builder: (
        BuildContext context,
        MenuController controller,
        Widget? child,
      ) {
        return OutlinedButton.icon(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: const Icon(Icons.swap_vert),
          label: Text(_labelOf(selected)),
        );
      },
    );
  }
}
