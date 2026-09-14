import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/utils/color_utils.dart';
import '../domain/crop_geometry.dart';

/// Opens the colour sampler for the image at [imagePath].
///
/// Returns the sampled ARGB32 colour, or `null` if the user backed out.
Future<int?> extractColorFromImage(
  BuildContext context, {
  required String imagePath,
}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute<int>(
      fullscreenDialog: true,
      builder: (_) => ColorExtractPage(imagePath: imagePath),
    ),
  );
}

/// Largest side the image is decoded at for sampling.
const int _maxEdge = 2048;

/// Pick a colour out of a picture: tap anywhere and take the colour under it.
///
/// Sampling a *neighbourhood* rather than the exact pixel is deliberate — a
/// photograph is full of noise, and a single pixel of a gradient looks random
/// next to its neighbours, leaving the user unsure whether they hit what they
/// aimed at. Zooming exists for the same reason: it is the only way to aim
/// precisely at a small feature.
class ColorExtractPage extends StatefulWidget {
  const ColorExtractPage({required this.imagePath, super.key});

  final String imagePath;

  @override
  State<ColorExtractPage> createState() => _ColorExtractPageState();
}

class _ColorExtractPageState extends State<ColorExtractPage> {
  ui.Image? _image;
  ByteData? _pixels;
  int? _sampled;

  /// Where the sample was taken, in viewport coordinates, for the marker.
  Offset? _marker;

  CropGeometry? _geometry;
  CropGeometry? _gestureStart;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Decodes the file once and keeps its pixels for sampling.
  ///
  /// One decode serves both the preview and the sampling, so what the user sees
  /// and what they sample cannot come from different renderings of the file.
  Future<void> _load() async {
    try {
      final Uint8List bytes = await File(widget.imagePath).readAsBytes();
      final ui.ImmutableBuffer buffer =
          await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.ImageDescriptor descriptor =
          await ui.ImageDescriptor.encoded(buffer);
      final double factor = math.min(
        1,
        _maxEdge / math.max(descriptor.width, descriptor.height),
      );
      final ui.Codec codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width >= descriptor.height
            ? (descriptor.width * factor).round()
            : null,
        targetHeight: descriptor.height > descriptor.width
            ? (descriptor.height * factor).round()
            : null,
      );
      final ui.Image image = (await codec.getNextFrame()).image;
      final ByteData? rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image = image;
        _pixels = rgba;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  CropGeometry _ensureGeometry(Size viewport) {
    final CropGeometry? current = _geometry;
    if (current != null && current.windowSize == viewport) {
      return current;
    }
    final ui.Image image = _image!;
    final CropGeometry fresh = CropGeometry(
      windowSize: viewport,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    );
    return fresh.withOffset(fresh.centredOffset);
  }

  void _sampleAt(Offset localPoint, CropGeometry geometry) {
    final ByteData? pixels = _pixels;
    final ui.Image? image = _image;
    if (pixels == null || image == null) {
      return;
    }
    final Offset target = geometry.imagePointFor(localPoint);
    final int? argb = averageArgbAtRgba(
      pixels,
      image.width,
      image.height,
      target.dx.round(),
      target.dy.round(),
    );
    if (argb == null) {
      return;
    }
    setState(() {
      _sampled = argb;
      _marker = localPoint;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _geometry;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final CropGeometry? start = _gestureStart;
    if (start == null) {
      return;
    }
    // Same focal-point maths as the cropper: the image point under the fingers
    // stays under them, which is what makes zooming feel anchored.
    final double nextScale = (start.scale * details.scale).clamp(1.0, 8.0);
    final Offset focalInImage =
        (details.localFocalPoint - start.offset) / start.effectiveScale;
    final CropGeometry scaled = start.withScale(nextScale);
    setState(() {
      _geometry =
          scaled.withOffset(details.localFocalPoint - focalInImage * scaled.effectiveScale);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final ui.Image? image = _image;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.colorExtractTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: AppStrings.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed:
                _sampled == null ? null : () => Navigator.of(context).pop(_sampled),
            child: const Text(AppStrings.cropApply),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _error != null
          ? Center(
              child: Text(
                AppStrings.colorExtractFailed,
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
                          final CropGeometry geometry = _ensureGeometry(
                            Size(box.maxWidth, box.maxHeight),
                          );
                          _geometry = geometry;
                          return GestureDetector(
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onTapUp: (TapUpDetails details) =>
                                _sampleAt(details.localPosition, geometry),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                ClipRect(
                                  child: Stack(
                                    children: <Widget>[
                                      Positioned(
                                        left: geometry.offset.dx,
                                        top: geometry.offset.dy,
                                        width: geometry.childSize.width,
                                        height: geometry.childSize.height,
                                        child: RawImage(
                                          image: image,
                                          fit: BoxFit.fill,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_marker != null)
                                  Positioned(
                                    left: _marker!.dx - 14,
                                    top: _marker!.dy - 14,
                                    child: IgnorePointer(
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                          color: _sampled == null
                                              ? null
                                              : Color(_sampled!),
                                          boxShadow: const <BoxShadow>[
                                            BoxShadow(
                                              color: Colors.black45,
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    _buildSampleBar(context, colors, text),
                  ],
                ),
    );
  }

  Widget _buildSampleBar(
    BuildContext context,
    ColorScheme colors,
    TextTheme text,
  ) {
    final int? sampled = _sampled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      color: colors.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: sampled == null ? colors.surfaceContainerHighest : Color(sampled),
                  borderRadius: AppShapes.radius(AppShapes.small),
                  border: Border.all(color: colors.outlineVariant),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  sampled == null ? AppStrings.colorExtractHint : hexFromArgb(sampled),
                  style: text.titleMedium,
                ),
              ),
              if (sampled != null)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(sampled),
                  child: const Text(AppStrings.colorPick),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.colorExtractHint,
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
