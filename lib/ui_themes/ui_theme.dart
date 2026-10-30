import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Absorb Plus "UI themes": whole-app looks the user picks once on first
/// launch and can change in Settings > Appearance > UI theme.
///
/// This is separate from the light/dark/OLED "Theme" setting and from the
/// color source. A UI theme only changes graphics (cover quality, badges,
/// shelf sizes, header buttons, surface style); motion and animation timing
/// are never part of it.
///
/// Themes are values: each look is an [AbsorbLook] preset, attached to the
/// app's [ThemeData] as a [ThemeExtension] (see `absorbLookFor` in main.dart's
/// ThemeData and `frosted.dart`). Widgets read it with [AbsorbLook.of].
///
/// Adding a look: add an enum value with a stable id, give it an
/// [AbsorbLook] preset in [AppUiTheme.lookFor], and add its name and
/// description strings in `ui_theme_picker.dart` (the switches there are
/// exhaustive, so the analyzer points at every place that needs it).
enum AppUiTheme {
  /// Today's Absorb Plus look. Its preset changes nothing.
  plus('plus'),

  /// The look of the first Windows port (windows-experimental-0.1.0).
  classic('classic'),

  /// Absorb Plus with lightly frosted, translucent surfaces over a stronger
  /// cover-colored glow.
  frosted('frosted');

  const AppUiTheme(this.id);

  /// Stable id stored in preferences. Never rename an existing id.
  final String id;

  /// The theme stored under [id], or null for a missing or unknown id.
  static AppUiTheme? fromId(String? id) {
    if (id == null) return null;
    for (final theme in values) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  /// The look's dark-mode preset (the app's default mode).
  AbsorbLook get spec => lookFor(Brightness.dark);

  /// The look's preset for [brightness]. E-ink always gets neutral surfaces
  /// (translucency and glow dither into noise there), but keeps the look's
  /// behavior flags.
  AbsorbLook lookFor(Brightness brightness, {bool eink = false}) {
    final look = switch (this) {
      AppUiTheme.plus => AbsorbLook.plus,
      AppUiTheme.classic => AbsorbLook.classic,
      AppUiTheme.frosted => brightness == Brightness.dark
          ? AbsorbLook.frostedDark
          : AbsorbLook.frostedLight,
    };
    return eink ? look.withNeutralSurfaces() : look;
  }
}

/// What a UI theme changes, as a [ThemeExtension] on the app's [ThemeData].
///
/// Every field's default is today's Absorb Plus behavior, so
/// [AbsorbLook.plus] is simply the default constructor. The visual tokens
/// (glow, panels, sheets, radius) are "neutral" by default: null alphas and
/// false flags mean "paint exactly what upstream paints".
@immutable
class AbsorbLook extends ThemeExtension<AbsorbLook> {
  const AbsorbLook({
    this.fullQualityCovers = false,
    this.defaultImageCache = false,
    this.showExtraCoverBadges = true,
    this.classicHomeShelves = false,
    this.compactHeaderActions = false,
    this.glowStrength,
    this.backdropTint = 0,
    this.panelFillAlpha,
    this.panelBorderAlpha = 0,
    this.panelBlurSigma = 0,
    this.cornerRadiusBoost = 0,
    this.sheetFillAlpha,
    this.frostedNavBar = false,
    this.frostedSheets = false,
    this.frostedPlayerCard = false,
  });

  // ── Behavior flags ──

  /// Book card covers decode at the source resolution instead of at display
  /// size, and the blurred letterbox behind square covers is not built from a
  /// 32 px thumbnail.
  final bool fullQualityCovers;

  /// Flutter's default decoded-image cache size, kept when the app goes to
  /// the background, instead of Absorb Plus's smaller, trimmed cache.
  final bool defaultImageCache;

  /// The ebook badge on covers and the "saved" strip on Continue Listening
  /// cards. When false they are hidden, whatever the badge setting says.
  final bool showExtraCoverBadges;

  /// Home shelves use the original fixed card height, and Continue Reading
  /// is a normal shelf instead of the big-card row.
  final bool classicHomeShelves;

