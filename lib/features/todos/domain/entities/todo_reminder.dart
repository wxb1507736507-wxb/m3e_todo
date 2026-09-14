/// How one todo's reminder makes itself noticed.
///
/// Three values rather than two, because "I have not chosen" is a real state: a
/// todo left alone must follow the app-wide default *and keep following it* when
/// that default changes later, which is not the same as having picked "ring"
/// once and being pinned to it.
///
/// Per todo rather than app-wide because urgency is per task: the deadline that
/// matters should ring, and the shopping list should not. A single global switch
/// forces one answer on both.
enum TodoReminder {
  /// Whatever the app's reminder setting says. The default for a new todo.
  followApp,

  /// Sound and vibration, through this todo's own ringtone.
  ring,

  /// A quiet notification, whatever the app-wide default is.
  silent,
}
