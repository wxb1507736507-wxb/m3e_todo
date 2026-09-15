import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/term.dart';
import 'course_editor_sheet.dart';

/// What a course is, without opening the editor for it.
///
/// The phone's own timetable calls this 课程详情 and opens it on a tap: a tap on
/// a course is usually a question ("where is this one, and which weeks?"), and
/// answering it by opening a form full of things to change gets the answer and
/// a chance of an accident in the same gesture. The form is one button away.
Future<void> showCourseDetailSheet(
  BuildContext context, {
  required Course course,
  required Term term,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // Scroll-controlled and scrollable: a course whose name, room and note are
    // each a paragraph is a real thing — a name pasted out of a school's system
    // arrives with the whole row in it — and a sheet that cannot scroll draws
    // that paragraph over the button underneath it.
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => CourseDetailSheet(
      course: course,
      term: term,
    ),
  );
}

class CourseDetailSheet extends StatelessWidget {
  const CourseDetailSheet({
    required this.course,
    required this.term,
    super.key,
  });

  final Course course;
  final Term term;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = course.color == null
        ? colors.primary
        : Color(course.color!);

    return SafeArea(
      // Never taller than most of the screen, and never a fixed height: what is
      // inside decides, and past three quarters of the screen it scrolls.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The content scrolls; the actions below it do not.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            AppStrings.courseDetailTitle,
                            style: text.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(AppStrings.courseDetailClose),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            course.name,
                            style: text.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Row(
                      icon: Icons.location_on_outlined,
                      text: AppStrings.courseDetailRoomPrefix +
                          (course.room ?? '未填写'),
                    ),
                    _Row(
                      icon: Icons.person_outline,
                      text: AppStrings.courseDetailNotePrefix +
                          (course.note ?? '未填写'),
                    ),
                    // One line per weekly meeting, with the clock times the term
                    // gives those periods — which is what the reader came for.
                    for (final CourseSlot slot in course.slots)
                      _Row(
                        icon: Icons.schedule_outlined,
                        text: _slotLine(slot),
                      ),
                    _Row(
                      icon: Icons.date_range_outlined,
                      text: course.weeksLabel(term.totalWeeks),
                    ),
                  ],
                ),
              ),
            ),
            _actions(context),
          ],
        ),
      ),
    );
  }

  /// The action row, pinned below the scrolling content.
  ///
  /// Outside the scroll view on purpose: a button that scrolls with the text is
  /// a button that can be pushed off the sheet by a long enough course name, and
  /// 编辑 is the one thing this sheet exists to offer.
  Widget _actions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: <Widget>[
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: () {
              // The sheet closes before the editor opens, rather than staying
              // behind it: a detail sheet left open behind a form is a sheet
              // showing what the course used to be, and after saving there would
              // be two versions of the same course on screen with no way to tell
              // which is which.
              final NavigatorState navigator = Navigator.of(context);
              navigator.pop();
              unawaited(showCourseEditorSheet(context, existing: course));
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text(AppStrings.actionEdit),
          ),
        ],
      ),
    );
  }

  String _slotLine(CourseSlot slot) {
    final String? clock = term.rangeLabel(slot.startPeriod, slot.endPeriod);
    return clock == null ? slot.label : '${slot.label}（$clock）';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
