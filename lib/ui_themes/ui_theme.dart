import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'look_details.dart';

export 'look_details.dart';

/// Absorb Plus "UI themes": whole-app looks the user picks once on first
/// launch and can change in Settings > Appearance > UI theme.
///
/// This is separate from the light/dark/OLED "Theme" setting and from the
/// color source. A UI theme only changes graphics (surface style, glow,
/// outlines); motion and animation timing are never part of it. The old
/// Classic look's behaviors (cover quality, badges, shelves, header buttons)
/// are [LookDetails] settings now, layered on top of every look.
///
/// Themes are values: each look is an [AbsorbLook] preset, attached to the
/// app's [ThemeData] as a [ThemeExtension] (see `absorbLookFor` in main.dart's
/// ThemeData and `frosted.dart`). Widgets read it with [AbsorbLook.of].
///
/// Adding a look: add an enum value with a stable id, give it an
/// [AbsorbLook] preset in [AppUiTheme.lookFor], and add its name and
/// description strings in `ui_theme_picker.dart` (the switches there are
/// exhaustive, so the analyzer points at every place that needs it).
/// The enum order is the picker's order.
enum AppUiTheme {
  /// "Standard": today's Absorb Plus look. Its preset changes nothing. The
  /// id stays 'plus' so saved choices keep working.
  plus('plus'),

  /// Absorb Plus with lightly frosted, translucent surfaces over a stronger
  /// cover-colored glow.
  frosted('frosted'),

  /// True black (paper white in light mode), no glow, and thin outlines
  /// instead of filled panels.
  midnight('midnight');

  const AppUiTheme(this.id);

  /// Stable id stored in preferences. Never rename an existing id.
  final String id;

  /// The id the retired Classic look was stored under. [UiThemeStore.load]
  /// moves it to Standard plus [LookDetails.classic].
  static const String retiredClassicId = 'classic';

  /// The theme stored under [id], or null for a missing or unknown id.
  static AppUiTheme? fromId(String? id) {
    if (id == null) return null;
    for (final theme in values) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  /// The look's dark-mode preset (the app's default mode), with the default
  /// [LookDetails].
  AbsorbLook get spec => lookFor(Brightness.dark);

  /// The look's preset for [brightness], with [details] layered on top.
  /// E-ink always gets neutral surfaces (translucency, outlines and glow
  /// dither into noise there), but keeps the behavior flags. [glass] picks
  /// Frosted's strength; other looks ignore it.
  AbsorbLook lookFor(
    Brightness brightness, {
    bool eink = false,
    GlassStrength glass = kDefaultGlassStrength,
    LookDetails details = LookDetails.standard,
  }) {
    final look = switch (this) {
      AppUiTheme.plus => AbsorbLook.plus,
      AppUiTheme.frosted => AbsorbLook.frosted(brightness, glass),
      AppUiTheme.midnight => AbsorbLook.midnight(brightness),
    }.withDetails(details);
    return eink ? look.withNeutralSurfaces() : look;
  }
}

/// How strong the Frosted look's glass is. Medium is the original Frosted.
enum GlassStrength {
  /// Subtler: more solid panels and sheets, less blur and accent tint.
  light('light'),

  /// The original Frosted values.
  medium('medium'),

  /// More see-through, more blur, a stronger tint and glow.
  strong('strong');

  const GlassStrength(this.id);

  /// Stable id stored in preferences. Never rename an existing id.
  final String id;

  /// The strength stored under [id], or null for a missing or unknown id.
  static GlassStrength? fromId(String? id) {
    if (id == null) return null;
    for (final strength in values) {
      if (strength.id == id) return strength;
    }
    return null;
  }
}

/// The glass strength used while none has been chosen: the original Frosted.
const GlassStrength kDefaultGlassStrength = GlassStrength.medium;

/// What a UI theme changes, as a [ThemeExtension] on the app's [ThemeData].
///
/// Every field's default is today's Absorb Plus behavior, so
/// [AbsorbLook.plus] is simply the default constructor. The behavior flags
/// come from the user's [LookDetails] ([withDetails]); the presets only set
/// visual tokens. The visual tokens (glow, panels, sheets, radius, canvas)
/// are "neutral" by default: null values and false flags mean "paint exactly
/// what upstream paints".
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
    this.cardFillOpacity = 1,
    this.frostedNavBar = false,
    this.frostedSheets = false,
    this.frostedPlayerCard = false,
    this.canvasColor,
    this.sheetColor,
    this.outlinedPanels = false,
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

