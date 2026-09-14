import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/media/domain/crop_frame.dart';

/// The picture the cropper works on: 1000×500, twice as wide as it is tall.
Rect get _bounds => const Rect.fromLTWH(0, 0, 1000, 500);

void main() {
  group('CropView', () {
    const CropView view = CropView(
      viewportSize: Size(400, 400),
      imageSize: Size(1000, 500),
    );

    test('fits the whole picture, leaving the margins empty', () {
      // Contain, not cover: half of a wide picture would be off-screen if the
      // picture had to fill the viewport, and the user cannot frame what they
      // cannot see.
      expect(view.fitScale, 0.4);
      expect(view.displaySize, const Size(400, 200));
      expect(view.centredOffset, const Offset(0, 100));
      expect(
        view.withOffset(view.centredOffset).displayRect,
        const Rect.fromLTWH(0, 100, 400, 200),
      );
    });

    test('maps image points to the viewport and back', () {
      final CropView centred = view.withOffset(view.centredOffset);
      expect(centred.toViewport(Offset.zero), const Offset(0, 100));
      // The middle of the picture is the middle of the viewport.
      expect(centred.toViewport(const Offset(500, 250)), const Offset(200, 200));
      expect(centred.toImage(const Offset(200, 200)), const Offset(500, 250));
      for (final Offset point in <Offset>[
        Offset.zero,
        const Offset(137, 402),
        const Offset(1000, 500),
      ]) {
        final Offset round = centred.toImage(centred.toViewport(point));
        expect(round.dx, closeTo(point.dx, 0.001));
        expect(round.dy, closeTo(point.dy, 0.001));
      }
    });

    test('zooming keeps the point under the fingers still', () {
      final CropView start = view.withOffset(view.centredOffset);
      final Offset focal = const Offset(300, 150);
      final Offset underFingers = start.toImage(focal);

      // Zoomed far enough that the picture is bigger than the viewport on both
      // axes — otherwise the clamp would pin an axis and the anchor could not
      // hold on it.
      final CropView zoomed = start.withZoom(3);
      final Offset offset = focal - underFingers * zoomed.effectiveScale;
      final CropView moved = zoomed.withOffset(offset);

      final Offset after = moved.toViewport(underFingers);
      expect(after.dx, closeTo(focal.dx, 0.001));
      expect(after.dy, closeTo(focal.dy, 0.001));
      expect(moved.effectiveScale, closeTo(1.2, 0.0001));
    });

    test('a picture smaller than the viewport is pinned to the centre', () {
      // Otherwise it could be dragged into a corner, which looks like a bug.
      expect(
        view.withOffset(const Offset(-500, -500)).offset,
        const Offset(0, 100),
      );
      expect(view.withOffset(const Offset(500, 500)).offset, const Offset(0, 100));
    });

    test('a zoomed picture cannot be dragged off the viewport', () {
      final CropView zoomed = view.withZoom(3);
      // Compared with a tolerance: 0.4 × 3 is not exactly 1.2 in binary.
      expect(zoomed.displaySize.width, closeTo(1200, 0.001));
      expect(zoomed.displaySize.height, closeTo(600, 0.001));
      // Panning is only allowed until an edge of the picture reaches an edge of
      // the viewport; past that a gap would open up.
      expect(zoomed.withOffset(const Offset(50, 50)).offset, Offset.zero);
      final Offset far = zoomed.withOffset(const Offset(-9999, -9999)).offset;
      expect(far.dx, closeTo(-800, 0.001));
      expect(far.dy, closeTo(-200, 0.001));
      expect(
        zoomed.withOffset(const Offset(-100, -30)).offset,
        const Offset(-100, -30),
      );
      // An axis that is exactly as large as the viewport is pinned instead of
      // being left free to drift.
      expect(view.withZoom(2).withOffset(const Offset(-100, -30)).offset,
          const Offset(-100, 0));
    });

    test('rectangles survive the round trip to the viewport', () {
      final CropView centred = view.withOffset(view.centredOffset);
      expect(
        centred.viewportRect(const Rect.fromLTWH(100, 100, 200, 100)),
        const Rect.fromLTWH(40, 140, 80, 40),
      );
    });
  });

  group('frame shapes', () {
    test('a shaped frame is the largest that fits, and stays inside', () {
      expect(centredRectIn(_bounds, 1), const Rect.fromLTWH(250, 0, 500, 500));

      final Rect wide = centredRectIn(_bounds, 16 / 9);
      expect(wide.width, closeTo(888.9, 0.1));
      expect(wide.height, 500);
      expect(wide.center.dx, closeTo(_bounds.center.dx, 0.001));
      expect(wide.center.dy, closeTo(_bounds.center.dy, 0.001));

      // A shape wider than the picture is trimmed by its width instead.
      final Rect veryWide = centredRectIn(_bounds, 4);
      expect(veryWide.width, 1000);
      expect(veryWide.height, 250);
      for (final Rect rect in <Rect>[wide, veryWide]) {
        expect(rect.left, greaterThanOrEqualTo(_bounds.left));
        expect(rect.top, greaterThanOrEqualTo(_bounds.top));
        expect(rect.right, lessThanOrEqualTo(_bounds.right));
        expect(rect.bottom, lessThanOrEqualTo(_bounds.bottom));
      }
    });
  });

  group('moving the frame', () {
    const Rect frame = Rect.fromLTWH(100, 100, 300, 200);

    test('moves by the drag', () {
      expect(
        translateRect(frame, const Offset(50, -30), _bounds),
        const Rect.fromLTWH(150, 70, 300, 200),
      );
    });

    test('stops at the edges of the picture', () {
      expect(
        translateRect(frame, const Offset(-999, -999), _bounds),
        const Rect.fromLTWH(0, 0, 300, 200),
      );
      expect(
        translateRect(frame, const Offset(999, 999), _bounds),
        const Rect.fromLTWH(700, 300, 300, 200),
      );
      // Size never changes while moving.
      final Rect moved = translateRect(frame, const Offset(999, 999), _bounds);
      expect(moved.size, frame.size);
    });
  });

  group('resizing the frame', () {
    const Rect frame = Rect.fromLTWH(200, 100, 400, 200);

    test('the opposite corner stays put', () {
      final Rect resized = resizeRect(
        rect: frame,
        handle: CropHandle.bottomRight,
        point: const Offset(800, 400),
        bounds: _bounds,
      );
      expect(resized.topLeft, frame.topLeft);
      expect(resized.bottomRight, const Offset(800, 400));
    });

    test('every handle anchors the corner across from it', () {
      for (final CropHandle handle in CropHandle.values) {
        final Rect resized = resizeRect(
          rect: frame,
          handle: handle,
          point: const Offset(300, 200),
          bounds: _bounds,
        );
        // The anchor is still on the frame — as a corner, exactly where it was.
        final Offset anchor = anchorFor(handle, frame);
        expect(anchorFor(handle, resized), anchor);
        expect(
          <Offset>[
            resized.topLeft,
            resized.topRight,
            resized.bottomLeft,
            resized.bottomRight,
          ],
          contains(anchor),
        );
      }
    });

    test('a handle sits diagonally across from its anchor', () {
      // The two are easy to confuse, and confusing them means every drag resizes
      // the frame from the wrong corner — which is a bug the user sees as "the
      // crop does not select what I chose".
      expect(cornerFor(CropHandle.topLeft, frame), frame.topLeft);
      expect(cornerFor(CropHandle.topRight, frame), frame.topRight);
      expect(cornerFor(CropHandle.bottomLeft, frame), frame.bottomLeft);
      expect(cornerFor(CropHandle.bottomRight, frame), frame.bottomRight);

      for (final CropHandle handle in CropHandle.values) {
        final Offset grip = cornerFor(handle, frame);
        final Offset anchor = anchorFor(handle, frame);
        expect(
          (grip - anchor).distance,
          closeTo(Offset(frame.width, frame.height).distance, 0.001),
          reason: 'the grip and its anchor are opposite corners',
        );
      }
    });

    test('stops at the edges of the picture', () {
      // Dragged far past the right edge: the frame ends at the edge instead of
      // outside the picture, where there are no pixels to keep.
      final Rect resized = resizeRect(
        rect: frame,
        handle: CropHandle.bottomRight,
        point: const Offset(5000, 5000),
        bounds: _bounds,
      );
      expect(resized.right, _bounds.right);
      expect(resized.bottom, _bounds.bottom);
    });

    test('never collapses, however far the finger goes', () {
      // Dragged through the anchor and out the other side: the frame is pinned
      // to the minimum rather than flipped inside out.
      final Rect resized = resizeRect(
        rect: frame,
        handle: CropHandle.bottomRight,
        point: const Offset(0, 0),
        bounds: _bounds,
        minSide: 40,
      );
      expect(resized.width, 40);
      expect(resized.height, 40);
      expect(resized.topLeft, frame.topLeft);
    });

    test('a locked shape keeps its ratio', () {
      const double aspect = 16 / 9;
      final Rect resized = resizeRect(
        rect: frame,
        handle: CropHandle.bottomRight,
        point: const Offset(900, 300),
        bounds: _bounds,
        aspect: aspect,
      );
      expect(resized.width / resized.height, closeTo(aspect, 0.0001));
      expect(resized.topLeft, frame.topLeft);
      // Pulled further down than right: the width follows the height.
      expect(resized.right, lessThanOrEqualTo(_bounds.right));
    });

    test('a locked shape is trimmed to the picture, not past it', () {
      final Rect resized = resizeRect(
        rect: frame,
        handle: CropHandle.topLeft,
        point: const Offset(-400, -400),
        bounds: _bounds,
        aspect: 1,
      );
      expect(resized.width / resized.height, closeTo(1, 0.0001));
      expect(resized.left, greaterThanOrEqualTo(_bounds.left));
      expect(resized.top, greaterThanOrEqualTo(_bounds.top));
      expect(resized.bottomRight, frame.bottomRight);
    });
  });

  group('drawing a frame from scratch', () {
    test('grows in whichever direction the drag goes', () {
      final Rect drawn = drawRect(
        from: const Offset(400, 200),
        to: const Offset(700, 400),
        bounds: _bounds,
      );
      expect(drawn, const Rect.fromLTWH(400, 200, 300, 200));

      final Rect upLeft = drawRect(
        from: const Offset(400, 200),
        to: const Offset(100, 50),
        bounds: _bounds,
      );
      expect(upLeft, const Rect.fromLTWH(100, 50, 300, 150));
      // The drag's starting corner is the one that stays put.
      expect(upLeft.bottomRight, const Offset(400, 200));
    });

    test('a drag that leaves the picture is clamped to it', () {
      final Rect drawn = drawRect(
        from: const Offset(-50, -50),
        to: const Offset(5000, 5000),
        bounds: _bounds,
      );
      expect(drawn, _bounds);
    });

    test('a locked shape drawn by hand keeps its ratio', () {
      final Rect drawn = drawRect(
        from: const Offset(100, 100),
        to: const Offset(600, 200),
        bounds: _bounds,
        aspect: 1,
      );
      expect(drawn.width / drawn.height, closeTo(1, 0.0001));
      expect(drawn.topLeft, const Offset(100, 100));
    });
  });

  group('what gets written out', () {
    test('the frame is rounded outwards to whole pixels', () {
      expect(
        sourceRectFor(const Rect.fromLTWH(10.4, 20.6, 100.3, 50.2), const Size(1000, 500)),
        const Rect.fromLTRB(10, 20, 111, 71),
      );
    });

    test('a frame overhanging the picture is clipped to it', () {
      final Rect source =
          sourceRectFor(const Rect.fromLTWH(-20, -20, 200, 200), const Size(1000, 500));
      expect(source.left, 0);
      expect(source.top, 0);
      expect(source.right, 180);
      expect(source.bottom, 180);
    });

    test('the output keeps the shape of the crop, up to the cap', () {
      expect(
        outputSizeFor(const Rect.fromLTWH(0, 0, 800, 400)),
        const Size(800, 400),
      );
      final Size capped = outputSizeFor(const Rect.fromLTWH(0, 0, 4000, 2000));
      expect(capped.width, 1440);
      expect(capped.height, 720);
      // Never zero, however thin the crop.
      expect(outputSizeFor(const Rect.fromLTWH(0, 0, 4000, 1)), const Size(1440, 1));
    });
  });
}
