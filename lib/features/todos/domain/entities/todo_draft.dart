import 'todo_priority.dart';

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
  });

  final String title;
  final String? notes;
  final TodoPriority priority;
  final DateTime? dueDate;

  @override
  String toString() => 'TodoDraft("$title", $priority, due: $dueDate)';
}
