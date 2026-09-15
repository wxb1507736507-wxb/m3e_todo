import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/platform/app_platform.dart';
import '../../../media/presentation/image_crop_page.dart';

/// Picks a picture for a background and returns the app's own copy of it.
///
/// Cropped on the way in, because every background in this app is drawn `cover`
/// across a screen-shaped surface: an uncropped photo would be scaled down to
/// its middle band and lose the composition the user picked.
Future<String?> pickBackgroundImage(BuildContext context) async {
  final CroppedImage? cropped = await pickAndCropImage(
    context,
    initialAspect: CropAspect.screen,
  );
  return cropped?.path;
}

/// Re-crops a background the user already chose, returning the new copy.
Future<String?> recropBackgroundImage(BuildContext context, String path) async {
  final CroppedImage? cropped = await cropImage(
    context,
    sourcePath: path,
    initialAspect: CropAspect.screen,
  );
  return cropped?.path;
}

/// The controls every background in the app is set with.
///
/// One widget rather than one per surface: the app's background, the
/// timetable's and a course's are the same four decisions — a picture, its
/// crop, its removal, and how strongly the surface covers it — and three copies
/// of them would drift apart the first time one of them was touched.
class BackgroundControls extends StatelessWidget {
  const BackgroundControls({
    required this.imagePath,
    required this.dim,
    required this.onPick,
    required this.onRecrop,
    required this.onRemove,
    required this.onDimChanged,
    super.key,
  });

  /// The picture in use, or `null` when the surface is left plain.
  final String? imagePath;

  /// How strongly the surface colour covers the picture, in `[0, maxDim]`.
  final double dim;

  final VoidCallback onPick;
  final VoidCallback onRecrop;
  final VoidCallback onRemove;
  final ValueChanged<double> onDimChanged;

  /// The scrim stops short of opaque.
  ///
  /// At 100% the picture is not a background any more, it is a picture nobody
  /// can see — and the way back to it would be a slider the user has to
  /// remember is there.
  static const double maxDim = 0.9;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final String? path = imagePath;

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
              onPressed: onPick,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                path == null
                    ? AppStrings.appBackgroundPick
                    : AppStrings.appBackgroundChange,
              ),
            ),
            if (path != null)
              OutlinedButton.icon(
                onPressed: onRecrop,
                icon: const Icon(Icons.crop),
                label: const Text(AppStrings.cropBackgroundImage),
              ),
            if (path != null)
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text(AppStrings.appBackgroundRemove),
              ),
          ],
        ),
        // The scrim only means something under a picture, and it is the control
        // that keeps text readable over an arbitrary one.
        if (path != null) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Text(AppStrings.backgroundDimLabel, style: text.labelLarge),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: dim.clamp(0.0, maxDim),
                  max: maxDim,
                  divisions: 18,
                  label: AppStrings.backgroundDimValue((dim * 100).round()),
                  onChanged: onDimChanged,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  AppStrings.backgroundDimValue((dim * 100).round()),
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
}
