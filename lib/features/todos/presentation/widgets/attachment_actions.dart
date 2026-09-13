import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/platform/app_platform.dart';
import '../../domain/entities/todo_attachment.dart';
import '../providers/todo_providers.dart';

/// Whether file-backed widgets (image previews) are usable on this platform.
///
/// `dart:io` files do not exist on web, which is also where the native picker
/// is unavailable — so the two limits coincide.
bool get attachmentsSupported => !kIsWeb;

/// Picks a file of [kind] and returns it as a domain attachment, with the file
/// already copied into the app's private attachments directory by the native
/// side.
///
/// Returns `null` when the user cancelled or the platform cannot pick at all.
Future<TodoAttachment?> pickAndCreateAttachment(
  BuildContext context,
  WidgetRef ref,
  String kind,
) async {
  if (!attachmentsSupported) {
    return null;
  }
  final PickedAttachment? picked = await AppPlatform.pickAttachment(kind);
  if (picked == null) {
    return null;
  }
  return TodoAttachment(
    id: ref.read(idGeneratorProvider)(),
    type: TodoAttachment.typeOf(picked.mime, picked.name),
    path: picked.path,
    name: picked.name,
    mime: picked.mime,
  );
}

/// Runs the voice-recording dialog and returns the recording as an attachment,
/// or `null` when it was cancelled or nothing was captured.
Future<TodoAttachment?> recordVoiceAttachment(
  BuildContext context,
  WidgetRef ref,
) {
  return showDialog<TodoAttachment>(
    context: context,
    builder: (_) => const _VoiceRecordDialog(),
  );
}

/// A dialog that records a voice memo with an explicit start/stop, so the
/// user is always in control of what gets saved.
class _VoiceRecordDialog extends ConsumerStatefulWidget {
  const _VoiceRecordDialog();

  @override
  ConsumerState<_VoiceRecordDialog> createState() => _VoiceRecordDialogState();
}

class _VoiceRecordDialogState extends ConsumerState<_VoiceRecordDialog> {
  bool _recording = false;
  bool _starting = false;
  int _elapsedSeconds = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    // A dialog dismissed mid-recording must not leave the microphone hot.
    if (_recording) {
      unawaited(AppPlatform.stopVoiceRecording());
    }
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    bool granted = await AppPlatform.startVoiceRecording();
    // A fresh install has no `RECORD_AUDIO` grant, and the recorder refuses to
    // start without it. Ask (once) and retry, so the first tap on the mic
    // produces a permission dialog instead of a failure message the user
    // cannot act on.
    if (!granted) {
      await AppPlatform.requestAudioPermission();
      granted = await AppPlatform.startVoiceRecording();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _starting = false;
      _recording = granted;
      _elapsedSeconds = 0;
    });
    if (granted) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _elapsedSeconds++),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.voiceRecordFailed)),
      );
    }
  }

  Future<void> _finish({required bool keep}) async {
    _ticker?.cancel();
    final String? path = await AppPlatform.stopVoiceRecording();
    if (!mounted) {
      return;
    }
    TodoAttachment? result;
    if (keep && path != null) {
      result = TodoAttachment(
        id: ref.read(idGeneratorProvider)(),
        type: TodoAttachmentType.audio,
        path: path,
        name: AppStrings.attachVoice,
        mime: 'audio/mp4',
      );
    } else if (!keep && path != null) {
      // Cancelled: delete the partial recording so nothing is left behind.
      unawaited(File(path).delete().catchError((Object _) => File(path)));
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.attachVoice),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _recording ? Icons.mic : Icons.mic_none,
            size: 48,
            color: _recording ? Theme.of(context).colorScheme.error : null,
          ),
          const SizedBox(height: 12),
          Text(
            _recording
                ? '${AppStrings.voiceRecording} '
                    '${(_elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:'
                    '${(_elapsedSeconds % 60).toString().padLeft(2, '0')}'
                : AppStrings.voiceRecordStart,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _starting ? null : () => unawaited(_finish(keep: false)),
          child: const Text(AppStrings.voiceRecordCancel),
        ),
        if (!_recording)
          FilledButton.icon(
            onPressed: _starting ? null : () => unawaited(_start()),
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text(AppStrings.voiceRecordStart),
          )
        else
          FilledButton.icon(
            onPressed: () => unawaited(_finish(keep: true)),
            icon: const Icon(Icons.stop),
            label: const Text(AppStrings.voiceRecordStop),
          ),
      ],
    );
  }
}

/// Small square preview for an image attachment; other types get a type icon.
///
/// Images decode at thumbnail size ([cacheWidth]) rather than at full sensor
/// resolution: on a low-end phone, decoding ten 12-megapixel photos for
/// 56dp-wide previews is the difference between a smooth scroll and a janky
/// one.
class AttachmentThumb extends StatelessWidget {
  const AttachmentThumb({required this.attachment, this.size = 56, super.key});

  final TodoAttachment attachment;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget child = attachment.type == TodoAttachmentType.image &&
            attachmentsSupported
        ? Image.file(
            File(attachment.path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 2).round(),
            errorBuilder: (_, _, _) => _icon(colors),
          )
        : _icon(colors);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _icon(ColorScheme colors) => Container(
        width: size,
        height: size,
        color: colors.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(_iconFor(attachment.type), color: colors.onSurfaceVariant),
      );

  static IconData _iconFor(TodoAttachmentType type) => switch (type) {
        TodoAttachmentType.image => Icons.image_outlined,
        TodoAttachmentType.video => Icons.videocam_outlined,
        TodoAttachmentType.audio => Icons.graphic_eq,
        TodoAttachmentType.document => Icons.description_outlined,
      };
}
