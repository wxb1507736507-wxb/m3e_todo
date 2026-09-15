import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import 'course_editor_sheet.dart';
import 'course_import_sheet.dart';
import 'term_sheet.dart';

/// The three ways into a timetable, as the phone's own app offers them.
///
/// They are not variations on one another: a single course is a few taps and
/// answers "I have one more class", importing a picture answers "the whole term
/// arrived at once", and filling the grid answers "I want to type it in
/// myself". The sheet exists so that the choice is made once, deliberately,
/// rather than by which button the user happened to press.
Future<void> showCourseNewMenu(
  BuildContext context, {
  int? weekday,
  int? period,
}) async {
  // A tap on an empty cell already answered "when", so that path goes straight
  // to the editor: asking again which of the three ways the user wants, when
  // they have just pointed at a time, would be asking them to say it twice.
  if (weekday != null || period != null) {
    await showCourseEditorSheet(context, weekday: weekday, period: period);
    return;
  }

  final _CourseNewChoice? choice = await showModalBottomSheet<_CourseNewChoice>(
    context: context,
    builder: (BuildContext sheetContext) => const _CourseNewMenu(),
  );
  if (choice == null || !context.mounted) {
    return;
  }
  switch (choice) {
    case _CourseNewChoice.single:
      await showCourseEditorSheet(context);
    case _CourseNewChoice.photo:
      await showCourseImportSheet(context);
    case _CourseNewChoice.manual:
      await showTermSheet(context);
  }
}

enum _CourseNewChoice { single, photo, manual }

class _CourseNewMenu extends StatelessWidget {
  const _CourseNewMenu();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(
              AppStrings.courseNew,
              style: text.titleLarge,
            ),
          ),
          _Option(
            icon: Icons.edit_calendar_outlined,
            title: AppStrings.courseNewSingle,
            subtitle: AppStrings.courseNewSingleHint,
            onTap: () => Navigator.of(context).pop(_CourseNewChoice.single),
          ),
          _Option(
            icon: Icons.document_scanner_outlined,
            title: AppStrings.courseNewPhoto,
            subtitle: AppStrings.courseNewPhotoHint,
            onTap: () => Navigator.of(context).pop(_CourseNewChoice.photo),
          ),
          _Option(
            icon: Icons.grid_on_outlined,
            title: AppStrings.courseNewManual,
            subtitle: AppStrings.courseNewManualHint,
            onTap: () => Navigator.of(context).pop(_CourseNewChoice.manual),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
