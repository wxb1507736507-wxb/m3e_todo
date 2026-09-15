import '../entities/timetable.dart';

/// Where the timetable is kept.
///
/// One method each way: the term and its courses are written together, because
/// they are only ever read together and a half-saved timetable would have
/// courses with no weeks to belong to.
abstract interface class TimetableRepository {
  /// The stored timetable, or `null` when nothing has been saved yet — which is
  /// not the same as an empty one: it is what a fresh install looks like, and it
  /// is what the controller turns into a timetable for the current term.
  Future<Timetable?> load();

  Future<void> save(Timetable timetable);
}
