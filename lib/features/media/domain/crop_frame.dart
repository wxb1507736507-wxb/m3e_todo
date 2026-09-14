import 'dart:math' as math;
import 'dart:ui';

/// Geometry of "show the whole photo, let the user frame the part to keep".
///
/// The cropper used to work the other way round: a fixed window filled the
/// screen and the *image* moved behind it, which meant the user could never see
/// what they were cutting away and could only trim the edges of a rectangle
/// whose shape the app had already chosen. Here the image is fitted whole onto
/// the screen and the frame is drawn on top of it, so the frame is the thing the
/// user drags — which is what "select the part I want" means.
///
/// Pure maths, deliberately separate from the widget: the parts that go wrong
/// silently are the transform and the resize rules, and both are unit-tested
/// (`test/features/media/domain/crop_frame_test.dart`) rather than eyeballed.
///
/// Coordinate systems, because mixing them up is the easy mistake:
///
///  * **image pixels** — the decoded image's own size, origin at its top-left;
///    the frame lives here, so it survives zooming and panning untouched;
///  * **viewport coordinates** — logical pixels of the box the image is drawn
///    in, origin at *its* top-left.
class CropView {
  const CropView({
    required this.viewportSize,
    required this.imageSize,
    this.zoom = 1,
    this.offset = Offset.zero,
  });

  /// The box the image is drawn in.
  final Size viewportSize;

  /// The decoded image's pixel dimensions.
  final Size imageSize;

  /// User zoom on top of the fit. `1` shows the whole image.
  final double zoom;

  /// Where the image's top-left corner sits, in viewport coordinates.
  final Offset offset;

  /// How much the image is scaled to *fit* the viewport at [zoom] = 1.
  ///
  /// Fit rather than cover: the frame is chosen by eye over the whole picture,
  /// so the picture has to be whole on screen. The empty margins that leaves are
  /// dimmed by the overlay, not cropped into the result.
  double get fitScale => math.min(
        viewportSize.width / imageSize.width,
        viewportSize.height / imageSize.height,
      );

  /// Image pixels → viewport logical pixels.
  double get effectiveScale => fitScale * zoom;

  /// The size the image is drawn at.
  Size get displaySize => Size(
        imageSize.width * effectiveScale,
        imageSize.height * effectiveScale,
      );

  /// The offset that centres the image in the viewport.
  Offset get centredOffset => Offset(
        (viewportSize.width - displaySize.width) / 2,
        (viewportSize.height - displaySize.height) / 2,
      );

  /// Where the image is drawn, in viewport coordinates.
  Rect get displayRect => offset & displaySize;

  /// Clamps [candidate] so the image cannot be pushed out of sight.
  ///
  /// An image that is smaller than the viewport on an axis is pinned to the
  /// centre of it rather than left free to drift; a larger one is clamped to the
  /// viewport's edges, so panning never opens a gap at a side.
  Offset clampOffset(Offset candidate) {
    final Size display = displaySize;
    double axis(double value, double viewport, double shown) {
      if (shown <= viewport) {
        return (viewport - shown) / 2;
      }
      return value.clamp(viewport - shown, 0.0);
    }

    return Offset(
      axis(candidate.dx, viewportSize.width, display.width),
      axis(candidate.dy, viewportSize.height, display.height),
    );
  }

  /// An image point in viewport coordinates.
  Offset toViewport(Offset imagePoint) => imagePoint * effectiveScale + offset;

  /// A viewport point in image coordinates.
  ///
  /// Not clamped: the inverse is also used mid-gesture, where the finger may
  /// legitimately be outside the picture — the callers clamp what they build
  /// from it.
  Offset toImage(Offset viewportPoint) =>
      (viewportPoint - offset) / effectiveScale;

  /// An image rectangle in viewport coordinates.
  Rect viewportRect(Rect imageRect) => Rect.fromPoints(
        toViewport(imageRect.topLeft),
        toViewport(imageRect.bottomRight),
      );

