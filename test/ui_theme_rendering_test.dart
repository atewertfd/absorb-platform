import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/ui_themes/frosted.dart';
import 'package:absorb/ui_themes/ui_theme.dart';
import 'package:absorb/ui_themes/ui_theme_hooks.dart';
import 'package:absorb/widgets/accessible_header_action.dart';
import 'package:absorb/widgets/collapsible_section.dart';
import 'package:absorb/widgets/cover_badges.dart';
import 'package:absorb/widgets/theme_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  ValueNotifier<AppUiTheme?> look,
  Widget child,
) {
  return tester.pumpWidget(
    UiThemeScope(
      notifier: look,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

/// Like main.dart: the look attached as a ThemeData extension plus the
/// [absorbLookBuilder] hook. Returns a context below the navigator.
Future<BuildContext> _pumpThemedApp(
  WidgetTester tester,
  AppUiTheme theme, {
  Brightness brightness = Brightness.dark,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [theme.lookFor(brightness)],
      ),
      builder: absorbLookBuilder,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle(); // let AnimatedTheme finish its lerp
  return captured;
}

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The app's scheme for [seed] the way main.dart builds it (neutral
/// surfaces), for the contrast checks.
ColorScheme _appScheme(Color seed, Brightness b) {
  final base = ColorScheme.fromSeed(seedColor: seed, brightness: b);
  return b == Brightness.dark
      ? base.copyWith(surface: const Color(0xFF0E0E0E))
      : base.copyWith(surface: const Color(0xFFF6F6F6));
}

void main() {
  late ValueNotifier<AppUiTheme?> look;
  setUp(() => look = ValueNotifier<AppUiTheme?>(null));
  tearDown(() => look.dispose());

  testWidgets('header actions: 44x44 in Absorb Plus, drawn size in Classic', (
    tester,
  ) async {
    final action = AccessibleHeaderAction(
      label: 'Refresh',
      onPressed: () {},
      child: const SizedBox(width: 30, height: 30),
    );
    await _pump(tester, look, action);
    expect(
      tester.getSize(find.byType(AccessibleHeaderAction)),
      const Size(44, 44),
    );

    look.value = AppUiTheme.classic;
    await tester.pump();
    expect(
      tester.getSize(find.byType(AccessibleHeaderAction)),
      const Size(30, 30),
    );

    // Still labelled and tappable when compact.
    expect(find.bySemanticsLabel('Refresh'), findsOneWidget);
  });

  testWidgets('ebook badge is hidden in Classic and follows look changes', (
    tester,
  ) async {
    await _pump(tester, look, const EbookCoverBadge(readAlong: true));
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.headphones_rounded), findsOneWidget);

    look.value = AppUiTheme.classic;
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
    expect(find.byIcon(Icons.headphones_rounded), findsNothing);

    look.value = AppUiTheme.plus;
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
  });

  testWidgets('cover decode width is bounded in Absorb Plus, full in Classic', (
    tester,
  ) async {
    final seen = <int?>[];
    final probe = Builder(
      builder: (context) {
        seen
          ..add(themedCoverDecodeWidth(context, 280))
          ..add(themedCoverDecodeWidth(context, 32));
        return const SizedBox.shrink();
      },
    );
    await _pump(tester, look, probe);
    expect(seen, [280, 32]);

    seen.clear();
    look.value = AppUiTheme.classic;
    await tester.pump();
    expect(seen, [null, null]);
  });

  testWidgets('Home shelf hooks: classic height and Continue Reading shelf', (
    tester,
  ) async {
    final heights = <double?>[];
    final shelves = <bool>[];
    final badges = <bool>[];
    final probe = Builder(
      builder: (context) {
        heights.add(classicShelfCardHeight(context, false, 140, 1, false));
        shelves.add(usesClassicHomeShelves(context));
        badges.add(showsExtraCoverBadges(context));
        return const SizedBox.shrink();
      },
    );
    await _pump(tester, look, probe);
    expect(heights.last, isNull);
    expect(shelves.last, isFalse);
    expect(badges.last, isTrue);

    look.value = AppUiTheme.classic;
    await tester.pump();
    expect(heights.last, 200);
    expect(shelves.last, isTrue);
    expect(badges.last, isFalse);
  });

  test('classic cover card height matches the first Windows port formula', () {
    double h(bool rect, double width, double aspect, bool subtitle) =>
        classicCoverCardHeight(
          isRectCover: rect,
          cardWidth: width,
          coverAspectRatio: aspect,
          subtitleLine: subtitle,
        );
    expect(h(false, 140, 1, false), 200);
    expect(h(true, 140, 2 / 3, false), 260);
    expect(h(false, 168, 1, false), 228);
    expect(h(true, 168, 2 / 3, false), closeTo(302, 1e-9));
    expect(h(false, 140, 1, true), 218);
  });
  group('Frosted surfaces', () {
    tearDown(() => debugFrostIsWebOverride = null);

    testWidgets('the look is attached to ThemeData for every look', (
      tester,
    ) async {
      for (final theme in AppUiTheme.values) {
        for (final b in Brightness.values) {
          final context = await _pumpThemedApp(tester, theme, brightness: b);
          expect(
            Theme.of(context).extension<AbsorbLook>(),
            theme.lookFor(b),
            reason: '$theme $b',
          );
          expect(AbsorbLook.of(context), theme.lookFor(b));
        }
      }
    });

    test('Absorb Plus and Classic leave the theme untouched', () {
      for (final theme in [AppUiTheme.plus, AppUiTheme.classic]) {
        for (final b in Brightness.values) {
          final base = ThemeData(
            brightness: b,
            extensions: [theme.lookFor(b)],
          );
          expect(identical(frostedThemeData(base), base), isTrue);
        }
      }
      final bare = ThemeData();
      expect(identical(frostedThemeData(bare), bare), isTrue);
    });

    testWidgets('Frosted makes cards, sheets, dialogs and nav bar glassy', (
      tester,
    ) async {
      final context = await _pumpThemedApp(tester, AppUiTheme.frosted);
      final t = Theme.of(context);
      expect(t.cardTheme.color, Colors.white.withValues(alpha: 0.10));
      expect(t.cardTheme.elevation, 0);
      final card = t.cardTheme.shape! as RoundedRectangleBorder;
      expect(card.borderRadius, BorderRadius.circular(20));
      expect(card.side.color, Colors.white.withValues(alpha: 0.16));
      expect(t.bottomSheetTheme.backgroundColor!.a, closeTo(0.90, 0.01));
      expect(t.dialogTheme.backgroundColor!.a, closeTo(0.90, 0.01));
      expect(t.navigationBarTheme.backgroundColor!.a, lessThan(1));
      // Menus, popups and other scheme surfaces stay opaque.
      expect(t.colorScheme.surfaceContainer.a, 1);
      expect(t.colorScheme.surfaceContainerHigh.a, 1);
    });

    testWidgets('nav bar wrapper adds a glass edge only in Frosted, no blur', (
      tester,
    ) async {
      final look = ValueNotifier<AppUiTheme?>(null);
      addTearDown(look.dispose);
      const bar = SizedBox(height: 80, width: 400);
      await _pump(tester, look, const FrostedNavBar(child: bar));
      BoxDecoration deco() => tester
          .widget<DecoratedBox>(find
              .descendant(
                  of: find.byType(FrostedNavBar),
                  matching: find.byType(DecoratedBox))
              .first)
          .decoration as BoxDecoration;
      expect(deco().border, isNull);

      look.value = AppUiTheme.classic;
      await tester.pump();
      expect(deco().border, isNull);

      look.value = AppUiTheme.frosted;
      await tester.pump();
      expect(deco().border, isNotNull);
      // Nothing scrolls under the bar, so it is never blurred.
      expect(
          find.descendant(
              of: find.byType(FrostedNavBar),
              matching: find.byType(BackdropFilter)),
          findsNothing);
    });

    testWidgets('desktop dialog blur follows the same rules', (tester) async {
      final look = ValueNotifier<AppUiTheme?>(AppUiTheme.plus);
      addTearDown(look.dispose);
      await _pump(tester, look, const FrostedSurface(child: SizedBox()));
      BackdropFilter filter() => tester.widget(find.byType(BackdropFilter));
      expect(filter().enabled, isFalse);
      look.value = AppUiTheme.frosted;
      await tester.pump();
      expect(filter().enabled, isTrue);
    });

    testWidgets('glow, panel and radius hooks', (tester) async {
      final look = ValueNotifier<AppUiTheme?>(null);
      addTearDown(look.dispose);
      late BuildContext ctx;
      await _pump(
        tester,
        look,
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      );
      // The test app is light.
      expect(lookGlow(ctx, 0.06), 0.06);
      expect(lookPanelColor(ctx, Colors.red), Colors.red);
      expect(lookPanelElevation(ctx, 2), 2);
      expect(lookPanelSide(ctx, BorderSide.none), BorderSide.none);
      expect(lookRadius(ctx, 16), 16);
      expect(lookSheetColor(ctx, Colors.red), Colors.red);
      expect(lookPlayerCardEdge(ctx, Colors.red), Colors.red);

      look.value = AppUiTheme.frosted;
      await tester.pump();
      expect(lookGlow(ctx, 0.06), AbsorbLook.frostedLight.glowStrength);
      expect(
        lookPanelColor(ctx, Colors.red),
        Colors.white.withValues(alpha: 0.5),
      );
      expect(lookPanelElevation(ctx, 2), 0);
      expect(
        lookPanelSide(ctx, BorderSide.none).color,
        Colors.black.withValues(alpha: 0.08),
      );
      expect(lookRadius(ctx, 16), 20);
      expect(lookSheetColor(ctx, Colors.red).a, closeTo(0.9, 0.01));
      expect(lookPlayerCardEdge(ctx, Colors.red), isNot(Colors.red));
    });

    testWidgets('settings sections become glass panels in Frosted', (
      tester,
    ) async {
      final look = ValueNotifier<AppUiTheme?>(null);
      addTearDown(look.dispose);
      final section = Builder(
        builder: (context) => CollapsibleSection(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          cs: Theme.of(context).colorScheme,
          children: const [Text('row')],
        ),
      );
      await _pump(tester, look, section);
      Card card() => tester.widget(find.byType(Card));
      expect(card().color!.a, 1);

      look.value = AppUiTheme.frosted;
      await tester.pump();
      expect(card().color, Colors.white.withValues(alpha: 0.5));
      expect(card().elevation, 0);
    });

    test('text on frosted panels keeps contrast over the brightest glow', () {
      final seeds = [
        for (final p in kThemePresets) p.color,
        const Color(0xFFFFEB3B), // bright yellow cover
        const Color(0xFFFFFFFF), // white cover
        const Color(0xFF00E5FF), // neon cyan cover
      ];
      for (final b in Brightness.values) {
        final look = AppUiTheme.frosted.lookFor(b);
        for (final seed in seeds) {
          final cs = _appScheme(seed, b);
          // The preset's glow and the owner's upper bound (0.30).
          for (final glow in [look.glowStrength!, 0.30]) {
            final bg = Color.alphaBlend(
              cs.primary.withValues(alpha: glow),
              cs.surface,
            );
            final panel = Color.alphaBlend(look.panelFill()!, bg);
            expect(
              _contrast(cs.onSurface, panel),
              greaterThanOrEqualTo(4.5),
              reason: 'onSurface $b seed=$seed glow=$glow',
            );
            expect(
              _contrast(cs.onSurfaceVariant, panel),
              greaterThanOrEqualTo(3.0),
              reason: 'onSurfaceVariant $b seed=$seed glow=$glow',
            );
          }
        }
      }
    });

    test('frosted sheets stay readable over the worst backdrop', () {
      for (final b in Brightness.values) {
        final look = AppUiTheme.frosted.lookFor(b);
        final cs = _appScheme(const Color(0xFF7C6FBF), b);
        final sheetBase = b == Brightness.dark
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFF1F1F1);
        // Worst case: no barrier over a full-white (dark mode) or black
        // (light mode) cover.
        final behind = b == Brightness.dark ? Colors.white : Colors.black;
        final sheet = Color.alphaBlend(
          sheetBase.withValues(alpha: look.sheetFillAlpha!),
          behind,
        );
        expect(_contrast(cs.onSurface, sheet), greaterThanOrEqualTo(4.5));
      }
    });
  });

  testWidgets('Frosted carries color down the screen and makes cards see-through',
      (tester) async {
    final look = ValueNotifier<AppUiTheme?>(AppUiTheme.plus);
    addTearDown(look.dispose);
    late BuildContext ctx;
    await _pump(tester, look, Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }));
    const stops = [Color(0x33FF0000), Color(0xFF111111), Color(0xFF0E0E0E)];
    const card = [Color(0xFF303040), Color(0xFF202030)];

    // Absorb Plus and Classic: exactly what upstream paints.
    expect(lookBackdrop(ctx, stops), stops);
    expect(lookCardColors(ctx, card), card);
    look.value = AppUiTheme.classic;
    await tester.pump();
    expect(lookBackdrop(ctx, stops), stops);
    expect(lookCardColors(ctx, card), card);

    // Frosted: the glow stays, the solid stops pick up the accent, and cards
    // keep their tint but let the background through.
    look.value = AppUiTheme.frosted;
    await tester.pump();
    final tinted = lookBackdrop(ctx, stops);
    expect(tinted.first, stops.first);
    expect(tinted.skip(1), everyElement(isNot(anyOf(stops))));
    final glass = lookCardColors(ctx, card);
    expect(glass.every((c) => c.a < 1), isTrue);
  });
}
