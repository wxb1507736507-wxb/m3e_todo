import '../entities/todo.dart';
import 'todo_mutation.dart';

/// Takes one folder off every todo filed under it.
///
/// The cleanup a deleted folder needs: without it, its todos would keep pointing
/// at an id nothing knows any more, and would be invisible from every view —
/// neither in the folder (gone) nor in "unfiled" (they think they are filed).
final class ClearTodoCategory extends TodoMutation {
  const ClearTodoCategory(super.repository);

  Future<List<Todo>> call(String categoryId) {
    return mutate(
      (List<Todo> current) => <Todo>[
        for (final Todo todo in current)
          if (todo.categoryId == categoryId)
            todo.edit(
              title: todo.title,
              notes: todo.notes,
              priority: todo.priority,
              dueDate: todo.dueDate,
              subtasks: todo.subtasks,
              attachments: todo.attachments,
              accentColor: todo.accentColor,
              textColor: todo.textColor,
              backgroundImage: todo.backgroundImage,
              reminder: todo.reminder,
              ringtoneUri: todo.ringtoneUri,
              reminderLead: todo.reminderLead,
              categoryId: null,
            )
          else
            todo,
      ],
    );
  }
}
