import '../../../../core/utils/clock.dart';
import '../../../../core/utils/id_generator.dart';
import '../entities/todo.dart';
import '../entities/todo_draft.dart';
import 'todo_mutation.dart';

/// Creates a todo from [draft] and returns the new collection.
///
/// New items go to the front, so a freshly captured task is immediately visible
/// in manual order &mdash; the order the list uses by default.
final class AddTodo extends TodoMutation {
  const AddTodo(
    super.repository, {
    required this.idGenerator,
    required this.clock,
  });

  /// Supplies ids for new todos; a public field because Dart forbids private
  /// named parameters, so the alternative would be an awkward manual assignment.
  final IdGenerator idGenerator;

  /// Supplies the creation timestamp.
  final Clock clock;

  Future<List<Todo>> call(TodoDraft draft) {
    return mutate((List<Todo> current) {
      final Todo todo = Todo.create(
        id: idGenerator(),
        title: draft.title,
        createdAt: clock(),
        notes: draft.notes,
        priority: draft.priority,
        dueDate: draft.dueDate,
        subtasks: draft.subtasks,
        attachments: draft.attachments,
        accentColor: draft.accentColor,
        textColor: draft.textColor,
        backgroundImage: draft.backgroundImage,
      );
      return <Todo>[todo, ...current];
    });
  }
}
