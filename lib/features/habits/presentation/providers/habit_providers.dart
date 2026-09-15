import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/document_store.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/utils/calendar.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../todos/presentation/providers/todo_providers.dart' show clockProvider;
import '../../data/datasources/habit_local_data_source.dart';
import '../../data/repositories/local_habit_repository.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/habit_planner.dart';
import '../../domain/repositories/habit_repository.dart';

/// The app's single clock, re-exported.
///
/// It is declared with the todos because that is where it was first needed, not
/// because time is a todo concern; every habit screen needs it too, and having
/// them import the todo feature just to ask what time it is would be a worse
/// dependency than this line.
export '../../../todos/presentation/providers/todo_providers.dart'
    show clockProvider;

/// File names of the two documents habits use.
const String habitFileName = 'habits.json';
const String habitLogFileName = 'habit_logs.json';

final Provider<DocumentStore> habitDocumentStoreProvider = Provider<DocumentStore>(
  (ref) => ref.watch(documentStoreFactoryProvider)(habitFileName),
  name: 'habitDocumentStore',
);

final Provider<DocumentStore> habitLogDocumentStoreProvider =
    Provider<DocumentStore>(
  (ref) => ref.watch(documentStoreFactoryProvider)(habitLogFileName),
  name: 'habitLogDocumentStore',
);

final Provider<HabitRepository> habitRepositoryProvider =
    Provider<HabitRepository>(
  (ref) => LocalHabitRepository(
    HabitLocalDataSource(ref.watch(habitDocumentStoreProvider)),
    HabitLogLocalDataSource(ref.watch(habitLogDocumentStoreProvider)),
  ),
  name: 'habitRepository',
);

/// Ids for new habits; overridden in tests with a deterministic sequence.
final Provider<IdGenerator> habitIdGeneratorProvider = Provider<IdGenerator>(
  (ref) => generateTodoId,
  name: 'habitIdGenerator',
);

/// The user's habits.
class HabitsController extends AsyncNotifier<List<Habit>> {
  @override
  Future<List<Habit>> build() => ref.watch(habitRepositoryProvider).loadHabits();

  Future<Habit> add({
    required String name,
    required String emoji,
    required int days,
    int? intervalDays,
    int? reminderMinutes,
    bool allowNote = true,
    int? color,
  }) async {
    final Habit created = Habit.create(
      id: ref.read(habitIdGeneratorProvider)(),
      name: name,
      emoji: emoji,
      days: days,
      createdAt: ref.read(clockProvider)(),
      intervalDays: intervalDays,
      reminderMinutes: reminderMinutes,
      allowNote: allowNote,
      color: color,
    );
    await _replace((List<Habit> current) => <Habit>[...current, created]);
    return created;
  }

  Future<void> edit(String id, Habit Function(Habit current) change) {
    return _replace(
      (List<Habit> current) => <Habit>[
        for (final Habit habit in current)
          if (habit.id == id) change(habit) else habit,
      ],
    );
  }

  /// Removes a habit and returns it.
  ///
  /// Its check-ins go with it, and are deliberately not left behind: a log with
  /// no habit cannot be shown anywhere, so keeping it would be keeping a secret
  /// the user cannot see or delete. The confirmation in the UI says so before
  /// this is ever called.
  Future<void> remove(String id) async {
    await _replace(
      (List<Habit> current) =>
          current.where((Habit habit) => habit.id != id).toList(),
    );
    await ref.read(habitLogsProvider.notifier).removeForHabit(id);
  }

  Future<void> _replace(List<Habit> Function(List<Habit> current) change) async {
    final List<Habit> current = await future;
    final List<Habit> updated = change(current);
    await ref.read(habitRepositoryProvider).saveHabits(updated);
    if (ref.mounted) {
      state = AsyncData<List<Habit>>(updated);
    }
  }
}

final AsyncNotifierProvider<HabitsController, List<Habit>> habitsProvider =
    AsyncNotifierProvider<HabitsController, List<Habit>>(
  HabitsController.new,
  name: 'habits',
);

/// Every check-in ever recorded, oldest first.
class HabitLogsController extends AsyncNotifier<List<HabitLog>> {
  @override
  Future<List<HabitLog>> build() => ref.watch(habitRepositoryProvider).loadLogs();

  /// Records a check-in for [habitId] on [day] (today when omitted), with an
  /// optional note.
  ///
  /// Checking in twice on the same day replaces the entry rather than adding a
  /// second one: pressing the widget button and then writing a note in the app
  /// is one check-in that gained a note, not two facts.
  Future<void> checkIn(
    String habitId, {
    DateTime? day,
    String? note,
    DateTime? at,
  }) async {
    await _replace((List<HabitLog> current) {
      final DateTime when = at ?? ref.read(clockProvider)();
      final int key = habitDayKey(day ?? when);
      final HabitLog entry = HabitLog(
        habitId: habitId,
        dayKey: key,
        at: when,
        note: note,
      );
      final List<HabitLog> next = <HabitLog>[
        for (final HabitLog log in current)
          if (!(log.habitId == habitId && log.dayKey == key)) log,
        entry,
      ];
      next.sort((HabitLog a, HabitLog b) => a.at.compareTo(b.at));
      return next;
    });
  }

  /// Adds a note to an existing check-in, or removes the note when [note] is
  /// empty. Does nothing when there is no check-in to write to.
  Future<void> setNote(String habitId, int dayKey, String? note) {
    return _replace(
      (List<HabitLog> current) => <HabitLog>[
        for (final HabitLog log in current)
          if (log.habitId == habitId && log.dayKey == dayKey)
            log.withNote(note)
          else
            log,
      ],
    );
  }

