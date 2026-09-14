import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/platform/app_platform.dart';
import '../../media/presentation/image_crop_page.dart';
import '../domain/app_settings.dart';
import 'appearance_sheet.dart';
import 'settings_controller.dart';

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
    final CroppedImage? cropped = await pickAndCropImage(
      context,
      initialAspect: CropAspect.screen,
    );
    if (cropped == null) {
      return;
    }
    await ref.read(settingsProvider.notifier).setBackgroundImage(cropped.path);
  }

  Future<void> _recropBackground() async {
    final String? current = ref.read(settingsProvider).backgroundImage;
    if (current == null) {
      return;
    }
    final CroppedImage? cropped = await cropImage(
      context,
      sourcePath: current,
      initialAspect: CropAspect.screen,
    );
    if (cropped == null) {
      return;
    }
    await ref.read(settingsProvider.notifier).setBackgroundImage(cropped.path);
  }

  Future<void> _removeBackground() =>
      ref.read(settingsProvider.notifier).setBackgroundImage(null);

  /// Background image picker, preview, crop and scrim strength.
  Widget _buildBackgroundControls(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final String? path = settings.backgroundImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (path != null && AppPlatform.isAndroid)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    // A 56dp thumbnail does not need a 1440px decode.
                    cacheWidth: 160,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            if (path != null && AppPlatform.isAndroid) const SizedBox(width: 12),
            Expanded(
              child: Text(
                path == null
                    ? AppStrings.appBackgroundNone
                    : AppStrings.backgroundImageLabel,
                style: text.bodyMedium?.copyWith(
                  color: path == null ? colors.onSurfaceVariant : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: () => unawaited(_pickBackground()),
              icon: const Icon(Icons.image_outlined),
              label: Text(
                path == null
                    ? AppStrings.appBackgroundPick
                    : AppStrings.appBackgroundChange,
              ),
            ),
            if (path != null)
              OutlinedButton.icon(
                onPressed: () => unawaited(_recropBackground()),
                icon: const Icon(Icons.crop),
                label: const Text(AppStrings.cropBackgroundImage),
              ),
            if (path != null)
              TextButton.icon(
                onPressed: () => unawaited(_removeBackground()),
                icon: const Icon(Icons.delete_outline),
                label: const Text(AppStrings.appBackgroundRemove),
              ),
          ],
        ),
        if (path != null) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Text(AppStrings.backgroundDimLabel, style: text.labelLarge),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: settings.backgroundDim,
                  max: 0.9,
                  divisions: 18,
                  label: AppStrings.backgroundDimValue(
                    (settings.backgroundDim * 100).round(),
                  ),
                  onChanged: controller.setBackgroundDim,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  AppStrings.backgroundDimValue(
                    (settings.backgroundDim * 100).round(),
                  ),
                  style: text.labelMedium,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ],
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
