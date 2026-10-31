import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Look details": the old Classic look's behaviors as ordinary settings,
/// applied on top of whichever look is active (Settings > Appearance, under
/// UI theme). They are device-wide, like the look.
///
/// They reach widgets through the active [AbsorbLook] (see
/// `AbsorbLook.withDetails` and `AppUiTheme.lookFor` in `ui_theme.dart`), so
/// the hooks in upstream files keep reading `AbsorbLook.of` unchanged.
@immutable
class LookDetails {
  const LookDetails({
    this.fullQualityCovers = false,
    this.extraCoverBadges = true,
    this.continueReadingShelf = false,
    this.compactHeaderButtons = false,
  });

  /// Covers decode at the source resolution, and Flutter's larger default
  /// image cache is kept (also in the background) so they stay sharp.
  final bool fullQualityCovers;

  /// The ebook badge on covers and the "saved" strip on Continue Listening
  /// cards (the user's own badge settings still apply on top).
  final bool extraCoverBadges;

  /// Continue Reading is a normal Home shelf, and Home shelves keep the
  /// original fixed card height.
  final bool continueReadingShelf;

  /// Header buttons keep their drawn size instead of a 44x44 tap area.
  final bool compactHeaderButtons;

  /// Absorb Plus's own behavior: the defaults.
  static const LookDetails standard = LookDetails();

  /// What the retired Classic look did. Devices that had Classic saved get
  /// these once, when they move to Standard ([LookDetailsStore]).
  static const LookDetails classic = LookDetails(
    fullQualityCovers: true,
    extraCoverBadges: false,
    continueReadingShelf: true,
    compactHeaderButtons: true,
  );

  LookDetails copyWith({
    bool? fullQualityCovers,
    bool? extraCoverBadges,
    bool? continueReadingShelf,
    bool? compactHeaderButtons,
  }) => LookDetails(
    fullQualityCovers: fullQualityCovers ?? this.fullQualityCovers,
    extraCoverBadges: extraCoverBadges ?? this.extraCoverBadges,
    continueReadingShelf: continueReadingShelf ?? this.continueReadingShelf,
    compactHeaderButtons: compactHeaderButtons ?? this.compactHeaderButtons,
  );

  @override
  bool operator ==(Object other) =>
      other is LookDetails &&
      other.fullQualityCovers == fullQualityCovers &&
      other.extraCoverBadges == extraCoverBadges &&
      other.continueReadingShelf == continueReadingShelf &&
      other.compactHeaderButtons == compactHeaderButtons;

  @override
  int get hashCode => Object.hash(
    fullQualityCovers,
    extraCoverBadges,
    continueReadingShelf,
    compactHeaderButtons,
  );

  @override
  String toString() =>
      'LookDetails(fullQualityCovers: $fullQualityCovers, '
      'extraCoverBadges: $extraCoverBadges, '
      'continueReadingShelf: $continueReadingShelf, '
      'compactHeaderButtons: $compactHeaderButtons)';
}

/// The saved look details for this device. The look notifiers in
/// `ui_theme.dart` re-notify when it changes, so the app theme, the hooks and
/// the image cache policy follow it without extra wiring.
final ValueNotifier<LookDetails> lookDetailsNotifier = ValueNotifier(
  LookDetails.standard,
);

/// Device-wide storage for [LookDetails], one bool per setting.
abstract final class LookDetailsStore {
  static const fullQualityCoversKey = 'fork_look_full_covers';
  static const extraCoverBadgesKey = 'fork_look_extra_badges';
  static const continueReadingShelfKey = 'fork_look_reading_shelf';
  static const compactHeaderButtonsKey = 'fork_look_compact_header';

  /// Loads the saved details into [lookDetailsNotifier] (defaults for any
  /// that were never set).
  static Future<LookDetails> load() async {
    final prefs = await SharedPreferences.getInstance();
    const d = LookDetails.standard;
    final details = LookDetails(
      fullQualityCovers:
          prefs.getBool(fullQualityCoversKey) ?? d.fullQualityCovers,
      extraCoverBadges:
          prefs.getBool(extraCoverBadgesKey) ?? d.extraCoverBadges,
      continueReadingShelf:
          prefs.getBool(continueReadingShelfKey) ?? d.continueReadingShelf,
      compactHeaderButtons:
          prefs.getBool(compactHeaderButtonsKey) ?? d.compactHeaderButtons,
    );
    lookDetailsNotifier.value = details;
    return details;
  }

  /// Applies [details] right away and saves all four.
  static Future<void> save(LookDetails details) async {
    lookDetailsNotifier.value = details;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(fullQualityCoversKey, details.fullQualityCovers);
    await prefs.setBool(extraCoverBadgesKey, details.extraCoverBadges);
    await prefs.setBool(continueReadingShelfKey, details.continueReadingShelf);
    await prefs.setBool(compactHeaderButtonsKey, details.compactHeaderButtons);
  }
}