  /// Takes back a check-in.
  Future<void> undo(String habitId, int dayKey) {
    return _replace(
      (List<HabitLog> current) => <HabitLog>[
        for (final HabitLog log in current)
          if (!(log.habitId == habitId && log.dayKey == dayKey)) log,
      ],
    );
  }

  Future<void> removeForHabit(String habitId) {
    return _replace(
      (List<HabitLog> current) => <HabitLog>[
        for (final HabitLog log in current)
          if (log.habitId != habitId) log,
      ],
    );
  }

  /// Merges check-ins that were made on the home-screen widget while the app was
  /// not running.
  ///
  /// The widget cannot write to the app's JSON documents — it may run with the
  /// app process dead — so it queues what the user did natively, and this is
  /// where that queue becomes real data. Entries that already exist are left
  /// alone, which is what makes draining safe to repeat.
  Future<void> adopt(List<HabitLog> incoming) async {
    if (incoming.isEmpty) {
      return;
    }
    await _replace((List<HabitLog> current) {
      final List<HabitLog> next = List<HabitLog>.of(current);
      for (final HabitLog entry in incoming) {
        final int index = next.indexWhere(
          (HabitLog log) =>
              log.habitId == entry.habitId && log.dayKey == entry.dayKey,
        );
        if (index >= 0) {
          // A check-in that already exists keeps the note the app may have
          // added, unless the widget is reporting an undo.
          next[index] = entry;
        } else {
          next.add(entry);
        }
      }
      next.sort((HabitLog a, HabitLog b) => a.at.compareTo(b.at));
      return next;
    });
  }

  Future<void> _replace(
    List<HabitLog> Function(List<HabitLog> current) change,
  ) async {
    final List<HabitLog> current = await future;
    final List<HabitLog> updated = change(current);
    await ref.read(habitRepositoryProvider).saveLogs(updated);
    if (ref.mounted) {
      state = AsyncData<List<HabitLog>>(updated);
    }
  }
}

final AsyncNotifierProvider<HabitLogsController, List<HabitLog>>
    habitLogsProvider =
    AsyncNotifierProvider<HabitLogsController, List<HabitLog>>(
  HabitLogsController.new,
  name: 'habitLogs',
);

/// Which days each habit was checked off, keyed by habit id.
///
/// Built once per change rather than searched per habit per rebuild: every habit
/// row asks "is this day done", and a linear scan of the whole log for each of
/// them is the shape that turns a long history into a slow list.
final Provider<Map<String, Set<int>>> habitDoneDaysProvider =
    Provider<Map<String, Set<int>>>(
  (ref) {
    final List<HabitLog> logs =
        ref.watch(habitLogsProvider).value ?? const <HabitLog>[];
    final Map<String, Set<int>> days = <String, Set<int>>{};
    for (final HabitLog log in logs) {
      (days[log.habitId] ??= <int>{}).add(log.dayKey);
    }
    return days;
  },
  name: 'habitDoneDays',
);

/// Every check-in for one habit, newest first.
final habitLogsOfProvider = Provider.family<List<HabitLog>, String>(
  (ref, String habitId) {
    final List<HabitLog> logs =
        ref.watch(habitLogsProvider).value ?? const <HabitLog>[];
    return <HabitLog>[
      for (final HabitLog log in logs)
        if (log.habitId == habitId) log,
    ]..sort((HabitLog a, HabitLog b) => b.at.compareTo(a.at));
  },
  name: 'habitLogsOf',
);

/// Today's habits, each with its check-in, in the order they should be done.
final Provider<List<HabitDayStatus>> todaysHabitsProvider =
    Provider<List<HabitDayStatus>>(
  (ref) {
    final List<Habit> habits =
        ref.watch(habitsProvider).value ?? const <Habit>[];
    final List<HabitLog> logs =
        ref.watch(habitLogsProvider).value ?? const <HabitLog>[];
    return habitsDueOn(habits, logs, startOfDay(ref.watch(clockProvider)()));
  },
  name: 'todaysHabits',
);

/// A habit by id, or `null` when it has been deleted.
final habitByIdProvider = Provider.family<Habit?, String>(
  (ref, String id) {
    final List<Habit> habits =
        ref.watch(habitsProvider).value ?? const <Habit>[];
    for (final Habit habit in habits) {
      if (habit.id == id) {
        return habit;
      }
    }
    return null;
  },
  name: 'habitById',
);

/// The habit the home-screen widget asked the app to open.
///
/// Set when the widget's ＋ button is tapped — that button is how a note gets
/// written from the home screen, since a widget cannot take typing — and cleared
/// by the habits page once it has opened the check-in editor for it.
class PendingHabitOpen extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String habitId) => state = habitId;

  void clear() => state = null;
}

final NotifierProvider<PendingHabitOpen, String?> pendingHabitOpenProvider =
    NotifierProvider<PendingHabitOpen, String?>(
  PendingHabitOpen.new,
  name: 'pendingHabitOpen',
);

/// Whether the habit widget is currently on one of the home screens.
///
/// Read from the platform after the first sync, because only Android knows. The
/// habits page shows the answer from here rather than guessing, so it never
/// offers to add a widget that is already there.
class HabitWidgetPlaced extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool placed) => state = placed;
}

final NotifierProvider<HabitWidgetPlaced, bool> habitWidgetPlacedProvider =
    NotifierProvider<HabitWidgetPlaced, bool>(
  HabitWidgetPlaced.new,
  name: 'habitWidgetPlaced',
);
