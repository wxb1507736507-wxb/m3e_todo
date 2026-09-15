import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../timetable/data/vision_import_client.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../domain/app_settings.dart';
import '../settings_controller.dart';

/// The network reader's settings: which provider, which model, whose key.
///
/// One section rather than four loose settings, because the four are one
/// decision — "read my timetables with a model" — and a half-filled decision is
/// a recognition attempt against an address with no model behind it. The test
/// button exists for the same reason: getting a key, an address and a model name
/// all right is the whole difficulty, and finding out at the moment a photo is
/// waiting is the worst time to find out.
class VisionImportSettings extends ConsumerStatefulWidget {
  const VisionImportSettings({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<VisionImportSettings> createState() =>
      _VisionImportSettingsState();
}

class _VisionImportSettingsState extends ConsumerState<VisionImportSettings> {
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.settings.visionBaseUrl ?? '');
  late final TextEditingController _model =
      TextEditingController(text: widget.settings.visionModel ?? '');
  late final TextEditingController _apiKey =
      TextEditingController(text: widget.settings.visionApiKey ?? '');

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  bool _obscure = true;

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(settingsProvider.notifier).setVisionImport(
          baseUrl: _baseUrl.text.trim(),
          model: _model.text.trim(),
          apiKey: _apiKey.text.trim(),
        );
  }

  void _applyPreset(VisionProvider provider) {
    setState(() {
      _baseUrl.text = provider.baseUrl;
      _model.text = provider.model;
      _testResult = null;
    });
    _save();
  }

  Future<void> _test() async {
    _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final SettingsController controller = ref.read(settingsProvider.notifier);

    // A tiny picture made of nothing: the test is about the address, the key and
    // the model name being accepted, and asking to read a real timetable would
    // cost the user money to answer a question that is not about the timetable.
    const String probe = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';
    final String path = await _writeProbe(probe);

    try {
      await ref.read(visionCompleteProvider)(
        VisionRequest(
          baseUrl: _baseUrl.text.trim(),
          apiKey: _apiKey.text.trim(),
          model: _model.text.trim(),
          prompt: '这是一张 1x1 的图片。请只回答 {}',
          imagePath: path,
          timeout: const Duration(seconds: 45),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _testing = false;
        _testOk = true;
        _testResult = AppStrings.visionTestOk;
      });
      // A test that worked is also the moment to switch the reader on: the user
      // has just proved it can work, and asking them to flip a switch next would
      // be asking twice.
      controller.setVisionImport(enabled: true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _testing = false;
        _testOk = false;
        _testResult = AppStrings.visionTestFailed('$error');
      });
    } finally {
      await _deleteQuietly(path);
      if (mounted) {
        controller.setVisionImport(
          baseUrl: _baseUrl.text.trim(),
          model: _model.text.trim(),
          apiKey: _apiKey.text.trim(),
        );
      }
    }
  }

  /// Writes the one-pixel probe into the app's own directory.
  Future<String> _writeProbe(String base64Png) async {
    final Directory directory = Directory.systemTemp;
    final File file = File(
      '${directory.path}${Platform.pathSeparator}m3e_vision_probe.png',
    );
    await file.writeAsBytes(base64Decode(base64Png));
    return file.path;
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on Object {
      // Nothing to clean up is not a problem.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final AppSettings settings = ref.watch(settingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(AppStrings.visionSectionTitle, style: text.titleMedium),
        const SizedBox(height: 2),
        Text(
          AppStrings.visionEnabledHint,
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.visionImportEnabled,
          onChanged: (bool value) {
            ref.read(settingsProvider.notifier).setVisionImport(enabled: value);
          },
          title: const Text(AppStrings.visionEnabledLabel),
        ),
        const SizedBox(height: 4),
        Text(AppStrings.visionProviderLabel, style: text.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final VisionProvider provider in visionProviders)
              ChoiceChip(
                label: Text(provider.name),
                selected:
                    settings.visionBaseUrl == provider.baseUrl &&
                        provider.baseUrl.isNotEmpty,
                onSelected: (_) => _applyPreset(provider),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _baseUrl,
          onSubmitted: (_) => _save(),
          onTapOutside: (_) => _save(),
          decoration: const InputDecoration(
            labelText: AppStrings.visionBaseUrlLabel,
            hintText: AppStrings.visionBaseUrlHint,
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _model,
          onSubmitted: (_) => _save(),
          onTapOutside: (_) => _save(),
          decoration: const InputDecoration(
            labelText: AppStrings.visionModelLabel,
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _apiKey,
          obscureText: _obscure,
          onSubmitted: (_) => _save(),
          onTapOutside: (_) => _save(),
          decoration: InputDecoration(
            labelText: AppStrings.visionApiKeyLabel,
            helperText: AppStrings.visionApiKeyHint,
            isDense: true,
            suffixIcon: IconButton(
              tooltip: _obscure ? '显示' : '隐藏',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: _testing ? null : () => unawaited(_test()),
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(
                _testing ? AppStrings.visionTestRunning : AppStrings.visionTest,
              ),
            ),
            const SizedBox(width: 12),
            if (_testResult != null)
              Expanded(
                child: Text(
                  _testResult!,
                  style: text.bodySmall?.copyWith(
                    color: _testOk ? colors.primary : colors.error,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
