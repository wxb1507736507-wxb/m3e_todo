import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Paints the user's application background behind [child].
///
/// Three layers, in this order, and each one earns its place:
///
///  1. an opaque theme surface, so the frame is *never* see-through — not while
///     the photo decodes on the first frame, and not if it has been deleted
///     behind the app's back, which would otherwise leave the window's raw
///     background showing;
///  2. the photo itself, drawn `cover` so no letterboxing appears at any window
///     shape;
///  3. a scrim of the surface colour at the user's chosen strength, which is
///     what keeps body text legible over an arbitrary picture.
///
/// The `child` (the app's `Scaffold`, with its own transparent background) then
/// draws on top, so this widget owns exactly one decision: what is behind
/// everything.
class AppBackground extends StatelessWidget {
  const AppBackground({
    required this.imagePath,
    required this.dim,
    required this.child,
    super.key,
  });

  /// Path to the private copy of the background, or `null` for none.
  final String? imagePath;

  /// Strength of the scrim, in `[0, 1]`.
  final double dim;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final String? path = imagePath;
    // `Image.file` needs dart:io, and the picker that produces these images is
    // native-only, so web simply keeps the plain surface.
    if (path == null || kIsWeb) {
      return child;
    }
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: colors.surface),
        // One cached layer for the whole backdrop, and it is worth being
        // explicit about why: without this boundary the backdrop shares a layer
        // with the list, so scrolling re-rasterises a full-screen filtered image
        // on every frame. Measured on the Android 13 device with a 1440x1440
        // background, that showed up as a 17.7ms raster spike on the first
        // scrolled frames while the Dart build was only 0.27ms — the tell-tale
        // signature of work that belongs in its own layer.
        RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.file(
                File(path),
                fit: BoxFit.cover,
                // Decode at the size it will be drawn: the cropper caps images
                // at 1440px, but on a narrow phone screen that is still more
                // than twice the pixels needed, and every extra pixel is decode
                // time plus texture memory.
                cacheWidth: _decodeWidth(context),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              if (dim > 0)
                ColoredBox(
                  color: colors.surface.withValues(alpha: dim.clamp(0.0, 1.0)),
                ),
            ],
          ),
        ),
        child,
      ],
    );
  }

  /// Width, in physical pixels, the backdrop is actually displayed at.
  int _decodeWidth(BuildContext context) {
    final double logical = MediaQuery.sizeOf(context).width;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return (logical * dpr).clamp(360, 2048).round();
  }
}
