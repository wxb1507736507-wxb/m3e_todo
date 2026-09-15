import 'package:m3e_todo/features/timetable/domain/entities/timetable.dart';
import 'package:m3e_todo/features/timetable/domain/repositories/timetable_repository.dart';

/// In-memory [TimetableRepository] for tests.
///
/// The real one reads a file, and a widget test that waits for the disk is a
/// widget test that fails on a slow machine; a fake keeps the term and its
/// courses deterministic and the assertions about the grid.
class FakeTimetableRepository implements TimetableRepository {
  FakeTimetableRepository([this._timetable]);

  Timetable? _timetable;
  int saveCount = 0;

  /// The timetable as it stands now, for a test to assert against.
  Timetable? get stored => _timetable;

  @override
  Future<Timetable?> load() async => _timetable;

  @override
  Future<void> save(Timetable timetable) async {
    saveCount++;
    _timetable = timetable;
  }
}
