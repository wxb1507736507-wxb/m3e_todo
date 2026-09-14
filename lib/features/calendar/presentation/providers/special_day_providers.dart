import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/document_store.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../todos/presentation/providers/todo_providers.dart';
import '../../data/datasources/special_day_local_data_source.dart';
import '../../data/repositories/local_special_day_repository.dart';
import '../../domain/entities/special_day.dart';
import '../../domain/repositories/special_day_repository.dart';

/// File name of the personal-dates document inside the app data directory.
const String specialDayFileName = 'special_days.json';

/// The JSON document backing the calendar's birthdays and countdowns.
final Provider<DocumentStore> specialDayDocumentStoreProvider =
    Provider<DocumentStore>(
  (ref) => ref.watch(documentStoreFactoryProvider)(specialDayFileName),
  name: 'specialDayDocumentStore',
);

final Provider<SpecialDayRepository> specialDayRepositoryProvider =
    Provider<SpecialDayRepository>(
  (ref) => LocalSpecialDayRepository(
    SpecialDayLocalDataSource(ref.watch(specialDayDocumentStoreProvider)),
  ),
  name: 'specialDayRepository',
);

/// The stored personal dates.
///
/// A plain [AsyncNotifier] rather than a family of use cases: unlike todos there
/// is no ordering to preserve, no undo, and no bulk operation — adding, editing
/// and removing are the whole surface.
class SpecialDaysController extends AsyncNotifier<List<SpecialDay>> {
  @override
  Future<List<SpecialDay>> build() =>
      ref.watch(specialDayRepositoryProvider).loadAll();

  Future<void> add({
    required String title,
    required SpecialDayKind kind,
    required DateTime date,
    String? notes,
  }) {
    return _replace(
      (List<SpecialDay> current) => <SpecialDay>[
        ...current,
        SpecialDay.create(
          id: ref.read(specialDayIdGeneratorProvider)(),
          title: title,
          kind: kind,
          date: date,
          notes: notes,
        ),
      ],
    );
  }

  Future<void> edit(
    String id, {
    required String title,
    required SpecialDayKind kind,
    required DateTime date,
    String? notes,
  }) {
    return _replace(
      (List<SpecialDay> current) => <SpecialDay>[
        for (final SpecialDay day in current)
          if (day.id == id)
            day.edit(title: title, kind: kind, date: date, notes: notes)
          else
            day,
      ],
    );
  }

  Future<void> remove(String id) {
    return _replace(
      (List<SpecialDay> current) =>
          current.where((SpecialDay day) => day.id != id).toList(),
    );
  }

  /// Saves the whole collection once the change has been computed.
  ///
  /// State is only replaced after the write succeeds, so a failure leaves the
  /// screen agreeing with the disk — the same rule the todo controller follows
  /// for everything except the one gesture that needs to be instant (a drag).
  Future<void> _replace(
    List<SpecialDay> Function(List<SpecialDay> current) change,
  ) async {
    final List<SpecialDay> current = await future;
    final List<SpecialDay> updated = change(current);
    await ref.read(specialDayRepositoryProvider).saveAll(updated);
    if (ref.mounted) {
      state = AsyncData<List<SpecialDay>>(updated);
    }
  }
}

final AsyncNotifierProvider<SpecialDaysController, List<SpecialDay>>
    specialDaysProvider =
    AsyncNotifierProvider<SpecialDaysController, List<SpecialDay>>(
  SpecialDaysController.new,
  name: 'specialDays',
);

/// Ids for new personal dates; overridden in tests with a deterministic
/// sequence. Shares the `todo` generator's shape (timestamp plus counter), which
/// is what keeps the two collections' ids from colliding in a log.
final Provider<IdGenerator> specialDayIdGeneratorProvider = Provider<IdGenerator>(
  (ref) => generateTodoId,
  name: 'specialDayIdGenerator',
);

/// Upcoming personal dates, soonest first.
///
/// Derived rather than stored: it recomputes from the collection and the clock,
/// so a countdown that ticks over at midnight needs no invalidation of its own.
final Provider<AsyncValue<List<SpecialDay>>> upcomingSpecialDaysProvider =
    Provider<AsyncValue<List<SpecialDay>>>(
  (ref) {
    final DateTime now = ref.watch(clockProvider)();
    return ref.watch(specialDaysProvider).whenData(
          (List<SpecialDay> days) => List<SpecialDay>.of(days)
            ..sort((SpecialDay a, SpecialDay b) => compareSpecialDays(a, b, now)),
        );
  },
  name: 'upcomingSpecialDays',
);
