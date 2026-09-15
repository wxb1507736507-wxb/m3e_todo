import '../entities/habit.dart';
import '../entities/habit_log.dart';

/// Where habits and their check-ins are kept.
///
/// Two documents rather than one: a check-in is written far more often than a
/// habit is edited, and every document here is replaced whole, so keeping the
/// log apart is what stops a one-tap check-in from rewriting the definitions.
abstract interface class HabitRepository {
  /// Every habit, in creation order.
  Future<List<Habit>> loadHabits();

  Future<void> saveHabits(List<Habit> habits);

  /// Every check-in ever recorded, oldest first.
  Future<List<HabitLog>> loadLogs();

  Future<void> saveLogs(List<HabitLog> logs);
}
