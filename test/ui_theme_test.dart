import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/main.dart' show colorSourceNotifier, manualSeedNotifier;
import 'package:absorb/services/player_settings.dart';
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
    colorSourceNotifier.value = 'dynamic';
    manualSeedNotifier.value = const Color(0xFF7C6FBF);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => uiThemeNotifier.value = null);

  group('presets', () {
    test('Absorb Plus changes nothing', () {
      expect(AppUiTheme.plus.spec, const AbsorbLook());
      final spec = AppUiTheme.plus.spec;
      expect(spec.fullQualityCovers, isFalse);
      expect(spec.defaultImageCache, isFalse);
      expect(spec.showExtraCoverBadges, isTrue);
      expect(spec.classicHomeShelves, isFalse);
      expect(spec.compactHeaderActions, isFalse);
    });

    test('Classic restores the first Windows port look', () {
      final spec = AppUiTheme.classic.spec;
      expect(spec.fullQualityCovers, isTrue);
      expect(spec.defaultImageCache, isTrue);
      expect(spec.showExtraCoverBadges, isFalse);
      expect(spec.classicHomeShelves, isTrue);
      expect(spec.compactHeaderActions, isTrue);
    });

    test('Absorb Plus and Classic keep neutral surface tokens', () {
      for (final theme in [AppUiTheme.plus, AppUiTheme.classic]) {
        for (final b in Brightness.values) {
          final look = theme.lookFor(b);
          expect(look.glowStrength, isNull, reason: '$theme $b');
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
        }
      }
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
      expect(
        AppUiTheme.frosted.lookFor(Brightness.light, eink: true),
        AbsorbLook.plus,
      );
      expect(
        AppUiTheme.classic.lookFor(Brightness.light, eink: true),
        AbsorbLook.classic,
      );
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
    });

    test('ids are stable and round-trip', () {
      expect(AppUiTheme.plus.id, 'plus');
      expect(AppUiTheme.classic.id, 'classic');
      expect(AppUiTheme.frosted.id, 'frosted');
      for (final theme in AppUiTheme.values) {
        expect(AppUiTheme.fromId(theme.id), theme);
      }
      expect(
        AppUiTheme.values.map((t) => t.id).toSet().length,
        AppUiTheme.values.length,
      );
    });

    test('unknown or missing ids are null and fall back to Absorb Plus', () {
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
    });
  });

  group('persistence', () {
    test('choosing a look saves it and applies it', () async {
      await UiThemeStore.choose(AppUiTheme.classic);
      expect(uiThemeNotifier.value, AppUiTheme.classic);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UiThemeStore.prefKey), 'classic');
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
      SharedPreferences.setMockInitialValues({UiThemeStore.prefKey: 'classic'});
      expect(await UiThemeStore.load(), AppUiTheme.classic);
      expect(uiThemeNotifier.value, AppUiTheme.classic);
      expect(await UiThemeStore.needsChoice(), isFalse);
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
      expect(find.text('Absorb Plus'), findsOneWidget);
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Frosted'), findsOneWidget);
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
      expect(find.textContaining("Today's look"), findsOneWidget);
      await tester.tap(find.text('Frosted'));
      await tester.pump();
      expect(find.textContaining('frosted-glass'), findsOneWidget);
      expect(find.textContaining("Today's look"), findsNothing);
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
      await tester.tap(find.text('Classic'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a look'), findsOneWidget);
      expect(find.textContaining('first Windows version'), findsOneWidget);
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

    testWidgets('dismissing keeps Absorb Plus and marks it chosen', (
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
      expect(find.text('Absorb Plus'), findsOneWidget);

      await tester.tap(find.byType(UiThemeSettingsTile));
      await tester.pumpAndSettle();
      await _pickLookAndFinish(tester, 'Classic');

      expect(uiThemeNotifier.value, AppUiTheme.classic);
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Absorb Plus'), findsNothing);
      expect(changed, 1);
    });

    testWidgets('dismissing from settings changes nothing', (tester) async {
      var changed = 0;
      await tester.pumpWidget(
        _app(
          home: Scaffold(body: UiThemeSettingsTile(onChanged: () => changed++)),
        ),
      );
      await tester.tap(find.byType(UiThemeSettingsTile));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(uiThemeNotifier.value, isNull);
      expect(await UiThemeStore.needsChoice(), isTrue);
      expect(changed, 0);
    });
  });

  group('image cache policy', () {
    test('Absorb Plus keeps the small cache and trims it in background', () {
      final cache = _RecordingImageCache();
      configureImageCache(cache);
      expect(cache.maximumSizeBytes, kAbsorbImageCacheMaximumBytes);
      expect(cache.maximumSize, kAbsorbImageCacheMaximumEntries);
      trimDecodedImageCacheForBackground(cache);
      expect(cache.clearCalls, 1);
    });

    test('Frosted keeps the Absorb Plus cache policy', () {
      final cache = _RecordingImageCache();
      configureImageCache(cache);
      uiThemeNotifier.value = AppUiTheme.frosted;
      expect(cache.maximumSizeBytes, kAbsorbImageCacheMaximumBytes);
      trimDecodedImageCacheForBackground(cache);
      expect(cache.clearCalls, 1);
    });

    test('Classic uses Flutter defaults and keeps the cache in background', () {
      final cache = _RecordingImageCache();
      configureImageCache(cache);
      uiThemeNotifier.value = AppUiTheme.classic;
      expect(cache.maximumSizeBytes, kFlutterDefaultImageCacheMaximumBytes);
      expect(cache.maximumSize, kFlutterDefaultImageCacheMaximumEntries);
      expect(
        ImageCache().maximumSizeBytes,
        kFlutterDefaultImageCacheMaximumBytes,
      );
      expect(ImageCache().maximumSize, kFlutterDefaultImageCacheMaximumEntries);
      trimDecodedImageCacheForBackground(cache);
      expect(cache.clearCalls, 0);

      // Switching back re-applies the Absorb Plus limits.
      uiThemeNotifier.value = AppUiTheme.plus;
      expect(cache.maximumSizeBytes, kAbsorbImageCacheMaximumBytes);
      expect(cache.maximumSize, kAbsorbImageCacheMaximumEntries);
    });
  });
}
