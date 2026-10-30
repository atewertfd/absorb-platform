import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Smooths mouse-wheel scrolling on Windows and Linux.
///
/// Flutter applies each wheel notch as one instant jump, which reads as
/// choppy scrolling. This sits between the engine and the gesture binding:
/// each mouse-wheel event is held back and re-sent as smaller wheel events,
/// one per frame, following a critically damped spring (95% of a notch lands
/// within about 190 ms). A spring keeps the speed steady while the wheel keeps
/// turning; a plain ease-out pulses fast-slow on every notch, which still
/// looks choppy. Scrollables handle those
/// like any other wheel input, so nested lists, scroll limits and Shift+wheel
/// keep working and no widget needs to change. Everything else (clicks,
/// moves, trackpad pan/zoom) passes straight through.
class SmoothWheelScroll {
  SmoothWheelScroll({
    required this.emit,
    required this.onActive,
    this.shouldSmooth = _always,
    this.stiffness = 25,
  });

  static bool _always(ui.PointerData d) => true;

  /// Forwards a packet to the gesture binding (the engine's original handler).
  final void Function(ui.PointerDataPacket packet) emit;

  /// Called when wheel motion is pending, so the caller starts ticking.
  final VoidCallback onActive;

  /// Wheel events this returns false for pass through as plain jumps.
  final bool Function(ui.PointerData d) shouldSmooth;

  /// The spring's angular frequency (1/s); higher settles faster.
  final double stiffness;

  /// A pointer that moves this far (physical px) starts a new scroll target.
  static const double _retargetDistance = 32;

  /// Below this (physical px, and px per frame) the motion finishes in one step.
  static const double _finishThreshold = 0.5;

  ui.PointerData? _template;
  // Distance still to scroll, and the current speed (physical px per second).
  double _remainingX = 0;
  double _remainingY = 0;
  double _velocityX = 0;
  double _velocityY = 0;
  Duration _sinceEvent = Duration.zero;

  bool get isActive => _remainingX != 0 || _remainingY != 0;

  static bool isMouseWheel(ui.PointerData d) =>
      d.signalKind == ui.PointerSignalKind.scroll &&
      d.kind == ui.PointerDeviceKind.mouse;

  void handlePacket(ui.PointerDataPacket packet) {
    bool smooth(ui.PointerData d) => isMouseWheel(d) && shouldSmooth(d);
    if (!packet.data.any(smooth)) {
      emit(packet);
      return;
    }
    var passthrough = <ui.PointerData>[];
    for (final d in packet.data) {
      if (!smooth(d)) {
        passthrough.add(d);
        continue;
      }
      if (passthrough.isNotEmpty) {
        emit(ui.PointerDataPacket(data: passthrough));
        passthrough = <ui.PointerData>[];
      }
      _absorb(d);
    }
    if (passthrough.isNotEmpty) emit(ui.PointerDataPacket(data: passthrough));
  }

  void _absorb(ui.PointerData d) {
    final previous = _template;
    if (previous != null && isActive && !_sameTarget(previous, d)) {
      _send(_remainingX, _remainingY); // finish where the old motion started
      _stop();
    }
    _sinceEvent = Duration.zero;
    _template = d;
    // Turning the wheel the other way stops the old motion instead of
    // fighting it; the same direction keeps its speed, so spinning stays even.
    if (_remainingX * d.scrollDeltaX < 0) {
      _remainingX = 0;
      _velocityX = 0;
    }
    if (_remainingY * d.scrollDeltaY < 0) {
      _remainingY = 0;
      _velocityY = 0;
    }
    _remainingX += d.scrollDeltaX;
    _remainingY += d.scrollDeltaY;
    if (isActive) onActive();
  }

  void _stop() {
    _remainingX = 0;
    _remainingY = 0;
    _velocityX = 0;
    _velocityY = 0;
  }

  static bool _sameTarget(ui.PointerData a, ui.PointerData b) =>
      a.viewId == b.viewId &&
      a.device == b.device &&
      (a.physicalX - b.physicalX).abs() <= _retargetDistance &&
      (a.physicalY - b.physicalY).abs() <= _retargetDistance;

