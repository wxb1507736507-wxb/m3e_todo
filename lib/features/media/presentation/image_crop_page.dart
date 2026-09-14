import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/platform/app_platform.dart';
import '../domain/crop_frame.dart';

/// What a crop produced: a new file in the app's private directory.
class CroppedImage {
  const CroppedImage({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;

  @override
  String toString() => 'CroppedImage($path, ${width}x$height)';
}

/// The shapes the frame can take.
///
/// [free] locks nothing and is the only one that lets the user pick a rectangle
/// the app did not think of — which is the point of a cropper, so it sits first
/// in the bar. [original] keeps the source's own shape, [screen] matches the
/// device window (what an application-wide background wants, since it is drawn
/// `cover` across the whole page).
enum CropAspect { free, original, screen, square, standard, wide, portrait }

/// Largest side a crop is decoded at.
///
/// Bounds two costs at once: a 50 MP photo is not held as a 200 MB bitmap, and a
/// crop never produces a file larger than the app can usefully draw.
const int _maxEdge = 2048;
const double _maxOutputEdge = 1440;

/// How far the picture may be magnified while framing.
///
/// The frame is chosen by eye, so a few times magnification is a precision aid,
/// not a microscope: past this the picture is a wall of blurred pixels and the
/// user has lost sight of what they are cropping.
const double _maxZoom = 8;

/// How close to a corner a touch has to land to grab it, in logical pixels.
const double _handleTouch = 32;

/// Opens the cropper for the image at [sourcePath].
///
/// Returns `null` when the user cancels or the source cannot be read.
Future<CroppedImage?> cropImage(
  BuildContext context, {
  required String sourcePath,
  CropAspect initialAspect = CropAspect.free,
}) {
  return Navigator.of(context).push<CroppedImage>(
    MaterialPageRoute<CroppedImage>(
      fullscreenDialog: true,
      builder: (_) => ImageCropPage(
        sourcePath: sourcePath,
        initialAspect: initialAspect,
      ),
    ),
  );
}

/// Picks an image with the system picker and immediately crops it.
///
/// The pick and the crop are one user intent ("choose a background"), so they
/// are one call: every caller that wants an image wants it cropped, and leaving
/// the two steps separate invites callers that forget the second.
///
/// The picker's own copy is deleted either way — the app stores the *cropped*
/// result, so keeping the original would leave a full-size duplicate behind on
/// every background change.
Future<CroppedImage?> pickAndCropImage(
  BuildContext context, {
  CropAspect initialAspect = CropAspect.free,
}) async {
  final PickedAttachment? picked = await AppPlatform.pickAttachment('image');
  if (picked == null || !context.mounted) {
    return null;
  }
  final CroppedImage? cropped = await cropImage(
    context,
    sourcePath: picked.path,
    initialAspect: initialAspect,
  );
  unawaited(_deleteQuietly(picked.path));
  return cropped;
}

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } on Object {
    // Already gone, or not ours to delete; neither is worth reporting.
  }
}

/// What a drag on the picture is doing.
enum _DragMode { none, move, resize, draw, view }

/// Full-screen cropper: the whole picture is shown, the frame is drawn on top of
/// it, and the user drags the frame.
///
/// The older arrangement — a fixed window with the picture sliding behind it —
/// could only ever trim the edges of a rectangle the app had chosen, and hid the
/// parts of the picture the user was cutting away. Here the picture is fitted
/// whole onto the screen and the frame moves over it, so "keep this bit" is a
/// thing the user can point at.
///
/// The gestures are handled explicitly rather than with [InteractiveViewer]
/// because the crop needs the exact transform to know which source pixels are
/// inside the frame; owning it keeps that arithmetic in one place
/// ([CropView]) where it can be unit-tested.
class ImageCropPage extends StatefulWidget {
  const ImageCropPage({
    required this.sourcePath,
    this.initialAspect = CropAspect.free,
    super.key,
  });

