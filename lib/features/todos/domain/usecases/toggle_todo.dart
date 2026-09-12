import '../../../../core/utils/clock.dart';
import '../entities/todo.dart';
import 'todo_mutation.dart';

/// Flips the completion state of the todo with [id].
final class ToggleTodo extends TodoMutation {
  const ToggleTodo(super.repository, {required this.clock});

  /// Supplies the completion timestamp.
  final Clock clock;

  Future<List<Todo>> call(String id) {
    final DateTime moment = clock();
    return mutate(
      (List<Todo> current) => <Todo>[
        for (final Todo todo in current)
          if (todo.id == id) todo.toggledAt(moment) else todo,
      ],
    );
  }
}
