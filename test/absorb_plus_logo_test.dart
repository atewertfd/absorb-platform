import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:absorb/services/player_settings.dart';
import 'package:absorb/services/wording.dart';
import 'package:absorb/widgets/absorb_plus_logo.dart';
import 'package:absorb/widgets/absorb_wave_icon.dart';
import 'package:absorb/widgets/absorbing_nav_icon.dart';
import 'package:absorb/widgets/absorbing_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

const _boundaryKey = Key('logo-boundary');
const _ink = Color(0xFFFF0000);

Widget _host(Widget child, {bool disableAnimations = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(key: _boundaryKey, child: child),
    ),
  ),
);

/// Renders the boundary to RGBA bytes (1 logical px = 1 image px).
Future<(ByteData, int)> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    image.dispose();
    return (bytes!, width);
  }))!;
}

int _alpha(ByteData bytes, int width, double x, double y) =>
    bytes.getUint8((y.floor() * width + x.floor()) * 4 + 3);

/// Maps a point of make_icons.py's 1024 box to the painted [size] square.
Offset _toCanvas(double size, double x, double y) {
  final box = AbsorbPlusGeometry.dropBox;
  final s = AbsorbPlusGeometry.markHeight * size / box.height;
  return Offset(
    size / 2 + (x - box.center.dx) * s,
    size / 2 + (y - box.center.dy) * s,
  );
}

bool get _framesPending =>
    SchedulerBinding.instance.hasScheduledFrame ||
    SchedulerBinding.instance.transientCallbackCount > 0;