  /// How much of a cover-tinted card's own fill stays when panels are
  /// frosted (Home's Continue Listening cards): 1 keeps it, lower lets the
  /// screen's color through. Only applies with frosted panels.
  final double cardFillOpacity;

  /// The bottom nav bar is translucent with a blur behind it and a top edge.
  final bool frostedNavBar;

  /// Bottom sheets and dialogs are translucent (desktop dialogs also blur).
  final bool frostedSheets;

  /// The Absorbing (player) card gets the light glass edge. Its background is
  /// already a pre-blurred cover, so no extra blur is added.
  final bool frostedPlayerCard;

  /// The screens' background (scaffold, ColorScheme.surface, nav bar) in
  /// place of upstream's. Null keeps upstream's (Midnight: true black, or
  /// paper white in light mode).
  final Color? canvasColor;

  /// An opaque background for bottom sheets and dialogs, drawn with the 1 px
  /// panel edge. Null keeps upstream's.
  final Color? sheetColor;

  /// Cards and panels are a thin outline (the 1 px panel edge, see
  /// [panelBorderAlpha]) over the background instead of a filled panel, and
  /// the nav bar gets the same edge on top.
  final bool outlinedPanels;

  /// Whether cards and panels are frosted glass.
  bool get frostedPanels => panelFillAlpha != null;

  /// Whether cards and panels differ from upstream's filled panels (frosted
  /// glass or outlines): no elevation, the panel edge as their outline.
  bool get themedPanels => frostedPanels || outlinedPanels;

  /// Whether the nav bar gets a top edge.
  bool get navBarEdge => frostedNavBar || outlinedPanels;

  /// Whether any surface differs from the upstream look.
  bool get changesSurfaces =>
      frostedPanels ||
      frostedNavBar ||
      frostedSheets ||
      frostedPlayerCard ||
      outlinedPanels ||
      canvasColor != null ||
      sheetColor != null;

  static const AbsorbLook plus = AbsorbLook();

  /// Midnight in dark mode: true black for OLED, no glow or tint, panels as
  /// a white 14% hairline (about onSurface at 14%) instead of a grey fill,
  /// near-black sheets and dialogs with the same edge, and the usual radius.
  static const AbsorbLook midnightDark = AbsorbLook(
    glowStrength: 0,
    panelBorderAlpha: 0.14,
    canvasColor: Color(0xFF000000),
    sheetColor: Color(0xFF0A0A0A),
    outlinedPanels: true,
  );

  /// Midnight in light mode, its paper counterpart: white backgrounds and
  /// sheets, a black 12% hairline around panels, no glow.
  static const AbsorbLook midnightLight = AbsorbLook(
    glowStrength: 0,
    panelBorderAlpha: 0.12,
    canvasColor: Color(0xFFFFFFFF),
    sheetColor: Color(0xFFFFFFFF),
    outlinedPanels: true,
  );

  /// The Midnight preset for [brightness].
  static AbsorbLook midnight(Brightness brightness) =>
      brightness == Brightness.dark ? midnightDark : midnightLight;

  /// Frosted in dark mode, medium glass: the owner-approved demo's values
  /// (white 7% glass, 12% light edge, blur 18, radius +4) over a ~0.24 glow.
  static const AbsorbLook frostedDark = AbsorbLook(
    glowStrength: 0.30,
    backdropTint: 0.16,
    panelFillAlpha: 0.10,
    panelBorderAlpha: 0.16,
    panelBlurSigma: 18,
    cornerRadiusBoost: 4,
    sheetFillAlpha: 0.90,
    cardFillOpacity: 0.62,
    frostedNavBar: true,
    frostedSheets: true,
    frostedPlayerCard: true,
  );

