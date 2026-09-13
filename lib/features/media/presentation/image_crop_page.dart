import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/platform/app_platform.dart';
import '../domain/crop_geometry.dart';

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

/// The shapes the crop window can take.
///
/// [original] keeps the source's own shape (so the user zooms/pans to trim edges
/// without changing proportions), [screen] matches the device window — which is
/// what an application-wide background wants, since it is drawn `cover` across
/// the whole page.
enum CropAspect { original, screen, square, standard, wide, portrait }

/// Largest side a crop is decoded or written at.
///
/// Bounds two costs at once: a 50 MP photo is not held as a 200 MB bitmap, and a
/// crop never produces a file larger than the app can usefully draw.
const int _maxEdge = 2048;
const double _maxOutputEdge = 1440;

/// Opens the cropper for the image at [sourcePath].
///
/// Returns `null` when the user cancels or the source cannot be read.
Future<CroppedImage?> cropImage(
  BuildContext context, {
  required String sourcePath,
  CropAspect initialAspect = CropAspect.original,
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
  CropAspect initialAspect = CropAspect.original,
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

/// Full-screen cropper: pan and zoom the photo, then keep what the frame shows.
///
/// The gestures are handled explicitly rather than with [InteractiveViewer]
/// because the crop needs the exact transform to compute which source pixels are
/// visible; owning the transform keeps that arithmetic in one place
/// ([CropGeometry]) where it can be unit-tested.
class ImageCropPage extends StatefulWidget {
  const ImageCropPage({
    required this.sourcePath,
    this.initialAspect = CropAspect.original,
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

  CropAspect _aspect = CropAspect.original;
  CropGeometry? _geometry;

  /// Geometry at the moment the current gesture started.
  CropGeometry? _gestureStart;

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
        targetWidth:
            descriptor.width >= descriptor.height ? (descriptor.width * factor).round() : null,
        targetHeight:
            descriptor.height > descriptor.width ? (descriptor.height * factor).round() : null,
      );
      final ui.Image image = (await codec.getNextFrame()).image;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _loadError = error);
      }
    }
  }

  double _aspectValue(CropAspect aspect, Size imageSize, Size screenSize) {
    return switch (aspect) {
      CropAspect.original => imageSize.width / imageSize.height,
      CropAspect.screen => screenSize.width / screenSize.height,
      CropAspect.square => 1,
      CropAspect.standard => 4 / 3,
      CropAspect.wide => 16 / 9,
      CropAspect.portrait => 9 / 16,
    };
  }

  /// The largest rectangle of the chosen shape that fits in [available].
  Size _windowFor(double aspect, Size available) {
    double width = available.width;
    double height = width / aspect;
    if (height > available.height) {
      height = available.height;
      width = height * aspect;
    }
    return Size(width, height);
  }

  /// Rebuilds the geometry whenever the window shape or the available space
  /// changes, keeping the current zoom.
  CropGeometry _geometryFor(ui.Image image, Size window) {
    final CropGeometry? current = _geometry;
    if (current != null && current.windowSize == window) {
      return current;
    }
    // A new window shape starts fresh and centred: the previous offset was
    // valid for a different rectangle and could leave a gap.
    final CropGeometry fresh = CropGeometry(
      windowSize: window,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    );
    return fresh.withOffset(fresh.centredOffset);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _geometry;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final CropGeometry? start = _gestureStart;
    if (start == null) {
      return;
    }
    final double nextScale = (start.scale * details.scale).clamp(1.0, 6.0);
    // Keep the image point that was under the fingers under them still: this is
    // what makes pinch-zoom feel anchored, and it also carries the pan, because
    // `localFocalPoint` moves with the gesture.
    final Offset focalInImage = (details.localFocalPoint - start.offset) /
        start.effectiveScale;
    final CropGeometry scaled = start.withScale(nextScale);
    final Offset desired =
        details.localFocalPoint - focalInImage * scaled.effectiveScale;
    setState(() => _geometry = scaled.withOffset(desired));
  }

  Future<void> _confirm() async {
    final ui.Image? image = _image;
    final CropGeometry? geometry = _geometry;
    if (image == null || geometry == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final Rect source = geometry.sourceRect;
      final Size output = geometry.outputSize(maxLongSide: _maxOutputEdge);
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
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints box) {
                          final Size window = _windowFor(
                            _aspectValue(_aspect, Size(image.width.toDouble(),
                                image.height.toDouble()), MediaQuery.sizeOf(context)),
                            Size(box.maxWidth - 32, box.maxHeight - 32),
                          );
                          final CropGeometry geometry = _geometryFor(image, window);
                          // Built during layout, so the first frame already has
                          // geometry; assigning here (rather than in a post-frame
                          // callback) avoids a frame where nothing is painted.
                          _geometry = geometry;
                          return Center(
                            child: SizedBox(
                              width: window.width,
                              height: window.height,
                              child: GestureDetector(
                                onScaleStart: _onScaleStart,
                                onScaleUpdate: _onScaleUpdate,
                                child: _CropViewport(image: image, geometry: geometry),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _AspectBar(
                      selected: _aspect,
                      onSelected: (CropAspect aspect) {
                        setState(() {
                          _aspect = aspect;
                          _geometry = null;
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Text(
                        AppStrings.cropHint,
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Draws the image at its current transform, cropped to the window, plus the
/// thirds grid that helps line a crop up.
class _CropViewport extends StatelessWidget {
  const _CropViewport({required this.image, required this.geometry});

  final ui.Image image;
  final CropGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final Size child = geometry.childSize;
    return ClipRect(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: geometry.offset.dx,
            top: geometry.offset.dy,
            width: child.width,
            height: child.height,
            // `fill` on purpose: the child box already has the exact pixel size
            // the geometry asked for, so fitting must not scale it again.
            child: RawImage(image: image, fit: BoxFit.fill),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CropFramePainter()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid lines and corner marks for the crop frame.
class _CropFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    // Rule of thirds.
    for (int i = 1; i < 3; i++) {
      final double dx = size.width * i / 3;
      final double dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), line);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), line);
    }

    final Paint corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const double arm = 18;
    final Rect r = Offset.zero & size;
    // Four L-shaped marks, drawn just inside the frame.
    for (final (Offset point, Offset horizontal, Offset vertical) in <(Offset, Offset, Offset)>[
      (r.topLeft, const Offset(arm, 0), const Offset(0, arm)),
      (r.topRight, const Offset(-arm, 0), const Offset(0, arm)),
      (r.bottomLeft, const Offset(arm, 0), const Offset(0, -arm)),
      (r.bottomRight, const Offset(-arm, 0), const Offset(0, -arm)),
    ]) {
      canvas.drawLine(point, point + horizontal, corner);
      canvas.drawLine(point, point + vertical, corner);
    }
  }

  @override
  bool shouldRepaint(_CropFramePainter oldDelegate) => false;
}

/// The aspect-ratio chooser under the frame.
class _AspectBar extends StatelessWidget {
  const _AspectBar({required this.selected, required this.onSelected});

  final CropAspect selected;
  final ValueChanged<CropAspect> onSelected;

  static const Map<CropAspect, String> _labels = <CropAspect, String>{
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
