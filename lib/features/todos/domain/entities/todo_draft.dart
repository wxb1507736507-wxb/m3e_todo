import 'todo_attachment.dart';
import 'todo_priority.dart';
import 'todo_reminder.dart';
import 'todo_subtask.dart';

/// Raw, not-yet-validated input coming from the editor form.
///
/// Kept separate from `Todo` because a draft is what the user has typed so far
/// and may still be invalid. Turning a draft into a `Todo` is where the domain
/// applies its rules, so a draft never has to satisfy them.
class TodoDraft {
  const TodoDraft({
    required this.title,
    this.notes,
    this.priority = TodoPriority.normal,
    this.dueDate,
    this.subtasks = const <TodoSubtask>[],
    this.attachments = const <TodoAttachment>[],
    this.accentColor,
    this.textColor,
    this.backgroundImage,
    this.reminder = TodoReminder.followApp,
    this.ringtoneUri,
  });

  final String title;
  final String? notes;
  final TodoPriority priority;
  final DateTime? dueDate;

  /// Checklist steps as assembled by the editor; blank rows are dropped by the
  /// domain when the draft is applied.
  final List<TodoSubtask> subtasks;

  /// Files the editor picked; the files themselves are already copied into the
  /// app's attachments directory by the time a draft is submitted.
  final List<TodoAttachment> attachments;

  /// ARGB32 tile colour, or `null` to follow the theme.
  final int? accentColor;

  /// ARGB32 text colour, or `null` to follow the theme.
  final int? textColor;

  /// Absolute path of the tile background image, or `null` for none.
  final String? backgroundImage;

  /// Whether the reminder rings or stays quiet. Defaults to following the app's
  /// reminder setting.
  final TodoReminder reminder;

  /// This todo's own ringtone URI, or `null` to use the app-wide one.
  final String? ringtoneUri;

  @override
  String toString() => 'TodoDraft("$title", $priority, due: $dueDate, '
      '${subtasks.length} subtasks, ${attachments.length} attachments)';
}
