import 'dart:io';

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/main.dart' show colorSourceNotifier, manualSeedNotifier;
import 'package:absorb/services/player_settings.dart';
import 'package:absorb/services/wording.dart';
import 'package:absorb/ui_themes/ui_theme.dart';
import 'package:absorb/ui_themes/ui_theme_picker.dart';
import 'package:absorb/ui_themes/ui_theme_preview.dart';
import 'package:absorb/utils/memory_policy.dart';
import 'package:absorb/widgets/theme_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingImageCache extends ImageCache {
  int clearCalls = 0;

  @override
  void clear() {
    clearCalls++;
  }
}

Widget _app({required Widget home}) => UiThemeScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// Pumps an app and returns a context inside it.
Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    _app(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

/// Picks [look] on step 1, then finishes on step 2 without changing color.
Future<void> _pickLookAndFinish(WidgetTester tester, String look) async {
  await tester.tap(find.text(look));
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  expect(find.text('Choose a color'), findsOneWidget);
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

int _presetArgb(String id) =>
    kThemePresets.firstWhere((p) => p.id == id).color.toARGB32();

void main() {
  setUp(() {
    uiThemeNotifier.value = null;
    lookDetailsNotifier.value = LookDetails.standard;
    classicWordingNotifier.value = false;
    colorSourceNotifier.value = 'dynamic';
    manualSeedNotifier.value = const Color(0xFF7C6FBF);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    uiThemeNotifier.value = null;
    lookDetailsNotifier.value = LookDetails.standard;
    classicWordingNotifier.value = false;
  });

  group('presets', () {
    test('Standard changes nothing', () {
      expect(AppUiTheme.plus.spec, const AbsorbLook());
      final spec = AppUiTheme.plus.spec;
      expect(spec.fullQualityCovers, isFalse);
      expect(spec.defaultImageCache, isFalse);
      expect(spec.showExtraCoverBadges, isTrue);
      expect(spec.classicHomeShelves, isFalse);
      expect(spec.compactHeaderActions, isFalse);
    });

    test('Classic look details restore the first Windows port behavior', () {
      final spec = AppUiTheme.plus.lookFor(
        Brightness.dark,
        details: LookDetails.classic,
      );
      expect(spec.fullQualityCovers, isTrue);
      expect(spec.defaultImageCache, isTrue);
      expect(spec.showExtraCoverBadges, isFalse);
      expect(spec.classicHomeShelves, isTrue);
      expect(spec.compactHeaderActions, isTrue);
    });

    test('the looks are Standard, Frosted and Midnight, in that order', () {
      expect(AppUiTheme.values, [
        AppUiTheme.plus,
        AppUiTheme.frosted,
        AppUiTheme.midnight,
      ]);
    });

    test('Standard keeps neutral surface tokens, with any look details', () {
      for (final details in [LookDetails.standard, LookDetails.classic]) {
        for (final b in Brightness.values) {
          final look = AppUiTheme.plus.lookFor(b, details: details);
          expect(look.glowStrength, isNull, reason: '$details $b');
          expect(look.panelFillAlpha, isNull);
          expect(look.sheetFillAlpha, isNull);
          expect(look.panelBlurSigma, 0);
          expect(look.cornerRadiusBoost, 0);
          expect(look.frostedPanels, isFalse);
          expect(look.frostedNavBar, isFalse);
          expect(look.frostedSheets, isFalse);
          expect(look.frostedPlayerCard, isFalse);
          expect(look.changesSurfaces, isFalse);
          expect(look.panelFill(), isNull);
          expect(look.canvasColor, isNull);
          expect(look.sheetColor, isNull);
          expect(look.outlinedPanels, isFalse);
        }
      }
    });

    test('Midnight: true black, hairline outlines, no glow (dark)', () {
      final dark = AppUiTheme.midnight.lookFor(Brightness.dark);
      expect(dark, AbsorbLook.midnightDark);
      expect(dark.canvasColor, const Color(0xFF000000));
      expect(dark.sheetColor, const Color(0xFF0A0A0A));
      expect(dark.glowStrength, 0);
      expect(dark.backdropTint, 0);
      expect(dark.outlinedPanels, isTrue);
      expect(dark.themedPanels, isTrue);
      expect(dark.navBarEdge, isTrue);
      expect(dark.panelBorderAlpha, inInclusiveRange(0.12, 0.16));
      expect(
        dark.panelEdge(Brightness.dark),
        Colors.white.withValues(alpha: dark.panelBorderAlpha),
      );
      // Outlines, not fills: the background shows inside the panels.
      expect(dark.panelFill(), Colors.transparent);
      expect(dark.frostedPanels, isFalse);
      // No glass anywhere, and the usual radius.
      expect(dark.panelBlurSigma, 0);
      expect(dark.cornerRadiusBoost, 0);
      expect(dark.frostedNavBar, isFalse);
      expect(dark.frostedSheets, isFalse);
      expect(dark.frostedPlayerCard, isFalse);
      expect(dark.changesSurfaces, isTrue);
      // Behavior flags are Standard's.
      expect(dark.withNeutralSurfaces(), AbsorbLook.plus);
    });

    test('Midnight in light mode is its paper counterpart', () {
      final light = AppUiTheme.midnight.lookFor(Brightness.light);
      expect(light, AbsorbLook.midnightLight);
      expect(light.canvasColor, const Color(0xFFFFFFFF));
      expect(light.sheetColor, const Color(0xFFFFFFFF));
      expect(light.glowStrength, 0);
      expect(light.outlinedPanels, isTrue);
      expect(light.panelFill(), Colors.transparent);
      // A dark hairline: a white one would vanish on white.
      expect(
        light.panelEdge(Brightness.light),
        Colors.black.withValues(alpha: light.panelBorderAlpha),
      );
      expect(light.panelBorderAlpha, greaterThan(0.06));
    });

    test('Frosted: subtle glass tokens, Absorb Plus behavior flags', () {
      final dark = AppUiTheme.frosted.lookFor(Brightness.dark);
      expect(dark.glowStrength, inInclusiveRange(0.22, 0.32));
      expect(dark.panelFillAlpha, 0.10);
      expect(dark.panelBorderAlpha, 0.16);
      // Color carried down the screen, so the glass shows something.
      expect(dark.backdropTint, greaterThan(0));
      expect(dark.panelBlurSigma, inInclusiveRange(18, 20));
      expect(dark.cornerRadiusBoost, 4);
      expect(dark.sheetFillAlpha, greaterThanOrEqualTo(0.85));
      expect(dark.frostedNavBar, isTrue);
      expect(dark.frostedSheets, isTrue);
      expect(dark.frostedPlayerCard, isTrue);
      expect(
        dark.panelEdge(Brightness.dark),
        Colors.white.withValues(alpha: 0.16),
      );

      final light = AppUiTheme.frosted.lookFor(Brightness.light);
      expect(light.frostedPanels, isTrue);
      expect(light.glowStrength, lessThanOrEqualTo(dark.glowStrength!));

      for (final look in [dark, light]) {
        expect(look.withNeutralSurfaces(), AbsorbLook.plus);
      }
    });

    test('e-ink keeps the flags but drops every surface effect', () {
      for (final theme in AppUiTheme.values) {
        for (final b in Brightness.values) {
          expect(theme.lookFor(b, eink: true), AbsorbLook.plus);
          expect(
            theme.lookFor(b, eink: true, details: LookDetails.classic),
            AbsorbLook.plus.withDetails(LookDetails.classic),
          );
        }
      }
    });

    test('lerp blends numbers and switches flags halfway', () {
      const a = AbsorbLook.frostedDark;
      const b = AbsorbLook.frostedLight;
      final mid = a.lerp(b, 0.5);
      expect(mid.panelFillAlpha, closeTo((0.10 + 0.50) / 2, 1e-9));
      expect(a.lerp(AbsorbLook.plus, 0.25).frostedNavBar, isTrue);
      expect(a.lerp(AbsorbLook.plus, 0.75).frostedNavBar, isFalse);
      expect(a.lerp(AbsorbLook.plus, 0.75).panelFillAlpha, isNull);
      expect(a.lerp(null, 0.5), a);

      const m = AbsorbLook.midnightDark;
      expect(
        m.lerp(AbsorbLook.midnightLight, 0.5).canvasColor!.r,
        closeTo(0.5, 0.01),
      );
      expect(m.lerp(AbsorbLook.plus, 0.25).canvasColor, m.canvasColor);
      expect(m.lerp(AbsorbLook.plus, 0.75).canvasColor, isNull);
      expect(m.lerp(AbsorbLook.plus, 0.75).outlinedPanels, isFalse);
    });

    test('ids are stable and round-trip', () {
      expect(AppUiTheme.plus.id, 'plus');
      expect(AppUiTheme.frosted.id, 'frosted');
      expect(AppUiTheme.midnight.id, 'midnight');
      // The retired Classic id is no look of its own any more.
      expect(AppUiTheme.fromId('classic'), isNull);
      for (final theme in AppUiTheme.values) {
        expect(AppUiTheme.fromId(theme.id), theme);
      }
      expect(
        AppUiTheme.values.map((t) => t.id).toSet().length,
        AppUiTheme.values.length,
      );
    });

    test('unknown or missing ids are null and fall back to Standard', () {
      expect(AppUiTheme.fromId(null), isNull);
      expect(AppUiTheme.fromId(''), isNull);
      expect(AppUiTheme.fromId('neon'), isNull);
      expect(currentUiTheme, AppUiTheme.plus);
      expect(currentAbsorbLook, AbsorbLook.plus);
    });

    test('absorbLookFor follows the active look', () {
      expect(absorbLookFor(Brightness.dark), AbsorbLook.plus);
      uiThemeNotifier.value = AppUiTheme.frosted;
      expect(absorbLookFor(Brightness.dark), AbsorbLook.frostedDark);
      expect(absorbLookFor(Brightness.light), AbsorbLook.frostedLight);
      expect(absorbLookFor(Brightness.light, eink: true), AbsorbLook.plus);
      uiThemeNotifier.value = AppUiTheme.midnight;
      expect(absorbLookFor(Brightness.dark), AbsorbLook.midnightDark);
      expect(absorbLookFor(Brightness.light), AbsorbLook.midnightLight);
    });

    test('look details are layered on top of every look', () {
      const details = LookDetails(
        fullQualityCovers: true,
        extraCoverBadges: false,
        continueReadingShelf: true,
        compactHeaderButtons: true,
      );
      lookDetailsNotifier.value = details;
      for (final theme in AppUiTheme.values) {
        uiThemeNotifier.value = theme;
        for (final b in Brightness.values) {
          final look = absorbLookFor(b);
          expect(look.fullQualityCovers, isTrue, reason: '$theme $b');
          expect(look.defaultImageCache, isTrue);
          expect(look.showExtraCoverBadges, isFalse);
          expect(look.classicHomeShelves, isTrue);
          expect(look.compactHeaderActions, isTrue);
          // The look's own surfaces are untouched.
          expect(
            look.withNeutralSurfaces(),
            AbsorbLook.plus.withDetails(details),
          );
          expect(
            look.copyWith(
              fullQualityCovers: false,
              defaultImageCache: false,
              showExtraCoverBadges: true,
              classicHomeShelves: false,
              compactHeaderActions: false,
            ),
            theme.lookFor(b),
          );
        }
      }
      expect(currentAbsorbLook.defaultImageCache, isTrue);
    });

    test('each look detail maps to its own flag', () {
      final base = AbsorbLook.plus;
      expect(
        base.withDetails(const LookDetails(fullQualityCovers: true)),
        base.copyWith(fullQualityCovers: true, defaultImageCache: true),
      );
      expect(
        base.withDetails(const LookDetails(extraCoverBadges: false)),
        base.copyWith(showExtraCoverBadges: false),
      );
      expect(
        base.withDetails(const LookDetails(continueReadingShelf: true)),
        base.copyWith(classicHomeShelves: true),
      );
      expect(
        base.withDetails(const LookDetails(compactHeaderButtons: true)),
        base.copyWith(compactHeaderActions: true),
      );
      expect(base.withDetails(LookDetails.standard), base);
    });
  });

  group('persistence', () {
    test('choosing a look saves it and applies it', () async {
      await UiThemeStore.choose(AppUiTheme.midnight);
      expect(uiThemeNotifier.value, AppUiTheme.midnight);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UiThemeStore.prefKey), 'midnight');
    });

    test('Frosted round-trips through storage', () async {
      await UiThemeStore.choose(AppUiTheme.frosted);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UiThemeStore.prefKey), 'frosted');
      uiThemeNotifier.value = null;
      expect(await UiThemeStore.load(), AppUiTheme.frosted);
      expect(uiThemeNotifier.value, AppUiTheme.frosted);
    });

    test('load reads the saved look into the notifier', () async {
      SharedPreferences.setMockInitialValues({
        UiThemeStore.prefKey: 'midnight',
      });
      expect(await UiThemeStore.load(), AppUiTheme.midnight);
      expect(uiThemeNotifier.value, AppUiTheme.midnight);
      expect(lookDetailsNotifier.value, LookDetails.standard);
      expect(await UiThemeStore.needsChoice(), isFalse);
    });

    test('a saved Classic look becomes Standard with Classic details, '
        'once', () async {
      SharedPreferences.setMockInitialValues({UiThemeStore.prefKey: 'classic'});
      expect(await UiThemeStore.load(), AppUiTheme.plus);
      expect(uiThemeNotifier.value, AppUiTheme.plus);
      expect(lookDetailsNotifier.value, LookDetails.classic);
      expect(await UiThemeStore.needsChoice(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UiThemeStore.prefKey), 'plus');
      expect(prefs.getBool(LookDetailsStore.fullQualityCoversKey), isTrue);
      expect(prefs.getBool(LookDetailsStore.extraCoverBadgesKey), isFalse);
      expect(prefs.getBool(LookDetailsStore.continueReadingShelfKey), isTrue);
      expect(prefs.getBool(LookDetailsStore.compactHeaderButtonsKey), isTrue);
      // Nothing changes visually for that device.
      expect(
        absorbLookFor(Brightness.dark),
        AbsorbLook.plus.withDetails(LookDetails.classic),
      );

      // The user changes a detail; the next launch keeps it.
      await LookDetailsStore.save(
        LookDetails.classic.copyWith(extraCoverBadges: true),
      );
      lookDetailsNotifier.value = LookDetails.standard;
      expect(await UiThemeStore.load(), AppUiTheme.plus);
      expect(lookDetailsNotifier.value.extraCoverBadges, isTrue);
      expect(lookDetailsNotifier.value.fullQualityCovers, isTrue);
    });

    test('look details persist device-wide and default to Standard', () async {
      expect(await LookDetailsStore.load(), LookDetails.standard);
      const details = LookDetails(
        fullQualityCovers: true,
        continueReadingShelf: true,
      );
      await LookDetailsStore.save(details);
      expect(lookDetailsNotifier.value, details);
      lookDetailsNotifier.value = LookDetails.standard;
      expect(await LookDetailsStore.load(), details);
      expect(lookDetailsNotifier.value, details);
    });

    test('look detail changes re-notify the look listeners', () {
      var calls = 0;
      void listener() => calls++;
      uiThemeNotifier.addListener(listener);
      addTearDown(() => uiThemeNotifier.removeListener(listener));
      lookDetailsNotifier.value = LookDetails.classic;
      expect(calls, 1);
    });

    test('nothing saved (fresh install or update) needs a choice', () async {
      expect(await UiThemeStore.load(), isNull);
      expect(uiThemeNotifier.value, isNull);
      expect(await UiThemeStore.needsChoice(), isTrue);
    });

    test('an unknown stored id loads as unchosen, not a crash', () async {
      SharedPreferences.setMockInitialValues({UiThemeStore.prefKey: 'neon'});
      expect(await UiThemeStore.load(), isNull);
      expect(currentUiTheme, AppUiTheme.plus);
      expect(await UiThemeStore.needsChoice(), isTrue);
    });
  });

  group('first launch picker', () {
    testWidgets('shows a live preview per look and saves the picked look', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final done = UiThemePicker.showIfUnchosen(context, delay: Duration.zero);
      await tester.pumpAndSettle();

      expect(find.text('Choose a look'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Frosted'), findsOneWidget);
      expect(find.text('Midnight'), findsOneWidget);
      expect(find.text('Absorb Plus'), findsNothing);
      expect(find.text('Classic'), findsNothing);
      // Cards in the picker order: Standard, Frosted, Midnight.
      final xs = [
        for (final id in ['plus', 'frosted', 'midnight'])
          tester.getCenter(find.byKey(ValueKey('ui-look-$id'))).dx,
      ];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
      expect(
        find.byType(UiThemePreview),
        // One card per look; a short window has no room for the large one.
        findsNWidgets(AppUiTheme.values.length),
      );
      for (final theme in AppUiTheme.values) {
        final preview = tester.widget<UiThemePreview>(
          find.descendant(
            of: find.byKey(ValueKey('ui-look-${theme.id}')),
            matching: find.byType(UiThemePreview),
          ),
        );
        expect(preview.look, theme.lookFor(Brightness.light));
      }

      await _pickLookAndFinish(tester, 'Frosted');
      await done;

      expect(uiThemeNotifier.value, AppUiTheme.frosted);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UiThemeStore.prefKey), 'frosted');
      // Color untouched when not changed.
      expect(await PlayerSettings.getColorSource(), 'dynamic');
    });

    testWidgets('description follows the selected look', (tester) async {
      final context = await _pumpHost(tester);
      UiThemePicker.show(context);
      await tester.pumpAndSettle();
      expect(find.textContaining('usual Absorb Plus look'), findsOneWidget);
      await tester.tap(find.text('Frosted'));
      await tester.pump();
      expect(find.textContaining('frosted-glass'), findsOneWidget);
      expect(find.textContaining('usual Absorb Plus look'), findsNothing);
      await tester.tap(find.text('Midnight'));
      await tester.pump();
      expect(find.textContaining('thin outlines'), findsOneWidget);
      // Glass strength is Frosted's alone.
      expect(find.byKey(const ValueKey('ui-picker-glass')), findsNothing);
    });

    for (final size in const [Size(1280, 800), Size(390, 844)]) {
      testWidgets('large preview follows the selected look at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final context = await _pumpHost(tester);
        UiThemePicker.show(context);
        await tester.pumpAndSettle();
        final largeFinder = find.byKey(const ValueKey('ui-look-preview'));
        UiThemePreview large() => tester.widget<UiThemePreview>(
          find.descendant(
            of: largeFinder,
            matching: find.byType(UiThemePreview),
          ),
        );
        expect(large().look, AppUiTheme.plus.lookFor(Brightness.light));
        await tester.tap(find.text('Frosted'));
        await tester.pump();
        expect(large().look, AppUiTheme.frosted.lookFor(Brightness.light));
        await tester.tap(find.text('Midnight'));
        await tester.pump();
        expect(large().look, AppUiTheme.midnight.lookFor(Brightness.light));
        // It keeps the window's shape, and the whole dialog fits on screen.
        final frame = tester.getSize(
          find.descendant(
            of: largeFinder,
            matching: find.byKey(const ValueKey('ui-preview-frame')),
          ),
        );
        expect(frame.aspectRatio, closeTo(size.aspectRatio, 0.01));
        expect(frame.height, greaterThan(140));
        final window = Offset.zero & size;
        for (final theme in AppUiTheme.values) {
          final card = tester.getRect(
            find.byKey(ValueKey('ui-look-${theme.id}')),
          );
          expect(
            window.contains(card.bottomRight - const Offset(1, 1)),
            isTrue,
          );
        }
        expect(
          tester.getBottomLeft(find.text('Continue')).dy,
          lessThan(size.height),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('color step saves through the existing color settings', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final done = UiThemePicker.showIfUnchosen(context, delay: Duration.zero);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      UiThemePreview preview() => tester.widget<UiThemePreview>(
        find.descendant(
          of: find.byKey(const ValueKey('ui-color-preview')),
          matching: find.byType(UiThemePreview),
        ),
      );
      final before = preview().scheme.primary;

      final saturate = _presetArgb('saturate');
      await tester.ensureVisible(find.byKey(ValueKey('ui-color-$saturate')));
      await tester.tap(find.byKey(ValueKey('ui-color-$saturate')));
      await tester.pump();
      // The preview updates live, before anything is saved.
      expect(preview().scheme.primary, isNot(before));
      expect(colorSourceNotifier.value, 'dynamic');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await done;

      expect(await PlayerSettings.getColorSource(), 'manual');
      expect(await PlayerSettings.getManualSeedColor(), saturate);
      expect(colorSourceNotifier.value, 'manual');
      expect(manualSeedNotifier.value.toARGB32(), saturate);
      expect(uiThemeNotifier.value, AppUiTheme.plus);
    });

    testWidgets('"From cover" switches a manual color back to dynamic', (
      tester,
    ) async {
      colorSourceNotifier.value = 'manual';
      final context = await _pumpHost(tester);
      final done = UiThemePicker.showIfUnchosen(context, delay: Duration.zero);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From cover'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await done;
      expect(await PlayerSettings.getColorSource(), 'dynamic');
      expect(colorSourceNotifier.value, 'dynamic');
    });

    testWidgets('Back returns to the looks and keeps the selection', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      UiThemePicker.show(context);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Midnight'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a look'), findsOneWidget);
      expect(find.textContaining('OLED'), findsOneWidget);
    });

    testWidgets('both steps fit a small phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final context = await _pumpHost(tester);
      UiThemePicker.show(context);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(UiThemePreview), findsNWidgets(3));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('From cover'), findsOneWidget);
    });

    testWidgets('does not show once a look is chosen', (tester) async {
      SharedPreferences.setMockInitialValues({UiThemeStore.prefKey: 'plus'});
      final context = await _pumpHost(tester);
      await UiThemePicker.showIfUnchosen(context, delay: Duration.zero);
      await tester.pumpAndSettle();
      expect(find.text('Choose a look'), findsNothing);
    });

    testWidgets('dismissing keeps Standard and marks it chosen', (
      tester,
    ) async {
      final context = await _pumpHost(tester);
      final done = UiThemePicker.showIfUnchosen(context, delay: Duration.zero);
      await tester.pumpAndSettle();
      expect(find.text('Choose a look'), findsOneWidget);

      // Tap the barrier outside the dialog.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await done;

      expect(find.text('Choose a look'), findsNothing);
      expect(uiThemeNotifier.value, AppUiTheme.plus);
      expect(await UiThemeStore.needsChoice(), isFalse);
      expect(await PlayerSettings.getColorSource(), 'dynamic');

      // Next launch: no picker.
      await UiThemePicker.showIfUnchosen(context, delay: Duration.zero);
      await tester.pumpAndSettle();
      expect(find.text('Choose a look'), findsNothing);
    });
  });

  group('settings tile', () {
    testWidgets('shows the current look and changes it', (tester) async {
      var changed = 0;
      await tester.pumpWidget(
        _app(
          home: Scaffold(body: UiThemeSettingsTile(onChanged: () => changed++)),
        ),
      );
      expect(find.text('UI theme'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);

      await tester.tap(find.text('UI theme'));
      await tester.pumpAndSettle();
      await _pickLookAndFinish(tester, 'Midnight');

      expect(uiThemeNotifier.value, AppUiTheme.midnight);
      expect(find.text('Midnight'), findsOneWidget);
      expect(find.text('Standard'), findsNothing);
      expect(changed, 1);
    });

    testWidgets('look detail switches save and apply over the active look', (
      tester,
    ) async {
      final saved = <LookDetails>[];
      uiThemeNotifier.value = AppUiTheme.midnight;
      await tester.pumpWidget(
        _app(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UiThemeSettingsTile(
                saveDetails: (d) async {
                  saved.add(d);
                  lookDetailsNotifier.value = d;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Look details'), findsOneWidget);
      bool on(String id) => tester
          .widget<SwitchListTile>(find.byKey(ValueKey('ui-detail-$id')))
          .value;
      // Defaults are Standard's behavior.
      expect(on('full-covers'), isFalse);
      expect(on('extra-badges'), isTrue);
      expect(on('reading-shelf'), isFalse);
      expect(on('compact-header'), isFalse);

      for (final id in [
        'full-covers',
        'extra-badges',
        'reading-shelf',
        'compact-header',
      ]) {
        await tester.ensureVisible(find.byKey(ValueKey('ui-detail-$id')));
        await tester.tap(find.byKey(ValueKey('ui-detail-$id')));
        await tester.pump();
      }
      expect(saved.last, LookDetails.classic);
      expect(on('full-covers'), isTrue);
      expect(on('extra-badges'), isFalse);
      // The look stays Midnight, with the details on top.
      expect(uiThemeNotifier.value, AppUiTheme.midnight);
      expect(
        absorbLookFor(Brightness.dark),
        AbsorbLook.midnightDark.withDetails(LookDetails.classic),
      );
    });

    testWidgets('look detail switches persist through the real store', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          home: const Scaffold(
            body: SingleChildScrollView(child: UiThemeSettingsTile()),
          ),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('ui-detail-compact-header')),
      );
      await tester.tap(find.byKey(const ValueKey('ui-detail-compact-header')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LookDetailsStore.compactHeaderButtonsKey), isTrue);
      expect(lookDetailsNotifier.value.compactHeaderButtons, isTrue);
    });

    testWidgets('Plain wording drives the classic wording setting', (
      tester,
    ) async {
      final saved = <bool>[];
      await tester.pumpWidget(
        _app(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UiThemeSettingsTile(
                savePlainWording: (v) async => saved.add(v),
              ),
            ),
          ),
        ),
      );
      final plain = find.byKey(const ValueKey('ui-plain-wording'));
      expect(find.text('Plain wording'), findsOneWidget);
      expect(
        find.text('Using "Absorb", "Absorbing", "Fully Absorbed"'),
        findsOneWidget,
      );
      await tester.ensureVisible(plain);
      await tester.tap(plain);
      await tester.pump();
      expect(classicWordingNotifier.value, isTrue);
      expect(saved, [true]);
      expect(
        find.text('Using "Play", "Now Playing", "Finished"'),
        findsOneWidget,
      );
      // Follows changes made elsewhere too.
      classicWordingNotifier.value = false;
      await tester.pump();
      expect(tester.widget<SwitchListTile>(plain).value, isFalse);
    });

    test('the old Classic wording switch is gone from Settings', () {
      // Settings shows Plain wording through UiThemeSettingsTile, in
      // Appearance; an upstream merge must not bring the old switch back.
      final settings = File(
        'lib/screens/settings_screen.dart',
      ).readAsStringSync();
      expect(settings, isNot(contains("'Classic wording'")));
      expect(settings, isNot(contains('setClassicWording')));
      expect(RegExp(r'UiThemeSettingsTile\(').allMatches(settings).length, 1);
    });

    testWidgets('Plain wording saves to the existing preference', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          home: const Scaffold(
            body: SingleChildScrollView(child: UiThemeSettingsTile()),
          ),
        ),
      );
      final plain = find.byKey(const ValueKey('ui-plain-wording'));
      await tester.ensureVisible(plain);
      await tester.tap(plain);
      await tester.pumpAndSettle();
      expect(await PlayerSettings.getClassicWording(), isTrue);
    });

    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      testWidgets('the tile fits without overflow at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final theme in AppUiTheme.values) {
          uiThemeNotifier.value = theme;
          await tester.pumpWidget(
            _app(
              home: const Scaffold(
                body: SingleChildScrollView(child: UiThemeSettingsTile()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$theme');
          expect(
            find.byKey(const ValueKey('ui-settings-glass')),
            theme == AppUiTheme.frosted ? findsOneWidget : findsNothing,
          );
        }
      });
    }

    testWidgets('dismissing from settings changes nothing', (tester) async {
      var changed = 0;
      await tester.pumpWidget(
        _app(
          home: Scaffold(body: UiThemeSettingsTile(onChanged: () => changed++)),
        ),
      );
      await tester.tap(find.text('UI theme'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(uiThemeNotifier.value, isNull);
      expect(await UiThemeStore.needsChoice(), isTrue);
      expect(changed, 0);
    });
  });

  group('image cache policy', () {
    test('Standard keeps the small cache and trims it in background', () {
      final cache = _RecordingImageCache();
      configureImageCache(cache);
      expect(cache.maximumSizeBytes, kAbsorbImageCacheMaximumBytes);
      expect(cache.maximumSize, kAbsorbImageCacheMaximumEntries);
      trimDecodedImageCacheForBackground(cache);
      expect(cache.clearCalls, 1);
    });

    test('Frosted and Midnight keep the Standard cache policy', () {
      final cache = _RecordingImageCache();
      configureImageCache(cache);
      uiThemeNotifier.value = AppUiTheme.frosted;
      expect(cache.maximumSizeBytes, kAbsorbImageCacheMaximumBytes);
      trimDecodedImageCacheForBackground(cache);
      expect(cache.clearCalls, 1);
      uiThemeNotifier.value = AppUiTheme.midnight;
      expect(cache.maximumSizeBytes, kAbsorbImageCacheMaximumBytes);
      trimDecodedImageCacheForBackground(cache);
      expect(cache.clearCalls, 2);
    });

    test('Full-quality covers use Flutter defaults and keep the cache in '
        'background, in any look', () {
      final cache = _RecordingImageCache();
      configureImageCache(cache);
      uiThemeNotifier.value = AppUiTheme.midnight;
      lookDetailsNotifier.value = const LookDetails(fullQualityCovers: true);
      expect(cache.maximumSizeBytes, kFlutterDefaultImageCacheMaximumBytes);
      expect(cache.maximumSize, kFlutterDefaultImageCacheMaximumEntries);
      expect(
        ImageCache().maximumSizeBytes,
        kFlutterDefaultImageCacheMaximumBytes,
      );
      expect(ImageCache().maximumSize, kFlutterDefaultImageCacheMaximumEntries);
      trimDecodedImageCacheForBackground(cache);
      expect(cache.clearCalls, 0);

      // Turning it off re-applies the Standard limits.
      lookDetailsNotifier.value = LookDetails.standard;
      expect(cache.maximumSizeBytes, kAbsorbImageCacheMaximumBytes);
      expect(cache.maximumSize, kAbsorbImageCacheMaximumEntries);
    });
  });
}
