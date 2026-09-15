import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/platform/app_platform.dart';
import '../domain/app_settings.dart';
import '../../notifications/domain/reminder.dart';
import '../../notifications/presentation/reminder_lead_picker.dart';
import 'appearance_sheet.dart';
import 'settings_controller.dart';
import 'widgets/background_controls.dart';
import 'widgets/vision_import_settings.dart';

/// Opens the integrated settings sheet.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (BuildContext context) => const SettingsSheet(),
  );
}

/// Every configurable extra lives here: reminders (ring vs silent, ringtone),
/// appearance, and usage tips. One entry point keeps "where is that setting?"
/// answerable with a single sentence.
class SettingsSheet extends ConsumerStatefulWidget {
  const SettingsSheet({super.key});

  @override
  ConsumerState<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<SettingsSheet>
    with WidgetsBindingObserver {
  bool? _notificationsEnabled;
  bool? _exactAlarmsAllowed;

  @override
  void initState() {
    super.initState();
    // The exact-alarm grant is decided on a system screen this app opens, so the
    // answer changes while the app is in the background; without this observer
    // the banner would still claim the grant is missing after it was given.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissions());
    }
  }

  Future<void> _refreshPermissions() async {
    final bool notifications = await AppPlatform.notificationsEnabled();
    final bool exactAlarms = await AppPlatform.canScheduleExactAlarms();
    if (mounted) {
      setState(() {
        _notificationsEnabled = notifications;
        _exactAlarmsAllowed = exactAlarms;
      });
    }
  }

  Future<void> _requestPermission() async {
    await AppPlatform.requestNotificationPermission();
    await _refreshPermissions();
  }

  Future<void> _requestExactAlarms() async {
    await AppPlatform.requestExactAlarmPermission();
    await _refreshPermissions();
  }

  Future<void> _pickRingtone() async {
    final String? uri = await AppPlatform.pickRingtone();
    if (uri != null) {
      await ref.read(settingsProvider.notifier).setRingtone(uri);
    }
  }

