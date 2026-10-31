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

/// Every Frosted preset: each brightness at each glass strength.
final _frostedVariants = [
  for (final b in Brightness.values)
    for (final glass in GlassStrength.values) (b, glass),
];

void main() {
  late ValueNotifier<AppUiTheme?> look;
  setUp(() {
    look = ValueNotifier<AppUiTheme?>(null);
    lookDetailsNotifier.value = LookDetails.standard;
  });
  tearDown(() {
    look.dispose();
    lookDetailsNotifier.value = LookDetails.standard;
  });

  testWidgets('header actions: 44x44 by default, drawn size with compact '
      'header buttons in every look', (tester) async {
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

    lookDetailsNotifier.value = const LookDetails(compactHeaderButtons: true);
    for (final theme in AppUiTheme.values) {
      look.value = theme;
      await tester.pump();
      expect(
        tester.getSize(find.byType(AccessibleHeaderAction)),
        const Size(30, 30),
        reason: '$theme',
      );
    }

    // Still labelled and tappable when compact.
    expect(find.bySemanticsLabel('Refresh'), findsOneWidget);
  });

  testWidgets('ebook badge follows the extra badges setting in every look', (
    tester,
  ) async {
    await _pump(tester, look, const EbookCoverBadge(readAlong: true));
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.headphones_rounded), findsOneWidget);

    lookDetailsNotifier.value = const LookDetails(extraCoverBadges: false);
    for (final theme in AppUiTheme.values) {
      look.value = theme;
      await tester.pump();
      expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
      expect(find.byIcon(Icons.headphones_rounded), findsNothing);
    }

    lookDetailsNotifier.value = LookDetails.standard;
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
  });

  testWidgets('cover decode width is bounded by default, full with '
      'full-quality covers', (tester) async {
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
    lookDetailsNotifier.value = const LookDetails(fullQualityCovers: true);
    await tester.pump();
    expect(seen, [null, null]);

    seen.clear();
    look.value = AppUiTheme.midnight;
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

    lookDetailsNotifier.value = LookDetails.classic;
    for (final theme in AppUiTheme.values) {
      look.value = theme;
      await tester.pump();
      expect(heights.last, 200, reason: '$theme');
      expect(shelves.last, isTrue);
      expect(badges.last, isFalse);
    }

    // Each switch on its own.
    lookDetailsNotifier.value = const LookDetails(continueReadingShelf: true);
    await tester.pump();
    expect(shelves.last, isTrue);
    expect(badges.last, isTrue);
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

    test('Standard leaves the theme untouched, with any look details', () {
      for (final details in [LookDetails.standard, LookDetails.classic]) {
        for (final b in Brightness.values) {
          final base = ThemeData(
            brightness: b,
            extensions: [AppUiTheme.plus.lookFor(b, details: details)],
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
      expect(
        t.searchBarTheme.backgroundColor!.resolve({}),
        Colors.white.withValues(alpha: 0.10),
      );
      // Menus, popups and other scheme surfaces stay opaque.
      expect(t.colorScheme.surfaceContainer.a, 1);
      expect(t.colorScheme.surfaceContainerHigh.a, 1);
    });

    testWidgets('Midnight: true black canvas, outlined cards, near-black '
        'sheets with a hairline, black nav bar', (tester) async {
      final context = await _pumpThemedApp(tester, AppUiTheme.midnight);
      final t = Theme.of(context);
      const black = Color(0xFF000000);
      final edge = Colors.white.withValues(
        alpha: AbsorbLook.midnightDark.panelBorderAlpha,
      );
      expect(t.scaffoldBackgroundColor, black);
      expect(t.canvasColor, black);
      expect(t.colorScheme.surface, black);
      expect(t.appBarTheme.backgroundColor, black);
      expect(t.navigationBarTheme.backgroundColor, black);
      // Cards: no grey fill, a 1 px outline at the usual radius.
      expect(t.cardTheme.color, Colors.transparent);
      expect(t.cardTheme.elevation, 0);
      final card = t.cardTheme.shape! as RoundedRectangleBorder;
      expect(card.borderRadius, BorderRadius.circular(16));
      expect(card.side.color, edge);
      expect(card.side.width, 1);
      expect(t.searchBarTheme.side!.resolve({})!.color, edge);
      // Sheets and dialogs: opaque near-black with the hairline.
      expect(t.bottomSheetTheme.backgroundColor, const Color(0xFF0A0A0A));
      expect(t.bottomSheetTheme.modalBackgroundColor, const Color(0xFF0A0A0A));
      expect(
        (t.bottomSheetTheme.shape! as RoundedRectangleBorder).side.color,
        edge,
      );
      expect(t.dialogTheme.backgroundColor, const Color(0xFF0A0A0A));
      expect((t.dialogTheme.shape! as RoundedRectangleBorder).side.color, edge);
      // The accent and the other scheme surfaces stay as they were.
      final base = ThemeData(brightness: Brightness.dark).colorScheme;
      expect(t.colorScheme.primary, base.primary);
      expect(t.colorScheme.surfaceContainerHigh, base.surfaceContainerHigh);
    });

    testWidgets('Midnight in light mode: paper white, outlined panels', (
      tester,
    ) async {
      final context = await _pumpThemedApp(
        tester,
        AppUiTheme.midnight,
        brightness: Brightness.light,
      );
      final t = Theme.of(context);
      const white = Color(0xFFFFFFFF);
      expect(t.scaffoldBackgroundColor, white);
      expect(t.colorScheme.surface, white);
      expect(t.navigationBarTheme.backgroundColor, white);
      expect(t.bottomSheetTheme.backgroundColor, white);
      expect(t.dialogTheme.backgroundColor, white);
      expect(t.cardTheme.color, Colors.transparent);
      expect(
        (t.cardTheme.shape! as RoundedRectangleBorder).side.color,
        Colors.black.withValues(
          alpha: AbsorbLook.midnightLight.panelBorderAlpha,
        ),
      );
    });

    testWidgets('e-ink overrides Midnight like every look', (tester) async {
      final base = ThemeData(
        extensions: [AppUiTheme.midnight.lookFor(Brightness.dark, eink: true)],
      );
      expect(identical(frostedThemeData(base), base), isTrue);
    });

    test('text keeps contrast on Midnight\'s canvas and sheets', () {
      final seeds = [
        for (final p in kThemePresets) p.color,
        const Color(0xFFFFEB3B), // bright yellow cover
        const Color(0xFFFFFFFF), // white cover
        const Color(0xFF00E5FF), // neon cyan cover
        const Color(0xFF1A237E), // deep navy cover
      ];
      for (final b in Brightness.values) {
        final look = AppUiTheme.midnight.lookFor(b);
        for (final seed in seeds) {
          final cs = _appScheme(seed, b);
          for (final (what, bg) in [
            ('canvas', look.canvasColor!),
            ('sheet', look.sheetColor!),
          ]) {
            final reason = '$b seed=$seed $what';
            expect(
              _contrast(cs.onSurface, bg),
              greaterThanOrEqualTo(7.0),
              reason: 'onSurface $reason',
            );
            expect(
              _contrast(cs.onSurfaceVariant, bg),
              greaterThanOrEqualTo(4.5),
              reason: 'onSurfaceVariant $reason',
            );
            // Accent text, icons and progress on the background.
            expect(
              _contrast(cs.primary, bg),
              greaterThanOrEqualTo(3.0),
              reason: 'primary $reason',
            );
          }
          // The hairline is visible against the canvas.
          final edge = Color.alphaBlend(look.panelEdge(b), look.canvasColor!);
          expect(edge, isNot(look.canvasColor));
        }
      }
    });

    testWidgets('nav bar wrapper adds a glass edge only in Frosted, no blur', (
      tester,
    ) async {
      final look = ValueNotifier<AppUiTheme?>(null);
      addTearDown(look.dispose);
      const bar = SizedBox(height: 80, width: 400);
      await _pump(tester, look, const FrostedNavBar(child: bar));
      BoxDecoration deco() =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(FrostedNavBar),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(deco().border, isNull);

      // Midnight: the hairline top edge, no blur either.
      look.value = AppUiTheme.midnight;
      await tester.pump();
      expect(
        (deco().border! as Border).top.color,
        Colors.black.withValues(
          alpha: AbsorbLook.midnightLight.panelBorderAlpha,
        ),
      );

      look.value = AppUiTheme.frosted;
      await tester.pump();
      expect(deco().border, isNotNull);
      // Nothing scrolls under the bar, so it is never blurred.
      expect(
        find.descendant(
          of: find.byType(FrostedNavBar),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
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

      // Midnight: no glow, outlines instead of fills, the usual radius.
      look.value = AppUiTheme.midnight;
      await tester.pump();
      expect(lookGlow(ctx, 0.06), 0);
      expect(lookPanelColor(ctx, Colors.red), Colors.transparent);
      expect(lookPanelElevation(ctx, 2), 0);
      expect(
        lookPanelSide(ctx, BorderSide.none).color,
        Colors.black.withValues(alpha: 0.12),
      );
      expect(lookRadius(ctx, 16), 16);
      expect(lookSheetColor(ctx, Colors.red), const Color(0xFFFFFFFF));
      expect(lookPlayerCardEdge(ctx, Colors.red), Colors.red);
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

      // Midnight: an outline, not a grey panel.
      look.value = AppUiTheme.midnight;
      await tester.pump();
      expect(card().color, Colors.transparent);
      expect(card().elevation, 0);
      final shape = card().shape! as RoundedRectangleBorder;
      expect(shape.side.color, Colors.black.withValues(alpha: 0.12));
      expect(shape.borderRadius, BorderRadius.circular(16));
    });

    test('text on frosted panels keeps contrast over the brightest glow', () {
      final seeds = [
        for (final p in kThemePresets) p.color,
        const Color(0xFFFFEB3B), // bright yellow cover
        const Color(0xFFFFFFFF), // white cover
        const Color(0xFF00E5FF), // neon cyan cover
      ];
      for (final (b, glass) in _frostedVariants) {
        final look = AppUiTheme.frosted.lookFor(b, glass: glass);
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
              reason: 'onSurface $b $glass seed=$seed glow=$glow',
            );
            expect(
              _contrast(cs.onSurfaceVariant, panel),
              greaterThanOrEqualTo(3.0),
              reason: 'onSurfaceVariant $b $glass seed=$seed glow=$glow',
            );
          }
        }
      }
    });

    test('frosted sheets stay readable over the worst backdrop', () {
      for (final (b, glass) in _frostedVariants) {
        final look = AppUiTheme.frosted.lookFor(b, glass: glass);
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
        expect(
          _contrast(cs.onSurface, sheet),
          greaterThanOrEqualTo(4.5),
          reason: '$b $glass',
        );
      }
    });
  });

  testWidgets(
    'Frosted carries color down the screen and makes cards see-through',
    (tester) async {
      final look = ValueNotifier<AppUiTheme?>(AppUiTheme.plus);
      addTearDown(look.dispose);
      late BuildContext ctx;
      await _pump(
        tester,
        look,
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      const stops = [Color(0x33FF0000), Color(0xFF111111), Color(0xFF0E0E0E)];
      const card = [Color(0xFF303040), Color(0xFF202030)];

      // Standard: exactly what upstream paints.
      expect(lookBackdrop(ctx, stops), stops);
      expect(lookCardColors(ctx, card), card);

      // Midnight: not even a faint glow; the solid stops stay.
      look.value = AppUiTheme.midnight;
      await tester.pump();
      expect(lookBackdrop(ctx, stops), [stops[1], stops[1], stops[2]]);
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
    },
  );
}
