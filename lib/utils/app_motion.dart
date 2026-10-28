import 'package:flutter/animation.dart';

/// The motion modes shared by shell, navigation, and desktop input.
enum AppMotionMode { normal, reduced, instant }

/// Central timing tokens for interactions that should feel related.
///
/// Keep this class pure so policy decisions can be tested without a widget
/// tree. Widgets decide whether reduced motion is requested and pass the
/// resulting mode here.
abstract final class AppMotion {
  static const micro = Duration(milliseconds: 120);
  static const state = Duration(milliseconds: 180);
  static const navigation = Duration(milliseconds: 220);
  static const modal = Duration(milliseconds: 280);

  static const curve = Curves.easeOutCubic;
  static const navigationCurve = Curves.easeInOutCubic;

  static AppMotionMode resolveMode({
    required bool eInk,
    required bool snappy,
    required bool reduceMotion,
  }) {
    if (eInk || snappy) return AppMotionMode.instant;
    if (reduceMotion) return AppMotionMode.reduced;
    return AppMotionMode.normal;
  }

  static Duration duration(Duration requested, AppMotionMode mode) =>
      mode == AppMotionMode.normal ? requested : Duration.zero;
}