  Future<void> _sendTestNotification() async {
    // Five seconds out, via the same channel a real reminder uses — so what
    // the user hears is exactly what a due todo will sound like.
    await AppPlatform.scheduleAlarm(
      notificationId: 999001,
      title: AppStrings.notificationTest,
      body: AppStrings.reminderTimeHint,
      triggerAt: DateTime.now().add(const Duration(seconds: 5)),
      ring: ref.read(settingsProvider).reminderMode == ReminderMode.ring,
      ringtoneUri: ref.read(settingsProvider).ringtoneUri,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.notificationTest)),
      );
    }
  }

  Future<void> _pickBackground() async {
    // Picked and cropped in one step: the image is drawn `cover` across the
    // whole window, so an uncropped 4:3 photo would be scaled down to its
    // middle band and lose the composition the user chose.
    final String? path = await pickBackgroundImage(context);
    if (path == null) {
      return;
    }
    await ref.read(settingsProvider.notifier).setBackgroundImage(path);
  }

  Future<void> _recropBackground() async {
    final String? current = ref.read(settingsProvider).backgroundImage;
    if (current == null) {
      return;
    }
    final String? recropped = await recropBackgroundImage(context, current);
    if (recropped == null) {
      return;
    }
    await ref.read(settingsProvider.notifier).setBackgroundImage(recropped);
  }

  Future<void> _removeBackground() =>
      ref.read(settingsProvider.notifier).setBackgroundImage(null);

  /// Picks the picture the home-screen tiles will be drawn on.
  ///
  /// The same file the app's own background would produce, kept in the same
  /// place: a tile is a widget of this app, and a second directory for its
  /// pictures would only be a second thing to keep clean.
  Future<void> _pickWidgetBackground() async {
    final String? path = await pickBackgroundImage(context);
    if (path == null) {
      return;
    }
    await ref.read(settingsProvider.notifier).setWidgetBackgroundImage(path);
  }

  Future<void> _recropWidgetBackground() async {
    final String? current = ref.read(settingsProvider).widgetBackgroundImage;
    if (current == null) {
      return;
    }
    final String? recropped = await recropBackgroundImage(context, current);
    if (recropped == null) {
      return;
    }
    await ref.read(settingsProvider.notifier).setWidgetBackgroundImage(recropped);
  }

  /// Background image picker, preview, crop and scrim strength.
  Widget _buildBackgroundControls(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) {
    return BackgroundControls(
      imagePath: settings.backgroundImage,
      dim: settings.backgroundDim,
      onPick: () => unawaited(_pickBackground()),
      onRecrop: () => unawaited(_recropBackground()),
      onRemove: () => unawaited(_removeBackground()),
      onDimChanged: controller.setBackgroundDim,
    );
  }


  /// A tappable strip reporting a permission this app needs and does not have.
  Widget _banner(BuildContext context, String message, VoidCallback onTap) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final BorderRadius radius = BorderRadius.circular(8);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: radius,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.info_outline, color: colors.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: text.bodyMedium?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool onAndroid = AppPlatform.isAndroid;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(AppStrings.settingsTitle, style: text.headlineSmall),
              const SizedBox(height: 20),

              // --- Reminders -------------------------------------------------
              Text(AppStrings.settingsSectionReminders, style: text.titleMedium),
              const SizedBox(height: 8),
              Text(AppStrings.reminderModeLabel, style: text.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<ReminderMode>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<ReminderMode>>[
                  ButtonSegment<ReminderMode>(
                    value: ReminderMode.ring,
                    label: Text(AppStrings.reminderModeRing),
                    icon: Icon(Icons.notifications_active_outlined),
                  ),
                  ButtonSegment<ReminderMode>(
                    value: ReminderMode.silent,
                    label: Text(AppStrings.reminderModeSilent),
                    icon: Icon(Icons.notifications_none),
                  ),
                ],
                selected: <ReminderMode>{settings.reminderMode},
                onSelectionChanged: (Set<ReminderMode> selection) =>
                    unawaited(controller.setReminderMode(selection.first)),
              ),
              const SizedBox(height: 14),
              Text(AppStrings.reminderLeadLabel, style: text.labelLarge),
              const SizedBox(height: 8),
              ReminderLeadPicker(
                value: settings.reminderLead,
                // No "follow the default" here: this *is* the default, so the
                // picker only ever hands back a concrete lead.
                onChanged: (ReminderLead? lead) {
                  if (lead != null) {
                    controller.setReminderLead(lead);
                  }
                },
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.reminderDefaultHint,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.reminderTimeHint,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (settings.reminderMode == ReminderMode.ring && onAndroid) ...<Widget>[
                const SizedBox(height: 14),
                Text(AppStrings.ringtoneDefaultLabel, style: text.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        settings.ringtoneUri == null
                            ? AppStrings.ringtoneSystem
                            : AppStrings.ringtoneCustom,
                        style: text.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          unawaited(controller.previewRingtone(settings.ringtoneUri)),
                      child: const Text(AppStrings.ringtonePreview),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton(
                      onPressed: () => unawaited(_pickRingtone()),
                      child: const Text(AppStrings.ringtonePick),
                    ),
                  ],
                ),
              ],
              if (onAndroid) ...<Widget>[
                const SizedBox(height: 14),
                if (_notificationsEnabled == false)
                  _banner(
                    context,
                    AppStrings.notificationPermissionNeeded,
                    () => unawaited(_requestPermission()),
                  ),
                // Without this grant reminders still arrive, but the OS widens
                // the trigger by up to an hour, so "9:00" becomes "sometime
                // before 10:00". Say so instead of letting it look broken.
                if (_exactAlarmsAllowed == false)
                  _banner(
                    context,
                    AppStrings.exactAlarmNeeded,
                    () => unawaited(_requestExactAlarms()),
                  ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_sendTestNotification()),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text(AppStrings.notificationTest),
                ),
              ],

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 20),

              // --- Appearance (unchanged controls, relocated here) ------------
              Text(AppStrings.settingsSectionAppearance, style: text.titleMedium),
              const SizedBox(height: 12),
              const AppearanceSheet(),

              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 20),

              // --- Application background --------------------------------------
              Text(
                AppStrings.settingsSectionBackground,
                style: text.titleMedium,
              ),
              const SizedBox(height: 12),
              _buildBackgroundControls(context, settings, controller),

              const SizedBox(height: 20),
              Text(AppStrings.widgetBackgroundLabel, style: text.titleMedium),
              const SizedBox(height: 2),
              Text(
                AppStrings.widgetBackgroundHint,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              BackgroundControls(
                imagePath: settings.widgetBackgroundImage,
                dim: settings.widgetBackgroundDim,
                onPick: () => unawaited(_pickWidgetBackground()),
                onRecrop: () => unawaited(_recropWidgetBackground()),
                onRemove: () => unawaited(
                  controller.setWidgetBackgroundImage(null),
                ),
                onDimChanged: controller.setWidgetBackgroundDim,
              ),

              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 20),

              const Divider(),
              const SizedBox(height: 20),

              // --- 识图导课: reading a timetable with a model over the network ---
              VisionImportSettings(settings: settings),

              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 20),

              // --- Tips --------------------------------------------------------
              Text(AppStrings.settingsSectionTips, style: text.titleMedium),
              const SizedBox(height: 8),
              for (final String tip in const <String>[
                AppStrings.tipReorder,
                AppStrings.tipSubtask,
                AppStrings.tipCalendar,
                AppStrings.tipAttachment,
                AppStrings.tipReminder,
                AppStrings.tipAppearance,
                AppStrings.tipAppBackground,
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.tips_and_updates_outlined,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(tip, style: text.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
