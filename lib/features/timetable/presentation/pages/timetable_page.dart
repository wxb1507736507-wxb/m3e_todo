import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../../../core/utils/calendar.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/period_time.dart';
import '../../domain/entities/term.dart';
import '../../domain/entities/timetable.dart';
import '../providers/timetable_providers.dart';
import '../widgets/course_editor_sheet.dart';
import '../widgets/course_list_page.dart';
import '../widgets/term_sheet.dart';

/// The week grid: seven days across, the day's periods down.
///
/// The shape follows the timetable this one imitates — a period column with its
/// clock times on the left, the week's dates over the columns, a course drawn as
/// a block that covers the periods it runs — because that is the shape a
/// timetable is read in: down a column to see a day, across a row to see what
/// clashes with what.
class TimetablePage extends ConsumerWidget {
  const TimetablePage({super.key});

  /// Height of one period's row. A block spans as many rows as it has periods.
  static const double rowHeight = 62;

  /// Width of the period column on the left.
  static const double periodColumnWidth = 46;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Timetable> asyncTimetable = ref.watch(timetableProvider);
    final DateTime now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.timetableTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: AppStrings.timetableCourseList,
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CourseListPage(),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.event_note_outlined),
            tooltip: AppStrings.timetableTermSettings,
            onPressed: () => unawaited(showTermSheet(context)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: asyncTimetable.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(AppStrings.loadFailedTitle),
          ),
        ),
        data: (Timetable timetable) => _Body(timetable: timetable, now: now),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(showCourseEditorSheet(context)),
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.courseNew),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.timetable, required this.now});

  final Timetable timetable;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Term term = timetable.term;
    final int week = ref.watch(shownWeekProvider);
    final int currentWeek = ref.watch(currentWeekProvider);

    return Column(
      children: <Widget>[
        _WeekHeader(
          term: term,
          week: week,
          currentWeek: currentWeek,
          onWeek: (int delta) =>
              ref.read(selectedWeekProvider.notifier).step(delta, currentWeek),
          onThisWeek: () => ref.read(selectedWeekProvider.notifier).show(null),
        ),
        _DayHeader(term: term, week: week, now: now),
        Expanded(
          child: timetable.isEmpty
              ? const _NoCourses()
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 96),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _PeriodColumn(periods: term.periods),
                      for (int weekday = 1; weekday <= 7; weekday++)
                        Expanded(
                          child: _DayColumn(
                            term: term,
                            week: week,
                            weekday: weekday,
                            meetings: timetable.meetingsOnDay(week, weekday),
                            isToday: _isToday(term, week, weekday, now),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// Whether the cell being drawn *is* today, which is what the column is tinted
  /// for: on any other week no day is today, however the weekday matches.
  bool _isToday(Term term, int week, int weekday, DateTime now) {
    final DateTime day = term.mondayOfWeek(week).add(Duration(days: weekday - 1));
    return isSameDay(day, now);
  }
}

/// The term, the week being shown, and the way to another one.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.term,
    required this.week,
    required this.currentWeek,
    required this.onWeek,
    required this.onThisWeek,
  });

  final Term term;
  final int week;
  final int currentWeek;
  final ValueChanged<int> onWeek;
  final VoidCallback onThisWeek;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(term.name, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  AppDateFormatter.weekRange(
                    term.mondayOfWeek(week),
                    term.mondayOfWeek(week).add(const Duration(days: 6)),
                  ),
                  style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onWeek(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: AppStrings.timetablePrevWeek,
          ),
          // The week is the one control a timetable is used through, so it is a
          // button as well as a label: tapping it goes back to this week.
          TextButton(
            onPressed: week == currentWeek ? null : onThisWeek,
            child: Text(
              week == currentWeek
                  ? AppStrings.timetableWeek(week)
                  : '${AppStrings.timetableWeek(week)} · ${AppStrings.timetableThisWeek}',
              style: text.labelLarge,
            ),
          ),
          IconButton(
            onPressed: () => onWeek(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: AppStrings.timetableNextWeek,
          ),
        ],
      ),
    );
  }
}

