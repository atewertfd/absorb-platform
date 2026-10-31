import 'dart:io';

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/services/player_settings.dart';
import 'package:absorb/services/whats_new_notes.dart';
import 'package:absorb/widgets/welcome_sheet.dart';
import 'package:absorb/widgets/whats_new_prompt.dart';
import 'package:absorb/widgets/whats_new_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _beta11 = File('test/fixtures/whats_new/beta-11.md').readAsStringSync();

void main() {
  final opened = <Uri>[];
  final originalService = WhatsNewSheet.notesService;
  final originalOpen = WhatsNewSheet.openExternal;
  late WhatsNewFetcher fetch;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    opened.clear();
    fetch = (_) async => WhatsNewRelease(_beta11, name: 'Absorb Plus 1.12.1-318 (Beta 11)');
    WhatsNewSheet.notesService = () => WhatsNewNotesService(fetch: (t) => fetch(t));
    WhatsNewSheet.openExternal = (url) async {
      opened.add(url);
      return true;
    };
  });

  tearDown(() {
    WhatsNewSheet.notesService = originalService;
    WhatsNewSheet.openExternal = originalOpen;
    PlayerSettings.einkMode = false;
  });

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home, {ThemeMode mode = ThemeMode.light, double textScale = 1}) =>
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: mode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: home),
      );

  Future<void> openSheet(WidgetTester tester,
      {ThemeMode mode = ThemeMode.light, double textScale = 1}) async {
    await tester.pumpWidget(app(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => WhatsNewSheet.show(context,
                version: '1.12.1',
                build: 318,
                previous: const WhatsNewPrevious(version: '1.11.1', build: 300, beta: 10)),
            child: const Text('open'),
          ),
        ),
      ),
      mode: mode,
      textScale: textScale,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('phone (390x844)', () {
    testWidgets('bottom sheet with header, highlight and sections', (tester) async {
      setSize(tester, const Size(390, 844));
      await openSheet(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text("What's new in Beta 11"), findsOneWidget);
      expect(find.text('1.12.1+318'), findsOneWidget);
      expect(find.text('Updated from Beta 10'), findsOneWidget);
      expect(find.textContaining('The biggest Absorb Plus update', findRichText: true),
          findsOneWidget);
      expect(find.text('NEW: CHOOSE YOUR LOOK'), findsOneWidget);
      // The body scrolls; the footer stays put.
      await tester.scrollUntilVisible(find.text('FROM UPSTREAM ABSORB'), 300,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Got it'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // No more than ~86% of the screen.
      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.height, lessThanOrEqualTo(844 * 0.86 + 0.5));
    });

    testWidgets('section headings are headers for screen readers', (tester) async {
      setSize(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();
      await openSheet(tester);
      expect(
        tester.getSemantics(find.text("What's new in Beta 11")),
        matchesSemantics(label: "What's new in Beta 11", isHeader: true),
      );
      await tester.ensureVisible(find.text('FIXES'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('FIXES')),
        matchesSemantics(label: 'FIXES', isHeader: true),
      );
      semantics.dispose();
    });

    testWidgets('Got it closes; the switch writes the prompt preference', (tester) async {
      setSize(tester, const Size(390, 844));
      await openSheet(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(await WhatsNewPrompt.isEnabled(), isFalse);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('large text and dark mode lay out without overflow', (tester) async {
      setSize(tester, const Size(390, 844));
      await openSheet(tester, mode: ThemeMode.dark, textScale: 2);
      expect(find.text('Got it'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('e-ink: no gradients', (tester) async {
      PlayerSettings.einkMode = true;
      setSize(tester, const Size(390, 844));
      await openSheet(tester);
      final gradients = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient != null);
      expect(gradients, findsNothing);
    });

    testWidgets('offline with nothing cached: Open on GitHub', (tester) async {
      fetch = (_) async => throw const SocketException('offline');
      setSize(tester, const Size(390, 844));
      await openSheet(tester);

      expect(find.text("Couldn't load the notes"), findsOneWidget);
      // The header still names the build.
      expect(find.text('1.12.1+318'), findsOneWidget);
      await tester.tap(find.text('Open on GitHub'));
      expect(opened, [
        Uri.parse('https://github.com/atewertfd/absorb-platform/releases/tag/v1.12.1-318'),
      ]);
    });

    testWidgets('offline after one load: shows the cached notes', (tester) async {
      setSize(tester, const Size(390, 844));
      await openSheet(tester);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      fetch = (_) async => throw const SocketException('offline');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('FIXES'), findsOneWidget);
      expect(find.text("Couldn't load the notes"), findsNothing);
    });

    testWidgets('links open in the browser', (tester) async {
      fetch = (_) async => const WhatsNewRelease(
          '## Beta 12\n\nRead [the guide](https://example.com/guide).\n### Fixes\n- one');
      setSize(tester, const Size(390, 844));
      await openSheet(tester);
      await tester.tapOnText(find.textRange.ofSubstring('the guide'));
      await tester.tap(find.text('Full notes on GitHub'));
      expect(opened, [
        Uri.parse('https://example.com/guide'),
        Uri.parse('https://github.com/atewertfd/absorb-platform/releases/tag/v1.12.1-318'),
      ]);
    });
  });

  group('desktop (1280x800)', () {
    testWidgets('centered dialog with two columns of sections', (tester) async {
      setSize(tester, const Size(1280, 800));
      await openSheet(tester);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final dialog = tester.getRect(
          find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first);
      expect(dialog.width, inInclusiveRange(560, 640));
      expect(dialog.center.dx, closeTo(640, 1));

      final newX = tester.getTopLeft(find.text('NEW: CHOOSE YOUR LOOK')).dx;
      final fixesX = tester.getTopLeft(find.text('FIXES')).dx;
      expect(fixesX, greaterThan(newX + 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Got it is focused; Escape closes', (tester) async {
      setSize(tester, const Size(1280, 800));
      await openSheet(tester);

      final gotIt = find.ancestor(of: find.text('Got it'), matching: find.byType(FilledButton));
      final focus = Focus.of(tester.element(find.text('Got it')));
      expect(focus.hasPrimaryFocus, isTrue, reason: 'Got it starts focused');
      expect(gotIt, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('after an update', () {
    Future<void> launch(WidgetTester tester) async {
      setSize(tester, const Size(390, 844));
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () => WhatsNewPrompt.showIfUpdated(context),
          child: const Text('launch'),
        ),
      )));
      await tester.tap(find.text('launch'));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
    }

    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'Absorb',
        packageName: 'com.absorb.test',
        version: '1.12.1',
        buildNumber: '318',
        buildSignature: '',
      );
    });

    testWidgets('the prompt opens the notes', (tester) async {
      SharedPreferences.setMockInitialValues({
        WelcomeSheet.prefKey: true,
        'whats_new_last_build': 300,
      });
      await launch(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text("What's new in Beta 11"), findsOneWidget);
      expect(find.text('Updated from build 300'), findsOneWidget);
    });

    testWidgets('not when turned off, nor for the same build', (tester) async {
      SharedPreferences.setMockInitialValues({
        WelcomeSheet.prefKey: true,
        'whats_new_last_build': 300,
        'whats_new_enabled': false,
      });
      await launch(tester);
      expect(find.byType(BottomSheet), findsNothing);

      SharedPreferences.setMockInitialValues({
        WelcomeSheet.prefKey: true,
        'whats_new_last_build': 318,
      });
      await tester.tap(find.text('launch'));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