  final String sourcePath;
  final CropAspect initialAspect;

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<ImageCropPage> {
  ui.Image? _image;
  Object? _loadError;

  CropAspect _aspect = CropAspect.free;

  /// The part of the picture to keep, in image pixels. `null` until the picture
  /// has loaded and its size is known.
  Rect? _frame;

  /// Where the picture sits on screen, and how far it is zoomed in.
  CropView? _view;
  double _zoom = 1;

  /// Gesture bookkeeping, all of it in the coordinates it is named after.
  _DragMode _mode = _DragMode.none;
  CropHandle? _handle;
  CropView? _viewStart;
  Rect? _frameStart;
  Offset? _dragOrigin;

  /// How far the finger has travelled since the gesture started, in viewport
  /// pixels. Tells a selection apart from a tap.
  double _dragTravel = 0;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _aspect = widget.initialAspect;
    unawaited(_load());
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Reads the file and decodes it at a bounded size.
  ///
  /// The dimensions come from the image *descriptor*, which reads only the
  /// header, so the target size can be chosen before any pixels are allocated.
  Future<void> _load() async {
    try {
      final Uint8List bytes = await File(widget.sourcePath).readAsBytes();
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        bytes,
      );
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final double factor = math.min(
        1,
        _maxEdge / math.max(descriptor.width, descriptor.height),
      );
      // Only one axis is given, so the aspect ratio is preserved.
      final ui.Codec codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width >= descriptor.height
            ? (descriptor.width * factor).round()
            : null,
        targetHeight: descriptor.height > descriptor.width
            ? (descriptor.height * factor).round()
            : null,
      );
      final ui.Image image = (await codec.getNextFrame()).image;
      if (!mounted) {
        image.dispose();
        return;
      }
      // The frame is settled here rather than during layout: the size line under
      // the picture is built before the layout pass that would know the picture's
      // size, and a frame created there would leave that line blank.
      setState(() {
        _image = image;
        _frame = _initialFrameFor(image);
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _loadError = error);
      }
    }
  }

  Size get _imageSize {
    final ui.Image image = _image!;
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  Rect get _imageBounds => Offset.zero & _imageSize;

  /// The aspect the frame is locked to, or `null` when it is free.
  double? _aspectValue(CropAspect aspect, Size imageSize, Size screenSize) {
    return switch (aspect) {
      CropAspect.free => null,
      CropAspect.original => imageSize.width / imageSize.height,
      CropAspect.screen => screenSize.width / screenSize.height,
      CropAspect.square => 1,
      CropAspect.standard => 4 / 3,
      CropAspect.wide => 16 / 9,
      CropAspect.portrait => 9 / 16,
    };
  }

  double? get _lockedAspect {
    final ui.Image? image = _image;
    if (image == null) {
      return null;
    }
    return _aspectValue(
      _aspect,
      _imageSize,
      MediaQuery.sizeOf(context),
    );
  }

  /// Builds the view for [viewport], keeping the user's zoom.
  CropView _viewFor(Size imageSize, Size viewport) {
    final CropView? current = _view;
    if (current != null &&
        current.viewportSize == viewport &&
        current.imageSize == imageSize) {
      return current;
    }
    // A different viewport makes the old offset meaningless, but the zoom is the
    // user's own choice and survives.
    final CropView fresh = CropView(
      viewportSize: viewport,
      imageSize: imageSize,
      zoom: _zoom,
    );
    final CropView centred = fresh.withOffset(fresh.centredOffset);
    _view = centred;
    return centred;
  }

  /// The frame to start from: the whole picture when free, otherwise the largest
  /// rectangle of the chosen shape.
  Rect _initialFrameFor(ui.Image image) {
    final Rect bounds = Offset.zero &
        Size(image.width.toDouble(), image.height.toDouble());
    final double? aspect = _aspectValue(
      _aspect,
      bounds.size,
      MediaQuery.sizeOf(context),
    );
    return aspect == null ? bounds : centredRectIn(bounds, aspect);
  }

  /// Re-shapes the frame for a newly chosen aspect.
  ///
  /// Free keeps whatever is framed and only unlocks the corners — switching to
  /// "anything goes" must not throw away the selection the user just made. A
  /// fixed shape is re-fitted around the frame's current centre, so the part of
  /// the picture being looked at stays the part being looked at.
  Rect _refitFrame(double? aspect) {
    final Rect bounds = _imageBounds;
    final Rect current = _frame ?? bounds;
    if (aspect == null) {
      return current;
    }
    final Rect fitted = centredRectIn(bounds, aspect);
    return translateRect(fitted, current.center - fitted.center, bounds);
  }

  CropHandle? _handleAt(Offset point, Rect frame) {
    for (final CropHandle handle in CropHandle.values) {
      if ((point - cornerFor(handle, frame)).distance <= _handleTouch) {
        return handle;
      }
    }
    return null;
  }

  void _onScaleStart(ScaleStartDetails details) {
    final CropView? view = _view;
    final Rect? frame = _frame;
    if (view == null || frame == null) {
      return;
    }
    _viewStart = view;
    _frameStart = frame;
    _dragOrigin = details.localFocalPoint;
    _dragTravel = 0;

    if (details.pointerCount > 1) {
      // Two fingers always mean "look closer", wherever they land.
      _mode = _DragMode.view;
      return;
    }
    final Offset point = details.localFocalPoint;
    final Rect shown = view.viewportRect(frame);
    final CropHandle? grabbed = _handleAt(point, shown);
    // The frame itself is forgiving about being grabbed: a finger aiming at an
    // edge lands a few pixels off it, and missing means the frame the user was
    // moving is replaced by a new box instead.
    _mode = grabbed != null
        ? _DragMode.resize
        : shown.contains(point)
            ? _DragMode.move
            : _DragMode.draw;
    _handle = grabbed;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final CropView? start = _viewStart;
    final Rect? frameStart = _frameStart;
    final Offset? origin = _dragOrigin;
    if (start == null || frameStart == null || origin == null) {
      return;
    }
    final Rect bounds = Offset.zero & start.imageSize;
    _dragTravel = math.max(
      _dragTravel,
      (details.localFocalPoint - origin).distance,
    );

    // A pinch that began as a one-finger drag becomes a view gesture the moment
    // the second finger lands; `details.scale` is still 1 at that point, so the
    // gesture can be re-based on the view as it stands.
    if (details.pointerCount > 1 && _mode != _DragMode.view) {
      _mode = _DragMode.view;
      _viewStart = _view;
      _dragOrigin = details.localFocalPoint;
      return;
    }

    switch (_mode) {
      case _DragMode.view:
        final double zoom = (start.zoom * details.scale).clamp(1.0, _maxZoom);
        final CropView scaled = start.withZoom(zoom);
        // Keep the picture point that is under the fingers under them: that is
        // what makes a pinch feel anchored rather than slippery.
        final Offset focal = start.toImage(details.localFocalPoint);
        setState(() {
          _zoom = zoom;
          _view = scaled.withOffset(
            details.localFocalPoint - focal * scaled.effectiveScale,
          );
        });
      case _DragMode.move:
        final Offset delta =
            (details.localFocalPoint - origin) / start.effectiveScale;
        setState(() => _frame = translateRect(frameStart, delta, bounds));
      case _DragMode.resize:
        setState(() {
          _frame = resizeRect(
            rect: frameStart,
            handle: _handle!,
            point: start.toImage(details.localFocalPoint),
            bounds: bounds,
            aspect: _lockedAspect,
            minSide: kCropMinSide / start.effectiveScale,
          );
        });
      case _DragMode.draw:
        setState(() {
          // No minimum while the finger is down: the box should follow it
          // exactly, and a drag too small to be a selection is dropped on
          // release instead of being inflated into one.
          _frame = drawRect(
            from: start.toImage(origin),
            to: start.toImage(details.localFocalPoint),
            bounds: bounds,
            aspect: _lockedAspect,
          );
        });
      case _DragMode.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final CropView? view = _view;
    final Rect? frame = _frame;
    if (_mode == _DragMode.draw && view != null) {
      // A tap is not a selection: rather than replace a frame the user built
      // with one the size of a fingertip, a drag that never went anywhere is
      // dropped. Measured on the gesture, not on the frame it produced — a
      // frame that came out at the minimum size is still a frame the finger
      // barely drew.
      if (_dragTravel < kCropMinSide) {
        final Rect? before = _frameStart;
        setState(() => _frame = before);
      }
    } else if (_mode == _DragMode.view && view != null && frame != null) {
      // Zooming can leave the frame off-screen, which looks exactly like losing
      // it. Panning the picture until the frame is back in view costs nothing
      // and removes the dead end.
      setState(() => _view = _keepFrameVisible(view, frame));
    }
    _mode = _DragMode.none;
    _handle = null;
    _viewStart = null;
    _frameStart = null;
    _dragOrigin = null;
  }

  CropView _keepFrameVisible(CropView view, Rect frame) {
    const double inset = 32;
    final Rect shown = view.viewportRect(frame);
    final Size viewport = view.viewportSize;
    double axis(double value, double extent) => value.clamp(
          math.min(inset, extent / 2),
          math.max(extent - inset, extent / 2),
        );
    final Offset target = Offset(
      axis(shown.center.dx, viewport.width),
      axis(shown.center.dy, viewport.height),
    );
    if (target == shown.center) {
      return view;
    }
    return view.withOffset(view.offset + (target - shown.center));
  }

  Future<void> _confirm() async {
    final ui.Image? image = _image;
    final CropView? view = _view;
    final Rect? frame = _frame;
    if (image == null || view == null || frame == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final Rect source = sourceRectFor(frame, _imageSize);
      if (source.isEmpty) {
        throw StateError('empty crop');
      }
      final Size output = outputSizeFor(source, maxLongSide: _maxOutputEdge);
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        source,
        Offset.zero & output,
        Paint()..filterQuality = FilterQuality.medium,
      );
      final ui.Image cropped = await recorder.endRecording().toImage(
            output.width.round(),
            output.height.round(),
          );
      final ByteData? png = await cropped.toByteData(
        format: ui.ImageByteFormat.png,
      );
      cropped.dispose();
      if (png == null) {
        throw StateError('encode failed');
      }
      final String? path = await AppPlatform.saveImage(
        bytes: png.buffer.asUint8List(),
      );
      if (!mounted) {
        return;
      }
      if (path == null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.cropFailed)),
        );
        return;
      }
      Navigator.of(context).pop(
        CroppedImage(
          path: path,
          width: output.width.round(),
          height: output.height.round(),
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.cropFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final ui.Image? image = _image;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colors.surfaceContainerHigh,
        title: const Text(AppStrings.cropTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: AppStrings.cancel,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: image == null ? null : () => unawaited(_confirm()),
              child: const Text(AppStrings.cropApply),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loadError != null
          ? Center(
              child: Text(
                AppStrings.cropFailed,
                style: text.bodyLarge?.copyWith(color: colors.error),
              ),
            )
          : image == null
              ? const Center(child: CircularProgressIndicator())
              : _buildEditor(context, image, colors, text),
    );
  }

  Widget _buildEditor(
    BuildContext context,
    ui.Image image,
    ColorScheme colors,
    TextTheme text,
  ) {
    return Column(
      children: <Widget>[
        Expanded(
          // Room at the sides for the fingers to land in. A gesture-navigation
          // phone claims swipes that start in a strip along each screen edge —
          // measured at about 28 logical pixels on the device this was written
          // on — and sends them to "back" instead of to the app. With the
          // picture flush against the edge, the side grips of a full-width frame
          // sit inside that strip: reaching for one closes the cropper and
          // throws away the work. 32 leaves the grips reachable, and costs the
          // picture a tenth of its width.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final CropView view = _viewFor(
                  Size(image.width.toDouble(), image.height.toDouble()),
                  Size(box.maxWidth, box.maxHeight),
                );
                // Built during layout, so the first frame of the picture already
                // knows where it sits and how far it is zoomed.
                final Rect frame = _frame ?? (Offset.zero & _imageSize);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: view.displayRect,
                          // `fill` on purpose: the box is already the exact size
                          // the view asked for, so fitting must not scale again.
                          child: RawImage(image: image, fit: BoxFit.fill),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CropOverlayPainter(
                              frame: view.viewportRect(frame),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _buildSizeLine(text, colors),
        _AspectBar(
          selected: _aspect,
          onSelected: (CropAspect aspect) {
            setState(() {
              _aspect = aspect;
              _frame = _refitFrame(
                _aspectValue(aspect, _imageSize, MediaQuery.sizeOf(context)),
              );
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Text(
            AppStrings.cropHint,
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Says how big the kept part will be.
  ///
  /// Worth the line: the frame is drawn over a picture that may itself have been
  /// shrunk on the way in, so "how many pixels am I keeping" is not something
  /// the user can work out by looking.
  Widget _buildSizeLine(TextTheme text, ColorScheme colors) {
    final Rect? frame = _frame;
    if (frame == null) {
      return const SizedBox.shrink();
    }
    final Size output = outputSizeFor(
      sourceRectFor(frame, _imageSize),
      maxLongSide: _maxOutputEdge,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        '${AppStrings.cropOutputPrefix} ${output.width.round()} × '
        '${output.height.round()}',
        style: text.labelMedium?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

/// Dims everything outside the frame, and draws the frame's own chrome.
///
/// The dimming is the whole reason the frame can be moved: the part being kept
/// is the bright part, and what is being cut away stays visible around it
/// instead of being hidden by the edges of the screen.
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.frame});

  /// The frame, in viewport coordinates.
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(frame),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    // Rule of thirds, inside the frame: the usual help for lining a subject up.
    final Paint thirds = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      final double dx = frame.left + frame.width * i / 3;
      final double dy = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(dx, frame.top), Offset(dx, frame.bottom), thirds);
      canvas.drawLine(Offset(frame.left, dy), Offset(frame.right, dy), thirds);
    }

    // Frame and handles are drawn twice — a dark line under a light one — so
    // they stay visible over a white sky and a black shirt alike.
    final RRect edge = RRect.fromRectAndRadius(
      frame,
      const Radius.circular(2),
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    // Corner grips, drawn as the two arms of an L that meet on the corner the
    // finger has to grab.
    final double arm = math.min(20, math.min(frame.width, frame.height) / 2);
    final Paint gripShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final Paint grip = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    for (final (Offset corner, double sx, double sy)
        in <(Offset, double, double)>[
      (frame.topLeft, 1, 1),
      (frame.topRight, -1, 1),
      (frame.bottomLeft, 1, -1),
      (frame.bottomRight, -1, -1),
    ]) {
      for (final Offset tip in <Offset>[
        corner + Offset(sx * arm, 0),
        corner + Offset(0, sy * arm),
      ]) {
        canvas.drawLine(corner, tip, gripShadow);
        canvas.drawLine(corner, tip, grip);
      }
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.frame != frame;
}

/// The shape chooser under the picture.
class _AspectBar extends StatelessWidget {
  const _AspectBar({required this.selected, required this.onSelected});

  final CropAspect selected;
  final ValueChanged<CropAspect> onSelected;

  static const Map<CropAspect, String> _labels = <CropAspect, String>{
    CropAspect.free: AppStrings.cropAspectFree,
    CropAspect.original: AppStrings.cropAspectOriginal,
    CropAspect.screen: AppStrings.cropAspectScreen,
    CropAspect.square: AppStrings.cropAspectSquare,
    CropAspect.standard: AppStrings.cropAspectStandard,
    CropAspect.wide: AppStrings.cropAspectWide,
    CropAspect.portrait: AppStrings.cropAspectPortrait,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: <Widget>[
          for (final MapEntry<CropAspect, String> entry in _labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: entry.key == selected,
                onSelected: (_) => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}