/// The week's days across the top: 一 9/14, 二 9/15, and today marked.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.term, required this.week, required this.now});

  final Term term;
  final int week;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          const SizedBox(width: TimetablePage.periodColumnWidth),
          for (int weekday = 1; weekday <= 7; weekday++)
            Expanded(
              child: Builder(
                builder: (BuildContext context) {
                  final DateTime day =
                      term.mondayOfWeek(week).add(Duration(days: weekday - 1));
                  final bool today = isSameDay(day, now);
                  return Column(
                    children: <Widget>[
                      Text(
                        kCourseWeekdayNames[weekday - 1],
                        style: text.labelMedium?.copyWith(
                          color: today ? colors.primary : colors.onSurfaceVariant,
                          fontWeight: today ? FontWeight.w700 : null,
                        ),
                      ),
                      Text(
                        '${day.month}/${day.day}',
                        style: text.labelSmall?.copyWith(
                          color: today ? colors.primary : colors.outline,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The left column: each period's number and clock times.
class _PeriodColumn extends StatelessWidget {
  const _PeriodColumn({required this.periods});

  final List<PeriodTime> periods;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return SizedBox(
      width: TimetablePage.periodColumnWidth,
      child: Column(
        children: <Widget>[
          for (final PeriodTime period in periods)
            SizedBox(
              height: TimetablePage.rowHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text('${period.index}', style: text.titleSmall),
                  Text(
                    period.startLabel,
                    style: text.labelSmall?.copyWith(color: colors.outline),
                  ),
                  Text(
                    period.endLabel,
                    style: text.labelSmall?.copyWith(color: colors.outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One day of the week: its courses as blocks, placed by the periods they cover.
class _DayColumn extends ConsumerWidget {
  const _DayColumn({
    required this.term,
    required this.week,
    required this.weekday,
    required this.meetings,
    required this.isToday,
  });

  final Term term;
  final int week;
  final int weekday;
  final List<CourseMeeting> meetings;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int rows = term.periods.length;
    final Timetable? timetable = ref.watch(timetableProvider).value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SizedBox(
        height: TimetablePage.rowHeight * rows,
        child: Stack(
          children: <Widget>[
            // The day's ruled lines: every period is a row whether or not
            // something is in it, which is what makes the grid readable.
            Column(
              children: <Widget>[
                for (int index = 0; index < rows; index++)
                  Container(
                    height: TimetablePage.rowHeight,
                    decoration: BoxDecoration(
                      color: isToday
                          ? colors.primary.withValues(alpha: 0.04)
                          : null,
                      border: Border(
                        top: BorderSide(color: colors.outlineVariant, width: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
            for (final CourseMeeting meeting in meetings)
              Positioned(
                top: (meeting.slot.startPeriod - 1) * TimetablePage.rowHeight + 2,
                left: 0,
                right: 0,
                height: meeting.slot.periodCount * TimetablePage.rowHeight - 4,
                child: _CourseBlock(
                  meeting: meeting,
                  term: term,
                  accent: _accentOf(timetable, meeting.course, colors),
                  onTap: () => unawaited(
                    showCourseEditorSheet(context, existing: meeting.course),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A course's colour: its own, or one from the palette picked by name so the
  /// same course keeps the same colour between launches.
  Color _accentOf(Timetable? timetable, Course course, ColorScheme colors) {
    if (course.color != null) {
      return Color(course.color!);
    }
    final int index = timetable?.courses.indexWhere((Course c) => c.id == course.id) ?? 0;
    final List<Color> palette = <Color>[
      colors.primary,
      colors.tertiary,
      colors.secondary,
      colors.primaryContainer,
      colors.tertiaryContainer,
    ];
    return palette[index.abs() % palette.length];
  }
}

/// One course as it appears on the grid: its name, and where it is.
class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    required this.meeting,
    required this.term,
    required this.accent,
    required this.onTap,
  });

  final CourseMeeting meeting;
  final Term term;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool dense = meeting.slot.periodCount == 1;
    final String? time = meeting.timeLabel(term);

    return Material(
      color: accent.withValues(alpha: 0.22),
      borderRadius: AppShapes.radius(AppShapes.small),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.radius(AppShapes.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                meeting.course.name,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (meeting.course.room != null)
                Text(
                  meeting.course.room!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall,
                ),
              // The clock range only fits when the block is more than one period
              // tall; on a single period it would push the name out.
              if (!dense && time != null)
                Text(time, maxLines: 1, style: text.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// The placeholder for a term with nothing in it yet.
class _NoCourses extends StatelessWidget {
  const _NoCourses();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.calendar_view_week, size: 52, color: colors.outline),
            const SizedBox(height: 14),
            Text(AppStrings.timetableNoCourses, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              AppStrings.timetableNoCoursesBody,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
