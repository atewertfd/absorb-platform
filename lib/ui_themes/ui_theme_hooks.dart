import 'package:flutter/material.dart';

import 'ui_theme.dart';

/// One-line checks for upstream files, so each look's differences live here
/// rather than in the upstream widgets. Every helper reads the active
/// [AbsorbLook] through [AbsorbLook.of], which subscribes the calling widget
/// to look changes.

/// The decode width for a cover: [boundedWidth] normally, or null (decode at
/// the source resolution) when the look wants full-quality covers.
int? themedCoverDecodeWidth(BuildContext context, int boundedWidth) =>
    AbsorbLook.of(context).fullQualityCovers ? null : boundedWidth;

/// Whether the extra cover badges (ebook badge, Continue Listening "saved"
/// strip) are part of the active look. The user's own badge settings still
/// apply on top of this.
bool showsExtraCoverBadges(BuildContext context) =>
    AbsorbLook.of(context).showExtraCoverBadges;

/// Whether Continue Reading is a normal Home shelf instead of big cards.
bool usesClassicHomeShelves(BuildContext context) =>
    AbsorbLook.of(context).classicHomeShelves;

/// The original fixed Home shelf height for cover cards, or null to use the
/// measured height of the active look.
double? classicShelfCardHeight(
  BuildContext context,
  bool isRectCover,
  double cardWidth,
  double coverAspectRatio,
  bool subtitleLine,
) {
  if (!AbsorbLook.of(context).classicHomeShelves) return null;
  return classicCoverCardHeight(
    isRectCover: isRectCover,
    cardWidth: cardWidth,
    coverAspectRatio: coverAspectRatio,
    subtitleLine: subtitleLine,
  );
}

/// The shelf height formula of the first Windows port (056dd914).
double classicCoverCardHeight({
  required bool isRectCover,
  required double cardWidth,
  required double coverAspectRatio,
  required bool subtitleLine,
}) =>
    (isRectCover ? 260 : 200) +
    (cardWidth - 140) / coverAspectRatio +
    (subtitleLine ? 18 : 0);

/// Minimum tap area for header actions, or null to keep the drawn size.
BoxConstraints? headerActionConstraints(BuildContext context) =>
    AbsorbLook.of(context).compactHeaderActions
    ? null
    : const BoxConstraints(minWidth: 44, minHeight: 44);

// ── Surface hooks (Frosted, Midnight) ──

/// The top alpha of the screens' cover-colored background glow: the look's
/// own strength, or [userIntensity] (the gradient intensity setting) when the
/// look doesn't set one. Screens skip the glow when Flat background is on.
double lookGlow(BuildContext context, double userIntensity) =>
    AbsorbLook.of(context).glowStrength ?? userIntensity;

/// A screen background's gradient [colors] (glow first, then the solid
/// surface stops). In Frosted the accent color tints the stops below the
/// glow too, fading a little toward the bottom, so the translucent panels
/// have color behind them. A look with no glow at all (Midnight) gets the
/// first solid stop in place of the glow, so not even a faint fade of the
/// accent shows. Other looks get [colors] back unchanged.
List<Color> lookBackdrop(BuildContext context, List<Color> colors) {
  final look = AbsorbLook.of(context);
  if (colors.length < 2) return colors;
  if (look.glowStrength == 0) return [colors[1], ...colors.skip(1)];
  final tint = look.backdropTint;
  if (tint <= 0) return colors;
  final accent = Theme.of(context).colorScheme.primary;
  final last = colors.length - 1;
  return [
    colors.first,
    for (var i = 1; i <= last; i++)
      Color.alphaBlend(
        accent.withValues(alpha: tint * (1 - 0.4 * (i - 1) / last)),
        colors[i],
      ),
  ];
}

/// A card's own fill [colors] (e.g. tinted from its cover): in Frosted they
/// turn partly translucent so the screen's color shows through like glass,
/// keeping their tint (how much follows the glass strength); other looks get
/// them back unchanged.
List<Color> lookCardColors(BuildContext context, List<Color> colors) {
  final look = AbsorbLook.of(context);
  if (!look.frostedPanels) return colors;
  final opacity = look.cardFillOpacity;
  return [for (final c in colors) c.withValues(alpha: c.a * opacity)];
}

/// A panel's fill: frosted glass when the look frosts panels, transparent
/// when it outlines them (Midnight), else [opaque].
Color lookPanelColor(BuildContext context, Color opaque) =>
    AbsorbLook.of(context).panelFill() ?? opaque;

/// A panel's elevation: 0 for frosted glass (a shadow would show through
/// the translucent fill) and outlined panels, else [elevation].
double lookPanelElevation(BuildContext context, double elevation) =>
    AbsorbLook.of(context).themedPanels ? 0 : elevation;

/// A panel's outline: the thin glass edge when frosted, the hairline when
/// outlined (Midnight), else [side].
BorderSide lookPanelSide(BuildContext context, BorderSide side) {
  final look = AbsorbLook.of(context);
  if (!look.themedPanels) return side;
  return BorderSide(color: look.panelEdge(Theme.of(context).brightness));
}

/// [radius] plus the look's corner radius boost.
double lookRadius(BuildContext context, double radius) =>
    radius + AbsorbLook.of(context).cornerRadiusBoost;

/// The Absorbing card's border color: the light glass edge in Frosted, else
/// [color].
Color lookPlayerCardEdge(BuildContext context, Color color) {
  final look = AbsorbLook.of(context);
  if (!look.frostedPlayerCard) return color;
  return look.panelEdge(Theme.of(context).brightness);
}
