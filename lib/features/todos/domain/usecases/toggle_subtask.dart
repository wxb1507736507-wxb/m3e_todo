import '../../../../core/utils/clock.dart';
import '../entities/todo.dart';
import 'todo_mutation.dart';

/// Flips the completion state of one checklist step of the todo with [id].
final class ToggleSubtask extends TodoMutation {
  const ToggleSubtask(super.repository, {required this.clock});

  /// Supplies the completion timestamp.
  final Clock clock;

  Future<List<Todo>> call(String todoId, String subtaskId) {
    final DateTime moment = clock();
    return mutate(
      (List<Todo> current) => <Todo>[
        for (final Todo todo in current)
          if (todo.id == todoId) todo.toggleSubtask(subtaskId, moment) else todo,
      ],
    );
  }
}
