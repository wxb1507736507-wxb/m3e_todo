import '../entities/special_day.dart';

/// Persistence boundary for the calendar's personal dates.
///
/// Same shape as the todo repository: the collection is read and written whole,
/// and the domain never sees the file.
abstract interface class SpecialDayRepository {
  /// Every stored date, in the order it was entered.
  Future<List<SpecialDay>> loadAll();

  /// Replaces the stored collection with [days].
  Future<void> saveAll(List<SpecialDay> days);
}
