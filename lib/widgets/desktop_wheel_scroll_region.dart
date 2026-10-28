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

  Duration get _wheelDuration {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final mode = AppMotion.resolveMode(
      eInk: false,
      snappy: false,
      reduceMotion: reduceMotion,
    );
    return AppMotion.duration(AppMotion.state, mode);
  }

  void _pruneDrivers() {
    if (widget.controller != null) return;
    final activePositions = {
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
    _pruneDrivers();
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
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (delta == 0 || target == position.pixels) return null;
    final driver = _drivers[position];
    final base = driver?.target ?? position.pixels;
    final destination = (base + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (destination == base) return null;
    return _WheelTarget(position, destination.toDouble());
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
    // A real drag cancels an in-flight wheel animation. Rebase every active
    // driver so the next wheel event starts from the user's actual position.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      for (final driver in _drivers.values) {
        driver.rebase();
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
        () => _SmoothWheelDriver(target.position),
      );
      driver.setTarget(target.destination, _wheelDuration);
      resolvedEvent.respond(allowPlatformDefault: false);
    });
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
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _handlePointerSignal,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _handleMetricsNotification,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: widget.child,
        ),
      ),
    );
  }
}

class _DiscoveredScrollable {
  const _DiscoveredScrollable(this.scrollable, this.depth);

  final ScrollableState scrollable;
  final int depth;
}

class _WheelTarget {
  const _WheelTarget(this.position, this.destination);

  final ScrollPosition position;
  final double destination;
}

class _SmoothWheelDriver {
  _SmoothWheelDriver(this.position)
    : _accumulator = WheelScrollAccumulator(initialTarget: position.pixels);

  final ScrollPosition position;
  final WheelScrollAccumulator _accumulator;
  Future<void>? _run;
  Duration _duration = AppMotion.state;
  bool _disposed = false;

  double get target => _accumulator.target;

  void setTarget(double destination, Duration duration) {
    if (_disposed || !position.hasPixels) return;
    _duration = duration;
    _accumulator.rebase(destination);
    _run ??= _drain();
  }

  void rebase() {
    if (!_disposed && position.hasPixels) {
      _accumulator.rebase(position.pixels);
    }
  }

  Future<void> _drain() async {
    try {
      while (!_disposed && position.hasPixels) {
        final destination = _accumulator.target;
        if ((destination - position.pixels).abs() < 0.5) break;

        if (_duration == Duration.zero) {
          position.jumpTo(destination);
        } else {
          await position.animateTo(
            destination,
            duration: _duration,
            curve: AppMotion.curve,
          );
        }

        if (destination == _accumulator.target &&
            (destination - position.pixels).abs() < 0.5) {
          break;
        }
      }
    } finally {
      _run = null;
    }
  }

  void dispose() {
    _disposed = true;
    _accumulator.rebase(position.hasPixels ? position.pixels : 0);
  }
}
