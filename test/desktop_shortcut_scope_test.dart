import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/services/desktop_shortcuts.dart';
import 'package:absorb/widgets/desktop_shortcut_help.dart';
import 'package:absorb/widgets/desktop_shortcut_scope.dart';
import 'package:absorb/widgets/expanded_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app-wide desktop shortcuts (DesktopShortcutScope, installed above the
/// navigator by absorbLookBuilder): Esc, back, F5 and card switching, and
/// the playback keys over open pages.
void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  late List<DesktopShortcutAction> ran;
  late List<int> cardSteps;
  late GlobalKey<NavigatorState> navKey;

  setUp(() {
    ran = [];
    cardSteps = [];
    navKey = GlobalKey<NavigatorState>();
    DesktopShortcutScope.handlers = DesktopShortcutHandlers(
      canRun: (_) => true,
      run: ran.add,
      canSwitchCard: () => true,
      switchCard: cardSteps.add,
    );
  });
  tearDown(() => DesktopShortcutScope.handlers = null);

  /// Same shape as the app: scope in MaterialApp.builder, shell focus node.
  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      builder: (context, child) => DesktopShortcutScope(child: child!),
      home: Focus(
        focusNode: desktopShellFocusNode,
        autofocus: true,
        child: Scaffold(body: home),
      ),
    ));
    await tester.pump();
  }

  Future<void> push(WidgetTester tester, Route<void> route) async {
    navKey.currentState!.push(route);
    await tester.pumpAndSettle();
  }

  Route<void> page(String text) => MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: Center(child: Text(text))),
      );

  Future<void> sendWith(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  group('full-screen player', () {
    testWidgets('Esc closes it', variant: windows, (tester) async {
      await pumpApp(tester, const Text('shell'));
      await push(
        tester,
        ExpandedCardRoute(child: const Scaffold(body: Text('player'))),
      );
      expect(find.text('player'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('player'), findsNothing);
      expect(find.text('shell'), findsOneWidget);
    });

    testWidgets('Esc leaves other pages alone', variant: windows,
        (tester) async {
      await pumpApp(tester, const Text('shell'));
      await push(tester, page('downloads'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('downloads'), findsOneWidget);
    });

    testWidgets('Space and arrows keep working over it', variant: windows,
        (tester) async {
      await pumpApp(tester, const Text('shell'));
      await push(
        tester,
        ExpandedCardRoute(child: const Scaffold(body: Text('player'))),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      expect(ran, [
        DesktopShortcutAction.playPause,
        DesktopShortcutAction.rewind,
        DesktopShortcutAction.faster,
      ]);
    });

    testWidgets('a focused button inside it keeps Space', variant: windows,
        (tester) async {
      final buttonFocus = FocusNode();
      addTearDown(buttonFocus.dispose);
      var presses = 0;
      await pumpApp(tester, const Text('shell'));
      await push(
        tester,
        ExpandedCardRoute(
          child: Scaffold(
            body: ElevatedButton(
              focusNode: buttonFocus,
              onPressed: () => presses++,
              child: const Text('button'),
            ),
          ),
        ),
      );
      buttonFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(ran, isEmpty);
      expect(presses, 1);
    });

    testWidgets('on Android Esc does nothing', (tester) async {
      await pumpApp(tester, const Text('shell'));
      await push(
        tester,
        ExpandedCardRoute(child: const Scaffold(body: Text('player'))),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('player'), findsOneWidget);
    });
  });

  group('back', () {
    testWidgets('Alt+Left closes the top page', variant: windows,
        (tester) async {
      await pumpApp(tester, const Text('shell'));
      await push(tester, page('bookmarks'));
      await sendWith(
          tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowLeft);
      expect(find.text('bookmarks'), findsNothing);
      expect(find.text('shell'), findsOneWidget);
    });

    testWidgets('the mouse back button closes the top page', variant: windows,
        (tester) async {
      await pumpApp(tester, const Text('shell'));
      await push(tester, page('bookmarks'));
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await mouse.down(tester.getCenter(find.text('bookmarks')));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('bookmarks'), findsNothing);
    });

    testWidgets('never pops the shell itself', variant: windows,
        (tester) async {
      await pumpApp(tester, const Text('shell'));
      await sendWith(
          tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowLeft);
      expect(find.text('shell'), findsOneWidget);
      expect(navKey.currentState!.canPop(), isFalse);
    });
  });

  group('refresh', () {
    late int visible, hidden;

    Widget tabs() => IndexedStack(index: 1, children: [
          RefreshIndicator(
            onRefresh: () async => hidden++,
            child: ListView(children: const [Text('hidden tab')]),
          ),
          RefreshIndicator(
            onRefresh: () async => visible++,
            child: ListView(children: const [Text('visible tab')]),
          ),
        ]);

    setUp(() {
      visible = 0;
      hidden = 0;
    });

    testWidgets('F5 runs the visible tab\'s pull-to-refresh',
        variant: windows, (tester) async {
      await pumpApp(tester, tabs());
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(visible, 1);
      expect(hidden, 0);
    });

    testWidgets('Ctrl+R does too', variant: windows, (tester) async {
      await pumpApp(tester, tabs());
      await sendWith(
          tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyR);
      expect(visible, 1);
    });

    testWidgets('a page on top hides the shell\'s lists', variant: windows,
        (tester) async {
      await pumpApp(tester, tabs());
      await push(tester, page('settings page'));
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(visible, 0);
    });

    testWidgets('on Android F5 does nothing', (tester) async {
      await pumpApp(tester, tabs());
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(visible, 0);
    });
  });

  group('Absorbing cards', () {
    testWidgets('Page Down / Ctrl+Left switch cards', variant: windows,
        (tester) async {
      await pumpApp(tester, const Text('shell'));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await sendWith(tester, LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.arrowLeft);
      await sendWith(tester, LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.arrowRight);
      expect(cardSteps, [1, -1, -1, 1]);
    });

    testWidgets('not while typing', variant: windows, (tester) async {
      final field = FocusNode();
      addTearDown(field.dispose);
      await pumpApp(tester, TextField(focusNode: field));
      field.requestFocus();
      await tester.pump();
      await sendWith(tester, LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(cardSteps, isEmpty);
    });
  });

  group('shortcut table and help', () {
    final l = lookupAppLocalizations(const Locale('en'));

    test('navigation shortcuts are listed on desktop only', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect(desktopNavigationShortcuts.map((s) => s.label), [
          'Esc',
          'Alt+Left',
          'F5',
          'Ctrl+R',
          'Ctrl+Left',
          'Ctrl+Right',
          'Page Up',
          'Page Down',
        ]);
        final help = {
          for (final e in desktopShortcutHelpEntries(l)) e.description: e.keys,
        };
        expect(help[l.desktopShortcutClosePlayer], 'Esc');
        expect(help[l.desktopShortcutBack], 'Alt+Left / Mouse back button');
        expect(help[l.desktopShortcutRefresh], 'F5 / Ctrl+R');
        expect(help[l.desktopShortcutPreviousCard], 'Ctrl+Left / Page Up');
        expect(help[l.desktopShortcutNextCard], 'Ctrl+Right / Page Down');
        expect(help[l.desktopShortcutContextMenu], 'Right-click');
        expect(help[l.desktopShortcutPlayPause], 'Space');
        expect(help[l.desktopShortcutFullScreen], 'F11');

        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        expect(desktopNavigationShortcuts, isEmpty);
        final android = desktopShortcutHelpEntries(l).map((e) => e.keys);
        expect(android, isNot(contains('F5 / Ctrl+R')));
        expect(android, isNot(contains('Right-click')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the help list shows every entry', variant: windows,
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: DesktopShortcutHelpList()),
        ),
      ));
      expect(find.text('F5 / Ctrl+R'), findsOneWidget);
      expect(find.text(l.desktopShortcutClosePlayer), findsOneWidget);
      expect(find.byType(ListTile),
          findsNWidgets(desktopShortcutHelpEntries(l).length));
    });
  });
}
