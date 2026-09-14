/// How a due-date reminder makes itself noticed.
///
/// Lives with the reminders rather than with the settings, because it is not a
/// preference the settings own: the settings hold a *default*, and each todo
/// carries its own answer. Anything that needs to name the concept — the
/// settings sheet, the todo entity, the scheduler — can reach it here without
/// the todos feature having to know about the settings feature.
enum ReminderMode {
  /// Full sound + vibration through a "ring" notification channel.
  ring,

  /// A quiet notification through the "silent" channel.
  silent,
}

/// How far ahead of its deadline a reminder arrives.
///
/// Also per todo: an anniversary wants a week's warning, "buy milk" wants none,
/// and the app-wide setting is only the default for todos that have not chosen.
enum ReminderLead {
  /// At 09:00 on the day it is due.
  onDue(daysBefore: 0),
  oneDay(daysBefore: 1),
  threeDays(daysBefore: 3),
  oneWeek(daysBefore: 7);

  const ReminderLead({required this.daysBefore});

  /// Days between the notification and the deadline.
  final int daysBefore;
}
