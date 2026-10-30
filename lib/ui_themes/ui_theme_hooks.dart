import 'package:flutter/widgets.dart';

import 'ui_theme.dart';

/// One-line checks for upstream files, so each look's differences live here
/// rather than in the upstream widgets. Every helper subscribes the calling
/// widget to look changes through [UiThemeScope].

/// The decode width for a cover: [boundedWidth] normally, or null (decode at
/// the source resolution) when the look wants full-quality covers.
int? themedCoverDecodeWidth(BuildContext context, int boundedWidth) =>
    UiThemeScope.specOf(context).fullQualityCovers ? null : boundedWidth;

/// Whether the extra cover badges (ebook badge, Continue Listening "saved"
/// strip) are part of the active look. The user's own badge settings still
/// apply on top of this.
bool showsExtraCoverBadges(BuildContext context) =>
    UiThemeScope.specOf(context).showExtraCoverBadges;

/// Whether Continue Reading is a normal Home shelf instead of big cards.
bool usesClassicHomeShelves(BuildContext context) =>
    UiThemeScope.specOf(context).classicHomeShelves;

/// The original fixed Home shelf height for cover cards, or null to use the
/// measured height of the active look.
double? classicShelfCardHeight(
  BuildContext context,
  bool isRectCover,
  double cardWidth,
  double coverAspectRatio,
  bool subtitleLine,
) {
  if (!UiThemeScope.specOf(context).classicHomeShelves) return null;
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
    UiThemeScope.specOf(context).compactHeaderActions
    ? null
    : const BoxConstraints(minWidth: 44, minHeight: 44);
