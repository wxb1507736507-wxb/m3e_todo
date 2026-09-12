import '../../../../core/utils/calendar.dart';
import 'todo_priority.dart';

/// Thrown when a todo would break the domain rule that a title is required.
///
/// The editor validates before calling in, so this is a safety net that
/// guarantees the invariant holds no matter which code path creates a todo.
class TodoValidationException implements Exception {
  const TodoValidationException(this.message);

  final String message;

  @override
  String toString() => 'TodoValidationException: $message';
}

/// A single task.
///
/// Immutable: every change returns a new instance. That makes state comparison
/// cheap, which is what lets Riverpod decide whether to rebuild just by testing
/// `==` &mdash; hence [==] and [hashCode] cover every field.
///
/// All mutation is expressed as intention-revealing methods ([completeAt],
/// [reopen], [edit], …) instead of a generic `copyWith`. A generic copy is easy
/// to misuse, because a nullable parameter cannot distinguish "leave unchanged"
/// from "set to null"; explicit methods remove that ambiguity.
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.createdAt,
    this.notes,
    this.priority = TodoPriority.normal,
    this.dueDate,
    this.completedAt,
  });

  /// Creates a todo from raw user input, applying the domain's normalisation
  /// rules: the title is trimmed and must not be blank, notes are trimmed with
  /// empty collapsing to `null`, and a due date is reduced to midnight.
  ///
  /// Normalising here rather than in the UI means no code path can persist a
  /// padded title or use `''` as a stand-in for "no notes".
  factory Todo.create({
    required String id,
    required String title,
    required DateTime createdAt,
    String? notes,
    TodoPriority priority = TodoPriority.normal,
    DateTime? dueDate,
  }) {
    final String normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const TodoValidationException('A todo needs a title.');
    }
    return Todo(
      id: id,
      title: normalizedTitle,
      createdAt: createdAt,
      notes: _normalizeNotes(notes),
      priority: priority,
      dueDate: dueDate == null ? null : startOfDay(dueDate),
    );
  }

  /// Stable identity, generated once and never reused.
  final String id;

  /// What the task is. Never blank.
  final String title;

  /// When the user captured the task.
  final DateTime createdAt;

  /// Optional free-form detail. `null` when absent, never an empty string.
  final String? notes;

  final TodoPriority priority;

  /// Day-granular deadline, always midnight local time, or `null` for none.
  final DateTime? dueDate;

  /// When the task was completed, or `null` while it is still open.
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  bool get hasNotes => notes != null && notes!.isNotEmpty;

  /// Whether a still-open task's deadline has passed.
  bool isOverdue(DateTime now) {
    final DateTime? due = dueDate;
    return !isCompleted && due != null && isBeforeToday(due, now);
  }

  /// Whether the deadline falls on today.
  bool isDueToday(DateTime now) {
    final DateTime? due = dueDate;
    return due != null && isToday(due, now);
  }

  /// Whether the deadline falls on tomorrow.
  bool isDueTomorrow(DateTime now) {
    final DateTime? due = dueDate;
    return due != null && isTomorrow(due, now);
  }

  /// Whole days from today until the deadline; negative once overdue.
  /// Returns `null` when there is no deadline.
  int? daysUntilDue(DateTime now) {
    final DateTime? due = dueDate;
    return due == null ? null : daysBetween(now, due);
  }

  /// This todo marked complete at [moment].
  ///
  /// Idempotent: completing an already-complete todo keeps the original
  /// timestamp, so a stray double click cannot rewrite when work finished.
  Todo completeAt(DateTime moment) {
    if (isCompleted) {
      return this;
    }
    return Todo(
      id: id,
      title: title,
      createdAt: createdAt,
      notes: notes,
      priority: priority,
      dueDate: dueDate,
      completedAt: moment,
    );
  }

  /// This todo returned to the open state, clearing its completion timestamp.
  Todo reopen() {
    if (!isCompleted) {
      return this;
    }
    return Todo(
      id: id,
      title: title,
      createdAt: createdAt,
      notes: notes,
      priority: priority,
      dueDate: dueDate,
    );
  }

  /// Flips completion state at [moment].
  Todo toggledAt(DateTime moment) =>
      isCompleted ? reopen() : completeAt(moment);

  /// Replaces every user-editable field at once.
  ///
  /// The editor always submits the complete form state, so taking all four
  /// values as required parameters removes any need for "clear this field"
  /// sentinels.
  Todo edit({
    required String title,
    required String? notes,
    required TodoPriority priority,
    required DateTime? dueDate,
  }) {
    final String normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const TodoValidationException('A todo needs a title.');
    }
    return Todo(
      id: id,
      title: normalizedTitle,
      createdAt: createdAt,
      notes: _normalizeNotes(notes),
      priority: priority,
      dueDate: dueDate == null ? null : startOfDay(dueDate),
      completedAt: completedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Todo &&
        other.id == id &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.notes == notes &&
        other.priority == priority &&
        other.dueDate == dueDate &&
        other.completedAt == completedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, title, createdAt, notes, priority, dueDate, completedAt);

  @override
  String toString() =>
      'Todo($id, "$title", ${isCompleted ? 'completed' : 'active'})';

  static String? _normalizeNotes(String? notes) {
    final String trimmed = notes?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
