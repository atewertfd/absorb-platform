import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/ui_themes/ui_theme.dart';
import 'package:absorb/ui_themes/ui_theme_hooks.dart';
import 'package:absorb/widgets/accessible_header_action.dart';
import 'package:absorb/widgets/cover_badges.dart';
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
}
