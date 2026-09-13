/// A checklist item inside a todo — the "sub-memo".
///
/// Deliberately a value object with its own identity (`id`) rather than a bare
/// string list: completion state must survive reordering and title edits, and
/// the UI needs a stable key for its animation.
class TodoSubtask {
  const TodoSubtask({
    required this.id,
    required this.title,
    this.completedAt,
  });

  /// Creates a subtask from raw user input, applying the same normalisation
  /// rule as the parent todo: trimmed, never blank.
  factory TodoSubtask.create({
    required String id,
    required String title,
  }) {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(title, 'title', 'A subtask needs a title.');
    }
    return TodoSubtask(id: id, title: trimmed);
  }

  final String id;

  /// What the step is. Never blank.
  final String title;

  /// When the step was completed, or `null` while it is still open.
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  TodoSubtask completeAt(DateTime moment) =>
      isCompleted ? this : TodoSubtask(id: id, title: title, completedAt: moment);

  TodoSubtask reopen() =>
      isCompleted ? TodoSubtask(id: id, title: title) : this;

  TodoSubtask toggledAt(DateTime moment) =>
      isCompleted ? reopen() : completeAt(moment);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TodoSubtask &&
        other.id == id &&
        other.title == title &&
        other.completedAt == completedAt;
  }

  @override
  int get hashCode => Object.hash(id, title, completedAt);

  @override
  String toString() =>
      'TodoSubtask($id, "$title", ${isCompleted ? 'completed' : 'active'})';
}

/// Drops blank or whitespace-only titles, so a subtask can never exist unnamed.
///
/// Applied wherever subtask lists enter the domain (the editor's draft), which
/// means the UI can keep empty rows around for typing without polluting state.
List<TodoSubtask> normalizeSubtasks(Iterable<TodoSubtask> subtasks) {
  return List<TodoSubtask>.unmodifiable(
    subtasks.where((TodoSubtask subtask) => subtask.title.trim().isNotEmpty),
  );
}
