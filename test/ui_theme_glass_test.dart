import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/main.dart'
    show colorSourceNotifier, einkModeNotifier, manualSeedNotifier;
import 'package:absorb/screens/settings_search_index.dart';
import 'package:absorb/ui_themes/frosted.dart';
import 'package:absorb/ui_themes/ui_theme.dart';
import 'package:absorb/ui_themes/ui_theme_hooks.dart';
import 'package:absorb/ui_themes/ui_theme_picker.dart';
import 'package:absorb/ui_themes/ui_theme_preview.dart';
import 'package:absorb/ui_themes/ui_theme_try.dart';
import 'package:absorb/widgets/cover_decode.dart';
import 'package:absorb/widgets/settings_search.dart';
import 'package:absorb/widgets/theme_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app the way main.dart wires it: rebuilt on the saved and previewed
/// look notifiers only (glass changes must reach it through them), the look
/// as a ThemeData extension, and [absorbLookBuilder].
Future<BuildContext> _pumpApp(WidgetTester tester) async {
  late BuildContext home;
  await tester.pumpWidget(
    UiThemeScope(
      child: ListenableBuilder(
        listenable: Listenable.merge([uiThemeNotifier, uiThemePreviewNotifier]),
        builder: (context, _) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [absorbLookFor(Brightness.light)]),
          builder: absorbLookBuilder,
          home: Builder(
            builder: (context) {
              home = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return home;
}

/// The look a widget inside the app's pages sees right now.
AbsorbLook _lookIn(WidgetTester tester) =>
    AbsorbLook.of(tester.element(find.byType(Scaffold).first));

void _setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

Finder _inCard(AppUiTheme theme, Finder matching) => find.descendant(
  of: find.byKey(ValueKey('ui-look-${theme.id}')),
  matching: matching,
);

UiThemePreview _cardPreview(WidgetTester tester, AppUiTheme theme) =>
    tester.widget<UiThemePreview>(_inCard(theme, find.byType(UiThemePreview)));

UiThemePreview _largePreview(WidgetTester tester) =>
    tester.widget<UiThemePreview>(
      find.descendant(
        of: find.byKey(const ValueKey('ui-look-preview')),
        matching: find.byType(UiThemePreview),
      ),
    );

Set<GlassStrength> _pickerGlass(WidgetTester tester) => tester
    .widget<SegmentedButton<GlassStrength>>(
      find.descendant(
        of: find.byKey(const ValueKey('ui-picker-glass')),
        matching: find.byType(SegmentedButton<GlassStrength>),
      ),
    )
    .selected;

int _presetArgb(String id) =>
    kThemePresets.firstWhere((p) => p.id == id).color.toARGB32();

void main() {
  setUp(() {
    uiThemeNotifier.value = null;
    uiThemePreviewNotifier.value = null;
    glassStrengthNotifier.value = kDefaultGlassStrength;
    glassStrengthPreviewNotifier.value = null;
    lookDetailsNotifier.value = LookDetails.standard;
    einkModeNotifier.value = false;
    colorSourceNotifier.value = 'dynamic';
    manualSeedNotifier.value = const Color(0xFF7C6FBF);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    UiThemeTryOut.end(UiThemeTryOutOutcome.ended);
    uiThemeNotifier.value = null;
    glassStrengthNotifier.value = kDefaultGlassStrength;
    einkModeNotifier.value = false;
  });

  group('presets', () {
    test('medium is the original Frosted, value for value', () {
      const originalDark = AbsorbLook(
        glowStrength: 0.30,
        backdropTint: 0.16,
        panelFillAlpha: 0.10,
        panelBorderAlpha: 0.16,
        panelBlurSigma: 18,
        cornerRadiusBoost: 4,
        sheetFillAlpha: 0.90,
        cardFillOpacity: 0.62,
        frostedNavBar: true,
        frostedSheets: true,
        frostedPlayerCard: true,
      );
      const originalLight = AbsorbLook(
        glowStrength: 0.22,
        backdropTint: 0.10,
        panelFillAlpha: 0.50,
        panelBorderAlpha: 0.08,
        panelBlurSigma: 18,
        cornerRadiusBoost: 4,
        sheetFillAlpha: 0.90,
        cardFillOpacity: 0.62,
        frostedNavBar: true,
        frostedSheets: true,
        frostedPlayerCard: true,
      );
      final frosted = AppUiTheme.frosted;
      expect(kDefaultGlassStrength, GlassStrength.medium);
      expect(
        frosted.lookFor(Brightness.dark, glass: GlassStrength.medium),
        originalDark,
      );
      expect(
        frosted.lookFor(Brightness.light, glass: GlassStrength.medium),
        originalLight,
      );
      // Without a strength: medium.
      expect(frosted.lookFor(Brightness.dark), originalDark);
      expect(frosted.lookFor(Brightness.light), originalLight);
      // Other looks ignore the strength.
      for (final glass in GlassStrength.values) {
        expect(
          AppUiTheme.plus.lookFor(Brightness.dark, glass: glass),
          AbsorbLook.plus,
        );
        expect(
          AppUiTheme.midnight.lookFor(Brightness.light, glass: glass),
          AbsorbLook.midnightLight,
        );
      }
    });

    test('light is subtler and strong is stronger, in both modes', () {
      for (final b in Brightness.values) {
        AbsorbLook at(GlassStrength g) =>
            AppUiTheme.frosted.lookFor(b, glass: g);
        final l = at(GlassStrength.light);
        final m = at(GlassStrength.medium);
        final s = at(GlassStrength.strong);
        void rising(double Function(AbsorbLook) token, String name) {
          expect(token(l), lessThan(token(m)), reason: '$b $name light');
          expect(token(m), lessThan(token(s)), reason: '$b $name strong');
        }

        rising((x) => x.glowStrength!, 'glow');
        rising((x) => x.backdropTint, 'tint');
        rising((x) => x.panelBlurSigma, 'blur');
        rising((x) => x.panelBorderAlpha, 'edge');
        // See-through: sheets and cover-tinted cards let more through.
        rising((x) => 1 - x.sheetFillAlpha!, 'sheet see-through');
        rising((x) => 1 - x.cardFillOpacity, 'card see-through');
        if (b == Brightness.light) {
          // Milky glass: stronger glass is less milky.
          rising((x) => 1 - x.panelFillAlpha!, 'clear glass');
        } else {
          // Dark glass: stronger glass has a brighter sheen.
          rising((x) => x.panelFillAlpha!, 'sheen');
        }
        for (final look in [l, m, s]) {
          // Same shape and behavior at every strength, still readable.
          expect(look.cornerRadiusBoost, 4);
          expect(look.withNeutralSurfaces(), AbsorbLook.plus);
          expect(look.frostedPanels, isTrue);
          expect(look.frostedNavBar && look.frostedSheets, isTrue);
          expect(look.frostedPlayerCard, isTrue);
          expect(look.sheetFillAlpha, greaterThanOrEqualTo(0.8));
        }
      }
    });

    test('e-ink drops the glass at every strength', () {
      for (final glass in GlassStrength.values) {
        expect(
          AppUiTheme.frosted.lookFor(
            Brightness.light,
            eink: true,
            glass: glass,
          ),
          AbsorbLook.plus,
        );
      }
    });

    test('ids are stable and round-trip', () {
      expect(
        [for (final g in GlassStrength.values) g.id],
        ['light', 'medium', 'strong'],
      );
      for (final glass in GlassStrength.values) {
        expect(GlassStrength.fromId(glass.id), glass);
      }
      expect(GlassStrength.fromId(null), isNull);
      expect(GlassStrength.fromId('frost'), isNull);
    });

    test('lerp and copyWith carry the card see-through', () {
      const a = AbsorbLook.frostedDarkGlassLight;
      const b = AbsorbLook.frostedDarkGlassStrong;
      expect(a.lerp(b, 0.5).cardFillOpacity, closeTo((0.78 + 0.48) / 2, 1e-9));
      expect(a.copyWith(cardFillOpacity: 0.5).cardFillOpacity, 0.5);
      expect(a.copyWith(), a);
      expect(a == b, isFalse);
    });

    testWidgets('Frosted cards let more through as the glass gets stronger', (
      tester,
    ) async {
      final look = ValueNotifier<AppUiTheme?>(AppUiTheme.frosted);
      addTearDown(look.dispose);
      late BuildContext ctx;
      await tester.pumpWidget(
        UiThemeScope(
          notifier: look,
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      const card = [Color(0xFF303040)];
      final alphas = <double>[];
      for (final glass in GlassStrength.values) {
        glassStrengthNotifier.value = glass;
        await tester.pump();
        alphas.add(lookCardColors(ctx, card).single.a);
      }
      expect(alphas[1], closeTo(0.62, 0.005), reason: 'medium unchanged');
      expect(alphas[0], greaterThan(alphas[1]));
      expect(alphas[1], greaterThan(alphas[2]));
      // Other looks: untouched at any strength.
      look.value = AppUiTheme.plus;
      await tester.pump();
      expect(lookCardColors(ctx, card), card);
    });
  });

  group('storage', () {
    test('defaults to medium when nothing is saved', () async {
      glassStrengthNotifier.value = GlassStrength.strong;
      await UiThemeStore.load();
      expect(glassStrengthNotifier.value, GlassStrength.medium);
      expect((await _prefs()).getString(UiThemeStore.glassPrefKey), isNull);
    });

    test('a chosen strength is saved device-wide and loads back', () async {
      expect(UiThemeStore.glassPrefKey, 'fork_ui_glass');
      await UiThemeStore.chooseGlass(GlassStrength.light);
      expect(glassStrengthNotifier.value, GlassStrength.light);
      expect((await _prefs()).getString('fork_ui_glass'), 'light');
      glassStrengthNotifier.value = GlassStrength.medium;
      await UiThemeStore.load();
      expect(glassStrengthNotifier.value, GlassStrength.light);
    });

    test('an unknown stored strength loads as medium', () async {
      SharedPreferences.setMockInitialValues({'fork_ui_glass': 'frost'});
      await UiThemeStore.load();
      expect(glassStrengthNotifier.value, GlassStrength.medium);
    });

    test('choose saves the look and the strength together', () async {
      await UiThemeStore.choose(
        AppUiTheme.frosted,
        glass: GlassStrength.strong,
      );
      final prefs = await _prefs();
      expect(prefs.getString(UiThemeStore.prefKey), 'frosted');
      expect(prefs.getString(UiThemeStore.glassPrefKey), 'strong');
      expect(absorbLookFor(Brightness.dark), AbsorbLook.frostedDarkGlassStrong);
      // Without a strength, the saved one stays.
      await UiThemeStore.choose(AppUiTheme.plus);
      expect(savedGlassStrength, GlassStrength.strong);
    });

    test('the look notifiers also report glass changes', () async {
      var saved = 0;
      var preview = 0;
      void onSaved() => saved++;
      void onPreview() => preview++;
      uiThemeNotifier.addListener(onSaved);
      uiThemePreviewNotifier.addListener(onPreview);
      addTearDown(() {
        uiThemeNotifier.removeListener(onSaved);
        uiThemePreviewNotifier.removeListener(onPreview);
      });
      uiThemeNotifier.value = AppUiTheme.frosted;
      saved = 0;
      await UiThemeStore.chooseGlass(GlassStrength.strong);
      expect(saved, 1);
      expect(
        absorbLookFor(Brightness.light),
        AbsorbLook.frostedLightGlassStrong,
      );
      glassStrengthPreviewNotifier.value = GlassStrength.light;
      expect(preview, 1);
      expect(
        absorbLookFor(Brightness.light),
        AbsorbLook.frostedLightGlassLight,
      );
    });
  });

  group('picker', () {
    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      testWidgets('Glass shows only for Frosted and drives the previews at '
          '$size', (tester) async {
        _setWindow(tester, size);
        final home = await _pumpApp(tester);
        UiThemePicker.show(home);
        await tester.pumpAndSettle();
        final glassRow = find.byKey(const ValueKey('ui-picker-glass'));
        expect(glassRow, findsNothing);

        await tester.tap(find.text('Midnight'));
        await tester.pump();
        expect(glassRow, findsNothing);
        expect(_largePreview(tester).look, AbsorbLook.midnightLight);

        await tester.tap(find.text('Frosted'));
        await tester.pump();
        expect(glassRow, findsOneWidget);
        expect(_pickerGlass(tester), {GlassStrength.medium});
        final plusBefore = _cardPreview(tester, AppUiTheme.plus);

        await tester.tap(find.byKey(const ValueKey('ui-glass-strong')));
        await tester.pump();
        expect(_pickerGlass(tester), {GlassStrength.strong});
        expect(_largePreview(tester).look, AbsorbLook.frostedLightGlassStrong);
        expect(
          _cardPreview(tester, AppUiTheme.frosted).look,
          AbsorbLook.frostedLightGlassStrong,
        );
        // The other cards are reused as they were, not rebuilt.
        expect(
          identical(_cardPreview(tester, AppUiTheme.plus), plusBefore),
          isTrue,
        );
        // Nothing applied or saved yet.
        expect(currentGlassStrength, GlassStrength.medium);

        // Everything fits on screen, Glass row included.
        final window = Offset.zero & size;
        for (final finder in [
          glassRow,
          for (final t in AppUiTheme.values)
            find.byKey(ValueKey('ui-look-${t.id}')),
          find.text('Continue'),
        ]) {
          final rect = tester.getRect(finder);
          expect(window.contains(rect.topLeft), isTrue, reason: '$finder');
          expect(
            window.contains(rect.bottomRight - const Offset(1, 1)),
            isTrue,
            reason: '$finder',
          );
        }
        expect(
          tester.getSize(find.byKey(const ValueKey('ui-look-preview'))).height,
          greaterThan(140),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Done saves the strength with the look', (tester) async {
      final home = await _pumpApp(tester);
      final done = UiThemePicker.changeFromSettings(home);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frosted'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ui-glass-light')));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      // The color step's preview shows the chosen glass too.
      expect(
        tester
            .widget<UiThemePreview>(
              find.descendant(
                of: find.byKey(const ValueKey('ui-color-preview')),
                matching: find.byType(UiThemePreview),
              ),
            )
            .look,
        AbsorbLook.frostedLightGlassLight,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await done;

      expect(savedUiTheme, AppUiTheme.frosted);
      expect(savedGlassStrength, GlassStrength.light);
      expect((await _prefs()).getString(UiThemeStore.glassPrefKey), 'light');
      expect(_lookIn(tester), AbsorbLook.frostedLightGlassLight);
    });

    testWidgets('dismissing changes nothing', (tester) async {
      final home = await _pumpApp(tester);
      final done = UiThemePicker.changeFromSettings(home);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frosted'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ui-glass-strong')));
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await done;
      expect(uiThemeNotifier.value, isNull);
      expect(savedGlassStrength, GlassStrength.medium);
      expect((await _prefs()).getKeys(), isEmpty);
    });

    testWidgets('e-ink previews show what the app shows', (tester) async {
      einkModeNotifier.value = true;
      final home = await _pumpApp(tester);
      UiThemePicker.show(home);
      await tester.pumpAndSettle();
      expect(_cardPreview(tester, AppUiTheme.frosted).look, AbsorbLook.plus);
      expect(_cardPreview(tester, AppUiTheme.midnight).look, AbsorbLook.plus);
    });

    testWidgets('previews never take keyboard focus', (tester) async {
      _setWindow(tester, const Size(1280, 800));
      final home = await _pumpApp(tester);
      UiThemePicker.show(home);
      await tester.pumpAndSettle();
      expect(find.byType(UiThemePreview), findsNWidgets(4));
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        expect(
          focused?.findAncestorWidgetOfExactType<UiThemePreview>(),
          isNull,
          reason: 'tab $i landed inside a preview',
        );
      }
    });
  });

  group('settings', () {
    Future<void> pumpTile(WidgetTester tester) => tester.pumpWidget(
      UiThemeScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: UiThemeSettingsTile()),
        ),
      ),
    );

    testWidgets('Glass appears only in Frosted, applies and saves', (
      tester,
    ) async {
      _setWindow(tester, const Size(390, 844));
      final glass = find.byKey(const ValueKey('ui-settings-glass'));
      await pumpTile(tester);
      expect(glass, findsNothing);
      uiThemeNotifier.value = AppUiTheme.midnight;
      await tester.pump();
      expect(glass, findsNothing);

      uiThemeNotifier.value = AppUiTheme.frosted;
      await tester.pump();
      expect(glass, findsOneWidget);
      expect(find.text('Glass'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ui-glass-strong')));
      await tester.pump();
      expect(glassStrengthNotifier.value, GlassStrength.strong);
      expect(
        tester
            .widget<SegmentedButton<GlassStrength>>(
              find.byType(SegmentedButton<GlassStrength>),
            )
            .selected,
        {GlassStrength.strong},
      );
      await tester.pumpAndSettle();
      expect((await _prefs()).getString(UiThemeStore.glassPrefKey), 'strong');
      expect(tester.takeException(), isNull);
    });

    testWidgets('search finds Frosted and Glass under UI theme', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final entry = settingsSearchEntries(
        ctx,
      ).firstWhere((e) => e.title == 'UI theme');
      expect(entry.extras, containsAll(['Frosted', 'Glass']));
    });

    testWidgets('search finds the looks, look details and Plain wording', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final entries = settingsSearchEntries(ctx);
      List<String> titles(String query) => [
        for (final e in filterSettingEntries(entries, query)) e.title,
      ];
      expect(titles('Midnight'), contains('UI theme'));
      expect(titles('Standard'), contains('UI theme'));
      expect(titles('wording').first, 'Plain wording');
      expect(titles('plain').first, 'Plain wording');
      expect(titles('classic'), containsAll(['Plain wording', 'Look details']));
      expect(titles('Classic wording'), contains('Plain wording'));
      expect(titles('full-quality'), contains('Full-quality covers'));
      expect(titles('badges'), contains('Extra cover badges'));
      expect(
        titles('continue reading'),
        contains('Continue Reading as a shelf'),
      );
      expect(titles('compact'), contains('Compact header buttons'));
      // All of them open the Appearance section, where the tile lives.
      for (final title in [
        'UI theme',
        'Look details',
        'Full-quality covers',
        'Extra cover badges',
        'Continue Reading as a shelf',
        'Compact header buttons',
        'Plain wording',
      ]) {
        expect(
          entries.where((e) => e.title == title).single.sectionId,
          'Appearance',
          reason: title,
        );
      }
      expect(entries.where((e) => e.title == 'Classic wording'), isEmpty);
    });
  });

  group('Try it', () {
    Future<Future<UiThemePickerResult?>> tryFrosted(
      WidgetTester tester,
      Future<UiThemePickerResult?> Function() open, {
      GlassStrength glass = GlassStrength.strong,
    }) async {
      final result = open();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frosted'));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('ui-glass-${glass.id}')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ui-try-it')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('previews the strength; Go back restores look and strength', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        UiThemeStore.prefKey: 'midnight',
      });
      await UiThemeStore.load();
      final home = await _pumpApp(tester);
      final result = await tryFrosted(tester, () => UiThemePicker.show(home));

      expect(_lookIn(tester), AbsorbLook.frostedLightGlassStrong);
      expect(savedGlassStrength, GlassStrength.medium);
      expect((await _prefs()).getString(UiThemeStore.glassPrefKey), isNull);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(_lookIn(tester), AbsorbLook.midnightLight);
      expect(currentGlassStrength, GlassStrength.medium);
      expect(glassStrengthPreviewNotifier.value, isNull);
      // Back in the picker on the tried look and strength.
      expect(_pickerGlass(tester), {GlassStrength.strong});

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(savedUiTheme, AppUiTheme.midnight);
      expect(savedGlassStrength, GlassStrength.medium);
    });

    testWidgets('Keep saves the strength and the color picked before it', (
      tester,
    ) async {
      final home = await _pumpApp(tester);
      final done = UiThemePicker.changeFromSettings(home);
      await tester.pumpAndSettle();
      // Pick a color first, then go back and try a look.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final saturate = _presetArgb('saturate');
      await tester.ensureVisible(find.byKey(ValueKey('ui-color-$saturate')));
      await tester.tap(find.byKey(ValueKey('ui-color-$saturate')));
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tryFrosted(tester, () async => null, glass: GlassStrength.light);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await done;
      expect(savedUiTheme, AppUiTheme.frosted);
      expect(savedGlassStrength, GlassStrength.light);
      expect((await _prefs()).getString(UiThemeStore.glassPrefKey), 'light');
      expect(_lookIn(tester), AbsorbLook.frostedLightGlassLight);
      expect(colorSourceNotifier.value, 'manual');
      expect(manualSeedNotifier.value.toARGB32(), saturate);
    });

    testWidgets('Go back keeps the color picked so far', (tester) async {
      final home = await _pumpApp(tester);
      final done = UiThemePicker.changeFromSettings(home);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final saturate = _presetArgb('saturate');
      await tester.ensureVisible(find.byKey(ValueKey('ui-color-$saturate')));
      await tester.tap(find.byKey(ValueKey('ui-color-$saturate')));
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tryFrosted(tester, () async => null);
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();

      // The reopened picker still has the color: Done saves it.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await done;
      expect(colorSourceNotifier.value, 'manual');
      expect(manualSeedNotifier.value.toARGB32(), saturate);
      expect(savedGlassStrength, GlassStrength.strong);
    });

    test('Go back during Keep cannot undo the save', () async {
      final outcome = UiThemeTryOut.start(
        AppUiTheme.frosted,
        glass: GlassStrength.strong,
      );
      final keeping = UiThemeTryOut.keep();
      UiThemeTryOut.goBack(); // tapped while Keep is still saving
      expect(uiThemePreviewNotifier.value, AppUiTheme.frosted);
      await keeping;
      expect(await outcome, UiThemeTryOutOutcome.kept);
      expect(savedUiTheme, AppUiTheme.frosted);
      expect(savedGlassStrength, GlassStrength.strong);
      expect(uiThemePreviewNotifier.value, isNull);
      expect(glassStrengthPreviewNotifier.value, isNull);
    });

    testWidgets('a newer Try it keeps its preview and the first-launch '
        'question still counts as answered', (tester) async {
      final home = await _pumpApp(tester);
      final firstLaunch = UiThemePicker.showIfUnchosen(
        home,
        delay: Duration.zero,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frosted'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ui-try-it')));
      await tester.pumpAndSettle();

      // Settings > UI theme > Try it, while the first preview is up.
      final again = UiThemeTryOut.start(AppUiTheme.midnight);
      await firstLaunch;
      await tester.pumpAndSettle();

      expect(uiThemePreviewNotifier.value, AppUiTheme.midnight);
      expect(_lookIn(tester), AbsorbLook.midnightLight);
      expect(await UiThemeStore.needsChoice(), isFalse);
      expect(savedUiTheme, AppUiTheme.plus);

      UiThemeTryOut.goBack();
      expect(await again, UiThemeTryOutOutcome.wentBack);
    });
  });

  testWidgets('preview covers decode at Home\'s size', (tester) async {
    _setWindow(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
          child: SizedBox(
            width: 200,
            child: UiThemePreview(
              look: AbsorbLook.plus,
              scheme: ThemeData().colorScheme,
              glow: 0.2,
              covers: const [UiThemePreviewCover(url: '/missing/cover.jpg')],
            ),
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image).first);
    final provider = image.image as ResizeImage;
    expect(
      provider.width,
      coverDecodeWidth(width: 120, height: 120, devicePixelRatio: 1),
    );
  });
}
