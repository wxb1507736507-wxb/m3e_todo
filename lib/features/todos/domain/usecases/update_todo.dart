import '../entities/todo.dart';
import '../entities/todo_draft.dart';
import 'todo_mutation.dart';

/// Applies an edited [draft] to the todo with [id].
///
/// Silently leaves the collection untouched when [id] matches nothing, which
/// keeps the operation idempotent for a UI that may fire twice (a fast double
/// click on Save), rather than throwing from deep inside a mutation.
final class UpdateTodo extends TodoMutation {
  const UpdateTodo(super.repository);

  Future<List<Todo>> call(String id, TodoDraft draft) {
    return mutate(
      (List<Todo> current) => <Todo>[
        for (final Todo todo in current)
          if (todo.id == id)
            todo.edit(
              title: draft.title,
              notes: draft.notes,
              priority: draft.priority,
              dueDate: draft.dueDate,
              subtasks: draft.subtasks,
              attachments: draft.attachments,
              accentColor: draft.accentColor,
              textColor: draft.textColor,
              backgroundImage: draft.backgroundImage,
              reminder: draft.reminder,
              ringtoneUri: draft.ringtoneUri,
              reminderLead: draft.reminderLead,
              categoryId: draft.categoryId,
            )
          else
            todo,
      ],
    );
  }
}