  /// Frosted in light mode, medium glass: milky glass (white 50%) with a
  /// faint dark edge, and a softer glow since the light accent tone is darker.
  static const AbsorbLook frostedLight = AbsorbLook(
    glowStrength: 0.22,
    backdropTint: 0.10,
    panelFillAlpha: 0.50,
    panelBorderAlpha: 0.08,
    panelBlurSigma: 18,
    cornerRadiusBoost: 4,
    sheetFillAlpha: 0.90,
    cardFillOpacity: 0.62,
    frostedNavBar: true,
    frostedSheets: true,
    frostedPlayerCard: true,
  );

  /// Frosted dark, light glass: a fainter sheen and edge, less tint and blur,
  /// more solid sheets and cards; closer to Absorb Plus but still glass.
  static const AbsorbLook frostedDarkGlassLight = AbsorbLook(
    glowStrength: 0.26,
    backdropTint: 0.10,
    panelFillAlpha: 0.08,
    panelBorderAlpha: 0.12,
    panelBlurSigma: 12,
    cornerRadiusBoost: 4,
    sheetFillAlpha: 0.94,
    cardFillOpacity: 0.78,
    frostedNavBar: true,
    frostedSheets: true,
    frostedPlayerCard: true,
  );

  /// Frosted dark, strong glass: a brighter sheen and edge over more accent
  /// color, more blur, and sheets and cards that let more through.
  static const AbsorbLook frostedDarkGlassStrong = AbsorbLook(
    glowStrength: 0.34,
    backdropTint: 0.22,
    panelFillAlpha: 0.12,
    panelBorderAlpha: 0.20,
    panelBlurSigma: 26,
    cornerRadiusBoost: 4,
    sheetFillAlpha: 0.84,
    cardFillOpacity: 0.48,
    frostedNavBar: true,
    frostedSheets: true,
    frostedPlayerCard: true,
  );

  /// Frosted light, light glass: milkier (more solid) panels, less tint and
  /// blur, more solid sheets and cards.
  static const AbsorbLook frostedLightGlassLight = AbsorbLook(
    glowStrength: 0.18,
    backdropTint: 0.06,
    panelFillAlpha: 0.62,
    panelBorderAlpha: 0.07,
    panelBlurSigma: 12,
    cornerRadiusBoost: 4,
    sheetFillAlpha: 0.94,
    cardFillOpacity: 0.78,
    frostedNavBar: true,
    frostedSheets: true,
    frostedPlayerCard: true,
  );

  /// Frosted light, strong glass: clearer (less milky) panels over more
  /// accent color, more blur, and sheets and cards that let more through.
  static const AbsorbLook frostedLightGlassStrong = AbsorbLook(
    glowStrength: 0.26,
    backdropTint: 0.14,
    panelFillAlpha: 0.40,
    panelBorderAlpha: 0.10,
    panelBlurSigma: 26,
    cornerRadiusBoost: 4,
    sheetFillAlpha: 0.84,
    cardFillOpacity: 0.48,
    frostedNavBar: true,
    frostedSheets: true,
    frostedPlayerCard: true,
  );

  /// The Frosted preset for [brightness] and glass [strength].
  static AbsorbLook frosted(Brightness brightness, GlassStrength strength) {
    final dark = brightness == Brightness.dark;
    return switch (strength) {
      GlassStrength.light =>
        dark ? frostedDarkGlassLight : frostedLightGlassLight,
      GlassStrength.medium => dark ? frostedDark : frostedLight,
      GlassStrength.strong =>
        dark ? frostedDarkGlassStrong : frostedLightGlassStrong,
    };
  }