  CropView withZoom(double newZoom) => CropView(
        viewportSize: viewportSize,
        imageSize: imageSize,
        zoom: newZoom,
        offset: offset,
      );

  CropView withOffset(Offset newOffset) => CropView(
        viewportSize: viewportSize,
        imageSize: imageSize,
        zoom: zoom,
        offset: clampOffset(newOffset),
      );
}

/// Which corner of the frame a drag has hold of.
enum CropHandle { topLeft, topRight, bottomLeft, bottomRight }

/// Smallest frame a drag may leave behind, in viewport logical pixels.
///
/// In viewport pixels rather than image pixels on purpose: it is the size that
/// feels grabbable under a finger, and the same frame is the same size to hold
/// whatever the picture's resolution.
const double kCropMinSide = 44;

/// The largest rectangle of [aspect] that fits in [bounds], centred on it.
///
/// [aspect] is width ÷ height. A rectangle taller than the bounds is trimmed by
/// its height instead, so the result is inside [bounds] and keeps the shape.
Rect centredRectIn(Rect bounds, double aspect) {
  double width = bounds.width;
  double height = width / aspect;
  if (height > bounds.height) {
    height = bounds.height;
    width = height * aspect;
  }
  return Rect.fromCenter(
    center: bounds.center,
    width: width,
    height: height,
  );
}

/// Moves [rect] by [delta] without letting it leave [bounds].
Rect translateRect(Rect rect, Offset delta, Rect bounds) {
  final double maxLeft = math.max(bounds.left, bounds.right - rect.width);
  final double maxTop = math.max(bounds.top, bounds.bottom - rect.height);
  return Rect.fromLTWH(
    (rect.left + delta.dx).clamp(bounds.left, maxLeft),
    (rect.top + delta.dy).clamp(bounds.top, maxTop),
    rect.width,
    rect.height,
  );
}

/// Where the grip for [handle] sits on [rect].
///
/// The corner the finger has to land on — which is *not* the same thing as
/// [anchorFor], the corner that stays put while it is dragged. Confusing the two
/// is a two-line mistake with a very visible result: dragging the bottom-right
/// grip resizes the frame from its top-left instead, and the frame never ends up
/// where the finger went.
Offset cornerFor(CropHandle handle, Rect rect) => switch (handle) {
      CropHandle.topLeft => rect.topLeft,
      CropHandle.topRight => rect.topRight,
      CropHandle.bottomLeft => rect.bottomLeft,
      CropHandle.bottomRight => rect.bottomRight,
    };

/// The corner that stays put while [handle] is dragged.
Offset anchorFor(CropHandle handle, Rect rect) =>
    cornerFor(_opposite(handle), rect);

CropHandle _opposite(CropHandle handle) => switch (handle) {
      CropHandle.topLeft => CropHandle.bottomRight,
      CropHandle.topRight => CropHandle.bottomLeft,
      CropHandle.bottomLeft => CropHandle.topRight,
      CropHandle.bottomRight => CropHandle.topLeft,
    };

