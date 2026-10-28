import 'package:absorb/main.dart' show buildAppPageTransitionsTheme;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal motion uses an animated desktop transition builder', () {
    final theme = buildAppPageTransitionsTheme(instant: false);

    expect(theme.builders[TargetPlatform.windows],
        isA<FadeUpwardsPageTransitionsBuilder>());
    expect(theme.builders[TargetPlatform.linux],
        isA<FadeUpwardsPageTransitionsBuilder>());
    expect(theme.builders[TargetPlatform.macOS],
        isA<FadeUpwardsPageTransitionsBuilder>());
    expect(theme.builders[TargetPlatform.android],
        isA<CupertinoPageTransitionsBuilder>());
  });

  test('instant motion uses the immediate builder on every platform', () {
    final theme = buildAppPageTransitionsTheme(instant: true);

    expect(theme.builders[TargetPlatform.windows], isNotNull);
    expect(theme.builders[TargetPlatform.linux], isNotNull);
    expect(theme.builders[TargetPlatform.android], isNotNull);
    expect(theme.builders[TargetPlatform.iOS], isNotNull);
    expect(theme.builders[TargetPlatform.macOS], isNotNull);
  });
}
