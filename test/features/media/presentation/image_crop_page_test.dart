import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/media/presentation/image_crop_page.dart';

/// The picture the cropper is given: twice as wide as it is tall, so a crop that
/// keeps its shape is obviously different from one that does not.
const int _sourceWidth = 400;
const int _sourceHeight = 200;

void main() {
  late Directory directory;
  late File source;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('m3e_crop_page');
    source = await _writeImage(directory, _sourceWidth, _sourceHeight);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  testWidgets('the whole picture starts framed', (WidgetTester tester) async {
    await tester.runAsync(() => _pumpCropper(tester, source));

    expect(_reportedSize(tester), const Size(400, 200));
  });

  testWidgets('dragging a corner keeps the part that is left', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() => _pumpCropper(tester, source));

    final Rect shown = tester.getRect(find.byType(RawImage));
    final double scale = shown.width / _sourceWidth;

    // Grab the bottom-right corner and pull it in by a known part of the
    // picture: what is left inside the frame is what gets kept.
    //
    // Started a couple of pixels inside the corner, because the very corner of
    // the picture is the edge of the widget and a touch exactly on it lands
    // outside. The slack is why the assertions below allow a few pixels.
    await tester.dragFrom(
      shown.bottomRight - const Offset(2, 2),
      Offset(-100 * scale, -50 * scale),
    );
    await tester.pumpAndSettle();

    final Size kept = _reportedSize(tester);
    expect(kept.width, closeTo(300, 3));
    expect(kept.height, closeTo(150, 3));
  });

  testWidgets('the frame can be moved without changing its size', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() => _pumpCropper(tester, source));

    final Rect shown = tester.getRect(find.byType(RawImage));
    final double scale = shown.width / _sourceWidth;

    await tester.dragFrom(
      shown.bottomRight - const Offset(2, 2),
      Offset(-100 * scale, -50 * scale),
    );
    await tester.pumpAndSettle();
    final Size afterResize = _reportedSize(tester);

    // Dragging the middle of the frame moves it over the picture; the size must
    // survive — this is the "no, not that bit, this bit" gesture.
    await tester.dragFrom(
      shown.topLeft + Offset(150 * scale, 75 * scale),
      Offset(50 * scale, 20 * scale),
    );
    await tester.pumpAndSettle();

    // A pixel of slack: the frame is rounded outwards to whole source pixels on
    // the way out, and moving it over fractional coordinates can tip that
    // rounding either way without the frame itself changing size.
    final Size moved = _reportedSize(tester);
    expect(moved.width, closeTo(afterResize.width, 2));
    expect(moved.height, closeTo(afterResize.height, 2));
  });

  testWidgets('dragging outside the frame draws a new one', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() => _pumpCropper(tester, source));

    final Rect shown = tester.getRect(find.byType(RawImage));
    final double scale = shown.width / _sourceWidth;

    // Shrink the frame away from the top-left corner first, so there is bare
    // picture to draw on.
    await tester.dragFrom(
      shown.topLeft + const Offset(2, 2),
      Offset(200 * scale - 2, 100 * scale - 2),
    );
    await tester.pumpAndSettle();
    expect(_reportedSize(tester), const Size(200, 100));

    // Now draw a box in the empty corner: the frame should become exactly what
    // was dragged, not something the app decided.
    await tester.dragFrom(
      shown.topLeft + Offset(10 * scale, 10 * scale),
      Offset(80 * scale, 40 * scale),
    );
    await tester.pumpAndSettle();

    // A pixel of slack: the drag lands on fractions of a source pixel, and the
    // kept area is rounded outwards to whole ones.
    final Size drawn = _reportedSize(tester);
    expect(drawn.width, closeTo(80, 2));
    expect(drawn.height, closeTo(40, 2));
  });

  testWidgets('a drag that barely moved leaves the frame alone', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() => _pumpCropper(tester, source));

    final Rect shown = tester.getRect(find.byType(RawImage));
    final double scale = shown.width / _sourceWidth;

    // A tap on the picture is not a selection, and neither is a twitch.
    await tester.tapAt(shown.center);
    await tester.pumpAndSettle();
    expect(_reportedSize(tester), const Size(400, 200));

    // Shrink the frame, then twitch in the empty corner: the frame the user
    // built must survive an accidental touch.
    await tester.dragFrom(
      shown.topLeft + const Offset(2, 2),
      Offset(200 * scale - 2, 100 * scale - 2),
    );
    await tester.pumpAndSettle();
    await tester.dragFrom(
      shown.topLeft + const Offset(20, 20),
      const Offset(6, 6),
    );
    await tester.pumpAndSettle();

    expect(_reportedSize(tester), const Size(200, 100));
  });

  testWidgets('a shape chip re-fits the frame', (WidgetTester tester) async {
    await tester.runAsync(() => _pumpCropper(tester, source));

    await tester.tap(find.text('1:1'));
    await tester.pumpAndSettle();

    // The largest square that fits the picture, which for a 400×200 picture is
    // 200×200.
    expect(_reportedSize(tester), const Size(200, 200));

    await tester.tap(find.text('原图'));
    await tester.pumpAndSettle();
    // Back to the picture's own shape.
    expect(_reportedSize(tester), const Size(400, 200));

    await tester.tap(find.text('自由'));
    await tester.pumpAndSettle();
    // Free keeps what was framed instead of resetting it.
    expect(_reportedSize(tester), const Size(400, 200));
  });
}

/// Pumps the cropper for [file] on a phone-sized window.
Future<void> _pumpCropper(WidgetTester tester, File file) async {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: ImageCropPage(sourcePath: file.path),
    ),
  );
  // Decoding a real file is async work the test binding will not fake, so it
  // needs the real event loop; the extra pumps then let the picture appear.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

/// The size the page says it will keep, read off the line under the picture.
///
/// The line is the user's own view of the frame, which makes it the honest thing
/// to assert on: it is what "did I select the part I wanted" means.
Size _reportedSize(WidgetTester tester) {
  final Text label = tester.widget<Text>(
    find.byWidgetPredicate(
      (Widget widget) => widget is Text && (widget.data ?? '').startsWith('保留'),
    ),
  );
  final RegExpMatch? match =
      RegExp(r'(\d+)\s*×\s*(\d+)').firstMatch(label.data ?? '');
  expect(match, isNotNull, reason: 'the size line reads "${label.data}"');
  return Size(
    double.parse(match!.group(1)!),
    double.parse(match.group(2)!),
  );
}

/// Writes a real PNG of [width]×[height] to [directory].
///
/// A real encoder rather than a checked-in fixture: the cropper runs the file
/// through the engine's own decoder, so anything less than a real image would
/// test the fixture instead of the page.
Future<File> _writeImage(Directory directory, int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF1E88E5),
  );
  final ui.Image image = await recorder.endRecording().toImage(width, height);
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final File file = File('${directory.path}${Platform.pathSeparator}source.png');
  await file.writeAsBytes(png!.buffer.asUint8List());
  return file;
}
