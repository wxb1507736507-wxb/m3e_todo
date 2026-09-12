import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/todo_filter.dart';

/// Holds what the list should currently show: status, order and search text.
///
/// Kept in its own notifier rather than folded into the list controller, so
/// narrowing the view never touches the stored data and the two cannot corrupt
/// each other. Every setter no-ops when the value is unchanged, which prevents
/// pointless rebuilds while the user is typing.
class TodoFilterController extends Notifier<TodoFilter> {
  @override
  TodoFilter build() => const TodoFilter();

  void setStatus(TodoStatusFilter status) {
    if (state.status == status) {
      return;
    }
    state = state.copyWith(status: status);
  }

  void setSort(TodoSortOrder sort) {
    if (state.sort == sort) {
      return;
    }
    state = state.copyWith(sort: sort);
  }

  void setQuery(String query) {
    if (state.query == query) {
      return;
    }
    state = state.copyWith(query: query);
  }

  void clearQuery() => setQuery('');

  void reset() => state = const TodoFilter();
}