  /// The look in effect for [context]: the app theme's extension, or (in
  /// tests and widgets built outside the app theme) the active look from
  /// [UiThemeScope]. Subscribes [context] to look changes either way.
  static AbsorbLook of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AbsorbLook>() ??
        UiThemeScope.themeOf(context).lookFor(
          theme.brightness,
          glass: currentGlassStrength,
          details: lookDetailsNotifier.value,
        );
  }

  /// This look with [details]'s behavior flags. Full-quality covers also
  /// keep Flutter's default image cache, as the retired Classic look did.
  AbsorbLook withDetails(LookDetails details) => copyWith(
    fullQualityCovers: details.fullQualityCovers,
    defaultImageCache: details.fullQualityCovers,
    showExtraCoverBadges: details.extraCoverBadges,
    classicHomeShelves: details.continueReadingShelf,
    compactHeaderActions: details.compactHeaderButtons,
  );

  /// The same behavior flags with every visual token neutral.
  AbsorbLook withNeutralSurfaces() => AbsorbLook(
    fullQualityCovers: fullQualityCovers,
    defaultImageCache: defaultImageCache,
    showExtraCoverBadges: showExtraCoverBadges,
    classicHomeShelves: classicHomeShelves,
    compactHeaderActions: compactHeaderActions,
  );

  /// The fill for cards and panels: white glass when frosted, transparent
  /// (the background shows, inside the outline) when outlined, or null to
  /// keep upstream's opaque fills.
  Color? panelFill() {
    final alpha = panelFillAlpha;
    if (alpha != null) return Colors.white.withValues(alpha: alpha);
    return outlinedPanels ? Colors.transparent : null;
  }

  /// The 1 px panel edge for a scheme of [brightness].
  Color panelEdge(Brightness brightness) =>
      (brightness == Brightness.dark ? Colors.white : Colors.black).withValues(
        alpha: panelBorderAlpha,
      );

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
    double? cardFillOpacity,
    bool? frostedNavBar,
    bool? frostedSheets,
    bool? frostedPlayerCard,
    Color? canvasColor,
    Color? sheetColor,
    bool? outlinedPanels,
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
    cardFillOpacity: cardFillOpacity ?? this.cardFillOpacity,
    frostedNavBar: frostedNavBar ?? this.frostedNavBar,
    frostedSheets: frostedSheets ?? this.frostedSheets,
    frostedPlayerCard: frostedPlayerCard ?? this.frostedPlayerCard,
    canvasColor: canvasColor ?? this.canvasColor,
    sheetColor: sheetColor ?? this.sheetColor,
    outlinedPanels: outlinedPanels ?? this.outlinedPanels,
  );

  /// Used by [AnimatedTheme] (light/dark switches): numbers blend, flags and
  /// null tokens switch halfway.
  @override
  AbsorbLook lerp(covariant AbsorbLook? other, double t) {
    if (other == null) return this;
    final near = t < 0.5 ? this : other;
    double? nullable(double? a, double? b) =>
        a == null || b == null ? (t < 0.5 ? a : b) : lerpDouble(a, b, t);
    Color? color(Color? a, Color? b) =>
        a == null || b == null ? (t < 0.5 ? a : b) : Color.lerp(a, b, t);
    return AbsorbLook(
      fullQualityCovers: near.fullQualityCovers,
      defaultImageCache: near.defaultImageCache,
      showExtraCoverBadges: near.showExtraCoverBadges,
      classicHomeShelves: near.classicHomeShelves,
      compactHeaderActions: near.compactHeaderActions,
      glowStrength: nullable(glowStrength, other.glowStrength),
      backdropTint: lerpDouble(backdropTint, other.backdropTint, t)!,
      panelFillAlpha: nullable(panelFillAlpha, other.panelFillAlpha),
      panelBorderAlpha: lerpDouble(
        panelBorderAlpha,
        other.panelBorderAlpha,
        t,
      )!,
      panelBlurSigma: lerpDouble(panelBlurSigma, other.panelBlurSigma, t)!,
      cornerRadiusBoost: lerpDouble(
        cornerRadiusBoost,
        other.cornerRadiusBoost,
        t,
      )!,
      sheetFillAlpha: nullable(sheetFillAlpha, other.sheetFillAlpha),
      cardFillOpacity: lerpDouble(cardFillOpacity, other.cardFillOpacity, t)!,
      frostedNavBar: near.frostedNavBar,
      frostedSheets: near.frostedSheets,
      frostedPlayerCard: near.frostedPlayerCard,
      canvasColor: color(canvasColor, other.canvasColor),
      sheetColor: color(sheetColor, other.sheetColor),
      outlinedPanels: near.outlinedPanels,
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
      other.cardFillOpacity == cardFillOpacity &&
      other.frostedNavBar == frostedNavBar &&
      other.frostedSheets == frostedSheets &&
      other.frostedPlayerCard == frostedPlayerCard &&
      other.canvasColor == canvasColor &&
      other.sheetColor == sheetColor &&
      other.outlinedPanels == outlinedPanels;

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
    cardFillOpacity,
    frostedNavBar,
    frostedSheets,
    frostedPlayerCard,
    canvasColor,
    sheetColor,
    outlinedPanels,
  );
}

