import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../domain/entities/note.dart';

/// One note as a list row: what it says, and when it was written.
///
/// Shared by the folder screen and anywhere else notes are browsed rather than
/// pinned to a day, so a note looks the same wherever it is found.
class NoteRow extends StatelessWidget {
  const NoteRow({
    required this.note,
    required this.now,
    required this.onTap,
    this.showDate = true,
    super.key,
  });

  final Note note;
  final DateTime now;
  final VoidCallback onTap;

  /// Whether to spell out the day. A note listed under its own day does not
  /// need to repeat it; one listed inside a folder does.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.radius(AppShapes.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                note.hasAttachments ? Icons.attach_file : Icons.notes,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      note.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (showDate)
                          AppDateFormatter.calendarDate(note.date, now),
                        if (note.hasAttachments)
                          AppStrings.noteAttachmentCount(note.attachments.length),
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
