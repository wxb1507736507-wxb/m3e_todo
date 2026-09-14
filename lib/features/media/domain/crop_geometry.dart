import 'dart:math' as math;
import 'dart:ui';

/// Geometry of "show an image inside a fixed crop window, let the user pan and
/// zoom, then cut out what the window sees".
///
/// Pure maths, deliberately separate from the widget: this is the part of
/// cropping that can be silently wrong — an off-by-one scale factor produces an
/// image that is merely *slightly* mis-framed, which no screenshot review would
/// catch — so it is the part that gets unit tests
/// (`test/features/media/domain/crop_geometry_test.dart`).
///
/// Coordinate systems, because mixing them up is the other easy mistake:
///
///  * **image pixels** — the decoded image's own size, origin at its top-left;
///  * **window coordinates** — logical pixels of the crop rectangle on screen,
///    origin at *its* top-left (not the page's);
///  * **child coordinates** — the image laid out at [childSize] inside the
///    window, i.e. image pixels multiplied by [effectiveScale].
///
/// [offset] is the child's top-left corner expressed in window coordinates, so
/// it is always `<= 0` on both axes once clamped: the child must cover the
/// window, never leave a gap.
class CropGeometry {
  const CropGeometry({
    required this.windowSize,
    required this.imageSize,
    this.scale = 1,
    this.offset = Offset.zero,
  });

  /// The crop window on screen.
  final Size windowSize;

  /// The decoded image's pixel dimensions.
  final Size imageSize;

  /// User zoom on top of the cover fit. `1` is "as large as needed to cover".
  final double scale;

  /// Child top-left in window coordinates.
  final Offset offset;

  /// How much the image is scaled to *cover* the window at [scale] = 1.
  ///
  /// Cover rather than contain: a crop window showing empty margins would let
  /// the user produce an image with transparent or black bands in it.
  double get baseScale => math.max(
        windowSize.width / imageSize.width,
        windowSize.height / imageSize.height,
      );

  /// Image pixels → child logical pixels.
  double get effectiveScale => baseScale * scale;

  /// The laid-out size of the image inside the window.
  Size get childSize => Size(
        imageSize.width * effectiveScale,
        imageSize.height * effectiveScale,
      );

  /// The offset that centres the image in the window.
  Offset get centredOffset => Offset(
        (windowSize.width - childSize.width) / 2,
        (windowSize.height - childSize.height) / 2,
      );

  /// The image's size expressed in child logical pixels, ignoring [offset].
  ///
  /// Used by the overlay to draw the crop frame corners.
  Rect get childRect => Rect.fromLTWH(
        offset.dx,
        offset.dy,
        childSize.width,
        childSize.height,
      );

  /// Clamps [candidate] so the child still covers the whole window.
  ///
  /// When the child is exactly as large as the window on an axis, that axis is
  /// pinned to the window's edge instead of being left free to drift.
  Offset clampOffset(Offset candidate) {
    final Size child = childSize;
    final double minDx = math.min(0, windowSize.width - child.width);
    final double minDy = math.min(0, windowSize.height - child.height);
    return Offset(
      candidate.dx.clamp(minDx, 0),
      candidate.dy.clamp(minDy, 0),
    );
  }

  /// Re-centres while keeping the zoom, used when the window changes shape
  /// (the user switches aspect ratio) so the image does not jump off-screen.
  CropGeometry withWindow(Size newWindow) {
    final CropGeometry resized = CropGeometry(
      windowSize: newWindow,
      imageSize: imageSize,
      scale: scale,
    );
    return resized.withOffset(resized.centredOffset);
  }

  CropGeometry withScale(double newScale) => CropGeometry(
        windowSize: windowSize,
        imageSize: imageSize,
        scale: newScale,
        offset: offset,
      );

  CropGeometry withOffset(Offset newOffset) => CropGeometry(
        windowSize: windowSize,
        imageSize: imageSize,
        scale: scale,
        offset: clampOffset(newOffset),
      );

  /// The part of the source image the window currently shows, in image pixels.
  ///
  /// This is exactly what gets drawn into the cropped output, so the preview and
  /// the result cannot disagree.
  Rect get sourceRect {
    final double scaleDenominator = effectiveScale;
    final Rect rect = Rect.fromLTWH(
      -offset.dx / scaleDenominator,
      -offset.dy / scaleDenominator,
      windowSize.width / scaleDenominator,
      windowSize.height / scaleDenominator,
    );
    return rect.intersect(Offset.zero & imageSize);
  }

  /// The source pixel under [viewportPoint].
  ///
  /// The inverse of [sourceRect]: the colour sampler needs to turn a tap into an
  /// image pixel, the cropper needs to turn the frame into a source rectangle,
  /// and both must agree on the same transform — which is why neither derives
  /// one of its own.
  Offset imagePointFor(Offset viewportPoint) {
    final Offset point = (viewportPoint - offset) / effectiveScale;
    return Offset(
      point.dx.clamp(0, imageSize.width),
      point.dy.clamp(0, imageSize.height),
    );
  }

  /// Output pixel size for [sourceRect], bounded so a crop of a 50 MP photo does
  /// not produce a 50 MP file.
  Size outputSize({double maxLongSide = 1440}) {
    final Rect source = sourceRect;
    final double longSide = math.max(source.width, source.height);
    final double factor = longSide > maxLongSide ? maxLongSide / longSide : 1;
    return Size(
      math.max(1, (source.width * factor).roundToDouble()),
      math.max(1, (source.height * factor).roundToDouble()),
    );
  }
}
