import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Compile-time switch, set with `--dart-define=M3E_FRAME_LOG=true`.
///
/// A `const` on purpose: when it is false the call below is folded away by the
/// compiler, so a shipping build carries no timing callback and no cost.
const bool _frameLogEnabled = bool.fromEnvironment('M3E_FRAME_LOG');

/// Frames between percentile summaries.
const int _summaryEvery = 60;

/// How long a partial batch may sit unsummarised.
///
/// A tap or a single keystroke produces a handful of frames, never 60, so
/// without this a discrete interaction would report nothing but its janky
/// frames — and "no janky frames" is indistinguishable from "no frames".
const Duration _summaryAfter = Duration(seconds: 2);

/// Logs frame timings to logcat so "卡顿" can be measured rather than guessed at.
///
/// Why this exists instead of `adb shell dumpsys gfxinfo`: a Flutter app draws on
/// its own raster thread into a SurfaceView, so Android's per-app graphics stats
/// report **zero frames** for it. `dumpsys SurfaceFlinger --latency` does show
/// presented frames, but only *when* a frame reached the display — it cannot say
/// whether the time went into the Dart build phase or into rasterisation, which
/// is the first thing you need to know before optimising anything.
///
/// [FrameTiming] answers exactly that, and it is what Flutter's own benchmarks
/// use. Every frame over the budget is printed with its build/raster split;
/// every [_summaryEvery] frames a percentile summary follows.
///
/// Usage:
///
/// ```powershell
/// flutter build apk --profile --dart-define=M3E_FRAME_LOG=true
/// adb install -r build\app\outputs\flutter-apk\app-profile.apk
/// adb logcat -c; # ...exercise the app...
/// adb logcat -d | Select-String M3E_FRAME
/// ```
void installFrameLogger({
  Duration budget = const Duration(milliseconds: 32),
  bool verbose = true,
}) {
  if (!_frameLogEnabled) {
    return;
  }

  final int budgetUs = budget.inMicroseconds;
  final List<int> samples = <int>[];
  int total = 0;
  int janky = 0;

  void flush() {
    if (samples.isEmpty) {
      return;
    }
    final List<int> sorted = List<int>.of(samples)..sort();
    int at(double q) => sorted[((sorted.length - 1) * q).round()];
    debugPrint(
      'M3E_FRAME summary frames=${sorted.length} janky=$janky/$total '
      'p50=${at(0.5)}us p90=${at(0.9)}us p99=${at(0.99)}us '
      'max=${sorted.last}us',
    );
    samples.clear();
    total = 0;
    janky = 0;
  }

  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final FrameTiming timing in timings) {
      final int span = timing.totalSpan.inMicroseconds;
      total++;
      samples.add(span);
      if (span <= budgetUs) {
        continue;
      }
      janky++;
      if (verbose) {
        debugPrint(
          'M3E_FRAME janky #$janky/$total '
          'build=${timing.buildDuration.inMicroseconds}us '
          'raster=${timing.rasterDuration.inMicroseconds}us '
          'vsync=${timing.vsyncOverhead.inMicroseconds}us '
          'total=${span}us',
        );
      }
    }

    if (samples.length >= _summaryEvery) {
      flush();
    }
  });

  Timer.periodic(_summaryAfter, (Timer _) => flush());
}
