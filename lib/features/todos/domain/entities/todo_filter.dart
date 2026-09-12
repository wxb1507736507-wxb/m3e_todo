import 'todo.dart';

/// Which slice of the list the user wants to see.
enum TodoStatusFilter { all, active, completed }

/// How the visible slice should be ordered.
enum TodoSortOrder {
  /// The order the user established by dragging.
  manual,

  /// Newest capture first.
  createdNewest,

  /// Nearest deadline first; undated tasks sink to the bottom.
  dueSoonest,

  /// High priority first, then newest.
  priorityFirst,
}

/// The complete description of what the list should display.
///
/// This is a value object: the widget layer derives the visible list purely by
/// calling [apply], so there is exactly one implementation of "filter and sort"
/// shared by the UI and by tests.
class TodoFilter {
  const TodoFilter({
    this.status = TodoStatusFilter.all,
    this.sort = TodoSortOrder.manual,
    this.query = '',
  });

  final TodoStatusFilter status;
  final TodoSortOrder sort;

  /// Free-text search, matched case-insensitively against title and notes.
  final String query;

  bool get hasQuery => query.trim().isNotEmpty;

  /// Whether nothing has been narrowed down yet.
  bool get isPristine =>
      status == TodoStatusFilter.all &&
      sort == TodoSortOrder.manual &&
      !hasQuery;

  /// Reordering by hand only makes sense while the list is not being re-sorted
  /// by a rule; the list view uses this to enable or disable drag handles.
  bool get allowsManualReorder => sort == TodoSortOrder.manual;

  TodoFilter copyWith({
    TodoStatusFilter? status,
    TodoSortOrder? sort,
    String? query,
  }) {
    return TodoFilter(
      status: status ?? this.status,
      sort: sort ?? this.sort,
      query: query ?? this.query,
    );
  }

  /// Returns [todos] narrowed by status and query, then ordered by [sort].
  List<Todo> apply(List<Todo> todos) {
    final String needle = query.trim().toLowerCase();
    final List<Todo> visible = todos
        .where((Todo todo) => _matches(todo, needle))
        .toList(growable: true);

    if (sort != TodoSortOrder.manual) {
      visible.sort(_comparatorFor(sort));
    }
    return visible;
  }

  bool _matches(Todo todo, String needle) {
    final bool statusMatches = switch (status) {
      TodoStatusFilter.all => true,
      TodoStatusFilter.active => !todo.isCompleted,
      TodoStatusFilter.completed => todo.isCompleted,
    };
    if (!statusMatches) {
      return false;
    }
    if (needle.isEmpty) {
      return true;
    }
    return todo.title.toLowerCase().contains(needle) ||
        (todo.notes?.toLowerCase().contains(needle) ?? false);
  }

  static Comparator<Todo> _comparatorFor(TodoSortOrder order) {
    return switch (order) {
      TodoSortOrder.manual => _byNothing,
      TodoSortOrder.createdNewest => _byNewestFirst,
      TodoSortOrder.dueSoonest => _byDueSoonest,
      TodoSortOrder.priorityFirst => _byPriorityFirst,
    };
  }

  /// Manual order keeps the order the repository supplied.
  static int _byNothing(Todo a, Todo b) => 0;

  static int _byNewestFirst(Todo a, Todo b) =>
      b.createdAt.compareTo(a.createdAt);

  /// Undated todos sort last rather than first, because "no deadline" is not
  /// the same as "due in the year zero".
  static int _byDueSoonest(Todo a, Todo b) {
    final DateTime? left = a.dueDate;
    final DateTime? right = b.dueDate;
    if (left == null && right == null) {
      return _byNewestFirst(a, b);
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    final int byDate = left.compareTo(right);
    return byDate != 0 ? byDate : _byNewestFirst(a, b);
  }

  static int _byPriorityFirst(Todo a, Todo b) {
    final int byRank = b.priority.rank.compareTo(a.priority.rank);
    return byRank != 0 ? byRank : _byNewestFirst(a, b);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TodoFilter &&
        other.status == status &&
        other.sort == sort &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(status, sort, query);

  @override
  String toString() =>
      'TodoFilter(status: $status, sort: $sort, query: "$query")';
}
