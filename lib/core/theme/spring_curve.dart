import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// A [Curve] backed by a real spring simulation.
///
/// Material 3 Expressive describes motion as *springs* (stiffness plus damping
/// ratio) instead of fixed bezier curves, because springs compose naturally,
/// stay continuous when interrupted mid-flight, and give the characteristic
/// slight overshoot that plain easing cannot express.
///
/// This curve maps normalised time `t` in `[0, 1]` onto the step response of a
/// damped harmonic oscillator released from rest:
///
///  * `dampingRatio < 1` (underdamped) overshoots past the target and settles
///    back &mdash; used for *spatial* motion, where things physically move.
///  * `dampingRatio == 1` (critically damped) approaches the target without
///    overshoot &mdash; used for *effects* motion such as colour and opacity,
///    where a bounce would look like a glitch.
///
/// A spring only reaches its target asymptotically, so the response is squeezed
/// into a fixed window derived from [settlingTime]. That guarantees
/// `transform(0) == 0` and `transform(1) == 1` while preserving the spring's
/// shape, which is what [Curve] consumers require.
///
/// Use [suggestedDuration] as the matching [AnimationController] duration so the
/// animation ends exactly when the spring comes to rest.
class SpringCurve extends Curve {
  SpringCurve({
    required this.stiffness,
    this.dampingRatio = 1.0,
    this.mass = 1.0,
  })  : assert(stiffness > 0, 'stiffness must be positive'),
        assert(dampingRatio > 0, 'dampingRatio must be positive'),
        assert(mass > 0, 'mass must be positive'),
        // Convert the spec's dimensionless damping ratio into the damping
        // coefficient the physics simulation expects.
        damping = dampingRatio * 2 * math.sqrt(stiffness * mass);

  /// Spring stiffness, in Newtons per metre. Higher is faster and snappier.
  final double stiffness;

  /// Dimensionless damping ratio (`zeta`). `1.0` is critically damped.
  final double dampingRatio;

  /// Mass attached to the spring, in kilograms.
  final double mass;

  /// Damping coefficient derived from [dampingRatio] and [stiffness].
  final double damping;

  /// The step response of a critically damped or underdamped oscillator.
  ///
  /// Built on each evaluation rather than cached in a field. [Curve] is
  /// annotated `@immutable`, so a mutable cache would break that contract, and
  /// constructing a [SpringSimulation] is only a handful of assignments &mdash;
  /// far cheaper than the state that would have to be kept consistent.
  SpringSimulation get _simulation => SpringSimulation(
        SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
        0.0,
        1.0,
        0.0,
      );

  /// Natural (undamped) angular frequency in radians per second.
  double get angularFrequency => math.sqrt(stiffness / mass);

  /// Time, in seconds, for the oscillation envelope to decay to roughly 0.1% of
  /// its initial amplitude.
  ///
  /// A critically damped spring decays as `(1 + wt)e^-wt`, which is slower than
  /// the pure exponential of the underdamped case, hence the larger constant.
  double get settlingTime {
    final double threshold = dampingRatio < 1.0 ? 6.9 : 9.2;
    return threshold / (dampingRatio * angularFrequency);
  }

  /// Duration that lets this spring come to rest, clamped to a sane range so an
  /// extreme spring definition cannot produce a jarring animation.
  Duration get suggestedDuration {
    final int milliseconds = (settlingTime * 1000).ceil();
    return Duration(milliseconds: milliseconds.clamp(80, 1200));
  }

  @override
  double transformInternal(double t) {
    if (t <= 0.0) {
      return 0.0;
    }
    if (t >= 1.0) {
      return 1.0;
    }
    return _simulation.x(t * settlingTime);
  }

  @override
  String toString() => 'SpringCurve(stiffness: $stiffness, '
      'dampingRatio: $dampingRatio, mass: $mass)';
}
