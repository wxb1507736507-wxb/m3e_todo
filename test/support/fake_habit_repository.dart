import 'package:m3e_todo/features/habits/domain/entities/habit.dart';
import 'package:m3e_todo/features/habits/domain/entities/habit_log.dart';
import 'package:m3e_todo/features/habits/domain/repositories/habit_repository.dart';

/// In-memory [HabitRepository] for tests.
///
/// The real one reads two files, and a widget test that waits for the disk is a
/// widget test that fails on a slow machine; a fake keeps the habits
/// deterministic and the assertions about the UI.
class FakeHabitRepository implements HabitRepository {
  FakeHabitRepository({
    List<Habit>? habits,
    List<HabitLog>? logs,
  })  : _habits = List<Habit>.of(habits ?? const <Habit>[]),
        _logs = List<HabitLog>.of(logs ?? const <HabitLog>[]);

  List<Habit> _habits;
  List<HabitLog> _logs;
  int habitsSaved = 0;
  int logsSaved = 0;

  @override
  Future<List<Habit>> loadHabits() async => List<Habit>.unmodifiable(_habits);

  @override
  Future<void> saveHabits(List<Habit> habits) async {
    habitsSaved++;
    _habits = List<Habit>.of(habits);
  }

  @override
  Future<List<HabitLog>> loadLogs() async => List<HabitLog>.unmodifiable(_logs);

  @override
  Future<void> saveLogs(List<HabitLog> logs) async {
    logsSaved++;
    _logs = List<HabitLog>.of(logs);
  }
}
