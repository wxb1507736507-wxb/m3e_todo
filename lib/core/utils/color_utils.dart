/// Colour maths, kept free of Flutter so it can be unit-tested as plain Dart.
///
/// The editor hands raw ARGB32 ints to the domain (which must not import
/// Flutter), and the pickers work in HSV because that is the space a human can
/// actually steer: hue chooses the colour, saturation and value choose how
/// strong and how bright it is. Somewhere the two have to meet, and that
/// conversion is the part worth testing — an off-by-one in a hue sector shows up
/// as "the slider picks the neighbouring colour", which no screenshot review
/// would notice.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A colour as a hue/saturation/value triple.
///
/// [hue] is in degrees `[0, 360)`, [saturation] and [value] are in `[0, 1]`.
class HsvColor {
  const HsvColor({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  @override
  bool operator ==(Object other) =>
      other is HsvColor &&
      other.hue == hue &&
      other.saturation == saturation &&
      other.value == value;

  @override
  int get hashCode => Object.hash(hue, saturation, value);

  @override
  String toString() =>
      'HsvColor(${hue.toStringAsFixed(1)}°, '
      '${(saturation * 100).round()}%, ${(value * 100).round()}%)';
}

/// Packs [hsv] into an opaque ARGB32 integer.
int argbFromHsv(HsvColor hsv) {
  final double h = (hsv.hue % 360 + 360) % 360;
  final double s = hsv.saturation.clamp(0.0, 1.0);
  final double v = hsv.value.clamp(0.0, 1.0);

  final double c = v * s;
  final double x = c * (1 - ((h / 60) % 2 - 1).abs());
  final double m = v - c;
  final (double r, double g, double b) = switch (h) {
    < 60 => (c, x, 0.0),
    < 120 => (x, c, 0.0),
    < 180 => (0.0, c, x),
    < 240 => (0.0, x, c),
    < 300 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  int channel(double value) => ((value + m) * 255).round().clamp(0, 255);
  return 0xFF000000 |
      (channel(r) << 16) |
      (channel(g) << 8) |
      channel(b);
}

/// Splits an ARGB32 integer into hue/saturation/value.
///
/// The alpha channel is ignored: every colour this app stores is opaque, and the
/// pickers have no use for transparency.
HsvColor hsvFromArgb(int argb) {
  final double r = ((argb >> 16) & 0xFF) / 255;
  final double g = ((argb >> 8) & 0xFF) / 255;
  final double b = (argb & 0xFF) / 255;

  final double max = math.max(r, math.max(g, b));
  final double min = math.min(r, math.min(g, b));
  final double delta = max - min;

  double hue;
  if (delta == 0) {
    hue = 0;
  } else if (max == r) {
    hue = 60 * (((g - b) / delta) % 6);
  } else if (max == g) {
    hue = 60 * ((b - r) / delta + 2);
  } else {
    hue = 60 * ((r - g) / delta + 4);
  }
  return HsvColor(
    hue: (hue % 360 + 360) % 360,
    saturation: max == 0 ? 0 : delta / max,
    value: max,
  );
}

/// `#RRGGBB` for [argb], which is what a picker shows and what a user can paste
/// back in.
String hexFromArgb(int argb) {
  final int rgb = argb & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Parses a hex colour, generously.
///
/// Accepts `#RRGGBB`, `RRGGBB`, `#RGB` (shorthand, expanded) and
/// `#AARRGGBB`, in any case, with or without the hash — because people paste
/// colours from all sorts of places and rejecting `f00` would be pedantry.
/// Returns `null` when [text] is not a colour at all, which the field shows as
/// "not a colour" rather than silently keeping the previous value.
int? argbFromHex(String text) {
  final String cleaned = text.trim().replaceAll('#', '').replaceAll(' ', '');
  if (cleaned.isEmpty || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) {
    return null;
  }
  switch (cleaned.length) {
    case 3:
      final String expanded = cleaned.split('').map((String c) => '$c$c').join();
      return 0xFF000000 | int.parse(expanded, radix: 16);
    case 6:
      return 0xFF000000 | int.parse(cleaned, radix: 16);
    case 8:
      return int.parse(cleaned, radix: 16);
    default:
      return null;
  }
}

/// Relative luminance as WCAG defines it.
double _relativeLuminance(int argb) {
  double channel(int shift) {
    final double value = ((argb >> shift) & 0xFF) / 255;
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}

/// WCAG contrast ratio between two opaque colours, from 1 (identical) to 21.
double contrastRatio(int foreground, int background) {
  final double a = _relativeLuminance(foreground);
  final double b = _relativeLuminance(background);
  final double lighter = math.max(a, b);
  final double darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Whether a text colour is worth warning about on a given background.
///
/// Threshold well below WCAG's 4.5 for body text on purpose: this warns about
/// "you cannot read this at all" (dark text on a dark card), not about colours
/// that merely fall short of the guideline — the user picked them on purpose,
/// and nagging about taste is worse than saying nothing.
bool isHardToRead(int foreground, int background) =>
    contrastRatio(foreground, background) < 2.5;

/// Picks black or white for [background], whichever is easier to read.
///
/// Used when a tile has a background image and there is no fixed surface colour
/// to compare against — the image can be anything, so the scrim is chosen to
/// suit the text, not the other way round.
int readableOn(int background) =>
    contrastRatio(0xFF000000, background) >= contrastRatio(0xFFFFFFFF, background)
        ? 0xFF000000
        : 0xFFFFFFFF;

/// Reads one pixel out of a raw RGBA buffer, as an opaque ARGB32 integer.
///
/// The buffer is what `ui.Image.toByteData(format: ImageByteFormat.rawRgba)`
/// hands back: four bytes per pixel, row-major. Out-of-range coordinates return
/// `null` rather than clamping, because a caller asking for a pixel that is not
/// there has a bug worth surfacing.
int? argbAtRgba(ByteData rgba, int width, int height, int x, int y) {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    return null;
  }
  final int offset = (y * width + x) * 4;
  final int r = rgba.getUint8(offset);
  final int g = rgba.getUint8(offset + 1);
  final int b = rgba.getUint8(offset + 2);
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

/// The average colour of the [radius]-pixel box around `(x, y)`.
///
/// Averaging rather than taking the exact pixel because photographs are noisy:
/// sampling a single pixel of a gradient or a textured area gives a colour that
/// looks arbitrary next to its neighbours, and the user cannot tell whether they
/// hit what they aimed at. The box is clipped at the edges, so a tap near the
/// border still returns something sensible.
int? averageArgbAtRgba(
  ByteData rgba,
  int width,
  int height,
  int x,
  int y, {
  int radius = 2,
}) {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    return null;
  }
  int r = 0;
  int g = 0;
  int b = 0;
  int count = 0;
  for (int dx = -radius; dx <= radius; dx++) {
    for (int dy = -radius; dy <= radius; dy++) {
      final int? pixel = argbAtRgba(rgba, width, height, x + dx, y + dy);
      if (pixel == null) {
        continue;
      }
      r += (pixel >> 16) & 0xFF;
      g += (pixel >> 8) & 0xFF;
      b += pixel & 0xFF;
      count++;
    }
  }
  if (count == 0) {
    return null;
  }
  return 0xFF000000 | ((r ~/ count) << 16) | ((g ~/ count) << 8) | (b ~/ count);
}
