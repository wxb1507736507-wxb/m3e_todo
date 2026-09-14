import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../core/utils/calendar.dart';
import '../../notes/domain/entities/note.dart';
import '../../notes/presentation/providers/note_providers.dart';
import '../../notes/presentation/widgets/note_sheet.dart';
import '../../todos/domain/entities/todo.dart';
import '../../todos/presentation/providers/todo_providers.dart';
import '../domain/entities/special_day.dart';
import 'providers/special_day_providers.dart';
import 'widgets/special_day_sheet.dart';

/// Which collection the pane under the grid is showing.
enum _Pane { todos, specialDays }

/// Calendar review: every todo, past and present, laid over a month grid, with
/// the user's birthdays, anniversaries and countdowns alongside them.
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
  /// How many months can be swiped either side of the month the app opened in:
  /// ten years each way, which is more than a calendar needs and cheap, because
  /// a [PageView] only builds the pages near the one on screen.
  static const int _pageRadius = 120;

  /// The month the page index is measured from.
  late final DateTime _anchor;

  late final PageController _pageController;

  /// First day of the shown month.
  late DateTime _month;

  /// The day whose details are listed under the grid.
  late DateTime _selectedDay;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Which pane is showing. A calendar app's month grid is shared between
  /// "what is due" and "what is coming round", so the switch sits under it
  /// rather than becoming a fifth destination in the navigation bar.
  _Pane _pane = _Pane.todos;

  @override
  void initState() {
    super.initState();
    final DateTime now = ref.read(clockProvider)();
    _month = DateTime(now.year, now.month);
    _selectedDay = startOfDay(now);
    _anchor = DateTime(now.year, now.month);
    _pageController = PageController(initialPage: _pageRadius);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// The month a page index stands for.
  DateTime _monthForPage(int page) =>
      DateTime(_anchor.year, _anchor.month + (page - _pageRadius));

  /// The page index a month stands for.
  int _pageForMonth(DateTime month) =>
      _pageRadius + (month.year - _anchor.year) * 12 + (month.month - _anchor.month);

  /// Moves the grid to [month] — a swipe, an arrow, "today", or a date jump all
  /// end up here, so there is one definition of what changing month means.
  void _showMonth(DateTime month, {bool animate = true}) {
    final int page = _pageForMonth(month);
    if (page < 0 || page > _pageRadius * 2) {
      // Older than the grid reaches; moving the anchor would be the fix, but a
      // calendar that cannot show a month ten years out has no business
      // pretending otherwise.
      return;
    }
    if (page == _pageController.page?.round() && month == _month) {
      return;
    }
    // Applied immediately rather than when the slide lands: tapping the arrow
    // twice in quick succession has to count two months from where the user has
    // already decided to go, not from wherever the grid happens to be.
    if (month != _month) {
      _onMonthChanged(month);
    }
    if (!_pageController.hasClients) {
      return;
    }
    if (animate) {
      unawaited(
        _pageController.animateToPage(
          page,
          duration: AppMotion.effectsDefault.duration,
          curve: AppMotion.effectsDefault.curve,
        ),
      );
    } else {
      _pageController.jumpToPage(page);
    }
  }

  /// Applies the month a swipe landed on, and picks a sensible day inside it.
  void _onMonthChanged(DateTime month) {
    final DateTime now = ref.read(clockProvider)();
    final bool isCurrentMonth =
        month.year == now.year && month.month == now.month;
    setState(() {
      _month = month;
      // The day the details pane shows has to be inside the month on screen:
      // today if this is the current month, otherwise the 1st.
      _selectedDay =
          isCurrentMonth ? startOfDay(now) : DateTime(month.year, month.month, 1);
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
    setState(() => _selectedDay = startOfDay(picked));
    _showMonth(DateTime(picked.year, picked.month));
  }

  void _goToday() {
    final DateTime now = ref.read(clockProvider)();
    setState(() => _selectedDay = startOfDay(now));
    _showMonth(DateTime(now.year, now.month));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Todo>> asyncTodos = ref.watch(todoListProvider);
    final List<Todo> todos = asyncTodos.value ?? const <Todo>[];
    final List<SpecialDay> specialDays =
        ref.watch(specialDaysProvider).value ?? const <SpecialDay>[];
    // Already ordered soonest-first, and already holding the passed ones back.
    final List<SpecialDay> upcoming =
        ref.watch(upcomingSpecialDaysProvider).value ?? const <SpecialDay>[];
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
          // The weekday row never changes, so it is drawn once above the
          // swipeable grid rather than rebuilt inside every month page.
          const _WeekdayHeader(),
          const SizedBox(height: 4),
          // A page per month, so the grid can be swiped: a calendar you cannot
          // flick through is a calendar nobody uses. Fixed height, because a
          // month of five rows next to one of six would otherwise make the whole
          // page jump as the finger moves.
          SizedBox(
            height: _MonthGrid.heightForRows(_MonthGrid.maxRows),
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pageRadius * 2 + 1,
              onPageChanged: (int page) => _onMonthChanged(_monthForPage(page)),
              itemBuilder: (BuildContext context, int page) {
                final DateTime month = _monthForPage(page);
                return _MonthGrid(
                  month: month,
                  now: now,
                  counts: _DayCounts.from(todos),
                  specialDayKeys: <int>{
                    for (final SpecialDay day in specialDays)
                      if (day.repeatsYearly)
                        // A yearly date marks its month and day in *every* month
                        // view, which is the point of entering it once.
                        day.monthDayKey
                      else
                        dayKey(day.date),
                  },
                  yearlySpecialDayKeys: <int>{
                    for (final SpecialDay day in specialDays)
                      if (day.repeatsYearly) day.monthDayKey,
                  },
                  selectedDay: _selectedDay,
                  onDaySelected: (DateTime day) =>
                      setState(() => _selectedDay = day),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _buildPaneSwitch(context),
          const SizedBox(height: 8),
          if (_pane == _Pane.todos) _buildSearchField(context),
          Expanded(
            child: switch (_pane) {
              _Pane.todos => _query.isEmpty
                  ? _DayDetails(
                      day: _selectedDay,
                      todos: todos,
                      specialDays: _specialDaysOn(_selectedDay, specialDays),
                      notes: ref
                              .watch(notesOnDayProvider(dayKey(_selectedDay)))
                              .value ??
                          const <Note>[],
                      onWriteNote: () => unawaited(
                        showNoteSheet(context, date: _selectedDay),
                      ),
                      onOpenNote: (Note note) => unawaited(
                        showNoteSheet(context, existing: note, date: note.date),
                      ),
                      now: now,
                    )
                  : _SearchResults(
                      todos: todos,
                      query: _query,
                      today: now,
                      onJumpToDate: _jumpTo,
                    ),
              _Pane.specialDays => _SpecialDayList(
                  days: upcoming,
                  now: now,
                  selectedDay: _selectedDay,
                  onAdd: () => unawaited(showSpecialDaySheet(context)),
                  onEdit: (SpecialDay day) =>
                      unawaited(showSpecialDaySheet(context, existing: day)),
                ),
            },
          ),
        ],
      ),
    );
  }

  /// The personal dates that fall on [day].
  ///
  /// A yearly date matches on month and day whatever the year; a countdown only
  /// on its exact date.
  static List<SpecialDay> _specialDaysOn(
    DateTime day,
    List<SpecialDay> days,
  ) {
    final int key = dayKey(day);
    final int monthDay = day.month * 100 + day.day;
    return <SpecialDay>[
      for (final SpecialDay entry in days)
        if (entry.repeatsYearly
            ? entry.monthDayKey == monthDay
            : dayKey(entry.date) == key)
          entry,
    ];
  }

  Widget _buildPaneSwitch(BuildContext context) {
    return SegmentedButton<_Pane>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<_Pane>>[
        ButtonSegment<_Pane>(
          value: _Pane.todos,
          label: Text(AppStrings.calendarPaneTodos),
          icon: Icon(Icons.checklist),
        ),
        ButtonSegment<_Pane>(
          value: _Pane.specialDays,
          label: Text(AppStrings.specialDaySection),
          icon: Icon(Icons.cake_outlined),
        ),
      ],
      selected: <_Pane>{_pane},
      onSelectionChanged: (Set<_Pane> selection) =>
          setState(() => _pane = selection.first),
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
          onPressed: () => _showMonth(DateTime(_month.year, _month.month - 1)),
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
          onPressed: () => _showMonth(DateTime(_month.year, _month.month + 1)),
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
    required this.hasSpecialDay,
  });

  final DateTime day;
  final int dayNumber;
  final bool selected;
  final bool isToday;
  final int dueCount;
  final int doneCount;

  /// Whether a birthday, anniversary or countdown lands on this day — in this
  /// year's view *or*, for a recurring date, in any year's.
  final bool hasSpecialDay;
}

/// The `一二三四五六日` row above the grid, which never changes.
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const List<String> _weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        for (final String weekday in _weekdays)
          Expanded(
            child: Center(
              child: Text(
                weekday,
                style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.now,
    required this.counts,
    required this.specialDayKeys,
    required this.yearlySpecialDayKeys,
    required this.selectedDay,
    required this.onDaySelected,
  });

  /// Reused for every blank cell, so a month that starts mid-week does not
  /// allocate a fresh widget for each leading gap.
  static const Widget _blank = SizedBox(height: _cellHeight);

  static const double _cellHeight = 44;

  /// One cell plus the one-pixel inset that separates it from its neighbours —
  /// the row height the grid actually occupies.
  static const double _rowHeight = _cellHeight + 2;

  /// The most rows a month can need (a 31-day month starting on a Sunday in a
  /// Monday-first grid).
  static const int maxRows = 6;

  /// The height [rows] rows of cells take.
  ///&#10;  /// The weekday header is drawn once above the swiping grid rather than inside
  /// every page: it never changes, and leaving it out keeps this height a pure
  /// multiple of the cell height instead of something that shifts with the text
  /// scale.
  static double heightForRows(int rows) => _rowHeight * rows;

  final DateTime month;
  final DateTime now;
  final _DayCounts counts;

  /// Day keys (`year*10000+month*100+day`) carrying a personal date.
  final Set<int> specialDayKeys;

  /// `month*100+day` keys of the recurring personal dates, matched in any year.
  final Set<int> yearlySpecialDayKeys;

  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final List<_Cell?> cells = _resolveCells();
    final int rows = cells.length ~/ 7;

    return Column(
      children: <Widget>[
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
        hasSpecialDay:
            specialDayKeys.contains(key) ||
            yearlySpecialDayKeys.contains(day.month * 100 + day.day),
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
                    // A birthday or anniversary gets its own mark, in the colour
                    // nothing else on the grid uses: it is not a task, and it
                    // should not read as one.
                    if (cell.hasSpecialDay) ...<Widget>[
                      const SizedBox(width: 3),
                      _dot(colors.tertiary, selected),
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
  const _DayDetails({
    required this.day,
    required this.todos,
    required this.specialDays,
    required this.notes,
    required this.onWriteNote,
    required this.onOpenNote,
    required this.now,
  });

  final DateTime day;
  final List<Todo> todos;

  /// Birthdays and the like falling on this day, so tapping the 3rd of October
  /// shows the birthday as well as the tasks.
  final List<SpecialDay> specialDays;

  /// What was written on this day. A note belongs to a day, so the calendar is
  /// where it is found again — that is the whole filing system.
  final List<Note> notes;

  final VoidCallback onWriteNote;
  final ValueChanged<Note> onOpenNote;

  final DateTime now;

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

    if (due.isEmpty && completed.isEmpty && specialDays.isEmpty && notes.isEmpty) {
      // Scrollable: on a short window the pane can be shorter than this column,
      // and a placeholder that overflows is worse than one that scrolls.
      return SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                AppStrings.calendarNoTodos,
                style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onWriteNote,
                icon: const Icon(Icons.edit_note),
                label: const Text(AppStrings.noteAdd),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: <Widget>[
        ..._noteSection(context),
        if (specialDays.isNotEmpty) ...<Widget>[
          _legend(context, Icons.cake_outlined, AppStrings.specialDaySection),
          for (final SpecialDay special in specialDays)
            _SpecialDayRow(day: special, now: now, onTap: null),
        ],
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

  /// The day's notes as tappable tags, with the way to add one.
  List<Widget> _noteSection(BuildContext context) {
    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: _legend(context, Icons.edit_note, AppStrings.noteSection)),
          TextButton.icon(
            onPressed: onWriteNote,
            icon: const Icon(Icons.add, size: 18),
            label: const Text(AppStrings.noteAdd),
          ),
        ],
      ),
      if (notes.isEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 22, bottom: 4),
          child: Text(
            AppStrings.noteNone,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Note note in notes)
              ActionChip(
                avatar: Icon(
                  note.hasAttachments ? Icons.attach_file : Icons.notes,
                  size: 16,
                ),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    note.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: () => onOpenNote(note),
              ),
          ],
        ),
      const SizedBox(height: 4),
    ];
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

/// The birthdays, anniversaries and countdowns, soonest first.
class _SpecialDayList extends StatelessWidget {
  const _SpecialDayList({
    required this.days,
    required this.now,
    required this.selectedDay,
    required this.onAdd,
    required this.onEdit,
  });

  final List<SpecialDay> days;
  final DateTime now;
  final DateTime selectedDay;
  final VoidCallback onAdd;
  final ValueChanged<SpecialDay> onEdit;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    if (days.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                AppStrings.specialDayEmpty,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.specialDayAdd),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                AppStrings.specialDaySection,
                style: text.titleSmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text(AppStrings.specialDayAdd),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            children: <Widget>[
              for (final SpecialDay day in days)
                _SpecialDayRow(
                  day: day,
                  now: now,
                  onTap: () => onEdit(day),
                  highlight: day.repeatsYearly
                      ? day.monthDayKey == selectedDay.month * 100 + selectedDay.day
                      : isSameDay(day.date, selectedDay),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One personal date: what it is, when it next comes round, and how far off.
class _SpecialDayRow extends StatelessWidget {
  const _SpecialDayRow({
    required this.day,
    required this.now,
    required this.onTap,
    this.highlight = false,
  });

  final SpecialDay day;
  final DateTime now;
  final VoidCallback? onTap;

  /// Whether this row is on the day currently selected in the grid.
  final bool highlight;

  static IconData _iconFor(SpecialDayKind kind) => switch (kind) {
        SpecialDayKind.birthday => Icons.cake_outlined,
        SpecialDayKind.anniversary => Icons.favorite_border,
        SpecialDayKind.countdown => Icons.hourglass_bottom,
      };

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int days = day.daysUntil(now);
    final int? ordinal = day.ordinal(now);

    final String countdown = switch (days) {
      0 => AppStrings.specialDayToday,
      > 0 => AppStrings.specialDayInDays(days),
      // Only a one-off countdown can be behind: a yearly date always rolls
      // forward to its next occurrence.
      _ => AppStrings.specialDayPassedDays(-days),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.radius(AppShapes.small),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: highlight ? colors.tertiaryContainer : null,
            borderRadius: AppShapes.radius(AppShapes.small),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                _iconFor(day.kind),
                size: 18,
                color: highlight ? colors.onTertiaryContainer : colors.tertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      day.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        color: highlight ? colors.onTertiaryContainer : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        AppDateFormatter.calendarDate(
                          day.repeatsYearly ? day.nextOccurrence(now) : day.date,
                          now,
                        ),
                        if (ordinal != null)
                          day.kind == SpecialDayKind.birthday
                              ? AppStrings.specialDayAge(ordinal)
                              : AppStrings.specialDayYears(ordinal),
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(
                        color: highlight
                            ? colors.onTertiaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                countdown,
                style: text.labelLarge?.copyWith(
                  color: highlight ? colors.onTertiaryContainer : colors.primary,
                ),
              ),
            ],
          ),
        ),
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
