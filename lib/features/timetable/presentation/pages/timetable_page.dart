import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/presentation/settings_controller.dart';
import '../../../../app/app_background.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../../../core/utils/calendar.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/period_time.dart';
import '../../domain/entities/term.dart';
import '../../domain/entities/timetable.dart';
import '../../../../core/platform/app_platform.dart';
import '../course_widget_sync.dart';
import '../providers/timetable_providers.dart';
import '../widgets/course_detail_sheet.dart';
import '../widgets/course_editor_sheet.dart';
import '../widgets/course_list_page.dart';
import '../widgets/course_new_menu.dart';
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

  /// Puts a course tile on the home screen.
  ///
  /// Whether one now exists is decided by the launcher, outside this app, and the
  /// realme build used to develop this one both accepts and drops such a request
  /// — so the answer is read back rather than assumed, and the user is told how
  /// to add it by hand when the request went nowhere.
  Future<void> _addWidget(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool requested = await AppPlatform.requestCourseWidgetPin();
    if (!requested) {
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.habitWidgetUnsupported)),
      );
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await ref.read(courseWidgetSyncProvider).sync();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ref.read(courseWidgetPlacedProvider)
              ? AppStrings.courseWidgetOnDesktop
              : AppStrings.courseWidgetManualHint,
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Timetable> asyncTimetable = ref.watch(timetableProvider);
    final DateTime now = ref.watch(clockProvider)();
    final AppSettings settings = ref.watch(settingsProvider);

    // The timetable's own background, painted the way the app's is: this page is
    // pushed over the shell, so without this it would hide whatever the user
    // chose for the app behind an opaque surface of its own.
    return AppBackground(
      imagePath: settings.timetableBackgroundImage,
      dim: settings.timetableBackgroundDim,
      child: Scaffold(
        backgroundColor: settings.timetableBackgroundImage == null
            ? null
            : Colors.transparent,
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
          IconButton(
            icon: Icon(
              ref.watch(courseWidgetPlacedProvider)
                  ? Icons.widgets
                  : Icons.add_to_home_screen,
            ),
            tooltip: AppStrings.courseWidgetAdd,
            onPressed: () => unawaited(_addWidget(context, ref)),
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
          // The three ways in — one course, a picture of the whole term, or
          // filling the grid by hand — are one decision, so they are asked as
          // one. A tap on an empty cell still goes straight to the editor: the
          // cell already answered "when".
          onPressed: () => unawaited(showCourseNewMenu(context)),
          icon: const Icon(Icons.add),
          label: const Text(AppStrings.courseNew),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.timetable, required this.now});

  final Timetable timetable;
  final DateTime now;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  /// The empty cell the user has pointed at, waiting for its plus to be tapped.
  ///
  /// One cell at a time, and it is a *choice* rather than an action: the phone's
  /// own timetable answers a tap on an empty cell with a plus to press, and the
  /// difference matters — a timetable is mostly empty, and a grid where every
  /// stray tap opens a form is a grid you cannot touch to look at.
  int? _armedWeekday;
  int? _armedPeriod;

  /// Where the finger went down, when, and how far sideways it has been.
  Offset? _dragFrom;
  Duration? _dragStartedAt;
  double _dragFurthest = 0;

  /// The week the last frame was built for, and which way it moved.
  int? _lastWeek;
  double _slideFrom = 1;

  void _arm(int weekday, int period) {
    // A tick under the thumb. The plus appearing is the visual answer, but it
    // appears in the middle of a grid of small cells — the tick is what says the
    // tap landed on the one the user meant.
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      if (_armedWeekday == weekday && _armedPeriod == period) {
        _armedWeekday = null;
        _armedPeriod = null;
        return;
      }
      _armedWeekday = weekday;
      _armedPeriod = period;
    });
  }

  /// Moves the week, with the tick that says it moved.
  void _stepWeek(int delta, int currentWeek) {
    unawaited(HapticFeedback.selectionClick());
    ref.read(selectedWeekProvider.notifier).step(delta, currentWeek);
  }

  void _disarm() {
    if (_armedWeekday == null) {
      return;
    }
    setState(() {
      _armedWeekday = null;
      _armedPeriod = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Timetable timetable = widget.timetable;
    final DateTime now = widget.now;
    final Term term = timetable.term;
    final int week = ref.watch(shownWeekProvider);
    final int currentWeek = ref.watch(currentWeekProvider);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    // Which way the week moved, so the new one slides in from the side it came
    // from — forwards from the right, backwards from the left. Read during the
    // build rather than set in a listener: it is a fact about the frame being
    // built, not a state change of its own, and setting state here would be a
    // rebuild inside a rebuild.
    if (_lastWeek != week) {
      _slideFrom = _lastWeek == null || week > _lastWeek! ? 1.0 : -1.0;
      _lastWeek = week;
    }

    return Column(
      children: <Widget>[
        _WeekHeader(
          term: term,
          week: week,
          currentWeek: currentWeek,
          onWeek: (int delta) => _stepWeek(delta, currentWeek),
          onThisWeek: () => ref.read(selectedWeekProvider.notifier).show(null),
        ),
        _DayHeader(term: term, week: week, now: now),
        // The grid is drawn whether or not there is anything in it: an empty
        // timetable is a grid with nothing in it, and that is exactly the thing
        // you fill in by tapping a cell. A full-screen "no courses" placeholder
        // would take away the only way to add the first one.
        if (timetable.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text(
              AppStrings.timetableNoCoursesBody,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        Expanded(
          // Two layers, and each earns its place. The `Listener` sees raw
          // pointer movement rather than competing for it: the grid is full of
          // things that want a tap (every cell, every course), and a drag
          // recognizer in the same arena as all of them is a drag that sometimes
          // loses to a tap the user never meant. Movement is not claimed here —
          // it is only *watched* — so a scroll, a tap and this all still work.
          child: Listener(
            onPointerDown: (PointerDownEvent event) {
              _dragFrom = event.position;
              _dragStartedAt = event.timeStamp;
              _dragFurthest = 0;
            },
            onPointerMove: (PointerMoveEvent event) {
              final Offset from = _dragFrom ?? event.position;
              final Offset delta = event.position - from;
              // Mostly sideways, or it is a scroll being watched, not a swipe.
              if (delta.dx.abs() > delta.dy.abs() * 1.5) {
                _dragFurthest = delta.dx;
              }
            },
            onPointerUp: (PointerUpEvent event) {
              final double travelled = _dragFurthest;
              final Duration elapsed =
                  event.timeStamp - (_dragStartedAt ?? Duration.zero);
              _dragFrom = null;
              _dragStartedAt = null;
              _dragFurthest = 0;

              final bool dragged = travelled.abs() >= 48;
              // A short, fast flick counts too: a thumb does not always travel
              // half a screen to mean "next week".
              final double speed = elapsed.inMicroseconds == 0
                  ? 0
                  : travelled / (elapsed.inMicroseconds / 1e6);
              final bool flicked = travelled.abs() >= 20 && speed.abs() >= 320;
              if (!dragged && !flicked) {
                return;
              }
              _disarm();
              _stepWeek(travelled < 0 ? 1 : -1, currentWeek);
            },
            child: GestureDetector(
              // A tap that lands between the cells — on a rule, or on the padding
              // around the grid — puts the plus away, which is how a thing that
              // appeared is expected to disappear.
              behavior: HitTestBehavior.deferToChild,
              onTap: _disarm,
              // The new week slides in over the old one, and the old one waits
              // underneath until it is covered.
              //
              // Three attempts, and the reason each was dropped is the whole
              // design: fading both grids needed an offscreen layer per frame
              // (p99 23ms, over the 16.7ms a frame has); sliding both, with the
              // outgoing one still painted at full opacity, left the two weeks
              // legible on top of each other — 重影, which is worse than a slow
              // frame; and this covers, so at every instant the screen shows one
              // week's text in one place, moving.
              child: _WeekSlide(
                week: week,
                slideFrom: _slideFrom,
                builder: (int shown) => _grid(
                  context,
                  term: term,
                  timetable: timetable,
                  now: now,
                  week: shown,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One week of the grid.
  ///
  /// A function of the week rather than a widget built once, because the slide
  /// needs two of them at a time and the two have to keep their places in the
  /// tree: a grid that is *moved* from one slot to another loses its element —
  /// and its scroll position, and everything under it — and is rebuilt from
  /// scratch, which is exactly the cost that made the first frame of a switch
  /// the slowest one.
  Widget _grid(
    BuildContext context, {
    required Term term,
    required Timetable timetable,
    required DateTime now,
    required int week,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 96),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PeriodColumn(periods: term.periods),
          // Two columns or seven, from the term's own answer: a timetable
          // with no Saturday classes is not improved by two empty ones.
          for (final int weekday in term.shownWeekdays)
            Expanded(
              child: _DayColumn(
                term: term,
                week: week,
                weekday: weekday,
                meetings: timetable.meetingsOnDay(week, weekday),
                otherWeeks: term.showOtherWeeks
                    ? timetable.meetingsOnDayInOtherWeeks(week, weekday)
                    : const <CourseMeeting>[],
                isToday: _isToday(term, week, weekday, now),
                armedPeriod: _armedWeekday == weekday ? _armedPeriod : null,
                onCellTap: (int period) => _arm(weekday, period),
                onAddHere: (int period) {
                  _disarm();
                  unawaited(
                    showCourseEditorSheet(
                      context,
                      weekday: weekday,
                      period: period,
                    ),
                  );
                },
                onCourseTap: (Course course) {
                  _disarm();
                  unawaited(
                    showCourseDetailSheet(
                      context,
                      course: course,
                      term: term,
                    ),
                  );
                },
                      ),
                    ),
                ],
              ),
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
          //
          // One line, always: the label grows a "回到本周" once the week being
          // shown is not this one, and on a narrow phone that wrapped — which
          // moved the whole grid down sixteen pixels the moment the week changed,
          // on top of the slide. A header that changes height is a header that
          // makes a smooth transition look broken.
          Flexible(
            child: TextButton(
              onPressed: week == currentWeek ? null : onThisWeek,
              child: Text(
                week == currentWeek
                    ? AppStrings.timetableWeek(week)
                    : '${AppStrings.timetableWeek(week)} · ${AppStrings.timetableThisWeek}',
                style: text.labelLarge,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
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
          for (final int weekday in term.shownWeekdays)
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
              // Three lines of text in a fixed-height cell: at a large font
              // scale they need more room than the row has, and a timetable that
              // draws yellow and black stripes because somebody turned the system
              // font up is worse than one whose clock times are a little smaller.
              // Scaling down only when it does not fit keeps the usual case
              // exactly as it is.
              child: FittedBox(
                fit: BoxFit.scaleDown,
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
    required this.otherWeeks,
    required this.isToday,
    required this.armedPeriod,
    required this.onCellTap,
    required this.onAddHere,
    required this.onCourseTap,
  });

  final Term term;
  final int week;
  final int weekday;
  final List<CourseMeeting> meetings;

  /// The courses that meet on this day in weeks other than this one. Empty
  /// unless the term asked for them.
  final List<CourseMeeting> otherWeeks;

  final bool isToday;

  /// The period of this day whose plus is showing, if any.
  final int? armedPeriod;

  final ValueChanged<int> onCellTap;
  final ValueChanged<int> onAddHere;
  final ValueChanged<Course> onCourseTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {    final ColorScheme colors = Theme.of(context).colorScheme;
    final int rows = term.periods.length;
    final Timetable? timetable = ref.watch(timetableProvider).value;

    // A course of another week is only drawn where this week has nothing: the
    // grid is about the week being shown, and a faint block underneath a real
    // one would be a second thing drawn in the same place.
    final int firstPeriod = meetings.isEmpty
        ? rows + 1
        : meetings.first.slot.startPeriod;
    final int lastPeriod = meetings.isEmpty
        ? 0
        : meetings
            .map((CourseMeeting meeting) => meeting.slot.endPeriod)
            .reduce((int a, int b) => a > b ? a : b);
    final List<CourseMeeting> ghostMeetings = <CourseMeeting>[
      for (final CourseMeeting meeting in otherWeeks)
        if (meeting.slot.endPeriod < firstPeriod ||
            meeting.slot.startPeriod > lastPeriod)
          meeting,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SizedBox(
        height: TimetablePage.rowHeight * rows,
        child: Stack(
          children: <Widget>[
            // The day's ruled lines: every period is a row whether or not
            // something is in it, which is what makes the grid readable — and
            // every empty cell is also a way to put something in it. Tapping a
            // cell opens the editor with that day and period already filled in,
            // because a timetable is filled in *at* a place on the grid rather
            // than by describing one in a form.
            Column(
              children: <Widget>[
                for (int index = 0; index < rows; index++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onCellTap(index + 1),
                    child: Container(
                      height: TimetablePage.rowHeight,
                      decoration: BoxDecoration(
                        color: isToday
                            ? colors.primary.withValues(alpha: 0.04)
                            : null,
                        border: Border(
                          top:
                              BorderSide(color: colors.outlineVariant, width: 0.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // The plus, on the cell that was pointed at: an empty cell answers a
            // tap with a way to fill it rather than with the form itself.
            if (armedPeriod != null && armedPeriod! >= 1 && armedPeriod! <= rows)
              Positioned(
                top: (armedPeriod! - 1) * TimetablePage.rowHeight,
                left: 0,
                right: 0,
                height: TimetablePage.rowHeight,
                child: Center(
                  child: _AddHereButton(
                    onPressed: () => onAddHere(armedPeriod!),
                  ),
                ),
              ),
            // The courses of other weeks first, so that a real one of this week
            // is drawn over them rather than under.
            for (final CourseMeeting meeting in ghostMeetings)
              Positioned(
                top: (meeting.slot.startPeriod - 1) * TimetablePage.rowHeight + 2,
                left: 0,
                right: 0,
                height: meeting.slot.periodCount * TimetablePage.rowHeight - 4,
                child: _CourseBlock(
                  meeting: meeting,
                  term: term,
                  accent: _accentOf(timetable, meeting.course, colors),
                  ghost: true,
                  onTap: () => onCourseTap(meeting.course),
                ),
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
                  onTap: () => onCourseTap(meeting.course),
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

/// The plus that answers a tap on an empty cell.
///
/// Small and round and in the middle of the cell it belongs to, so that which
/// cell is about to be filled in is not in question.
class _AddHereButton extends StatelessWidget {
  const _AddHereButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.primary,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: AppStrings.courseAddHere,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.add, size: 20, color: colors.onPrimary),
          ),
        ),
      ),
    );
  }
}

/// The whole week sliding out while the next one slides in.
///
/// Two earlier attempts, and what was wrong with each is the design: fading the
/// pair needed an offscreen layer per frame and dropped frames; sliding only the
/// *arriving* week over a stationary one left the two legible on top of each
/// other — 虚影, a ghost of the week underneath, which is what a half-covered page
/// looks like.
///
/// So both move, a screen apart and never overlapping: one week leaves the way a
/// page does, the other follows it in. What the user sees is a single surface
/// being pushed sideways, which is what "整体滑动" means.
class _WeekSlide extends StatefulWidget {
  const _WeekSlide({
    required this.week,
    required this.slideFrom,
    required this.builder,
  });

  /// Which week is arriving; a change is what starts the slide.
  final int week;

  /// `1` when the week moved forwards, `-1` when it moved back, which is the
  /// side the new grid comes in from.
  final double slideFrom;

  /// Draws one week of the grid, by week number.
  ///
  /// A builder rather than a widget, so that *both* weeks — the one arriving and
  /// the one being covered — are built in their own slots of the same stack, in
  /// the same order, every time. Handing over a widget instance instead means
  /// moving it from one slot to another, which throws its element away: the whole
  /// grid is then rebuilt from scratch on the first frame of every switch, which
  /// is precisely the frame that was slowest.
  final Widget Function(int week) builder;

  @override
  State<_WeekSlide> createState() => _WeekSlideState();
}

class _WeekSlideState extends State<_WeekSlide>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 200);

  /// Starts *finished*: the first frame is a week in its place, not a week
  /// parked off the side waiting for an animation that only a change starts.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: 1,
  )..addStatusListener((AnimationStatus status) {
      // Covered: nothing left to hold on to.
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _under = null);
      }
    });

  /// Built once rather than per frame: a `CurvedAnimation` made inside `build`
  /// attaches a listener to the controller every time, and this one is built
  /// sixty times over the course of a slide.
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  /// The week being left behind, kept only for as long as the slide lasts.
  int? _under;

  /// Where the arriving week starts, and where the leaving one ends: a whole
  /// screen apart, and they travel together.
  Animation<Offset>? _arrival;
  Animation<Offset>? _departure;
  double? _positionFrom;

  void _positionsFor(double from) {
    if (_positionFrom == from && _arrival != null) {
      return;
    }
    _positionFrom = from;
    _arrival = Tween<Offset>(
      begin: Offset(from, 0),
      end: Offset.zero,
    ).animate(_curve);
    // The mirror of it, so the two move as one surface: what the arriving week
    // travels, the leaving week travels the other way, and they never overlap.
    _departure = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-from, 0),
    ).animate(_curve);
  }

  @override
  void didUpdateWidget(_WeekSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.week == widget.week) {
      return;
    }
    _under = oldWidget.week;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int? under = _under;
    _positionsFor(widget.slideFrom);

    // Clipped, because a page on its way in or out is off-screen at the start and
    // must not paint over the header above it, or past the edge of the grid.
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Always the first slot, whether or not it has anything in it: the two
          // slots keep their places in the tree so that neither week is ever
          // rebuilt because it moved.
          //
          // The leaving week is untouchable: it is on its way out, and a tap
          // aimed at what has arrived must not land on what is leaving.
          IgnorePointer(
            child: under == null
                ? const SizedBox.shrink()
                : SlideTransition(
                    position: _departure!,
                    child: RepaintBoundary(child: widget.builder(under)),
                  ),
          ),
          SlideTransition(
            position: _arrival!,
            child: RepaintBoundary(child: widget.builder(widget.week)),
          ),
        ],
      ),
    );
  }
}

/// One course as it appears on the grid: its name, and where it is.
class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    required this.meeting,
    required this.term,
    required this.accent,
    required this.onTap,
    this.ghost = false,
  });

  final CourseMeeting meeting;
  final Term term;
  final Color accent;
  final VoidCallback onTap;

  /// Whether this is a course of another week: drawn, but not as this week's.
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool dense = meeting.slot.periodCount == 1;
    final String? time = meeting.timeLabel(term);
    final String? picture = meeting.course.backgroundImage;

    final Widget label = Padding(
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
    );

    // A course with a picture of its own is a small window onto it, so the
    // block draws the picture rather than the colour — but through the same
    // scrim the app's own background uses, because this is the smallest text in
    // the app and it sits on top of an arbitrary photo.
    // A course of another week is drawn as an outline: enough to answer "when
    // does this ever happen", not enough to be mistaken for something to go to
    // this week. The colour stays, because the colour is how a course is
    // recognised.
    final Widget body = picture == null
        ? Material(
            color: ghost
                ? Colors.transparent
                : accent.withValues(alpha: 0.22),
            borderRadius: AppShapes.radius(AppShapes.small),
            child: InkWell(
              onTap: onTap,
              borderRadius: AppShapes.radius(AppShapes.small),
              child: ghost ? _ghosted(label, accent) : label,
            ),
          )
        : ClipRRect(
            borderRadius: AppShapes.radius(AppShapes.small),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return AppBackground(
                  imagePath: picture,
                  dim: meeting.course.backgroundDim,
                  cacheWidth:
                      (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: onTap, child: label),
                  ),
                );
              },
            ),
          );

    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        body,
        // The colour stays on as a hairline: a picture is what the user chose
        // to see, but the outline is what keeps two adjacent courses apart.
        if (picture != null || ghost)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppShapes.radius(AppShapes.small),
                  border: Border.all(
                    color: accent.withValues(alpha: ghost ? 0.6 : 0.5),
                    // Dashed would say it better than thin, and a dashed border
                    // is not something a BoxDecoration can draw.
                    width: ghost ? 1.4 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The label of a course that does not run this week, in its own colour but
  /// washed out towards the surface.
  Widget _ghosted(Widget label, Color accent) {
    return Opacity(opacity: 0.55, child: label);
  }
}