  /// Header actions (Absorbing page) keep their drawn size instead of
  /// growing to a 44x44 tap area.
  final bool compactHeaderActions;

  // ── Visual tokens ──

  /// Top alpha of the cover-colored background glow. Null follows the user's
  /// gradient intensity setting. "Flat background" always wins: the screens
  /// skip the glow entirely when it is on.
  final double? glowStrength;

  /// How much of the accent color tints the rest of a screen's background
  /// below the glow (0 = upstream's solid surfaces). Frosted needs color
  /// behind its translucent panels, or the glass shows plain dark.
  final double backdropTint;

  /// Alpha of the white glass fill on cards and panels. Null keeps the
  /// opaque upstream fills (the panels are not frosted).
  final double? panelFillAlpha;

  /// Alpha of the panels' 1 px edge: a light edge in dark mode, a faint dark
  /// one in light mode (a white line vanishes on white).
  final double panelBorderAlpha;

  /// Blur radius behind the few large frosted surfaces (nav bar, desktop
  /// dialogs). Never applied per list item.
  final double panelBlurSigma;

  /// Added to the corner radius of themed cards, sheets and dialogs.
  final double cornerRadiusBoost;

  /// Alpha of sheet, dialog and nav bar backgrounds. Kept high so text stays
  /// readable even where no blur sits behind it. Null keeps them opaque.
  final double? sheetFillAlpha;

  /// The bottom nav bar is translucent with a blur behind it and a top edge.
  final bool frostedNavBar;

  /// Bottom sheets and dialogs are translucent (desktop dialogs also blur).
  final bool frostedSheets;

  /// The Absorbing (player) card gets the light glass edge. Its background is
  /// already a pre-blurred cover, so no extra blur is added.
  final bool frostedPlayerCard;

  /// Whether cards and panels are frosted glass.
  bool get frostedPanels => panelFillAlpha != null;

  /// Whether any surface differs from the upstream look.
  bool get changesSurfaces =>
      frostedPanels || frostedNavBar || frostedSheets || frostedPlayerCard;

  static const AbsorbLook plus = AbsorbLook();

  static const AbsorbLook classic = AbsorbLook(
    fullQualityCovers: true,
    defaultImageCache: true,
    showExtraCoverBadges: false,
    classicHomeShelves: true,
    compactHeaderActions: true,
  );

  /// Frosted in dark mode: the owner-approved demo's values (white 7% glass,
  /// 12% light edge, blur 18, radius +4) over a ~0.24 glow.
  static const AbsorbLook frostedDark = AbsorbLook(
    glowStrength: 0.30,
    backdropTint: 0.16,
    panelFillAlpha: 0.10,
    panelBorderAlpha: 0.16,
    panelBlurSigma: 18,
    cornerRadiusBoost: 4,
    sheetFillAlpha: 0.90,
    frostedNavBar: true,
    frostedSheets: true,
    frostedPlayerCard: true,
  );

  /// Frosted in light mode: milky glass (white 50%) with a faint dark edge,
  /// and a softer glow since the light accent tone is darker.
  static const AbsorbLook frostedLight = AbsorbLook(
    glowStrength: 0.22,
    backdropTint: 0.10,
    panelFillAlpha: 0.50,
    panelBorderAlpha: 0.08,
    panelBlurSigma: 18,
    cornerRadiusBoost: 4,
    sheetFillAlpha: 0.90,
    frostedNavBar: true,
    frostedSheets: true,
    frostedPlayerCard: true,
  );

  /// The look in effect for [context]: the app theme's extension, or (in
  /// tests and widgets built outside the app theme) the active look from
  /// [UiThemeScope]. Subscribes [context] to look changes either way.
  static AbsorbLook of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AbsorbLook>() ??
        UiThemeScope.themeOf(context).lookFor(theme.brightness);
  }

  /// The same behavior flags with every visual token neutral.
  AbsorbLook withNeutralSurfaces() => AbsorbLook(
    fullQualityCovers: fullQualityCovers,
    defaultImageCache: defaultImageCache,
    showExtraCoverBadges: showExtraCoverBadges,
    classicHomeShelves: classicHomeShelves,
    compactHeaderActions: compactHeaderActions,
  );

