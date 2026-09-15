import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/repositories/habit_repository.dart';
import '../datasources/habit_local_data_source.dart';

/// A [HabitRepository] over the app's own JSON documents.
class LocalHabitRepository implements HabitRepository {
  LocalHabitRepository(this._habits, this._logs);

  final HabitLocalDataSource _habits;
  final HabitLogLocalDataSource _logs;

  @override
  Future<List<Habit>> loadHabits() => _habits.readAll();

  @override
  Future<void> saveHabits(List<Habit> habits) => _habits.writeAll(habits);

  @override
  Future<List<HabitLog>> loadLogs() => _logs.readAll();

  @override
  Future<void> saveLogs(List<HabitLog> logs) => _logs.writeAll(logs);
}
