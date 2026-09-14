import '../../../../core/utils/calendar.dart';
import '../../../notifications/domain/reminder.dart';
import 'todo_attachment.dart';
import 'todo_priority.dart';
import 'todo_reminder.dart';
import 'todo_subtask.dart';

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
    this.subtasks = const <TodoSubtask>[],
    this.attachments = const <TodoAttachment>[],
    this.accentColor,
    this.textColor,
    this.backgroundImage,
    this.reminder = TodoReminder.followApp,
    this.ringtoneUri,
    this.reminderLead,
    this.categoryId,
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
    List<TodoSubtask> subtasks = const <TodoSubtask>[],
    List<TodoAttachment> attachments = const <TodoAttachment>[],
    int? accentColor,
    int? textColor,
    String? backgroundImage,
    TodoReminder reminder = TodoReminder.followApp,
    String? ringtoneUri,
    ReminderLead? reminderLead,
    String? categoryId,
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
      subtasks: normalizeSubtasks(subtasks),
      attachments: normalizeAttachments(attachments),
      accentColor: accentColor,
      textColor: textColor,
      backgroundImage: backgroundImage,
      reminder: reminder,
      ringtoneUri: ringtoneUri,
      reminderLead: reminderLead,
      categoryId: categoryId,
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

  /// Checklist steps inside this todo. May be empty; never `null`.
  final List<TodoSubtask> subtasks;

  /// Files attached to this todo. May be empty; never `null`.
  final List<TodoAttachment> attachments;

  /// User-chosen tile colour as an ARGB32 integer, or `null` to follow the
  /// theme. Stored as an int rather than a `Color` so the domain stays free of
  /// Flutter imports.
  final int? accentColor;

  /// User-chosen text colour as an ARGB32 integer, or `null` to follow the
  /// theme's `onSurface` — which is what keeps text readable on any card, and
  /// why "auto" exists at all: a photo or a strong colour can make one fixed
  /// choice wrong.
  final int? textColor;

  /// Absolute path of an optional background image for the tile.
  final String? backgroundImage;

  /// Whether this todo's reminder rings or stays quiet, or follows the app-wide
  /// default. Per todo because urgency is per task.
  final TodoReminder reminder;

  /// This todo's own ringtone as a system `content://` URI, or `null` to sound
  /// whatever the app-wide reminder setting uses.
  ///
  /// Only meaningful while [reminder] resolves to ringing; kept when it does not
  /// so switching a todo to "just a message" and back does not lose the choice.
  final String? ringtoneUri;

  /// How early this todo's reminder arrives, or `null` to follow the app-wide
  /// default — the same "follow unless I say otherwise" rule as [reminder].
  final ReminderLead? reminderLead;

  /// The folder this todo is filed under, or `null` for unfiled.
  ///
  /// A plain id rather than the folder itself: the category is a separate
  /// collection with its own lifecycle, and the todo must survive a folder being
  /// renamed or deleted. Deleting a folder unfiles its todos rather than
  /// deleting them.
  final String? categoryId;

  bool get isCompleted => completedAt != null;

  bool get hasNotes => notes != null && notes!.isNotEmpty;

  bool get hasSubtasks => subtasks.isNotEmpty;

  bool get hasAttachments => attachments.isNotEmpty;

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

  /// How many of the checklist steps are done. `(0, 0)` when there are none.
  (int, int) subtaskProgress() {
    if (subtasks.isEmpty) {
      return (0, 0);
    }
    return (
      subtasks.where((TodoSubtask subtask) => subtask.isCompleted).length,
      subtasks.length,
    );
  }

  /// This todo marked complete at [moment].
  ///
  /// Idempotent: completing an already-complete todo keeps the original
  /// timestamp, so a stray double click cannot rewrite when work finished.
  Todo completeAt(DateTime moment) {
    if (isCompleted) {
      return this;
    }
    return _withCompletion(moment);
  }

  /// This todo returned to the open state, clearing its completion timestamp.
  Todo reopen() {
    if (!isCompleted) {
      return this;
    }
    return _withCompletion(null);
  }

  /// Flips completion state at [moment].
  Todo toggledAt(DateTime moment) =>
      isCompleted ? reopen() : completeAt(moment);

  /// Flips the completion state of one checklist step at [moment].
  ///
  /// Silently returns this todo when [subtaskId] matches nothing, mirroring how
  /// [toggledAt]'s caller tolerates a fast double tap.
  Todo toggleSubtask(String subtaskId, DateTime moment) {
    final List<TodoSubtask> updated = <TodoSubtask>[
      for (final TodoSubtask subtask in subtasks)
        if (subtask.id == subtaskId) subtask.toggledAt(moment) else subtask,
    ];
    return _withSubtasks(updated);
  }

  /// Replaces every user-editable field at once.
  ///
  /// The editor always submits the complete form state, so taking all values as
  /// required parameters removes any need for "clear this field" sentinels —
  /// passing an empty list explicitly clears subtasks or attachments.
  Todo edit({
    required String title,
    required String? notes,
    required TodoPriority priority,
    required DateTime? dueDate,
    required List<TodoSubtask> subtasks,
    required List<TodoAttachment> attachments,
    required int? accentColor,
    required int? textColor,
    required String? backgroundImage,
    required TodoReminder reminder,
    required String? ringtoneUri,
    required ReminderLead? reminderLead,
    required String? categoryId,
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
      subtasks: normalizeSubtasks(subtasks),
      attachments: normalizeAttachments(attachments),
      accentColor: accentColor,
      textColor: textColor,
      backgroundImage: backgroundImage,
      reminder: reminder,
      ringtoneUri: ringtoneUri,
      reminderLead: reminderLead,
      completedAt: completedAt,
    );
  }

  /// The same todo with its completion timestamp replaced by [completedAt].
  ///
  /// A plain `copyWith` cannot do this: a `null` argument would be
  /// indistinguishable from "leave it alone", so reopening a todo could never
  /// actually clear the timestamp. Assigning the value unconditionally — and
  /// exposing only these two named intents — removes the ambiguity instead of
  /// papering over it with a sentinel.
  Todo _withCompletion(DateTime? completedAt) {
    return Todo(
      id: id,
      title: title,
      createdAt: createdAt,
      notes: notes,
      priority: priority,
      dueDate: dueDate,
      completedAt: completedAt,
      subtasks: subtasks,
      attachments: attachments,
      accentColor: accentColor,
      textColor: textColor,
      backgroundImage: backgroundImage,
      reminder: reminder,
      ringtoneUri: ringtoneUri,
      reminderLead: reminderLead,
      categoryId: categoryId,
    );
  }

  /// The same todo with its checklist replaced by [subtasks].
  Todo _withSubtasks(List<TodoSubtask> subtasks) {
    return Todo(
      id: id,
      title: title,
      createdAt: createdAt,
      notes: notes,
      priority: priority,
      dueDate: dueDate,
      completedAt: completedAt,
      subtasks: subtasks,
      attachments: attachments,
      accentColor: accentColor,
      textColor: textColor,
      backgroundImage: backgroundImage,
      reminder: reminder,
      ringtoneUri: ringtoneUri,
      reminderLead: reminderLead,
      categoryId: categoryId,
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
        other.completedAt == completedAt &&
        _listEquals(other.subtasks, subtasks) &&
        _listEquals(other.attachments, attachments) &&
        other.accentColor == accentColor &&
        other.textColor == textColor &&
        other.backgroundImage == backgroundImage &&
        other.reminder == reminder &&
        other.ringtoneUri == ringtoneUri &&
        other.reminderLead == reminderLead &&
        other.categoryId == categoryId;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        createdAt,
        notes,
        priority,
        dueDate,
        completedAt,
        Object.hashAll(subtasks),
        Object.hashAll(attachments),
        accentColor,
        textColor,
        backgroundImage,
        reminder,
        ringtoneUri,
        reminderLead,
        categoryId,
      );

  @override
  String toString() =>
      'Todo($id, "$title", ${isCompleted ? 'completed' : 'active'})';

  static String? _normalizeNotes(String? notes) {
    final String trimmed = notes?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
