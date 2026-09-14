import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/media/domain/crop_geometry.dart';

void main() {
  // A wide source image against a square window: the interesting case, because
  // covering means it overflows horizontally and the user can pan sideways.
  const Size image = Size(4000, 2000);
  const Size window = Size(300, 300);

  CropGeometry geometry({
    Size windowSize = window,
    Size imageSize = image,
    double scale = 1,
    Offset offset = Offset.zero,
  }) {
    return CropGeometry(
      windowSize: windowSize,
      imageSize: imageSize,
      scale: scale,
      offset: offset,
    );
  }

  group('cover fit', () {
    test('scales so the shorter side fills the window', () {
      // 2000px tall into a 300px window: 0.15. Scaling by width instead would
      // leave the window half empty vertically.
      expect(geometry().baseScale, 0.15);
      expect(geometry().childSize, const Size(600, 300));
    });

    test('centring hides an equal amount on both overflowing sides', () {
      final CropGeometry g = geometry();
      expect(g.centredOffset, const Offset(-150, 0));
      // 150 of 600 cropped on each side => the middle 300px of 4000 => 1/3 off
      // each edge (0.15 scale: 150 / 0.15 = 1000px of the source).
      expect(g.centredOffset.dx / g.effectiveScale, -1000);
    });

    test('a portrait image against a landscape window covers by height', () {
      final CropGeometry g = geometry(
        imageSize: const Size(2000, 4000),
        windowSize: const Size(400, 200),
      );
      // width 2000 -> 400 is 0.2; height 4000 -> 200 is 0.05. Cover takes 0.2,
      // i.e. the larger factor, so the image overflows vertically.
      expect(g.baseScale, 0.2);
      expect(g.childSize, const Size(400, 800));
    });
  });

  group('source rect', () {
    test('a centred square window takes the middle third of a 2:1 image', () {
      final CropGeometry g = geometry().withOffset(geometry().centredOffset);
      final Rect source = g.sourceRect;
      expect(source.left, closeTo(1000, 0.01));
      expect(source.width, closeTo(2000, 0.01));
      expect(source.height, closeTo(2000, 0.01));
      // Fully inside the image, vertically exactly the whole height.
      expect(source.top, closeTo(0, 0.01));
      expect(source.bottom, closeTo(2000, 0.01));
    });

    test('zooming in shrinks the source rect proportionally', () {
      final CropGeometry once = geometry(scale: 1).withOffset(const Offset(-150, 0));
      final CropGeometry twice = geometry(scale: 2).withOffset(const Offset(-300, 0));
      expect(twice.sourceRect.width, closeTo(once.sourceRect.width / 2, 0.01));
      expect(twice.sourceRect.height, closeTo(once.sourceRect.height / 2, 0.01));
    });

    test('panning to the left edge reports the left part of the image', () {
      // Offset 0 puts the child's left edge on the window's left edge.
      final Rect source = geometry().withOffset(Offset.zero).sourceRect;
      expect(source.left, closeTo(0, 0.01));
      expect(source.right, closeTo(2000, 0.01));
    });

    test('an out-of-range offset is clamped on the way in', () {
      // The constructor is a plain value holder; `withOffset` is what the
      // gesture handler uses, and it is what guarantees coverage.
      final CropGeometry g = geometry().withOffset(const Offset(50, 50));
      expect(g.offset, Offset.zero);
      expect(g.sourceRect, const Rect.fromLTWH(0, 0, 2000, 2000));
    });

    test('even an unclamped offset cannot report pixels outside the image', () {
      // Belt and braces: the intersection in `sourceRect` means a bad offset
      // degrades to a smaller crop rather than to transparent edges.
      final Rect source = geometry(offset: const Offset(5000, 5000)).sourceRect;
      expect(source.isEmpty, isTrue);
      expect(source.left, greaterThanOrEqualTo(0));
      expect(source.top, greaterThanOrEqualTo(0));
    });

    test('output size respects the window shape and the cap', () {
      final CropGeometry g = geometry().withOffset(geometry().centredOffset);
      // Source crop is 2000x2000 (square window) => capped to 1440 square.
      expect(g.outputSize(), const Size(1440, 1440));

      // A 2:1 image in a 2:1 window needs no cropping at all: cover fit is
      // 120/400 = 0.3 on both axes, so the window sees the whole 400x200 image.
      final CropGeometry sameShape = CropGeometry(
        windowSize: const Size(120, 60),
        imageSize: const Size(400, 200),
      ).withOffset(Offset.zero);
      expect(sameShape.sourceRect.size, const Size(400, 200));
      expect(sameShape.outputSize(), const Size(400, 200));

      // A square window over the same image does crop: 200x200 out of 400x200.
      final CropGeometry squareWindow = CropGeometry(
        windowSize: const Size(120, 120),
        imageSize: const Size(400, 200),
      ).withOffset(Offset.zero);
      expect(squareWindow.baseScale, 0.6);
      expect(squareWindow.sourceRect.size, const Size(200, 200));
    });
  });

  group('clamping', () {
    test('pins an axis that has no slack', () {
      // 2:1 image in a 2:1 window: no horizontal slack at all.
      final CropGeometry g = geometry(windowSize: const Size(300, 150));
      expect(g.childSize, const Size(300, 150));
      expect(g.clampOffset(const Offset(-40, -40)), Offset.zero);
    });

    test('keeps the child covering the window on a zoomed axis', () {
      final CropGeometry g = geometry(scale: 2);
      expect(g.childSize, const Size(1200, 600));
      final Offset clamped = g.clampOffset(const Offset(500, 500));
      expect(clamped, Offset.zero);
      final Offset clampedLeft = g.clampOffset(const Offset(-5000, -5000));
      expect(clampedLeft, const Offset(-900, -300));
    });
  });

  group('window changes', () {
    test('switching aspect ratio re-centres at the same zoom', () {
      final CropGeometry square = geometry().withOffset(const Offset(-300, 0));
      final CropGeometry wide = square.withWindow(const Size(600, 300));
      expect(wide.scale, square.scale);
      expect(wide.childSize, const Size(600, 300));
      expect(wide.offset, Offset.zero);
      expect(wide.sourceRect.size, const Size(4000, 2000));
    });
  });

  group('viewport point to image pixel (colour extraction)', () {
    test('is the inverse of the visible source rect', () {
      final CropGeometry g = geometry().withOffset(geometry().centredOffset);
      // The window's top-left must map to the source rect's top-left, and its
      // bottom-right to the source rect's bottom-right.
      final Offset topLeft = g.imagePointFor(Offset.zero);
      expect(topLeft.dx, closeTo(g.sourceRect.left, 0.01));
      expect(topLeft.dy, closeTo(g.sourceRect.top, 0.01));
      final Offset bottomRight =
          g.imagePointFor(Offset(g.windowSize.width, g.windowSize.height));
      expect(bottomRight.dx, closeTo(g.sourceRect.right, 0.01));
      expect(bottomRight.dy, closeTo(g.sourceRect.bottom, 0.01));
    });

    test('the centre of the window maps to the centre of the crop', () {
      final CropGeometry g = geometry().withOffset(geometry().centredOffset);
      final Offset centre = g.imagePointFor(
        Offset(g.windowSize.width / 2, g.windowSize.height / 2),
      );
      expect(centre.dx, closeTo(g.sourceRect.center.dx, 0.01));
      expect(centre.dy, closeTo(g.sourceRect.center.dy, 0.01));
    });

    test('zooming in makes the same tap select a nearer pixel', () {
      final CropGeometry once = geometry().withOffset(const Offset(-150, 0));
      final CropGeometry twice =
          geometry(scale: 2).withOffset(const Offset(-300, 0));
      final double atOnce = once.imagePointFor(const Offset(10, 0)).dx;
      final double atTwice = twice.imagePointFor(const Offset(10, 0)).dx;
      expect(atTwice, lessThan(atOnce));
      // Halving the covered source distance per viewport pixel is the whole
      // point of zooming for precision.
      expect(atOnce - 1000, closeTo((atTwice - 1000) * 2, 0.01));
    });

    test('a tap outside the image is clamped, never negative', () {
      final CropGeometry g = geometry().withOffset(Offset.zero);
      expect(g.imagePointFor(const Offset(-500, -500)), Offset.zero);
      final Offset far = g.imagePointFor(const Offset(99999, 99999));
      expect(far.dx, 4000);
      expect(far.dy, 2000);
    });
  });
}