/// The [AbsorbLook] to attach to the app's [ThemeData] of [brightness]: the
/// active look's preset with the saved [LookDetails] on top. One-line hook in
/// main.dart's `extensions:`.
AbsorbLook absorbLookFor(Brightness brightness, {bool eink = false}) =>
    currentUiTheme.lookFor(
      brightness,
      eink: eink,
      glass: currentGlassStrength,
      details: lookDetailsNotifier.value,
    );

/// The look used while none has been chosen.
const AppUiTheme kDefaultUiTheme = AppUiTheme.plus;

/// The saved glass strength for Frosted on this device.
final ValueNotifier<GlassStrength> glassStrengthNotifier = ValueNotifier(
  kDefaultGlassStrength,
);

/// A glass strength being tried live with a look ("Try it"), ahead of the
/// saved one. Memory only, like [uiThemePreviewNotifier].
final ValueNotifier<GlassStrength?> glassStrengthPreviewNotifier =
    ValueNotifier(null);

/// The chosen UI theme for this device; null means it was never chosen.
/// It also notifies when the saved glass strength or [LookDetails] change, so
/// everything that follows the look (the app theme in main.dart,
/// [UiThemeScope], the image cache policy) follows them too.
final ValueNotifier<AppUiTheme?> uiThemeNotifier = _LookNotifier(
  Listenable.merge([glassStrengthNotifier, lookDetailsNotifier]),
);

/// A look being tried live ("Try it" in the picker), shown app-wide ahead of
/// the saved choice. Memory only: it is never stored, so a restart shows the
/// saved look, and saving any look ([UiThemeStore.choose]) clears it. It
/// also notifies when the previewed glass strength changes.
final ValueNotifier<AppUiTheme?> uiThemePreviewNotifier = _LookNotifier(
  glassStrengthPreviewNotifier,
);

/// A look notifier that also notifies its listeners when [also] changes.
class _LookNotifier extends ValueNotifier<AppUiTheme?> {
  _LookNotifier(Listenable also) : super(null) {
    also.addListener(notifyListeners);
  }
}

/// The saved glass strength, ignoring a live preview.
GlassStrength get savedGlassStrength => glassStrengthNotifier.value;

/// The active glass strength: the one being tried live, else the saved one.
GlassStrength get currentGlassStrength =>
    glassStrengthPreviewNotifier.value ?? savedGlassStrength;

/// The saved theme ([kDefaultUiTheme] until one is chosen), ignoring a live
/// preview.
AppUiTheme get savedUiTheme => uiThemeNotifier.value ?? kDefaultUiTheme;

/// The active theme: the look being tried live, else the saved one.
AppUiTheme get currentUiTheme => uiThemePreviewNotifier.value ?? savedUiTheme;

/// The saved look with the saved [LookDetails], read without a
/// [BuildContext] (image cache policy, which follows saved choices only, not
/// live previews). Widgets should use [AbsorbLook.of] so they rebuild when
/// the look changes.
AbsorbLook get currentAbsorbLook =>
    savedUiTheme.lookFor(Brightness.dark, details: lookDetailsNotifier.value);

