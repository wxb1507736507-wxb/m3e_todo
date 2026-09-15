import '../../../../core/storage/document_store.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../models/habit_model.dart';

/// Reads and writes the habits as a versioned JSON document.
class HabitLocalDataSource {
  HabitLocalDataSource(this._store);

  final DocumentStore _store;

  static const String _versionKey = 'version';
  static const String _habitsKey = 'habits';

  Future<List<Habit>> readAll() async {
    final Map<String, Object?>? document = await _store.read();
    if (document == null) {
      return <Habit>[];
    }
    final Object? raw = document[_habitsKey];
    if (raw is! List) {
      return <Habit>[];
    }

    final List<Habit> habits = <Habit>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final Habit? habit = HabitModel.fromJson(Map<String, Object?>.from(entry));
      if (habit != null) {
        habits.add(habit);
      }
    }
    return habits;
  }

  Future<void> writeAll(List<Habit> habits) {
    return _store.write(<String, Object?>{
      _versionKey: HabitModel.schemaVersion,
      _habitsKey: <Object?>[
        for (final Habit habit in habits) HabitModel.toJson(habit),
      ],
    });
  }
}

/// Reads and writes the check-in log as a versioned JSON document.
class HabitLogLocalDataSource {
  HabitLogLocalDataSource(this._store);

  final DocumentStore _store;

  static const String _versionKey = 'version';
  static const String _logsKey = 'logs';

  Future<List<HabitLog>> readAll() async {
    final Map<String, Object?>? document = await _store.read();
    if (document == null) {
      return <HabitLog>[];
    }
    final Object? raw = document[_logsKey];
    if (raw is! List) {
      return <HabitLog>[];
    }

    final List<HabitLog> logs = <HabitLog>[];
    for (final Object? entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final HabitLog? log =
          HabitLogModel.fromJson(Map<String, Object?>.from(entry));
      if (log != null) {
        logs.add(log);
      }
    }
    logs.sort((HabitLog a, HabitLog b) => a.at.compareTo(b.at));
    return logs;
  }

  Future<void> writeAll(List<HabitLog> logs) {
    return _store.write(<String, Object?>{
      _versionKey: HabitLogModel.schemaVersion,
      _logsKey: <Object?>[
        for (final HabitLog log in logs) HabitLogModel.toJson(log),
      ],
    });
  }
}
