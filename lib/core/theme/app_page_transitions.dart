import 'package:flutter/material.dart';

import 'app_motion.dart';

/// A page transition driven by Material 3 Expressive springs.
///
/// Two springs run at once, each chosen for what it animates:
///
///  * the incoming page *slides* using the spatial spring, so it arrives with a
///    barely perceptible settle rather than a hard stop;
///  * it *fades* using the effects spring, which is critically damped. That
///    matters because [FadeTransition] asserts its value stays within `[0, 1]`,
///    and an underdamped spring would overshoot past 1.
///
/// The outgoing page recedes by a couple of percent instead of sliding away,
/// which keeps the two layers visually stacked rather than crossing.
class ExpressivePageTransitionsBuilder extends PageTransitionsBuilder {
  const ExpressivePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<Offset> incomingSlide = animation.drive(
      Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).chain(CurveTween(curve: AppMotion.spatialDefault.curve)),
    );

    final Animation<double> incomingFade = animation.drive(
      CurveTween(curve: AppMotion.effectsDefault.curve),
    );

    final Animation<Offset> outgoingSlide = secondaryAnimation.drive(
      Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(0, -0.02),
      ).chain(CurveTween(curve: AppMotion.spatialDefault.curve)),
    );

    return SlideTransition(
      position: outgoingSlide,
      child: FadeTransition(
        opacity: incomingFade,
        child: SlideTransition(position: incomingSlide, child: child),
      ),
    );
  }
}

/// Applies the Expressive transition to every desktop platform.
abstract final class AppPageTransitions {
  static const PageTransitionsTheme theme = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.windows: ExpressivePageTransitionsBuilder(),
      TargetPlatform.macOS: ExpressivePageTransitionsBuilder(),
      TargetPlatform.linux: ExpressivePageTransitionsBuilder(),
      TargetPlatform.android: ExpressivePageTransitionsBuilder(),
      TargetPlatform.iOS: ExpressivePageTransitionsBuilder(),
      TargetPlatform.fuchsia: ExpressivePageTransitionsBuilder(),
    },
  );
}
