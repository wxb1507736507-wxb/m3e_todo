import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/theme/app_motion.dart';
import 'package:m3e_todo/core/theme/spring_curve.dart';

void main() {
  group('endpoints', () {
    test('maps 0 to 0 and 1 to 1 for every token', () {
      for (final MotionSpec spec in <MotionSpec>[
        AppMotion.spatialFast,
        AppMotion.spatialDefault,
        AppMotion.spatialSlow,
        AppMotion.effectsFast,
        AppMotion.effectsDefault,
        AppMotion.effectsSlow,
      ]) {
        expect(spec.curve.transform(0), 0, reason: spec.token);
        expect(spec.curve.transform(1), 1, reason: spec.token);
      }
    });

    test('rejects out-of-range input the way every Flutter curve does', () {
      // Curve.transform asserts its input lies within [0, 1]. The clamping in
      // transformInternal is a release-build safety net for the case where that
      // assert is compiled out, so it is not observable from here.
      final SpringCurve curve = SpringCurve(stiffness: 700, dampingRatio: 0.9);
      expect(() => curve.transform(-1), throwsA(isA<AssertionError>()));
      expect(() => curve.transform(2), throwsA(isA<AssertionError>()));
    });
  });

  group('shape', () {
    test('a critically damped spring approaches its target monotonically', () {
      // This is what makes the effects spring safe to feed straight into
      // opacity and progress values, which assert they stay within [0, 1] and
      // would look wrong if they ever went backwards.
      final SpringCurve effects = SpringCurve(stiffness: 1600, dampingRatio: 1.0);
      double previous = 0;
      for (int i = 1; i <= 200; i++) {
        final double value = effects.transform(i / 200);
        expect(value, greaterThanOrEqualTo(previous));
        previous = value;
      }
      expect(previous, 1);
    });

    test('an underdamped spring settles back onto its target', () {
      final SpringCurve spatial = SpringCurve(stiffness: 700, dampingRatio: 0.9);
      // By the end of the window it has come to rest, so the final frame lands
      // exactly on the destination rather than a few thousandths short.
      expect(spatial.transform(1), 1);
      expect(spatial.transform(0.999), closeTo(1, 0.01));
    });
  });

  group('damping behaviour', () {
    test('an underdamped spring overshoots, which is the point of it', () {
      final SpringCurve spatial =
          SpringCurve(stiffness: 700, dampingRatio: 0.9);
      final double peak = _peakOf(spatial);
      expect(peak, greaterThan(1.0));
    });

    test('a critically damped spring never overshoots', () {
      // This is what makes the effects spring safe for opacity and progress
      // values, which assert they stay within [0, 1].
      for (final double stiffness in <double>[800, 1600, 3800]) {
        final SpringCurve effects =
            SpringCurve(stiffness: stiffness, dampingRatio: 1.0);
        for (int i = 0; i <= 200; i++) {
          final double value = effects.transform(i / 200);
          expect(value, inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('a stiffer spring settles sooner', () {
      final SpringCurve soft = SpringCurve(stiffness: 300, dampingRatio: 0.9);
      final SpringCurve stiff = SpringCurve(stiffness: 1400, dampingRatio: 0.9);
      expect(stiff.settlingTime, lessThan(soft.settlingTime));
      expect(stiff.suggestedDuration, lessThan(soft.suggestedDuration));
    });

    test('suggestedDuration stays inside its documented bounds', () {
      for (final MotionSpec spec in <MotionSpec>[
        AppMotion.spatialFast,
        AppMotion.spatialDefault,
        AppMotion.spatialSlow,
        AppMotion.effectsFast,
        AppMotion.effectsDefault,
        AppMotion.effectsSlow,
      ]) {
        expect(spec.duration.inMilliseconds, inInclusiveRange(80, 1200));
      }
    });

    test('derives the damping coefficient from the ratio', () {
      final SpringCurve curve = SpringCurve(stiffness: 100, dampingRatio: 1.0);
      // zeta = c / (2 * sqrt(k * m)); with k = 100 and m = 1, c must be 20.
      expect(curve.damping, closeTo(20, 1e-9));
      expect(curve.angularFrequency, closeTo(10, 1e-9));
    });
  });

  test('rejects nonsensical spring parameters', () {
    expect(() => SpringCurve(stiffness: 0), throwsA(isA<AssertionError>()));
    expect(
      () => SpringCurve(stiffness: 100, dampingRatio: 0),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => SpringCurve(stiffness: 100, mass: -1),
      throwsA(isA<AssertionError>()),
    );
  });
}

/// Highest value [curve] reaches across its range.
double _peakOf(SpringCurve curve) {
  double peak = 0;
  for (int i = 0; i <= 400; i++) {
    final double value = curve.transform(i / 400);
    if (value > peak) {
      peak = value;
    }
  }
  return peak;
}
