import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/timetable.dart';
import '../providers/timetable_providers.dart';
import 'course_editor_sheet.dart';

/// Every course in the term, as a list.
///
/// The grid answers "what have I got on Tuesday"; this answers "where is that
/// course, and what weeks was it again" — the question you have when something
/// needs changing rather than when something needs attending.
class CourseListPage extends ConsumerWidget {
  const CourseListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Timetable> asyncTimetable = ref.watch(timetableProvider);
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.timetableCourseList)),
      body: asyncTimetable.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            Center(child: Text(AppStrings.loadFailedTitle)),
        data: (Timetable timetable) {
          if (timetable.isEmpty) {
            return const Center(child: Text(AppStrings.timetableNoCourses));
          }
          // Sorted by the first period they meet at, so the list reads in the
          // order the week happens rather than in the order they were typed in.
          final List<Course> courses = List<Course>.of(timetable.courses)
            ..sort((Course a, Course b) => a.firstPeriod.compareTo(b.firstPeriod));
          final List<CourseClash> clashes = ref.watch(courseClashesProvider);

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: courses.length,
            separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 6),
            itemBuilder: (BuildContext context, int index) {
              final Course course = courses[index];
              final List<CourseClash> itsClashes = <CourseClash>[
                for (final CourseClash clash in clashes)
                  if (clash.first.id == course.id || clash.second.id == course.id)
                    clash,
              ];
              return Material(
                color: colors.surfaceContainerHigh,
                borderRadius: AppShapes.radius(AppShapes.small),
                child: InkWell(
                  onTap: () => unawaited(
                    showCourseEditorSheet(context, existing: course),
                  ),
                  borderRadius: AppShapes.radius(AppShapes.small),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 6,
                          height: 42,
                          decoration: BoxDecoration(
                            color: course.color == null
                                ? colors.primary
                                : Color(course.color!),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                course.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                <String>[
                                  course.slotsLabel,
                                  if (course.room != null) course.room!,
                                ].join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                course.weeksLabel(timetable.term.totalWeeks),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              if (itsClashes.isNotEmpty)
                                Text(
                                  AppStrings.courseClash(
                                    itsClashes.first.first.id == course.id
                                        ? itsClashes.first.second.name
                                        : itsClashes.first.first.name,
                                    itsClashes.first.label,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.error),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