  /// The glass fill for cards and panels, or null when panels aren't frosted.
  Color? panelFill() {
    final alpha = panelFillAlpha;
    return alpha == null ? null : Colors.white.withValues(alpha: alpha);
  }

  /// The 1 px panel edge for a scheme of [brightness].
  Color panelEdge(Brightness brightness) =>
      (brightness == Brightness.dark ? Colors.white : Colors.black)
          .withValues(alpha: panelBorderAlpha);

  @override
  AbsorbLook copyWith({
    bool? fullQualityCovers,
    bool? defaultImageCache,
    bool? showExtraCoverBadges,
    bool? classicHomeShelves,
    bool? compactHeaderActions,
    double? glowStrength,
    double? backdropTint,
    double? panelFillAlpha,
    double? panelBorderAlpha,
    double? panelBlurSigma,
    double? cornerRadiusBoost,
    double? sheetFillAlpha,
    bool? frostedNavBar,
    bool? frostedSheets,
    bool? frostedPlayerCard,
  }) => AbsorbLook(
    fullQualityCovers: fullQualityCovers ?? this.fullQualityCovers,
    defaultImageCache: defaultImageCache ?? this.defaultImageCache,
    showExtraCoverBadges: showExtraCoverBadges ?? this.showExtraCoverBadges,
    classicHomeShelves: classicHomeShelves ?? this.classicHomeShelves,
    compactHeaderActions: compactHeaderActions ?? this.compactHeaderActions,
    glowStrength: glowStrength ?? this.glowStrength,
    backdropTint: backdropTint ?? this.backdropTint,
    panelFillAlpha: panelFillAlpha ?? this.panelFillAlpha,
    panelBorderAlpha: panelBorderAlpha ?? this.panelBorderAlpha,
    panelBlurSigma: panelBlurSigma ?? this.panelBlurSigma,
    cornerRadiusBoost: cornerRadiusBoost ?? this.cornerRadiusBoost,
    sheetFillAlpha: sheetFillAlpha ?? this.sheetFillAlpha,
    frostedNavBar: frostedNavBar ?? this.frostedNavBar,
    frostedSheets: frostedSheets ?? this.frostedSheets,
    frostedPlayerCard: frostedPlayerCard ?? this.frostedPlayerCard,
  );

