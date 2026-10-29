import 'package:flutter/widgets.dart';

/// Stops animation tickers on surfaces that are retained off-screen.
///
/// The widget tree and its state stay mounted, so scroll positions and form
/// state are preserved while inactive pages stop consuming frame callbacks.
Widget withActiveSurfaceTickers({
  required bool active,
  required Widget child,
}) {
  return TickerMode(enabled: active, child: child);
}
