import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'spring_curve.dart';

/// A motion curve paired with the duration it needs to finish.
///
/// Keeping the two together prevents the classic bug where a spring curve is
/// given an arbitrary duration, so the animation stops mid-flight or sits still
/// waiting for a spring that already settled.
@immutable
class MotionSpec {
  const MotionSpec({
    required this.curve,
    required this.duration,
    required this.token,
  });

  /// Shape of the motion.
  final Curve curve;

  /// How long the motion runs for.
  final Duration duration;

  /// Name of the Material motion token this spec was derived from, useful in
  /// debug output and documentation.
  final String token;

  @override
  String toString() => 'MotionSpec($token, ${duration.inMilliseconds}ms)';
}

/// Material 3 Expressive motion tokens.
///
/// Two families exist, mirroring the spec:
///
///  * **Spatial** springs move something from A to B. They are slightly
///    underdamped (`zeta = 0.9`) so they settle with a subtle bounce.
///  * **Effects** springs animate a property in place (colour, opacity,
///    elevation). They are critically damped (`zeta = 1.0`) so nothing wobbles.
///
/// Each family comes in fast / default / slow. The stiffness values follow the
/// published M3 Expressive spring tokens; the durations are *derived* from each
/// spring's own settling time rather than hard-coded, so an animation always
/// ends exactly as the spring comes to rest.
abstract final class AppMotion {
  static MotionSpec _spring({
    required String token,
    required double stiffness,
    required double dampingRatio,
  }) {
    final SpringCurve curve = SpringCurve(
      stiffness: stiffness,
      dampingRatio: dampingRatio,
    );
    return MotionSpec(
      curve: curve,
      duration: curve.suggestedDuration,
      token: token,
    );
  }

  /// For small components travelling a short distance.
  static final MotionSpec spatialFast =
      _spring(token: 'spatial.fast', stiffness: 1400, dampingRatio: 0.9);

  /// The workhorse for page and panel transitions.
  static final MotionSpec spatialDefault =
      _spring(token: 'spatial.default', stiffness: 700, dampingRatio: 0.9);

  /// For large surfaces entering or leaving the screen.
  static final MotionSpec spatialSlow =
      _spring(token: 'spatial.slow', stiffness: 300, dampingRatio: 0.9);

  /// Colour, opacity and state changes that should feel instant.
  static final MotionSpec effectsFast =
      _spring(token: 'effects.fast', stiffness: 3800, dampingRatio: 1.0);

  /// Default for in-place property changes such as hover and selection.
  static final MotionSpec effectsDefault =
      _spring(token: 'effects.default', stiffness: 1600, dampingRatio: 1.0);

  /// Deliberate property changes, such as a surface changing elevation.
  static final MotionSpec effectsSlow =
      _spring(token: 'effects.slow', stiffness: 800, dampingRatio: 1.0);
}