  /// Used by [AnimatedTheme] (light/dark switches): numbers blend, flags and
  /// null tokens switch halfway.
  @override
  AbsorbLook lerp(covariant AbsorbLook? other, double t) {
    if (other == null) return this;
    final near = t < 0.5 ? this : other;
    double? nullable(double? a, double? b) =>
        a == null || b == null ? (t < 0.5 ? a : b) : lerpDouble(a, b, t);
    return AbsorbLook(
      fullQualityCovers: near.fullQualityCovers,
      defaultImageCache: near.defaultImageCache,
      showExtraCoverBadges: near.showExtraCoverBadges,
      classicHomeShelves: near.classicHomeShelves,
      compactHeaderActions: near.compactHeaderActions,
      glowStrength: nullable(glowStrength, other.glowStrength),
      backdropTint: lerpDouble(backdropTint, other.backdropTint, t)!,
      panelFillAlpha: nullable(panelFillAlpha, other.panelFillAlpha),
      panelBorderAlpha: lerpDouble(panelBorderAlpha, other.panelBorderAlpha, t)!,
      panelBlurSigma: lerpDouble(panelBlurSigma, other.panelBlurSigma, t)!,
      cornerRadiusBoost:
          lerpDouble(cornerRadiusBoost, other.cornerRadiusBoost, t)!,
      sheetFillAlpha: nullable(sheetFillAlpha, other.sheetFillAlpha),
      frostedNavBar: near.frostedNavBar,
      frostedSheets: near.frostedSheets,
      frostedPlayerCard: near.frostedPlayerCard,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AbsorbLook &&
      other.fullQualityCovers == fullQualityCovers &&
      other.defaultImageCache == defaultImageCache &&
      other.showExtraCoverBadges == showExtraCoverBadges &&
      other.classicHomeShelves == classicHomeShelves &&
      other.compactHeaderActions == compactHeaderActions &&
      other.glowStrength == glowStrength &&
      other.backdropTint == backdropTint &&
      other.panelFillAlpha == panelFillAlpha &&
      other.panelBorderAlpha == panelBorderAlpha &&
      other.panelBlurSigma == panelBlurSigma &&
      other.cornerRadiusBoost == cornerRadiusBoost &&
      other.sheetFillAlpha == sheetFillAlpha &&
      other.frostedNavBar == frostedNavBar &&
      other.frostedSheets == frostedSheets &&
      other.frostedPlayerCard == frostedPlayerCard;

  @override
  int get hashCode => Object.hash(
    fullQualityCovers,
    defaultImageCache,
    showExtraCoverBadges,
    classicHomeShelves,
    compactHeaderActions,
    glowStrength,
    backdropTint,
    panelFillAlpha,
    panelBorderAlpha,
    panelBlurSigma,
    cornerRadiusBoost,
    sheetFillAlpha,
    frostedNavBar,
    frostedSheets,
    frostedPlayerCard,
  );
}

/// The [AbsorbLook] to attach to the app's [ThemeData] of [brightness]: the
/// active look's preset. One-line hook in main.dart's `extensions:`.
AbsorbLook absorbLookFor(Brightness brightness, {bool eink = false}) =>
    currentUiTheme.lookFor(brightness, eink: eink);

/// The look used while none has been chosen.
const AppUiTheme kDefaultUiTheme = AppUiTheme.plus;

/// The chosen UI theme for this device; null means it was never chosen.
final ValueNotifier<AppUiTheme?> uiThemeNotifier = ValueNotifier(null);

/// The active theme ([kDefaultUiTheme] until one is chosen).
AppUiTheme get currentUiTheme => uiThemeNotifier.value ?? kDefaultUiTheme;

/// The active look's behavior flags, read without a [BuildContext] (image
/// cache policy). Widgets should use [AbsorbLook.of] so they rebuild when the
/// look changes.
AbsorbLook get currentAbsorbLook => currentUiTheme.spec;

/// Device-wide storage for the chosen look. It is deliberately not a
/// per-account (scoped) setting: the look belongs to the device, like the
/// welcome sheet.
abstract final class UiThemeStore {
  static const prefKey = 'fork_ui_theme';

  /// Loads the saved look into [uiThemeNotifier]; null when never chosen
  /// (or when the stored id is unknown, e.g. from a newer build).
  static Future<AppUiTheme?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = AppUiTheme.fromId(prefs.getString(prefKey));
    uiThemeNotifier.value = theme;
    return theme;
  }

  /// Saves [theme] and applies it right away.
  static Future<void> choose(AppUiTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, theme.id);
    uiThemeNotifier.value = theme;
  }

  /// True until a look has been chosen (or the picker was dismissed) on this
  /// device. Covers both fresh installs and updates from older builds.
  static Future<bool> needsChoice() async {
    final prefs = await SharedPreferences.getInstance();
    return AppUiTheme.fromId(prefs.getString(prefKey)) == null;
  }
}

/// Makes the active look available below it and rebuilds dependents when it
/// changes. Sits above [MaterialApp] so dialogs and sheets see it too. The
/// app theme's [AbsorbLook] extension takes precedence (see [AbsorbLook.of]);
/// this is the fallback for widgets built outside it.
class UiThemeScope extends InheritedNotifier<ValueNotifier<AppUiTheme?>> {
  UiThemeScope({
    super.key,
    ValueNotifier<AppUiTheme?>? notifier,
    required super.child,
  }) : super(notifier: notifier ?? uiThemeNotifier);

  /// The active look. Subscribes [context] to changes when a scope is
  /// present; without one (some tests) it reads the global notifier.
  static AppUiTheme themeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiThemeScope>();
    return (scope?.notifier ?? uiThemeNotifier).value ?? kDefaultUiTheme;
  }
}
