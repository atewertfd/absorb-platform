import 'package:absorb/main.dart';
import 'package:absorb/services/wording.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// applyAppearanceFromPrefs is what an account switch, a sign-in and a
/// settings-sync pull use to put the stored look on screen, so it must cover
/// every per-account appearance setting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    snappyTransitionsNotifier.value = false;
    classicWordingNotifier.value = false;
    applyEinkModeTheme(false);
    themeNotifier.value = ThemeMode.dark;
  });

  test('applies theme, e-ink, snappy and wording from storage', () async {
    SharedPreferences.setMockInitialValues({
      'themeMode': 'light',
      'einkMode': true,
      'snappyTransitions': true,
      'classicWording': true,
    });
    snappyTransitionsNotifier.value = false;
    classicWordingNotifier.value = false;

    await applyAppearanceFromPrefs();

    expect(themeNotifier.value, ThemeMode.light);
    expect(einkModeNotifier.value, isTrue);
    expect(snappyTransitionsNotifier.value, isTrue);
    expect(classicWordingNotifier.value, isTrue);
  });

  test('turns snappy and wording back off for an account without them',
      () async {
    SharedPreferences.setMockInitialValues({});
    snappyTransitionsNotifier.value = true;
    classicWordingNotifier.value = true;

    await applyAppearanceFromPrefs();

    expect(snappyTransitionsNotifier.value, isFalse);
    expect(classicWordingNotifier.value, isFalse);
  });
}
