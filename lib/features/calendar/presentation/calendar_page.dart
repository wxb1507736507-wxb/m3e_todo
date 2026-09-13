import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../../../core/utils/calendar.dart';
import '../../todos/domain/entities/todo.dart';
import '../../todos/presentation/providers/todo_providers.dart';

/// Calendar review: every todo, past and present, laid over a month grid.
///
/// The grid is built as fixed rows of seven cells (not a [GridView]) because 42
/// lightweight cells are cheaper to build and lay out than a scrolling viewport
/// machinery, which matters on low-end devices.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  /// First day of the shown month.
  late DateTime _month;

  /// The day whose details are listed under the grid.
  late DateTime _selectedDay;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    final DateTime now = ref.read(clockProvider)();
    _month = DateTime(now.year, now.month);
    _selectedDay = startOfDay(now);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      // Landing on a month with no selected day: select the 1st, unless it is
      // the current month, where "today" is the useful default.
      final DateTime now = ref.read(clockProvider)();
      final bool isCurrentMonth =
          _month.year == now.year && _month.month == now.month;
      _selectedDay = isCurrentMonth
          ? startOfDay(now)
          : DateTime(_month.year, _month.month, 1);
    });
  }

  /// Date jump: the platform date picker doubles as a "go to date" control —
  /// picking any date lands the grid on its month and selects the day.
  Future<void> _jumpToDate() async {
    final DateTime now = ref.read(clockProvider)();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _month = DateTime(picked.year, picked.month);
      _selectedDay = startOfDay(picked);
    });
  }

  void _goToday() {
    final DateTime now = ref.read(clockProvider)();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selectedDay = startOfDay(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Todo>> asyncTodos = ref.watch(todoListProvider);
    final List<Todo> todos = asyncTodos.value ?? const <Todo>[];
    // One clock read per build, so the grid's "today" highlight, the row labels
    // and the day details cannot disagree about what today is.
    final DateTime now = ref.read(clockProvider)();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildMonthHeader(context),
          const SizedBox(height: 8),
          _MonthGrid(
            month: _month,
            now: now,
            counts: _DayCounts.from(todos),
            selectedDay: _selectedDay,
            onDaySelected: (DateTime day) =>
                setState(() => _selectedDay = day),
          ),
          const SizedBox(height: 12),
          _buildSearchField(context),
          const SizedBox(height: 8),
          Expanded(
            child: _query.isEmpty
                ? _DayDetails(day: _selectedDay, todos: todos)
                : _SearchResults(
                    todos: todos,
                    query: _query,
                    today: now,
                    onJumpToDate: _jumpTo,
                  ),
          ),
        ],
      ),
    );
  }

  /// Lands the grid on [day] and leaves search, so the user sees the day rather
  /// than the search result they came from.
  void _jumpTo(DateTime day) {
    setState(() {
      _month = DateTime(day.year, day.month);
      _selectedDay = startOfDay(day);
      _query = '';
      _searchController.clear();
    });
  }

  Widget _buildMonthHeader(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: AppStrings.calendarPreviousMonth,
          onPressed: () => _shiftMonth(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              AppStrings.calendarMonthLabel(_month.year, _month.month),
              style: text.titleLarge,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: AppStrings.calendarNextMonth,
          onPressed: () => _shiftMonth(1),
        ),
        TextButton(onPressed: _goToday, child: const Text(AppStrings.calendarToday)),
        IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: AppStrings.calendarJumpToDate,
          onPressed: () => unawaited(_jumpToDate()),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      onChanged: (String value) => setState(() => _query = value.trim()),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        hintText: AppStrings.calendarSearchHint,
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
    );
  }
}

/// Per-day counts derived once per build, so the 42 grid cells only ever read
/// from a precomputed map instead of rescanning the list per cell.
///
/// Days are keyed by an integer (`year * 10000 + month * 100 + day`) rather than
/// by `DateTime`: a `DateTime` key means allocating two objects per todo while
/// building the map **and** one per lookup in every cell, and `DateTime` equality
/// is far more expensive than an int hash. Long lists made that the single
/// biggest cost of drawing the grid.
class _DayCounts {
  const _DayCounts(this._due, this._completed);