/// The frame that results from dragging [handle] of [rect] to [point].
///
/// [aspect] locks the shape (width ÷ height); `null` leaves the drag free.
/// [minSide] is in image pixels and stops a frame from collapsing to a line when
/// the finger is dragged past the opposite corner: dragging "through" the anchor
/// pins the size to the minimum instead of flipping the frame inside out.
///
/// The result is always inside [bounds], because the anchor is inside it and the
/// growth in each direction is trimmed to the room the bounds leave.
Rect resizeRect({
  required Rect rect,
  required CropHandle handle,
  required Offset point,
  required Rect bounds,
  double? aspect,
  double minSide = 1,
}) {
  final Offset anchor = anchorFor(handle, rect);
  // Outward directions of this handle: the same code then serves all four.
  final double signX =
      handle == CropHandle.topLeft || handle == CropHandle.bottomLeft ? -1 : 1;
  final double signY =
      handle == CropHandle.topLeft || handle == CropHandle.topRight ? -1 : 1;

  double width = (point.dx - anchor.dx) * signX;
  double height = (point.dy - anchor.dy) * signY;

  // Room left on the dragged side; the frame may not grow past it.
  final double roomX = signX > 0 ? bounds.right - anchor.dx : anchor.dx - bounds.left;
  final double roomY = signY > 0 ? bounds.bottom - anchor.dy : anchor.dy - bounds.top;

  if (aspect == null) {
    // Free: the two sides are independent, so each one simply stops at the edge
    // it is heading for. Scaling both down to fit would be wrong here — dragging
    // the corner into a corner of the picture should reach that corner.
    width = width.clamp(0.0, roomX);
    height = height.clamp(0.0, roomY);
    // Still worth holding onto, but never at the cost of leaving the picture.
    width = math.max(width, math.min(minSide, roomX));
    height = math.max(height, math.min(minSide, roomY));
  } else {
    // Follow whichever axis the finger pulled further, so the frame tracks the
    // finger instead of lagging behind on the other one.
    if (width / aspect >= height) {
      height = width / aspect;
    } else {
      width = height * aspect;
    }
    width = math.max(width, minSide);
    height = width / aspect;
    // A locked shape has to give up both sides together, so it is scaled down
    // until it fits.
    final double shrink = math.min(
      1,
      math.max(0, math.min(roomX / width, roomY / height)),
    );
    width *= shrink;
    height *= shrink;
  }

  return Rect.fromPoints(
    anchor,
    anchor + Offset(signX * width, signY * height),
  );
}

/// The frame a free-hand drag from [from] to [to] describes.
///
/// Used for "drag anywhere to draw the part you want": the start of the drag is
/// the corner that stays put, so the frame grows in whichever direction the
/// finger goes.
Rect drawRect({
  required Offset from,
  required Offset to,
  required Rect bounds,
  double? aspect,
  double minSide = 1,
}) {
  final Offset start = _clampPoint(from, bounds);
  // A degenerate rectangle at the start picks the handle whose anchor is that
  // corner, which is exactly the corner a drag from here should keep still.
  final Rect pivot = Rect.fromLTWH(start.dx, start.dy, 0, 0);
  final CropHandle handle = switch ((to.dx >= start.dx, to.dy >= start.dy)) {
    (true, true) => CropHandle.bottomRight,
    (false, true) => CropHandle.bottomLeft,
    (true, false) => CropHandle.topRight,
    (false, false) => CropHandle.topLeft,
  };
  return resizeRect(
    rect: pivot,
    handle: handle,
    point: _clampPoint(to, bounds),
    bounds: bounds,
    aspect: aspect,
    minSide: minSide,
  );
}

Offset _clampPoint(Offset point, Rect bounds) => Offset(
      point.dx.clamp(bounds.left, bounds.right),
      point.dy.clamp(bounds.top, bounds.bottom),
    );

/// Output pixel size for a crop of [source], bounded so that cropping a corner
/// of a 50 MP photo does not produce a 50 MP file.
Size outputSizeFor(Rect source, {double maxLongSide = 1440}) {
  final double longSide = math.max(source.width, source.height);
  final double factor = longSide > maxLongSide ? maxLongSide / longSide : 1;
  return Size(
    math.max(1, (source.width * factor).roundToDouble()),
    math.max(1, (source.height * factor).roundToDouble()),
  );
}

/// The whole-pixel rectangle to read out of an image of [imageSize] for a frame
/// drawn as [frame].
///
/// Rounded outwards and clamped to the picture: a frame drawn by hand lands on
/// fractional pixels, and reading a half pixel would either blur the edge or, at
/// the border, index past the end of the image.
Rect sourceRectFor(Rect frame, Size imageSize) {
  final Rect bounds = Offset.zero & imageSize;
  final Rect pixels = Rect.fromLTRB(
    frame.left.floorToDouble(),
    frame.top.floorToDouble(),
    frame.right.ceilToDouble(),
    frame.bottom.ceilToDouble(),
  );
  return pixels.intersect(bounds);
}
