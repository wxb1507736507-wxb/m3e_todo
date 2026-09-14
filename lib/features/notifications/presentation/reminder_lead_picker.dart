import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../domain/reminder.dart';

/// The chip row that chooses how early a reminder arrives.
///
/// Shared by the todo editor and the settings sheet on purpose: the editor picks
/// one todo's lead time and can answer "follow the default", while the settings
/// sheet *is* that default and has no such answer — but the set of lead times a
/// user can choose must never differ between the two.
class ReminderLeadPicker extends StatelessWidget {
  const ReminderLeadPicker({
    required this.value,
    required this.onChanged,
    this.allowFollowDefault = false,
    super.key,
  });

  /// The chosen lead, or `null` when this todo follows the app default.
  final ReminderLead? value;

  final ValueChanged<ReminderLead?> onChanged;

  /// Whether "follow the default" is one of the answers.
  final bool allowFollowDefault;

  @override
  Widget build(BuildContext context) {
    // A Wrap, not a Row: four chips plus a possible fifth do not fit across a
    // phone, and an overflowing Row paints stripes over the last one.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        if (allowFollowDefault)
          ChoiceChip(
            label: const Text(AppStrings.reminderFollowApp),
            selected: value == null,
            onSelected: (_) => onChanged(null),
          ),
        for (final ReminderLead lead in ReminderLead.values)
          ChoiceChip(
            label: Text(reminderLeadLabel(lead)),
            selected: value == lead,
            onSelected: (_) => onChanged(lead),
          ),
      ],
    );
  }
}

/// The name of one lead time.
String reminderLeadLabel(ReminderLead lead) => switch (lead) {
      ReminderLead.onDue => AppStrings.reminderLeadOnDue,
      ReminderLead.oneDay => AppStrings.reminderLeadOneDay,
      ReminderLead.threeDays => AppStrings.reminderLeadThreeDays,
      ReminderLead.oneWeek => AppStrings.reminderLeadOneWeek,
    };
