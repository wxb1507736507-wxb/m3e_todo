/// Supplies the current time.
///
/// Injected rather than calling [DateTime.now] directly so that date-sensitive
/// behaviour (overdue detection, completion timestamps, sort order) can be
/// tested deterministically without touching global state.
typedef Clock = DateTime Function();

/// The production [Clock].
DateTime systemClock() => DateTime.now();
