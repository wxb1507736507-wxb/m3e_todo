import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../domain/entities/todo.dart';
import '../../domain/usecases/delete_todo.dart';
import '../controllers/todo_list_controller.dart';
import '../providers/todo_providers.dart';
import 'todo_editor_sheet.dart';
import 'todo_tile.dart';

/// The scrollable list of todos.
///
/// Reordering starts with a **long press anywhere on a row**: each item is
/// wrapped in a [ReorderableDelayedDragStartListener], which is simply not
/// built when a sort rule owns the order. No visible drag handle — the whole
/// row is the affordance, which is also what a thumb expects on a phone.
class TodoListView extends ConsumerWidget {
  const TodoListView({
    required this.todos,
    required this.now,
    required this.allowReorder,
    super.key,
  });

  final List<Todo> todos;
  final DateTime now;
  final bool allowReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      buildDefaultDragHandles: false,
      itemCount: todos.length,
      // The drop is described by *which todo* it landed in front of, not by two
      // indices: with the list filtered (a status tab, a search) the visible
      // rows are a subset of the stored ones, so an index means something
      // different in each — which is how a drag used to move the wrong row.
      onReorderItem: (int oldIndex, int newIndex) {
        final List<Todo> withoutMoved = List<Todo>.of(todos)
          ..removeAt(oldIndex);
        final String? beforeId = newIndex < withoutMoved.length
            ? withoutMoved[newIndex].id
            : null;
        unawaited(
          _guard(
            ScaffoldMessenger.of(context),
            () => ref
                .read(todoListProvider.notifier)
                .reorder(todos[oldIndex].id, beforeId),
          ),
        );
      },
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, Widget? _) {
            final double t =
                AppMotion.spatialFast.curve.transform(animation.value);
            // The lift is the only cue that a long press has turned into a drag:
            // the row grows slightly and gains a shadow, so it reads as picked up
            // off the list rather than merely highlighted.
            return Transform.scale(
              scale: 1 + 0.03 * t,
              child: Material(
                color: Colors.transparent,
                elevation: 6 * t,
                borderRadius: AppShapes.radius(AppShapes.large),
                shadowColor: Theme.of(context).colorScheme.shadow,
                child: child,
              ),
            );
          },
        );
      },
      itemBuilder: (BuildContext context, int index) {
        final Todo todo = todos[index];
        // RepaintBoundary: repainting one row (a checkbox animation, an image
        // decode) must not repaint its neighbours. With background images in
        // the mix this is what keeps scrolling cheap on weak GPUs.
        return RepaintBoundary(
          key: ValueKey<String>(todo.id),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: allowReorder
                ? ReorderableDelayedDragStartListener(
                    index: index,
                    child: _tile(context, ref, todo),
                  )
                : _tile(context, ref, todo),
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, Todo todo) {
    return TodoTile(
      todo: todo,
      now: now,
      onToggle: () => unawaited(
        _guard(
          ScaffoldMessenger.of(context),
          () => ref.read(todoListProvider.notifier).toggle(todo.id),
        ),
      ),
      onToggleSubtask: (String subtaskId) => unawaited(
        _guard(
          ScaffoldMessenger.of(context),
          () => ref
              .read(todoListProvider.notifier)
              .toggleSubtask(todo.id, subtaskId),
        ),
      ),
      onEdit: () => showTodoEditor(context, existing: todo),
      onDelete: () => unawaited(_delete(context, ref, todo)),
    );
  }

  /// Deletes [todo] and offers an undo that restores it to its old position.
  Future<void> _delete(BuildContext context, WidgetRef ref, Todo todo) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TodoListController controller = ref.read(todoListProvider.notifier);

    try {
      final TodoDeletion deletion = await controller.delete(todo.id);
      if (!deletion.removedSomething) {
        return;
      }
      final Todo removed = deletion.removed!;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppStrings.deletedTodo(todo.title)),
            action: SnackBarAction(
              label: AppStrings.undo,
              onPressed: () => unawaited(
                _guard(
                  messenger,
                  () => controller.restore(removed, deletion.index),
                ),
              ),
            ),
          ),
        );
    } on Object catch (error) {
      messenger.showSnackBar(_failure(error));
    }
  }

  static SnackBar _failure(Object error) {
    return SnackBar(content: Text('${AppStrings.saveFailed}：$error'));
  }

  /// Runs a write and reports any failure, so a storage problem surfaces as a
  /// message instead of an unhandled exception in the console.
  static Future<void> _guard(
    ScaffoldMessengerState messenger,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (error) {
      messenger.showSnackBar(_failure(error));
    }
  }
}