/// Device-wide storage for the chosen look. It is deliberately not a
/// per-account (scoped) setting: the look belongs to the device, like the
/// welcome sheet.
abstract final class UiThemeStore {
  static const prefKey = 'fork_ui_theme';

  /// Frosted's glass strength, device-wide like the look.
  static const glassPrefKey = 'fork_ui_glass';

  /// Loads the saved look into [uiThemeNotifier] (null when never chosen, or
  /// when the stored id is unknown, e.g. from a newer build), the saved
  /// glass strength into [glassStrengthNotifier] (medium when unset) and the
  /// saved [LookDetails] into [lookDetailsNotifier].
  ///
  /// A device that had the retired Classic look saved moves to Standard with
  /// [LookDetails.classic], once: the new id replaces 'classic', so nothing
  /// changes for it visually and later loads keep the user's own details.
  static Future<AppUiTheme?> load() async {
    final prefs = await SharedPreferences.getInstance();
    await LookDetailsStore.load();
    if (prefs.getString(prefKey) == AppUiTheme.retiredClassicId) {
      await LookDetailsStore.save(LookDetails.classic);
      await prefs.setString(prefKey, AppUiTheme.plus.id);
    }
    final theme = AppUiTheme.fromId(prefs.getString(prefKey));
    glassStrengthNotifier.value =
        GlassStrength.fromId(prefs.getString(glassPrefKey)) ??
        kDefaultGlassStrength;
    uiThemeNotifier.value = theme;
    return theme;
  }

  /// Saves [theme] (and [glass], when given) and applies it right away,
  /// ending any live preview.
  static Future<void> choose(AppUiTheme theme, {GlassStrength? glass}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, theme.id);
    if (glass != null) {
      await prefs.setString(glassPrefKey, glass.id);
      glassStrengthNotifier.value = glass;
    }
    uiThemeNotifier.value = theme;
    glassStrengthPreviewNotifier.value = null;
    uiThemePreviewNotifier.value = null;
  }

  /// Applies Frosted's glass strength right away and saves it. A live
  /// preview, if any, is left alone.
  static Future<void> chooseGlass(GlassStrength glass) async {
    glassStrengthNotifier.value = glass;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(glassPrefKey, glass.id);
  }

  /// Records that the question was answered (the first-launch picker was
  /// dismissed or interrupted) without changing the look or ending a live
  /// preview: stores the saved look when nothing valid is stored yet.
  static Future<void> markChosen() async {
    final prefs = await SharedPreferences.getInstance();
    if (AppUiTheme.fromId(prefs.getString(prefKey)) != null) return;
    final theme = savedUiTheme;
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
/// (or a live preview) changes. Sits above [MaterialApp] so dialogs and
/// sheets see it too. The app theme's [AbsorbLook] extension takes precedence
/// (see [AbsorbLook.of]); this is the fallback for widgets built outside it.
class UiThemeScope extends InheritedNotifier<Listenable> {
  UiThemeScope({
    super.key,
    ValueNotifier<AppUiTheme?>? notifier,
    required super.child,
  }) : saved = notifier ?? uiThemeNotifier,
       super(notifier: _withPreview(notifier ?? uiThemeNotifier));

  /// The saved choice this scope follows.
  final ValueNotifier<AppUiTheme?> saved;

  static final Expando<Listenable> _merged = Expando();

  /// One stable merged listenable per saved notifier, so rebuilding the
  /// scope doesn't count as a change.
  static Listenable _withPreview(ValueNotifier<AppUiTheme?> saved) =>
      _merged[saved] ??= Listenable.merge([
        saved,
        uiThemePreviewNotifier,
        glassStrengthNotifier,
        lookDetailsNotifier,
      ]);

  /// The active look, a live preview first. Subscribes [context] to changes
  /// when a scope is present; without one (some tests) it reads the globals.
  static AppUiTheme themeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiThemeScope>();
    return uiThemePreviewNotifier.value ??
        (scope?.saved ?? uiThemeNotifier).value ??
        kDefaultUiTheme;
  }
}
