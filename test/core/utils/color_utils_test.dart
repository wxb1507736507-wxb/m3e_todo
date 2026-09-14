import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/utils/color_utils.dart';

void main() {
  group('hsv <-> argb', () {
    test('the primary hues land on their exact channels', () {
      expect(argbFromHsv(const HsvColor(hue: 0, saturation: 1, value: 1)),
          0xFFFF0000);
      expect(argbFromHsv(const HsvColor(hue: 120, saturation: 1, value: 1)),
          0xFF00FF00);
      expect(argbFromHsv(const HsvColor(hue: 240, saturation: 1, value: 1)),
          0xFF0000FF);
    });

    test('sector boundaries pick the sector they belong to', () {
      // 60° is the boundary between the red and green sectors of the standard
      // conversion; getting it wrong swaps the two neighbouring colours.
      expect(argbFromHsv(const HsvColor(hue: 60, saturation: 1, value: 1)),
          0xFFFFFF00);
      expect(argbFromHsv(const HsvColor(hue: 180, saturation: 1, value: 1)),
          0xFF00FFFF);
      expect(argbFromHsv(const HsvColor(hue: 300, saturation: 1, value: 1)),
          0xFFFF00FF);
    });

    test('zero saturation is a grey of the requested value', () {
      expect(argbFromHsv(const HsvColor(hue: 200, saturation: 0, value: 0)),
          0xFF000000);
      expect(argbFromHsv(const HsvColor(hue: 200, saturation: 0, value: 1)),
          0xFFFFFFFF);
    });

    test('hue wraps instead of being rejected', () {
      expect(argbFromHsv(const HsvColor(hue: 360, saturation: 1, value: 1)),
          argbFromHsv(const HsvColor(hue: 0, saturation: 1, value: 1)));
      expect(argbFromHsv(const HsvColor(hue: -120, saturation: 1, value: 1)),
          argbFromHsv(const HsvColor(hue: 240, saturation: 1, value: 1)));
    });

    test('round-trips a spread of colours', () {
      for (final int argb in <int>[
        0xFFFF0000,
        0xFF00FF00,
        0xFF0000FF,
        0xFFFDD835,
        0xFF1E88E5,
        0xFF8E24AA,
        0xFF6D4C41,
        0xFF757575,
      ]) {
        final HsvColor hsv = hsvFromArgb(argb);
        expect(argbFromHsv(hsv), argb, reason: 'round trip of $argb via $hsv');
      }
    });

    test('grey has no hue rather than a random one', () {
      expect(hsvFromArgb(0xFF808080).saturation, 0);
      expect(hsvFromArgb(0xFF000000).value, 0);
    });
  });

  group('hex', () {
    test('formats as #RRGGBB', () {
      expect(hexFromArgb(0xFF1E88E5), '#1E88E5');
      expect(hexFromArgb(0xFF000000), '#000000');
      // The alpha channel is not part of the display form.
      expect(hexFromArgb(0x801E88E5), '#1E88E5');
    });

    test('parses the forms people actually paste', () {
      expect(argbFromHex('#1E88E5'), 0xFF1E88E5);
      expect(argbFromHex('1e88e5'), 0xFF1E88E5);
      expect(argbFromHex('  #1e88e5 '), 0xFF1E88E5);
      expect(argbFromHex('#f00'), 0xFFFF0000);
      expect(argbFromHex('#801E88E5'), 0x801E88E5);
    });

    test('rejects what is not a colour', () {
      expect(argbFromHex(''), isNull);
      expect(argbFromHex('#12345'), isNull);
      expect(argbFromHex('red'), isNull);
      expect(argbFromHex('#GGGGGG'), isNull);
    });

    test('format then parse is the identity', () {
      for (final int argb in <int>[0xFF1E88E5, 0xFF000000, 0xFFFFFFFF]) {
        expect(argbFromHex(hexFromArgb(argb)), argb);
      }
    });
  });

  group('readability', () {
    test('contrast spans the full range', () {
      expect(contrastRatio(0xFFFFFFFF, 0xFF000000), closeTo(21, 0.01));
      expect(contrastRatio(0xFF1E88E5, 0xFF1E88E5), closeTo(1, 0.001));
    });

    test('flags text that cannot be read on its card', () {
      // Dark grey text on a near-black card: the case the warning exists for.
      expect(isHardToRead(0xFF263238, 0xFF000000), isTrue);
      // And the same palette used sensibly is not flagged.
      expect(isHardToRead(0xFFFFFFFF, 0xFF000000), isFalse);
      expect(isHardToRead(0xFF000000, 0xFFFFFFFF), isFalse);
    });

    test('suggests the readable side for an arbitrary background', () {
      expect(readableOn(0xFFFFFFFF), 0xFF000000);
      expect(readableOn(0xFF000000), 0xFFFFFFFF);
      expect(readableOn(0xFFFFF9C4), 0xFF000000);
    });
  });

  group('pixel sampling (colour extraction)', () {
    /// A 3x2 image: two rows of three distinct colours.
    ByteData buffer() {
      final ByteData data = ByteData(3 * 2 * 4);
      const List<int> pixels = <int>[
        0xFF, 0x00, 0x00, 0xFF, // (0,0) red
        0x00, 0xFF, 0x00, 0xFF, // (1,0) green
        0x00, 0x00, 0xFF, 0xFF, // (2,0) blue
        0xFF, 0xFF, 0x00, 0xFF, // (0,1) yellow
        0x00, 0x00, 0x00, 0xFF, // (1,1) black
        0xFF, 0xFF, 0xFF, 0xFF, // (2,1) white
      ];
      for (int i = 0; i < pixels.length; i++) {
        data.setUint8(i, pixels[i]);
      }
      return data;
    }

    test('reads the requested pixel', () {
      final ByteData data = buffer();
      expect(argbAtRgba(data, 3, 2, 0, 0), 0xFFFF0000);
      expect(argbAtRgba(data, 3, 2, 2, 0), 0xFF0000FF);
      expect(argbAtRgba(data, 3, 2, 0, 1), 0xFFFFFF00);
      expect(argbAtRgba(data, 3, 2, 2, 1), 0xFFFFFFFF);
    });

    test('refuses coordinates outside the image instead of clamping', () {
      final ByteData data = buffer();
      expect(argbAtRgba(data, 3, 2, -1, 0), isNull);
      expect(argbAtRgba(data, 3, 2, 3, 0), isNull);
      expect(argbAtRgba(data, 3, 2, 0, 2), isNull);
    });

    test('averages a neighbourhood to smooth out noise', () {
      // A 4x4 mid-grey image with one white pixel: sampling the white pixel
      // alone would return white, the average stays close to grey.
      const int size = 4;
      final ByteData data = ByteData(size * size * 4);
      for (int i = 0; i < size * size; i++) {
        final int offset = i * 4;
        final bool white = i == 5;
        final int value = white ? 0xFF : 0x80;
        data.setUint8(offset, value);
        data.setUint8(offset + 1, value);
        data.setUint8(offset + 2, value);
        data.setUint8(offset + 3, 0xFF);
      }
      final int? exact = argbAtRgba(data, size, size, 1, 1);
      final int? averaged = averageArgbAtRgba(data, size, size, 1, 1);
      expect(exact, 0xFFFFFFFF);
      expect(averaged, isNotNull);
      final int red = (averaged! >> 16) & 0xFF;
      expect(red, lessThan(0xFF));
      expect(red, greaterThan(0x80));
    });

    test('clips the box at the edges rather than failing', () {
      final ByteData data = buffer();
      // Top-left corner: only the pixels that exist are averaged.
      expect(averageArgbAtRgba(data, 3, 2, 0, 0), isNotNull);
      expect(averageArgbAtRgba(data, 3, 2, 2, 1), isNotNull);
      expect(averageArgbAtRgba(data, 3, 2, 5, 5), isNull);
    });
  });
}
