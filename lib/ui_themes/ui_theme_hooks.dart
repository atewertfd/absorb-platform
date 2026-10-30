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

// ── Surface hooks (Frosted) ──

/// The top alpha of the screens' cover-colored background glow: the look's
/// own strength, or [userIntensity] (the gradient intensity setting) when the
/// look doesn't set one. Screens skip the glow when Flat background is on.
double lookGlow(BuildContext context, double userIntensity) =>
    AbsorbLook.of(context).glowStrength ?? userIntensity;

/// A panel's fill: frosted glass when the look frosts panels, else [opaque].
Color lookPanelColor(BuildContext context, Color opaque) =>
    AbsorbLook.of(context).panelFill() ?? opaque;

/// A panel's elevation: 0 for frosted glass (a shadow would show through
/// the translucent fill), else [elevation].
double lookPanelElevation(BuildContext context, double elevation) =>
    AbsorbLook.of(context).frostedPanels ? 0 : elevation;

/// A panel's outline: the thin glass edge when frosted, else [side].
BorderSide lookPanelSide(BuildContext context, BorderSide side) {
  final look = AbsorbLook.of(context);
  if (!look.frostedPanels) return side;
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
