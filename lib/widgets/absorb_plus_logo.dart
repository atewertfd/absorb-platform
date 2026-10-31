import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/player_settings.dart';
import '../utils/app_motion.dart';

/// Absorb Plus's logo drawn in code: a drop with three sound bars cut out of
/// it. The geometry is the same as `tool/make_icons.py` (the launcher icon),
/// in its 1024-unit box, so the in-app mark matches the app icon exactly.
abstract final class AbsorbPlusGeometry {
  /// The drop's bounding box in the 1024 box (DROP_BOX in make_icons.py).
  static const Rect dropBox = Rect.fromLTRB(274, 170, 750, 838);

  /// Bar centers (x), all at [barCenterY]; width and static heights come from
  /// `_bars()` in make_icons.py (104 x {220, 500, 320}, scaled by 0.6).
  static const List<double> barCenterX = [411.2, 512, 612.8];
  static const double barCenterY = 620;
  static const double barWidth = 62.4;
  static const List<double> barHeights = [132, 300, 192];

  /// Share of the square the drop's height fills for the bare mark. Same as
  /// `assets/icon/source/absorb-plus-mark.svg`; large enough that the bars
  /// still read at 16-24 px.
  static const double markHeight = 0.9;

  /// The dark rounded tile behind the launcher icon (TILE, TILE_RADIUS and the
  /// 'tile' mark_height in make_icons.py).
  static const Color tileColor = Color(0xFF101014);
  static const double tileRadius = 230 / 1024;
  static const double tileMarkHeight = 0.62;

  /// The mark's teal on the launcher tile (COLOR in make_icons.py).
  static const Color teal = Color(0xFF5FD0C0);

  static final Path drop = Path()
    ..moveTo(512, 170)
    ..cubicTo(590, 290, 750, 450, 750, 600)
    ..arcToPoint(
      const Offset(274, 600),
      radius: const Radius.circular(238),
      clockwise: true,
    )
    ..cubicTo(274, 450, 434, 290, 512, 170)
    ..close();

  static final Path _staticMark = markPath(const [1, 1, 1]);

  /// The drop with the bars as holes (even-odd fill: every bar lies wholly
  /// inside the drop, so each one is a transparent cut-out). [scales]
  /// multiplies each bar's static height around [barCenterY].
  static Path markPath(List<double> scales) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(drop, Offset.zero);
    for (var i = 0; i < 3; i++) {
      final h = barHeights[i] * scales[i];
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(barCenterX[i], barCenterY),
            width: barWidth,
            height: h,
          ),
          const Radius.circular(barWidth / 2),
        ),
      );
    }
    return path;
  }

  /// Paints the mark centered in [size] with the drop [heightShare] of it.
  static void paint(
    Canvas canvas,
    Size size,
    Color color, {
    double heightShare = markHeight,
    List<double>? scales,
  }) {
    final s = heightShare * size.shortestSide / dropBox.height;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-dropBox.center.dx, -dropBox.center.dy);
    canvas.drawPath(
      scales == null ? _staticMark : markPath(scales),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();
  }
}

/// The bare mark in one color (default: the theme's primary color).
class AbsorbPlusMark extends StatelessWidget {
  final double size;
  final Color? color;

