import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/app_motion.dart';
import '../utils/wheel_scroll_accumulator.dart';

/// Lets a desktop pane's empty gutters scroll its primary content.
class DesktopWheelScrollRegion extends StatefulWidget {
  const DesktopWheelScrollRegion({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final ScrollController? controller;

  @override
  State<DesktopWheelScrollRegion> createState() =>
      _DesktopWheelScrollRegionState();
}

class _DesktopWheelScrollRegionState extends State<DesktopWheelScrollRegion> {
  final List<_DiscoveredScrollable> _discoveredScrollables = [];
  final Map<ScrollPosition, _SmoothWheelDriver> _drivers = {};
  AppMotionMode? _lastMotionMode;

  AppMotionMode get _motionMode {
    final inherited = AppMotionScope.maybeOf(context);
    if (inherited != null) return inherited;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AppMotion.resolveMode(
      eInk: false,
      snappy: false,
      reduceMotion: reduceMotion,
    );
  }

  Duration get _wheelDuration =>
      AppMotion.duration(AppMotion.state, _motionMode);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = _motionMode;
    if (_lastMotionMode != null && _lastMotionMode != mode) {
      for (final driver in _drivers.values) {
        driver.cancel();
      }
    }
    _lastMotionMode = mode;
  }

  void _pruneDrivers() {
    final activePositions = widget.controller != null
        ? (widget.controller!.hasClients
              ? widget.controller!.positions.toSet()
              : <ScrollPosition>{})
        : {
            for (final candidate in _discoveredScrollables)
              if (candidate.scrollable.mounted) candidate.scrollable.position,
          };
    _drivers.removeWhere((position, driver) {
      if (activePositions.contains(position)) return false;
      driver.dispose();
      return true;
    });
  }

  _WheelTarget? _targetFor(PointerScrollEvent event) {
    _pruneDrivers();
    final controller = widget.controller;
    if (controller != null) {
      if (!controller.hasClients || controller.positions.length != 1) {
        return null;
      }
      return _targetForPosition(controller.position, event);
    }

    _discoveredScrollables.removeWhere(
      (candidate) => !candidate.scrollable.mounted,
    );
    _WheelTarget? bestTarget;
    var bestDepth = 1 << 20;
    var bestVisibleArea = -1.0;
    final preferredAxis =
        event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
        ? Axis.vertical
        : Axis.horizontal;
    for (final candidate in _discoveredScrollables) {
      final scrollable = candidate.scrollable;
      if (!_isActive(scrollable)) continue;
      final position = scrollable.position;
      if (axisDirectionToAxis(position.axisDirection) != preferredAxis) {
        continue;
      }
      final target = _targetForPosition(position, event);
      if (target == null) continue;
      final visibleArea = _visibleArea(scrollable);
      if (visibleArea <= 0) continue;
      if (candidate.depth < bestDepth ||
          (candidate.depth == bestDepth && visibleArea > bestVisibleArea)) {
        bestTarget = target;
        bestDepth = candidate.depth;
        bestVisibleArea = visibleArea;
      }
    }
    return bestTarget;
  }

  double _visibleArea(ScrollableState scrollable) {
    final regionObject = context.findRenderObject();
    final scrollObject = scrollable.context.findRenderObject();
    if (regionObject is! RenderBox ||
        scrollObject is! RenderBox ||
        !regionObject.attached ||
        !scrollObject.attached) {
      return 0;
    }
    final scrollBounds = MatrixUtils.transformRect(
      scrollObject.getTransformTo(regionObject),
      scrollObject.paintBounds,
    );
    final visibleBounds = scrollBounds.intersect(
      Offset.zero & regionObject.size,
    );
    if (visibleBounds.isEmpty) return 0;
    return visibleBounds.width * visibleBounds.height;
  }

  _WheelTarget? _targetForPosition(
    ScrollPosition position,
    PointerScrollEvent event,
  ) {
    if (!position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return null;
    }
    final axis = axisDirectionToAxis(position.axisDirection);
    var delta = axis == Axis.vertical
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (axisDirectionIsReversed(position.axisDirection)) delta = -delta;
    final destination = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (delta == 0 || destination == position.pixels) return null;
    return _WheelTarget(position, delta);
  }

  bool _isActive(ScrollableState scrollable) {
    final renderObject = scrollable.context.findRenderObject();
    if (!(renderObject?.attached ?? false)) return false;
    final route = ModalRoute.of(scrollable.context);
    return (route == null || route.isCurrent) &&
        TickerMode.of(scrollable.context);
  }

  void _rememberPosition(BuildContext? notificationContext, int depth) {
    if (notificationContext == null) return;
    final scrollable = Scrollable.maybeOf(notificationContext);
    if (scrollable == null) return;
    _discoveredScrollables
      ..removeWhere((candidate) => candidate.scrollable == scrollable)
      ..insert(0, _DiscoveredScrollable(scrollable, depth));
  }

  bool _handleMetricsNotification(ScrollMetricsNotification notification) {
    _rememberPosition(notification.context, notification.depth);
    return false;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    _rememberPosition(notification.context, notification.depth);
    // A real drag cancels an in-flight wheel animation. The next wheel event
    // always starts from the actual position, so rebasing here also covers
    // scrollbar and keyboard movement that ends before the next wheel event.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      for (final driver in _drivers.values) {
        driver.cancel();
      }
    }
    return false;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final target = _targetFor(event);
    if (target == null) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      if (resolvedEvent is! PointerScrollEvent) return;
      final driver = _drivers.putIfAbsent(
        target.position,
        () => _SmoothWheelDriver(
          target.position,
          isAttached: () => _isPositionActive(target.position),
        ),
      );
      driver.addDelta(
        target.delta,
        min: target.position.minScrollExtent,
        max: target.position.maxScrollExtent,
        duration: _wheelDuration,
      );
      resolvedEvent.respond(allowPlatformDefault: false);
    });
  }

  bool _isPositionActive(ScrollPosition position) {
    final controller = widget.controller;
    if (controller != null) {
      return controller.hasClients && controller.positions.contains(position);
    }
    return _discoveredScrollables.any(
      (candidate) =>
          candidate.scrollable.mounted &&
          identical(candidate.scrollable.position, position),
    );
  }

  @override
  void dispose() {
    for (final driver in _drivers.values) {
      driver.dispose();
    }
    _drivers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = NotificationListener<ScrollMetricsNotification>(
      onNotification: _handleMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: widget.child,
      ),
    );
    return Stack(
      children: [
        content,
        // Put the pointer-signal listener above descendant Scrollables. This
        // lets the smooth driver win the resolver for wheel/trackpad input
        // over the content itself, not only in the surrounding gutters.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: _handlePointerSignal,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _DiscoveredScrollable {
  const _DiscoveredScrollable(this.scrollable, this.depth);

  final ScrollableState scrollable;
  final int depth;
}

class _WheelTarget {
  const _WheelTarget(this.position, this.delta);

  final ScrollPosition position;
  final double delta;
}

class _SmoothWheelDriver {
  _SmoothWheelDriver(this.position, {required this.isAttached})
    : _accumulator = WheelScrollAccumulator(initialTarget: position.pixels);

  final ScrollPosition position;
  final bool Function() isAttached;
  final WheelScrollAccumulator _accumulator;
  bool _disposed = false;

  void addDelta(
    double delta, {
    required double min,
    required double max,
    required Duration duration,
  }) {
    if (_disposed || !isAttached() || !position.hasPixels) return;
    // Start from the real position on every event. This prevents keyboard,
    // scrollbar, touchpad, and user-drag movement from leaving a stale target
    // behind while still giving each wheel tick a smooth easing curve.
    _accumulator.rebase(position.pixels);
    final destination = _accumulator.add(delta: delta, min: min, max: max);
    unawaited(_animateTo(destination, duration));
  }

  void cancel() {
    if (_disposed || !isAttached() || !position.hasPixels) return;
    // jumpTo at the current value cancels an active animateTo without moving
    // the user-visible scroll position.
    position.jumpTo(position.pixels);
    _accumulator.rebase(position.pixels);
  }

  Future<void> _animateTo(double destination, Duration duration) async {
    if (_disposed || !isAttached() || !position.hasPixels) return;
    if (duration == Duration.zero) {
      position.jumpTo(destination);
      return;
    }
    try {
      await position.animateTo(
        destination,
        duration: duration,
        curve: AppMotion.curve,
      );
    } catch (_) {
      // A scroll position can detach while an input animation is in flight.
      // Its owner is already going away, so there is no useful recovery here.
    }
  }

  void dispose() {
    _disposed = true;
  }
}
