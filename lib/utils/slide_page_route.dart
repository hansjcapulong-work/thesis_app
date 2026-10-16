import 'package:flutter/material.dart';

/// Builds a slide transition whose direction depends on whether you're
/// moving to a "later" tab (slides in from the right) or an "earlier"
/// tab (slides in from the left) — like real forward/back navigation.
Route<T> slideToTabRoute<T>({
  required Widget page,
  required int fromIndex,
  required int toIndex,
  Duration duration = const Duration(milliseconds: 260),
}) {
  final bool movingForward = toIndex > fromIndex;
  final Offset beginOffset = movingForward ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0);

  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween(begin: beginOffset, end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}