import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../utils/app_motion.dart';
import '../utils/wheel_scroll_accumulator.dart';

/// Lets a desktop pane's empty gutters scroll its primary content.
class DesktopWheelScrollRegion extends StatefulWidget {
  const DesktopWheelScrollRegion({
    super.key,
    required this.child,
    this.controller,
    this.enabled = true,
  });

  final Widget child;
  final ScrollController? controller;
  final bool enabled;

  @override
  State<DesktopWheelScrollRegion> createState() =>
      _DesktopWheelScrollRegionState();
}

class _DesktopWheelScrollRegionState extends State<DesktopWheelScrollRegion>
    with TickerProviderStateMixin {
  // Each discovered scroll position gets one ticker-driven animation. Keeping
  // the ticker here (rather than calling ScrollPosition.animateTo for every
  // pointer packet) lets a fast wheel stream retarget the same animation
  // without producing visible stop/start chunks.
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
      AppMotion.duration(AppMotion.wheel, _motionMode);

  // Flutter's Windows engine reports a mouse-wheel notch as a fixed 20-pixel
  // pointer delta, while trackpads report their actual pixel movement. A
  // modest mouse-only multiplier restores a useful line-sized scroll without
  // magnifying precise trackpad input.
  static const _mouseWheelScale = 2.5;

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
    if (event.kind == PointerDeviceKind.mouse) {
      delta *= _mouseWheelScale;
    }
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
    // AppShell keeps its tabs in an IndexedStack. Offstage pages remain
    // mounted, but they must never compete for pointer-wheel ownership with
    // the page currently visible to the user.
    RenderObject? ancestor = renderObject;
    while (ancestor != null) {
      if (ancestor is RenderOffstage && ancestor.offstage) return false;
      ancestor = ancestor.parent;
    }
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
          vsync: this,
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
    if (!widget.enabled) return widget.child;
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
  _SmoothWheelDriver(
    this.position, {
    required TickerProvider vsync,
    required this.isAttached,
  }) : _accumulator = WheelScrollAccumulator(initialTarget: position.pixels),
       _controller = AnimationController.unbounded(
         vsync: vsync,
         value: position.pixels,
       ) {
    _controller.addListener(_applyFrame);
  }

  final ScrollPosition position;
  final bool Function() isAttached;
  final WheelScrollAccumulator _accumulator;
  final AnimationController _controller;
  bool _disposed = false;

  void addDelta(
    double delta, {
    required double min,
    required double max,
    required Duration duration,
  }) {
    if (_disposed || !isAttached() || !position.hasPixels) return;
    // Preserve the accumulated target while our animation is running. Only
    // rebase when another input source moved the position underneath us; if
    // we rebase every packet, fast wheel input is reduced to repeated small
    // hops and feels exactly like the old choppy implementation.
    final wasAnimating = _controller.isAnimating;
    final externalDrift =
        (_controller.value - position.pixels).abs() > 0.5;
    _controller.stop(canceled: false);
    if (!wasAnimating || externalDrift) {
      _accumulator.rebase(position.pixels);
    }
    final destination = _accumulator.add(delta: delta, min: min, max: max);
    if (duration == Duration.zero) {
      position.jumpTo(destination);
      _controller.value = destination;
      return;
    }
    _controller.value = position.pixels;
    unawaited(
      _controller.animateTo(
        destination,
        duration: duration,
        curve: AppMotion.curve,
      ),
    );
  }

  void cancel() {
    if (_disposed || !isAttached() || !position.hasPixels) return;
    _controller.stop(canceled: false);
    // Rebase at the current visual position without moving the user-visible
    // scroll position. External input will establish the next target.
    position.jumpTo(position.pixels);
    _controller.value = position.pixels;
    _accumulator.rebase(position.pixels);
  }

  void _applyFrame() {
    if (_disposed || !isAttached() || !position.hasPixels) return;
    final target = _controller.value.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) {
      position.jumpTo(target);
    }
  }

  void dispose() {
    _disposed = true;
    _controller.removeListener(_applyFrame);
    _controller.dispose();
  }
}
