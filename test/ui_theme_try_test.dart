import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/main.dart' show colorSourceNotifier, manualSeedNotifier;
import 'package:absorb/providers/library_provider.dart';
import 'package:absorb/ui_themes/frosted.dart';
import 'package:absorb/ui_themes/ui_theme.dart';
import 'package:absorb/ui_themes/ui_theme_picker.dart';
import 'package:absorb/ui_themes/ui_theme_preview.dart';
import 'package:absorb/ui_themes/ui_theme_try.dart';
import 'package:absorb/widgets/absorbing_shared.dart';
import 'package:absorb/widgets/collapsible_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app the way main.dart wires it: the look as a ThemeData extension
/// (rebuilt on saved and previewed looks), [absorbLookBuilder], and a home
/// with a real bottom nav bar. [onHome] receives a context inside the app.
class _App extends StatelessWidget {
  const _App({required this.onHome, this.onNavTap, this.library});

  final ValueChanged<BuildContext> onHome;
  final ValueChanged<int>? onNavTap;
  final LibraryProvider? library;

  @override
  Widget build(BuildContext context) {
    final app = UiThemeScope(
      child: ListenableBuilder(
        listenable: Listenable.merge([uiThemeNotifier, uiThemePreviewNotifier]),
        builder: (context, _) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [absorbLookFor(Brightness.light)]),
          builder: absorbLookBuilder,
          home: Builder(
            builder: (context) {
              onHome(context);
              return Scaffold(
                body: const SizedBox.expand(),
                bottomNavigationBar: FrostedNavBar(
                  child: NavigationBar(
                    key: const ValueKey('app-nav'),
                    selectedIndex: 0,
                    onDestinationSelected: onNavTap,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        label: 'Settings',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final lib = library;
    return lib == null
        ? app
        : ChangeNotifierProvider<LibraryProvider>.value(value: lib, child: app);
  }
}

Future<BuildContext> _pumpApp(
  WidgetTester tester, {
  ValueChanged<int>? onNavTap,
  LibraryProvider? library,
}) async {
  late BuildContext home;
  await tester.pumpWidget(
    _App(onHome: (c) => home = c, onNavTap: onNavTap, library: library),
  );
  await tester.pumpAndSettle();
  return home;
}

/// The look a widget inside the app's pages sees right now.
AbsorbLook _lookIn(WidgetTester tester) =>
    AbsorbLook.of(tester.element(find.byType(Scaffold).first));

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

/// Opens the picker, highlights [look] and taps "Try it".
Future<Future<UiThemePickerResult?>> _tryLook(
  WidgetTester tester,
  BuildContext home,
  String look,
) async {
  final result = UiThemePicker.show(home);
  await tester.pumpAndSettle();
  await tester.tap(find.text(look));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('ui-try-it')));
  await tester.pumpAndSettle();
  return result;
}

void _setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    uiThemeNotifier.value = null;
    uiThemePreviewNotifier.value = null;
    colorSourceNotifier.value = 'dynamic';
    manualSeedNotifier.value = const Color(0xFF7C6FBF);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    UiThemeTryOut.end(UiThemeTryOutOutcome.ended);
    uiThemeNotifier.value = null;
  });

  group('Try it live', () {
    testWidgets('applies the look app-wide without saving it', (tester) async {
      final home = await _pumpApp(tester);
      expect(_lookIn(tester), AbsorbLook.plus);

      await _tryLook(tester, home, 'Frosted');

      expect(find.text('Choose a look'), findsNothing, reason: 'picker closes');
      expect(uiThemePreviewNotifier.value, AppUiTheme.frosted);
      expect(currentUiTheme, AppUiTheme.frosted);
      expect(_lookIn(tester), AbsorbLook.frostedLight);
      // The real app's surfaces follow: the nav bar wrapper draws its edge.
      final navTheme = NavigationBarTheme.of(
        tester.element(find.byKey(const ValueKey('app-nav'))),
      );
      expect(navTheme.backgroundColor!.a, lessThan(1));
      // Nothing saved.
      expect(uiThemeNotifier.value, isNull);
      expect((await _prefs()).getString(UiThemeStore.prefKey), isNull);
      expect(find.text('Previewing Frosted'), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);
    });

    testWidgets('Keep saves the look through the store', (tester) async {
      final home = await _pumpApp(tester);
      final result = await _tryLook(tester, home, 'Classic');

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(uiThemeNotifier.value, AppUiTheme.classic);
      expect((await _prefs()).getString(UiThemeStore.prefKey), 'classic');
      expect(uiThemePreviewNotifier.value, isNull);
      expect(find.byKey(const ValueKey('ui-try-bar')), findsNothing);
      expect(_lookIn(tester), AbsorbLook.classic);
      final picked = await result;
      expect(picked?.theme, AppUiTheme.classic);
      expect(picked?.tryLive, isFalse);
      // Color untouched.
      expect(colorSourceNotifier.value, 'dynamic');
    });

    testWidgets('Go back restores the saved look and reopens the picker', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({UiThemeStore.prefKey: 'classic'});
      await UiThemeStore.load();
      final home = await _pumpApp(tester);
      final result = await _tryLook(tester, home, 'Frosted');
      expect(_lookIn(tester), AbsorbLook.frostedLight);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();

      expect(uiThemePreviewNotifier.value, isNull);
      expect(uiThemeNotifier.value, AppUiTheme.classic);
      expect(_lookIn(tester), AbsorbLook.classic);
      expect((await _prefs()).getString(UiThemeStore.prefKey), 'classic');
      expect(find.byKey(const ValueKey('ui-try-bar')), findsNothing);
      // Back in the picker, on the look that was tried.
      expect(find.text('Choose a look'), findsOneWidget);
      expect(find.textContaining('frosted-glass'), findsOneWidget);

      await tester.tapAt(const Offset(5, 5)); // dismiss
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(uiThemeNotifier.value, AppUiTheme.classic);
    });

    testWidgets('settings flow: Keep reports the change', (tester) async {
      var changed = 0;
      final home = await _pumpApp(tester);
      final done = UiThemePicker.changeFromSettings(
        home,
        onChanged: () => changed++,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frosted'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ui-try-it')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await done;
      expect(uiThemeNotifier.value, AppUiTheme.frosted);
      expect(changed, 1);
    });

    test('a preview is never persisted', () async {
      await UiThemeStore.choose(AppUiTheme.classic);
      final ended = UiThemeTryOut.start(AppUiTheme.frosted);
      expect(currentUiTheme, AppUiTheme.frosted);
      expect(savedUiTheme, AppUiTheme.classic);
      // Image cache policy follows saved choices only.
      expect(currentAbsorbLook, AbsorbLook.classic);
      expect((await _prefs()).getString(UiThemeStore.prefKey), 'classic');

      // A restart: memory is gone, the store gives the saved look back.
      uiThemePreviewNotifier.value = null;
      uiThemeNotifier.value = null;
      expect(await UiThemeStore.load(), AppUiTheme.classic);
      expect(currentUiTheme, AppUiTheme.classic);
      expect(await ended, UiThemeTryOutOutcome.ended);
    });

    test('saving any look ends a preview', () async {
      final ended = UiThemeTryOut.start(AppUiTheme.frosted);
      await UiThemeStore.choose(AppUiTheme.plus);
      expect(uiThemePreviewNotifier.value, isNull);
      expect(currentUiTheme, AppUiTheme.plus);
      expect(await ended, UiThemeTryOutOutcome.ended);
    });

    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      testWidgets(
        'bar sits above the nav bar and leaves it tappable at $size',
        (tester) async {
          _setWindow(tester, size);
          final taps = <int>[];
          final home = await _pumpApp(tester, onNavTap: taps.add);
          await _tryLook(tester, home, 'Frosted');

          final bar = tester.getRect(find.byKey(const ValueKey('ui-try-bar')));
          final nav = tester.getRect(find.byKey(const ValueKey('app-nav')));
          expect(bar.bottom, lessThanOrEqualTo(nav.top));
          expect(bar.width, lessThanOrEqualTo(460));
          expect(tester.takeException(), isNull);

          // The real app stays usable underneath.
          await tester.tap(find.text('Settings'));
          await tester.pump();
          expect(taps, [1]);
          expect(uiThemePreviewNotifier.value, AppUiTheme.frosted);
        },
      );
    }

    testWidgets('bar stays readable in every look', (tester) async {
      final home = await _pumpApp(tester);
      for (final look in ['Absorb Plus', 'Classic', 'Frosted']) {
        await _tryLook(tester, home, look);
        final bar = tester.widget<Material>(
          find.byKey(const ValueKey('ui-try-bar')),
        );
        expect(bar.color!.a, 1, reason: '$look: opaque bar');
        final text = tester.widget<Text>(find.text('Previewing $look'));
        final ratio = _contrast(text.style!.color!, bar.color!);
        expect(ratio, greaterThan(4.5), reason: '$look: text contrast');
        await tester.tap(find.text('Go back'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5)); // close the reopened picker
        await tester.pumpAndSettle();
      }
    });
  });

  group('real previews', () {
    Finder inCard(AppUiTheme theme, Finder matching) => find.descendant(
      of: find.byKey(ValueKey('ui-look-${theme.id}')),
      matching: matching,
    );

    testWidgets('each card renders the app widgets in its own look', (
      tester,
    ) async {
      final home = await _pumpApp(tester);
      UiThemePicker.show(home);
      await tester.pumpAndSettle();

      for (final theme in AppUiTheme.values) {
        expect(inCard(theme, find.byType(UiThemePreview)), findsOneWidget);
        expect(inCard(theme, find.byType(FrostedNavBar)), findsOneWidget);
        expect(inCard(theme, find.byType(NavigationBar)), findsOneWidget);
        expect(
          inCard(theme, find.byType(CollapsibleSection)),
          findsNWidgets(2),
        );
        final look = AbsorbLook.of(
          tester.element(inCard(theme, find.byType(NavigationBar))),
        );
        expect(look, theme.lookFor(Brightness.light));
      }

      Color panel(AppUiTheme theme) => tester
          .widget<Card>(
            find.descendant(
              of: inCard(theme, find.byType(CollapsibleSection)).first,
              matching: find.byType(Card),
            ),
          )
          .color!;
      expect(panel(AppUiTheme.frosted), isNot(panel(AppUiTheme.plus)));
      expect(panel(AppUiTheme.frosted).a, lessThan(1));
      expect(panel(AppUiTheme.plus).a, 1);

      Color? navBg(AppUiTheme theme) => NavigationBarTheme.of(
        tester.element(inCard(theme, find.byType(NavigationBar))),
      ).backgroundColor;
      expect(navBg(AppUiTheme.frosted)!.a, lessThan(1));
      expect(navBg(AppUiTheme.plus), isNot(navBg(AppUiTheme.frosted)));
    });

    testWidgets('a Plus card stays Plus while the app is Frosted', (
      tester,
    ) async {
      await UiThemeStore.choose(AppUiTheme.frosted);
      final home = await _pumpApp(tester);
      UiThemePicker.show(home);
      await tester.pumpAndSettle();
      final plusNav = tester.element(
        inCard(AppUiTheme.plus, find.byType(NavigationBar)),
      );
      expect(AbsorbLook.of(plusNav), AbsorbLook.plus);
      expect(NavigationBarTheme.of(plusNav).backgroundColor?.a ?? 1, 1);
    });

    testWidgets('previews follow the window shape', (tester) async {
      Future<Size> frameIn(Size window) async {
        _setWindow(tester, window);
        final home = await _pumpApp(tester);
        UiThemePicker.show(home);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final size = tester.getSize(
          inCard(
            AppUiTheme.plus,
            find.byKey(const ValueKey('ui-preview-frame')),
          ),
        );
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        return size;
      }

      final wide = await frameIn(const Size(1280, 720));
      expect(wide.width / wide.height, closeTo(1280 / 720, 0.02));
      final tall = await frameIn(const Size(390, 844));
      expect(tall.width / tall.height, closeTo(390 / 844, 0.02));
    });

    test('virtual size keeps the window shape within limits', () {
      expect(
        UiThemePreview.virtualSizeFor(const Size(1920, 1080)),
        const Size(1920, 1080),
      );
      expect(
        UiThemePreview.virtualSizeFor(const Size(390, 844)),
        const Size(390, 844),
      );
      final ultraWide = UiThemePreview.virtualSizeFor(const Size(3000, 400));
      expect(ultraWide.aspectRatio, closeTo(21 / 9, 0.001));
      expect(UiThemePreview.virtualSizeFor(Size.zero), const Size(390, 844));
    });

    testWidgets('works with an empty library', (tester) async {
      final lib = LibraryProvider();
      addTearDown(lib.dispose);
      final home = await _pumpApp(tester, library: lib);
      UiThemePicker.show(home);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(UiThemePreview), findsNWidgets(3));
      expect(
        inCard(AppUiTheme.plus, find.byType(CoverPlaceholder)),
        findsWidgets,
      );
    });

    testWidgets('shows the given books, placeholders after them', (
      tester,
    ) async {
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
                covers: const [
                  UiThemePreviewCover(title: 'Dune', author: 'Frank Herbert'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Dune'), findsOneWidget);
      // 390 wide: two 120 px slots per shelf, two shelves; the slots past
      // the user's one book are placeholders.
      expect(find.byType(CoverPlaceholder), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    test('books come from Home shelves, Continue Listening first', () {
      Map<String, dynamic> book(String id, String title) => {
        'id': id,
        'media': {
          'metadata': {'title': title, 'authorName': 'A'},
        },
      };
      final books = previewBooks([
        {
          'id': 'recently-added',
          'entities': [book('b2', 'Two'), book('b1', 'One')],
        },
        {
          'id': 'continue-series',
          'entities': [
            {'id': 's1', 'name': 'A series'}, // not a book
          ],
        },
        {
          'id': 'continue-listening',
          'entities': [book('b1', 'One'), book('b3', 'Three')],
        },
      ], max: 3);
      expect([for (final b in books) b.id], ['b1', 'b3', 'b2']);
      expect(books.first.title, 'One');
      expect(previewBooks(const []), isEmpty);
    });
  });
}

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
