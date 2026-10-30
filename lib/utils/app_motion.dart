import 'package:flutter/widgets.dart';

/// The motion modes shared by shell, navigation, and desktop input.
enum AppMotionMode { normal, reduced, instant }

/// The app-wide motion policy. Animation timings themselves stay at upstream
/// Absorb's and Material's values; this only decides when they are skipped.
///
/// Keep this class pure so policy decisions can be tested without a widget
/// tree. Widgets decide whether reduced motion is requested and pass the
/// resulting mode here.
abstract final class AppMotion {
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

/// Makes the app-wide motion mode available to shared desktop widgets without
/// importing the app entrypoint into lower-level UI code.
class AppMotionScope extends InheritedWidget {
  const AppMotionScope({
    super.key,
    required this.mode,
    required super.child,
  });

  final AppMotionMode mode;

  static AppMotionMode? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppMotionScope>()?.mode;

  @override
  bool updateShouldNotify(AppMotionScope oldWidget) => mode != oldWidget.mode;
}