  factory _DayCounts.from(List<Todo> todos) {
    final Map<int, int> due = <int, int>{};
    final Map<int, int> completed = <int, int>{};
    for (final Todo todo in todos) {
      final DateTime? dueDate = todo.dueDate;
      if (dueDate != null) {
        final int key = dayKey(dueDate);
        due[key] = (due[key] ?? 0) + 1;
      }
      final DateTime? completedAt = todo.completedAt;
      if (completedAt != null) {
        final int key = dayKey(completedAt);
        completed[key] = (completed[key] ?? 0) + 1;
      }
    }
    return _DayCounts(due, completed);
  }

  final Map<int, int> _due;
  final Map<int, int> _completed;

  int dueOn(int key) => _due[key] ?? 0;
  int completedOn(int key) => _completed[key] ?? 0;
}

/// Sortable, hashable day identity: `2026-09-13` becomes `20260913`.
int dayKey(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

/// One cell of the month grid, resolved once per build.
///
/// The grid is a pure function of `(month, counts, now, selectedDay)`, so the
/// per-cell decisions — is it a real day, is it today, is it selected, how many
/// todos — are computed in one pass and then rendered. Deciding them inside the
/// cell widget meant re-reading `Theme.of` twice per cell and re-deriving the
/// same `DateTime` two or three times.
class _Cell {
  const _Cell({
    required this.day,
    required this.dayNumber,
    required this.selected,
    required this.isToday,
    required this.dueCount,
    required this.doneCount,
  });

  final DateTime day;
  final int dayNumber;
  final bool selected;
  final bool isToday;
  final int dueCount;
  final int doneCount;
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.now,
    required this.counts,
    required this.selectedDay,
    required this.onDaySelected,
  });

  static const List<String> _weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];

  /// Reused for every blank cell, so a month that starts mid-week does not
  /// allocate a fresh widget for each leading gap.
  static const Widget _blank = SizedBox(height: _cellHeight);

  static const double _cellHeight = 44;

  final DateTime month;
  final DateTime now;
  final _DayCounts counts;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final List<_Cell?> cells = _resolveCells();
    final int rows = cells.length ~/ 7;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final String weekday in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    weekday,
                    style: text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (int row = 0; row < rows; row++)
          Row(
            children: <Widget>[
              for (int column = 0; column < 7; column++)
                Expanded(child: _cellWidget(context, cells[row * 7 + column])),
            ],
          ),
      ],
    );
  }

  /// Resolves the whole grid — including the leading blanks — in one pass.
  List<_Cell?> _resolveCells() {
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first grid: weekday 1 (Monday) is column 0.
    final int leading = (DateTime(month.year, month.month, 1).weekday - 1) % 7;
    final int rows = ((leading + daysInMonth) / 7).ceil();
    final int selectedKey = dayKey(selectedDay);
    final int todayKey = dayKey(now);

    return List<_Cell?>.generate(rows * 7, (int index) {
      final int dayNumber = index - leading + 1;
      if (dayNumber < 1 || dayNumber > daysInMonth) {
        return null;
      }
      final DateTime day = DateTime(month.year, month.month, dayNumber);
      final int key = dayKey(day);
      return _Cell(
        day: day,
        dayNumber: dayNumber,
        selected: key == selectedKey,
        isToday: key == todayKey,
        dueCount: counts.dueOn(key),
        doneCount: counts.completedOn(key),
      );
    });
  }

  Widget _cellWidget(BuildContext context, _Cell? cell) {
    if (cell == null) {
      return _blank;
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool selected = cell.selected;
    final bool todayCell = cell.isToday;

    return Padding(
      padding: const EdgeInsets.all(1),
      child: InkWell(
        onTap: () => onDaySelected(cell.day),
        borderRadius: AppShapes.radius(AppShapes.small),
        child: Container(
          height: _cellHeight,
          decoration: BoxDecoration(
            color: selected ? colors.primaryContainer : null,
            borderRadius: AppShapes.radius(AppShapes.small),
            border: todayCell && !selected
                ? Border.all(color: colors.primary, width: 1)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '${cell.dayNumber}',
                style: text.bodyMedium?.copyWith(
                  color: selected ? colors.onPrimaryContainer : null,
                  fontWeight: todayCell || selected ? FontWeight.bold : null,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (cell.dueCount > 0)
                      _dot(colors.primary, selected),
                    if (cell.doneCount > 0) ...<Widget>[
                      const SizedBox(width: 3),
                      _dot(colors.onSurfaceVariant, selected),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _dot(Color color, bool onSelected) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onSelected ? null : color,
          border: onSelected ? Border.all(color: color, width: 1.5) : null,
        ),
      );
}

/// Todos connected to one day: due that day, or completed that day.
///
/// Rows carry no date of their own — every one of them belongs to the selected
/// day, which the grid above already highlights; repeating it 20 times would be
/// noise.
class _DayDetails extends StatelessWidget {
  const _DayDetails({required this.day, required this.todos});

  final DateTime day;
  final List<Todo> todos;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    // One pass, not two: the selected day is compared by integer key, so this
    // stays O(n) with no per-todo `DateTime` allocation.
    final int key = dayKey(day);
    final List<Todo> due = <Todo>[];
    final List<Todo> completed = <Todo>[];
    for (final Todo todo in todos) {
      final DateTime? dueDate = todo.dueDate;
      if (dueDate != null && dayKey(dueDate) == key) {
        due.add(todo);
        continue;
      }
      final DateTime? completedAt = todo.completedAt;
      if (completedAt != null && dayKey(completedAt) == key) {
        completed.add(todo);
      }
    }

    if (due.isEmpty && completed.isEmpty) {
      return Center(
        child: Text(
          AppStrings.calendarNoTodos,
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }

    return ListView(
      children: <Widget>[
        if (due.isNotEmpty) ...<Widget>[
          _legend(context, Icons.event_outlined, AppStrings.calendarDueLegend),
          for (final Todo todo in due) _TodoRow(todo: todo),
        ],
        if (completed.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _legend(
            context,
            Icons.check_circle_outline,
            AppStrings.calendarCompletedLegend,
          ),
          for (final Todo todo in completed) _TodoRow(todo: todo),
        ],
      ],
    );
  }

  Widget _legend(BuildContext context, IconData icon, String label) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: text.labelLarge),
        ],
      ),
    );
  }
}

/// Search across all todos by title and notes.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.todos,
    required this.query,
    required this.today,
    required this.onJumpToDate,
  });

  final List<Todo> todos;
  final String query;

  /// Used only to decide whether a date needs its year spelled out.
  final DateTime today;

  final ValueChanged<DateTime> onJumpToDate;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String lower = query.toLowerCase();

    final List<(Todo, DateTime)> hits = <(Todo, DateTime)>[];
    for (final Todo todo in todos) {
      if (!todo.title.toLowerCase().contains(lower) &&
          !(todo.notes?.toLowerCase().contains(lower) ?? false)) {
        continue;
      }
      // Jumping to a hit means showing it on its day: prefer the due date,
      // then completion, then creation.
      final DateTime anchor =
          todo.dueDate ?? todo.completedAt ?? todo.createdAt;
      hits.add((todo, anchor));
    }

    if (hits.isEmpty) {
      return Center(
        child: Text(
          AppStrings.emptySearchTitle,
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (BuildContext context, int index) {
        final (Todo todo, DateTime anchor) = hits[index];
        return _TodoRow(
          todo: todo,
          dateLabel: AppDateFormatter.calendarDate(anchor, today),
          onJump: () => onJumpToDate(anchor),
        );
      },
    );
  }
}

/// One todo inside the calendar's lower pane.
class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.todo, this.dateLabel, this.onJump});

  final Todo todo;

  /// Shown at the trailing edge when the row is not already grouped under a
  /// single day — search results need it, day details do not.
  final String? dateLabel;

  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onJump,
        borderRadius: AppShapes.radius(AppShapes.small),
        child: Row(
          children: <Widget>[
            Icon(
              todo.isCompleted ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: todo.isCompleted ? colors.primary : colors.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                todo.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyLarge?.copyWith(
                  decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (dateLabel != null) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                dateLabel!,
                style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
