import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:absorb/main.dart' show buildAppPageTransitionsTheme;

void main() {
  test('normal motion matches upstream: Cupertino on mobile, '
      "Flutter's default on desktop", () {
    final theme = buildAppPageTransitionsTheme(instant: false);

    expect(theme.builders[TargetPlatform.android],
        isA<CupertinoPageTransitionsBuilder>());
    expect(theme.builders[TargetPlatform.iOS],
        isA<CupertinoPageTransitionsBuilder>());
    // No override, so desktop keeps Flutter's own animated transition.
    expect(theme.builders[TargetPlatform.windows], isNull);
    expect(theme.builders[TargetPlatform.linux], isNull);
  });

  test('instant motion uses the immediate builder on every platform', () {
    final theme = buildAppPageTransitionsTheme(instant: true);

    expect(theme.builders[TargetPlatform.windows], isNotNull);
    expect(theme.builders[TargetPlatform.linux], isNotNull);
    expect(theme.builders[TargetPlatform.android], isNotNull);
    expect(theme.builders[TargetPlatform.iOS], isNotNull);
    expect(theme.builders[TargetPlatform.macOS], isNotNull);
    expect(theme.builders[TargetPlatform.windows]!.transitionDuration,
        Duration.zero);
    expect(theme.builders[TargetPlatform.windows]!.reverseTransitionDuration,
        Duration.zero);
  });
}
