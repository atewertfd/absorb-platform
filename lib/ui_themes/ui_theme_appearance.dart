import 'package:flutter/material.dart';

import '../main.dart'
    show
        applyColorSource,
        applyManualSeed,
        colorSourceNotifier,
        coverSchemeNotifier,
        flatNotifier,
        gradientIntensityNotifier,
        manualSeedNotifier;
import '../services/player_settings.dart';

/// The app color picked in the UI theme picker's color step: follow the
/// playing cover (the default), or a fixed seed. It is the same setting as
/// Settings > Appearance > Color source.
@immutable
class AppColorChoice {
  const AppColorChoice.fromCover() : seed = null;
  const AppColorChoice.fixed(Color this.seed);

  /// The fixed seed, or null to follow the cover.
  final Color? seed;

  bool get fromCover => seed == null;

  @override
  bool operator ==(Object other) =>
      other is AppColorChoice &&
      other.seed?.toARGB32() == seed?.toARGB32();

  @override
  int get hashCode => seed?.toARGB32().hashCode ?? 0;
}

/// The picker's window onto the app's existing appearance settings, so the
/// picker stays testable and owns no settings of its own.
abstract class UiThemeAppearance {
  /// The color setting in effect now.
  AppColorChoice get currentColor;

  /// The seed used for previews of "From cover".
  Color get coverSeed;

  /// The user's gradient intensity (used by looks without their own glow).
  double get userGlow;

  /// Whether Flat background is on (no glow in any look).
  bool get flat;

  /// Saves [choice] exactly as the Settings color controls do and applies it.
  Future<void> saveColor(AppColorChoice choice);
}

/// The real settings: [PlayerSettings] storage plus main.dart's appliers.
class AppUiThemeAppearance implements UiThemeAppearance {
  const AppUiThemeAppearance();

  static const Color _defaultSeed = Color(0xFF7C6FBF);

  @override
  AppColorChoice get currentColor => colorSourceNotifier.value == 'manual'
      ? AppColorChoice.fixed(manualSeedNotifier.value)
      : const AppColorChoice.fromCover();

  @override
  Color get coverSeed => coverSchemeNotifier.value?.primary ?? _defaultSeed;

  @override
  double get userGlow => gradientIntensityNotifier.value;

  @override
  bool get flat => flatNotifier.value;

  @override
  Future<void> saveColor(AppColorChoice choice) async {
    final seed = choice.seed;
    if (seed == null) {
      await PlayerSettings.setColorSource('dynamic');
      applyColorSource('dynamic');
    } else {
      final argb = seed.toARGB32();
      await PlayerSettings.setManualSeedColor(argb);
      applyManualSeed(argb);
      await PlayerSettings.setColorSource('manual');
      applyColorSource('manual');
    }
  }
}

/// [base] (the app's scheme, with its neutral surfaces) with the accent
/// colors of [seed], for previews.
ColorScheme previewScheme(ColorScheme base, Color seed) {
  final seeded = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: base.brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  );
  return base.copyWith(
    primary: seeded.primary,
    onPrimary: seeded.onPrimary,
    primaryContainer: seeded.primaryContainer,
    secondary: seeded.secondary,
    tertiary: seeded.tertiary,
  );
}