void main() {
  tearDown(() => PlayerSettings.einkMode = false);

  group('AbsorbPlusMark', () {
    for (final size in [16.0, 24.0, 48.0, 128.0]) {
      testWidgets('paints at $size px', (tester) async {
        await tester.pumpWidget(_host(AbsorbPlusMark(size: size, color: _ink)));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(AbsorbPlusMark)), Size(size, size));
        final (bytes, width) = await _capture(tester);
        expect(width, size.round());
      });
    }

    testWidgets('the bars are transparent holes in an opaque drop', (
      tester,
    ) async {
      const size = 128.0;
      await tester.pumpWidget(
        _host(const AbsorbPlusMark(size: size, color: _ink)),
      );
      final (bytes, width) = await _capture(tester);
      int alphaAt(double x, double y) {
        final p = _toCanvas(size, x, y);
        return _alpha(bytes, width, p.dx, p.dy);
      }

      // Inside each bar: cut out.
      for (final x in AbsorbPlusGeometry.barCenterX) {
        expect(
          alphaAt(x, AbsorbPlusGeometry.barCenterY),
          0,
          reason: 'bar at $x should be a hole',
        );
      }
      // The drop body above the bars and between two bars: solid.
      expect(alphaAt(512, 380), 255);
      expect(alphaAt(461.6, AbsorbPlusGeometry.barCenterY), 255);
      // Outside the drop: the corner stays clear.
      expect(_alpha(bytes, width, 2, 2), 0);
    });

    testWidgets('AbsorbWaveIcon now draws the new mark', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: const Scaffold(body: AbsorbWaveIcon(size: 44))),
      );
      expect(find.byType(AbsorbPlusMark), findsOneWidget);
    });

    testWidgets('AbsorbPlusLogo puts the mark on the dark tile', (
      tester,
    ) async {
      const size = 96.0;
      await tester.pumpWidget(_host(const AbsorbPlusLogo(size: size)));
      final (bytes, width) = await _capture(tester);
      // The tile shows through the bar holes; the drop is teal.
      final box = AbsorbPlusGeometry.dropBox;
      final s = AbsorbPlusGeometry.tileMarkHeight * size / box.height;
      int redAt(double x, double y) {
        final px = size / 2 + (x - box.center.dx) * s;
        final py = size / 2 + (y - box.center.dy) * s;
        return bytes.getUint8((py.floor() * width + px.floor()) * 4);
      }

      expect(redAt(512, AbsorbPlusGeometry.barCenterY), 0x10);
      expect(redAt(512, 380), 0x5F);
    });
  });

  group('AnimatedAbsorbDrop', () {
    testWidgets('schedules no frames while not animating', (tester) async {
      await tester.pumpWidget(
        _host(
          const AnimatedAbsorbDrop(size: 24, animating: false, color: _ink),
        ),
      );
      expect(_framesPending, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(_framesPending, isFalse);
    });

    testWidgets('ticks while animating, then fades out and stops', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const AnimatedAbsorbDrop(size: 48, animating: true, color: _ink)),
      );
      // A steady 15 updates a second (not every display frame).
      await tester.pump(const Duration(milliseconds: 600));
      final (a, _) = await _capture(tester);
      await tester.pump(const Duration(milliseconds: 270));
      final (b, _) = await _capture(tester);
      expect(
        a.buffer.asUint8List(),
        isNot(equals(b.buffer.asUint8List())),
        reason: 'bars should move between frames',
      );

      await tester.pumpWidget(
        _host(
          const AnimatedAbsorbDrop(size: 48, animating: false, color: _ink),
        ),
      );
      // Fade-out updates, then the timer stops by itself.
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_framesPending, isFalse);

      // Back at rest it draws exactly the static logo.
      final (rest, _) = await _capture(tester);
      await tester.pumpWidget(
        _host(const AbsorbPlusMark(size: 48, color: _ink)),
      );
      final (logo, _) = await _capture(tester);
      expect(rest.buffer.asUint8List(), equals(logo.buffer.asUint8List()));
    });

    testWidgets('stays static with reduced motion', (tester) async {
      await tester.pumpWidget(
        _host(
          const AnimatedAbsorbDrop(size: 24, animating: true, color: _ink),
          disableAnimations: true,
        ),
      );
      expect(_framesPending, isFalse);
    });

    testWidgets('snaps to static when reduced motion turns on mid-play', (
      tester,
    ) async {
      const drop = AnimatedAbsorbDrop(size: 24, animating: true, color: _ink);
      await tester.pumpWidget(_host(drop));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(_host(drop, disableAnimations: true));
      // The timer stopped: time passing schedules nothing more.
      await tester.pump(const Duration(milliseconds: 300));
      expect(_framesPending, isFalse);
      final (still, _) = await _capture(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final (later, _) = await _capture(tester);
      expect(still.buffer.asUint8List(), equals(later.buffer.asUint8List()));
    });

    testWidgets('stays static in e-ink mode', (tester) async {
      PlayerSettings.einkMode = true;
      await tester.pumpWidget(
        _host(const AnimatedAbsorbDrop(size: 24, animating: true, color: _ink)),
      );
      expect(_framesPending, isFalse);
    });
  });

  group('AbsorbingNavIcon', () {
    Widget navBar() => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: NavigationBar(
          selectedIndex: 1,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
              icon: AbsorbingNavIcon(size: 24, active: false),
              selectedIcon: AbsorbingNavIcon(size: 24, active: true),
              label: 'Absorbing',
            ),
          ],
        ),
      ),
    );

    testWidgets('shows the drop in the nav bar, idle when nothing plays', (
      tester,
    ) async {
      await tester.pumpWidget(navBar());
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedAbsorbDrop), findsOneWidget);
      final drop = tester.widget<AnimatedAbsorbDrop>(
        find.byType(AnimatedAbsorbDrop),
      );
      expect(drop.animating, isFalse);
      expect(drop.size, 24);
      final cs = Theme.of(
        tester.element(find.byType(AnimatedAbsorbDrop)),
      ).colorScheme;
      expect(drop.color, cs.primary);
      expect(_framesPending, isFalse);
    });
  });

  group('Absorb buttons', () {
    tearDown(() => classicWordingNotifier.value = false);

    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: child))),
        );

    testWidgets('play button shows the drop, or a play arrow with Plain wording', (
      tester,
    ) async {
      await pump(tester, const AbsorbActionIcon(size: 24));
      expect(find.byType(AbsorbPlusMark), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

      classicWordingNotifier.value = true;
      await pump(tester, const AbsorbActionIcon(size: 24, color: Colors.white));
      expect(find.byType(AbsorbPlusMark), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('Absorb again shows the replay drop, or the replay icon with Plain wording', (
      tester,
    ) async {
      await pump(tester, const AbsorbReplayIcon(size: 24));
      expect(find.byIcon(Icons.replay_rounded), findsNothing);
      expect(tester.takeException(), isNull);

      classicWordingNotifier.value = true;
      await pump(tester, const AbsorbReplayIcon(size: 24));
      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
    });

    testWidgets('watch icon paints the drop without errors', (tester) async {
      await pump(tester, const AbsorbWatchIcon(size: 18));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the starting animation is the moving drop', (tester) async {
      await pump(tester, const AbsorbingWave(color: Colors.white));
      final drop = tester.widget<AnimatedAbsorbDrop>(find.byType(AnimatedAbsorbDrop));
      expect(drop.animating, isTrue);
      expect(drop.color, Colors.white);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
