import 'package:absorb/widgets/action_pill.dart';
import 'package:absorb/widgets/card_buttons.dart';
import 'package:absorb/widgets/desktop_input.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desktop mouse extras: right-click runs the long-press action, Pressable
/// card buttons get a cursor, focus and tooltip, and shelves drag with a
/// mouse. Android (the default test platform) must stay as upstream.
void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ));

  Future<void> rightClick(WidgetTester tester, Finder finder) => tester.tap(
        finder,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );

  group('right-click opens what long-press opens', () {
    testWidgets('Pressable card button (quick bookmark, card buttons)',
        variant: windows, (tester) async {
      var taps = 0, holds = 0;
      await pump(
        tester,
        Pressable(
          onTap: () => taps++,
          onLongPress: () => holds++,
          child: const SizedBox(width: 80, height: 40, child: Text('btn')),
        ),
      );
      await rightClick(tester, find.text('btn'));
      await tester.pump();
      expect(holds, 1);
      expect(taps, 0);
      await tester.longPress(find.text('btn'));
      expect(holds, 2);
    });

    testWidgets('action pill (nav-bar hold menu items)', variant: windows,
        (tester) async {
      var holds = 0;
      await pump(
        tester,
        SizedBox(
          width: 360,
          child: ActionPillGrid(items: [
            ActionPillData(
              icon: Icons.search,
              label: 'Search',
              onTap: () {},
              onLongPress: () => holds++,
            ),
          ]),
        ),
      );
      await rightClick(tester, find.text('Search'));
      await tester.pump();
      expect(holds, 1);
    });

    testWidgets('library tiles and episode rows', variant: windows,
        (tester) async {
      var tileHolds = 0, rowHolds = 0;
      await pump(
        tester,
        Column(mainAxisSize: MainAxisSize.min, children: [
          DesktopGestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            onLongPress: () => tileHolds++,
            child: const SizedBox(width: 80, height: 40, child: Text('tile')),
          ),
          Material(
            child: DesktopInkWell(
              onTap: () {},
              onLongPress: () => rowHolds++,
              child: const SizedBox(width: 80, height: 40, child: Text('row')),
            ),
          ),
        ]),
      );
      await rightClick(tester, find.text('tile'));
      await rightClick(tester, find.text('row'));
      await tester.pump();
      expect(tileHolds, 1);
      expect(rowHolds, 1);
    });

    testWidgets('on Android right-click does nothing', (tester) async {
      var holds = 0;
      await pump(
        tester,
        Column(mainAxisSize: MainAxisSize.min, children: [
          Pressable(
            onLongPress: () => holds++,
            child: const SizedBox(width: 80, height: 40, child: Text('btn')),
          ),
          DesktopGestureDetector(
            onLongPress: () => holds++,
            child: const SizedBox(width: 80, height: 40, child: Text('tile')),
          ),
        ]),
      );
      await rightClick(tester, find.text('btn'));
      await rightClick(tester, find.text('tile'));
      await tester.pump();
      expect(holds, 0);
      expect(desktopSecondaryTap(() {}), isNull);
    });
  });

  group('Pressable on desktop', () {
    testWidgets('hand cursor, tooltip, Tab focus and Enter', variant: windows,
        (tester) async {
      var taps = 0, holds = 0;
      await pump(
        tester,
        Pressable(
          onTap: () => taps++,
          onLongPress: () => holds++,
          tooltip: 'Timer',
          child: const SizedBox(width: 80, height: 40, child: Icon(Icons.timer)),
        ),
      );
      final region = tester.widget<MouseRegion>(find
          .descendant(
            of: find.byType(FocusableActionDetector),
            matching: find.byType(MouseRegion),
          )
          .first);
      expect(region.cursor, SystemMouseCursors.click);
      expect(find.byTooltip('Timer'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(holds, 1);
    });

    testWidgets('clicking does not take keyboard focus', variant: windows,
        (tester) async {
      await pump(
        tester,
        Pressable(
          onTap: () {},
          child: const SizedBox(width: 80, height: 40, child: Text('btn')),
        ),
      );
      final before = FocusManager.instance.primaryFocus;
      await tester.tap(find.text('btn'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, before);
    });

    testWidgets('on Android it is the plain upstream button', (tester) async {
      await pump(
        tester,
        Pressable(
          onTap: () {},
          tooltip: 'Timer',
          child: const SizedBox(width: 80, height: 40),
        ),
      );
      expect(find.byType(FocusableActionDetector), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('mouse drag on horizontal shelves', () {
    Future<ScrollController> pumpShelf(WidgetTester tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        SizedBox(
          height: 100,
          child: DesktopMouseDrag(
            child: ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: 30,
              itemBuilder: (_, i) => SizedBox(width: 100, child: Text('$i')),
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('a mouse drags the shelf on desktop', variant: windows,
        (tester) async {
      final controller = await pumpShelf(tester);
      await tester.dragFrom(
        tester.getCenter(find.byType(ListView)),
        const Offset(-300, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
    });

    testWidgets('on Android a mouse drag still does not scroll',
        (tester) async {
      final controller = await pumpShelf(tester);
      await tester.dragFrom(
        tester.getCenter(find.byType(ListView)),
        const Offset(-300, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
    });
  });
}