  const AbsorbPlusMark({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// The mark on the launcher icon's dark rounded tile, like the app icon.
class AbsorbPlusLogo extends StatelessWidget {
  final double size;
  final Color color;

  const AbsorbPlusLogo({
    super.key,
    this.size = 96,
    this.color = AbsorbPlusGeometry.teal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AbsorbPlusGeometry.tileColor,
        borderRadius: BorderRadius.circular(
          size * AbsorbPlusGeometry.tileRadius,
        ),
      ),
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(
          color: color,
          heightShare: AbsorbPlusGeometry.tileMarkHeight,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  final double heightShare;

  const _MarkPainter({
    required this.color,
    this.heightShare = AbsorbPlusGeometry.markHeight,
  });

  @override
  void paint(Canvas canvas, Size size) =>
      AbsorbPlusGeometry.paint(canvas, size, color, heightShare: heightShare);

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.color != color || old.heightShare != heightShare;
}

/// The mark whose three bars move like a quiet equalizer while [animating].
///
/// The drop stays fixed; the bars (holes in the drop) grow and shrink around
/// their logo heights, each at its own pace. Motion fades in and out over
/// [rampSeconds], and once it has faded out the ticker is stopped, so an
/// inactive drop schedules no frames at all. Reduced motion
/// (`MediaQuery.disableAnimations`) and e-ink mode keep it static.
class AnimatedAbsorbDrop extends StatefulWidget {
  final double size;
  final bool animating;

  /// Default: the ambient [IconTheme] color.
  final Color? color;

  const AnimatedAbsorbDrop({
    super.key,
    this.size = 24,
    required this.animating,
    this.color,
  });

  /// How far each bar swings from its logo height (0.3 = +/-30%).
  static const double amplitude = 0.3;

  /// Each bar's cycles per second and phase, so they never move in lockstep.
  static const List<double> frequencies = [0.8, 1.15, 0.95];
  static const List<double> phases = [0, 2.2, 4.4];

  /// Fade in/out time for the motion.
  static const double rampSeconds = 0.4;

  @override
  State<AnimatedAbsorbDrop> createState() => _AnimatedAbsorbDropState();
}

class _AnimatedAbsorbDropState extends State<AnimatedAbsorbDrop> {
  /// The motion runs at a steady 15 updates a second instead of every display
  /// frame: at 24 px it looks the same, and the app doesn't redraw at 60-144
  /// fps for the whole time audio plays.
  static const _step = Duration(milliseconds: 66);
  Timer? _timer;
  final _motion = _DropMotion();
  bool _reduced = false;
  double _time = 0;

  bool get _running => _timer != null;

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  bool get _wantsMotion => widget.animating && !_reduced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppMotionScope rebuilds this when e-ink or reduced motion flips; the
    // e-ink flag itself is read from PlayerSettings (set before the notifier).
    final scopeMode = AppMotionScope.maybeOf(context);
    _reduced =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        scopeMode == AppMotionMode.reduced ||
        PlayerSettings.einkMode;
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedAbsorbDrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animating != widget.animating) _sync();
  }

  void _sync() {
    if (_reduced) {
      // Snap to the static logo; no fade-out frames.
      _stopTimer();
      _motion.set(0, 0);
      return;
    }
    if (_wantsMotion && !_running) {
      _time = 0;
      _timer = Timer.periodic(_step, (_) => _onTick());
    }
    // When motion is no longer wanted, the running ticker fades the bars back
    // to the logo heights and stops itself (see _onTick).
  }

  void _onTick() {
    const dt = 66 / 1000;
    _time += dt;
    final t = _time;
    const step = dt / AnimatedAbsorbDrop.rampSeconds;
    final envelope = (_motion.envelope + (_wantsMotion ? step : -step)).clamp(
      0.0,
      1.0,
    );
    if (!_wantsMotion && envelope == 0) {
      _stopTimer();
      _motion.set(0, 0);
      return;
    }
    _motion.set(envelope, t);
  }

  @override
  void dispose() {
    _stopTimer();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.primary;
    // Its own layer, so a moving bar repaints only the icon, not the nav bar.
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _AnimatedDropPainter(color: color, motion: _motion),
      ),
    );
  }
}

/// Where the bars are in their motion: envelope 0 = the static logo.
class _DropMotion extends ChangeNotifier {
  double envelope = 0;
  double seconds = 0;

  void set(double envelope, double seconds) {
    if (envelope == this.envelope && seconds == this.seconds) return;
    this.envelope = envelope;
    this.seconds = seconds;
    notifyListeners();
  }

  List<double>? get scales {
    if (envelope == 0) return null;
    return [
      for (var i = 0; i < 3; i++)
        1 +
            envelope *
                AnimatedAbsorbDrop.amplitude *
                math.sin(
                  2 * math.pi * AnimatedAbsorbDrop.frequencies[i] * seconds +
                      AnimatedAbsorbDrop.phases[i],
                ),
    ];
  }
}

class _AnimatedDropPainter extends CustomPainter {
  final Color color;
  final _DropMotion motion;

  _AnimatedDropPainter({required this.color, required this.motion})
    : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) =>
      AbsorbPlusGeometry.paint(canvas, size, color, scales: motion.scales);

  @override
  bool shouldRepaint(_AnimatedDropPainter old) =>
      old.color != color || old.motion != motion;
}
