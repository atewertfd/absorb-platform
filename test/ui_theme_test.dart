import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/ui_themes/ui_theme.dart';
import 'package:absorb/ui_themes/ui_theme_picker.dart';
import 'package:absorb/utils/memory_policy.dart';
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

void main() {
  setUp(() {
    uiThemeNotifier.value = null;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => uiThemeNotifier.value = null);

  group('presets', () {
    test('Absorb Plus changes nothing', () {
      expect(AppUiTheme.plus.spec, const UiThemeSpec());
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

    test('ids are stable and round-trip', () {
      expect(AppUiTheme.plus.id, 'plus');
      expect(AppUiTheme.classic.id, 'classic');
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
      expect(currentUiThemeSpec, UiThemeSpec.plus);
    });
  });

  group('persistence', () {
    test('choosing a look saves it and applies it', () async {
      await UiThemeStore.choose(AppUiTheme.classic);
      expect(uiThemeNotifier.value, AppUiTheme.classic);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UiThemeStore.prefKey), 'classic');
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
    testWidgets('shows when unset and saves the picked look', (tester) async {
      final context = await _pumpHost(tester);
      final done = UiThemePicker.showIfUnchosen(context, delay: Duration.zero);
      await tester.pumpAndSettle();

      expect(find.text('Choose a look'), findsOneWidget);
      expect(find.text('Absorb Plus'), findsOneWidget);
      expect(find.text('Classic'), findsOneWidget);

      await tester.tap(find.text('Classic'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await done;

      expect(uiThemeNotifier.value, AppUiTheme.classic);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UiThemeStore.prefKey), 'classic');
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

      // Next launch: no picker.
      await UiThemePicker.showIfUnchosen(context, delay: Duration.zero);
      await tester.pumpAndSettle();
      expect(find.text('Choose a look'), findsNothing);
    });
  });

  group('settings tile', () {
    testWidgets('shows the current look and changes it', (tester) async {
      await tester.pumpWidget(
        _app(home: const Scaffold(body: UiThemeSettingsTile())),
      );
      expect(find.text('UI theme'), findsOneWidget);
      expect(find.text('Absorb Plus'), findsOneWidget);

      await tester.tap(find.byType(UiThemeSettingsTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Classic'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(uiThemeNotifier.value, AppUiTheme.classic);
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Absorb Plus'), findsNothing);
    });

    testWidgets('dismissing from settings changes nothing', (tester) async {
      await tester.pumpWidget(
        _app(home: const Scaffold(body: UiThemeSettingsTile())),
      );
      await tester.tap(find.byType(UiThemeSettingsTile));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(uiThemeNotifier.value, isNull);
      expect(await UiThemeStore.needsChoice(), isTrue);
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