  /// Advances the motion by [dt]; returns whether more motion is pending.
  bool tick(Duration dt) {
    if (!isActive) return false;
    _sinceEvent += dt;
    final seconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
    final (stepX, velocityX) = _springStep(_remainingX, _velocityX, seconds);
    final (stepY, velocityY) = _springStep(_remainingY, _velocityY, seconds);
    _remainingX -= stepX;
    _remainingY -= stepY;
    _velocityX = velocityX;
    _velocityY = velocityY;
    _send(stepX, stepY);
    return isActive;
  }

  /// Exact critically damped spring step towards zero remaining distance;
  /// stable for any frame time. Returns the distance moved and the new speed.
  (double, double) _springStep(double remaining, double velocity, double dt) {
    if (remaining == 0) return (0, 0);
    final w = stiffness;
    final error = -remaining; // position relative to the target
    final decay = math.exp(-w * dt);
    final newError = (error + (velocity + w * error) * dt) * decay;
    final newVelocity = (velocity - w * (velocity + w * error) * dt) * decay;
    if (newError.abs() < _finishThreshold &&
        (newVelocity * dt).abs() < _finishThreshold) {
      return (remaining, 0); // land exactly on the target
    }
    return (newError - error, newVelocity);
  }

  void _send(double dx, double dy) {
    final d = _template;
    if (d == null || (dx == 0 && dy == 0)) return;
    emit(ui.PointerDataPacket(data: [
      ui.PointerData(
        viewId: d.viewId,
        embedderId: d.embedderId,
        timeStamp: d.timeStamp + _sinceEvent,
        change: d.change,
        kind: d.kind,
        signalKind: d.signalKind,
        device: d.device,
        pointerIdentifier: d.pointerIdentifier,
        physicalX: d.physicalX,
        physicalY: d.physicalY,
        buttons: d.buttons,
        platformData: d.platformData,
        scrollDeltaX: dx,
        scrollDeltaY: dy,
      ),
    ]));
  }
}

/// Installs [SmoothWheelScroll] on Windows and Linux desktop builds. Call once,
/// right after `WidgetsFlutterBinding.ensureInitialized()`. While [enabled]
/// returns false (e-ink, "Disable page fade") the wheel jumps as before.
void installSmoothWheelScroll({required bool Function() enabled}) {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.linux)) {
    return;
  }
  final dispatcher = ui.PlatformDispatcher.instance;
  final original = dispatcher.onPointerDataPacket;
  if (original == null) return;

  var last = Duration.zero;
  late final Ticker ticker;
  late final SmoothWheelScroll smoother;
  ticker = Ticker((elapsed) {
    // The first tick after start reports zero; count it as one 60 Hz frame
    // so the scroll starts moving on the very next frame.
    final dt = elapsed == Duration.zero
        ? const Duration(microseconds: 16667)
        : elapsed - last;
    last = elapsed;
    if (!smoother.tick(dt)) ticker.stop();
  }, debugLabel: 'SmoothWheelScroll');
  smoother = SmoothWheelScroll(
    emit: original,
    onActive: () {
      if (ticker.isActive) return;
      last = Duration.zero;
      ticker.start();
    },
    shouldSmooth: (d) =>
        enabled() &&
        // Respect the OS "reduce motion" switch.
        !dispatcher.accessibilityFeatures.disableAnimations &&
        !isOverTexture(d),
  );
  dispatcher.onPointerDataPacket = smoother.handlePacket;
}

/// Whether a native texture (the Windows ebook reader's WebView) is under the
/// pointer. WebView2 smooths wheel input itself and its plugin rounds each
/// event's delta, so it gets the original events.
@visibleForTesting
bool isOverTexture(ui.PointerData d) {
  final view = ui.PlatformDispatcher.instance.view(id: d.viewId);
  if (view == null) return false;
  final result = HitTestResult();
  GestureBinding.instance.hitTestInView(
    result,
    Offset(d.physicalX, d.physicalY) / view.devicePixelRatio,
    d.viewId,
  );
  return result.path.any((entry) => entry.target is TextureBox);
}
