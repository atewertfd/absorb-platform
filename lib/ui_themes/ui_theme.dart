import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Absorb Plus "UI themes": whole-app looks the user picks once on first
/// launch and can change in Settings > Appearance > UI theme.
///
/// This is separate from the light/dark/OLED "Theme" setting. A UI theme only
/// changes graphics (cover quality, badges, shelf sizes, header buttons);
/// motion and animation timing are never part of it.
///
/// Adding a look: add an enum value with a stable id, give it a
/// [UiThemeSpec] preset in [AppUiTheme.spec], and add its name and
/// description strings in `ui_theme_picker.dart` (the switches there are
/// exhaustive, so the analyzer points at every place that needs it).
enum AppUiTheme {
  /// Today's Absorb Plus look. Its preset changes nothing.
  plus('plus'),

  /// The look of the first Windows port (windows-experimental-0.1.0).
  classic('classic');

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

  UiThemeSpec get spec => switch (this) {
    AppUiTheme.plus => UiThemeSpec.plus,
    AppUiTheme.classic => UiThemeSpec.classic,
  };
}

/// What a UI theme changes. Every flag's default is today's Absorb Plus
/// behavior, so [UiThemeSpec.plus] is simply the default constructor.
@immutable
class UiThemeSpec {
  const UiThemeSpec({
    this.fullQualityCovers = false,
    this.defaultImageCache = false,
    this.showExtraCoverBadges = true,
    this.classicHomeShelves = false,
    this.compactHeaderActions = false,
  });

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

  static const UiThemeSpec plus = UiThemeSpec();

  static const UiThemeSpec classic = UiThemeSpec(
    fullQualityCovers: true,
    defaultImageCache: true,
    showExtraCoverBadges: false,
    classicHomeShelves: true,
    compactHeaderActions: true,
  );

  @override
  bool operator ==(Object other) =>
      other is UiThemeSpec &&
      other.fullQualityCovers == fullQualityCovers &&
      other.defaultImageCache == defaultImageCache &&
      other.showExtraCoverBadges == showExtraCoverBadges &&
      other.classicHomeShelves == classicHomeShelves &&
      other.compactHeaderActions == compactHeaderActions;

  @override
  int get hashCode => Object.hash(
    fullQualityCovers,
    defaultImageCache,
    showExtraCoverBadges,
    classicHomeShelves,
    compactHeaderActions,
  );
}

/// The look used while none has been chosen.
const AppUiTheme kDefaultUiTheme = AppUiTheme.plus;

/// The chosen UI theme for this device; null means it was never chosen.
final ValueNotifier<AppUiTheme?> uiThemeNotifier = ValueNotifier(null);

/// The active theme ([kDefaultUiTheme] until one is chosen).
AppUiTheme get currentUiTheme => uiThemeNotifier.value ?? kDefaultUiTheme;

/// The active theme's flags, read without subscribing to changes. Widgets
/// should use [UiThemeScope.specOf] so they rebuild when the look changes.
UiThemeSpec get currentUiThemeSpec => currentUiTheme.spec;

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
/// changes. Sits above [MaterialApp] so dialogs and sheets see it too.
class UiThemeScope extends InheritedNotifier<ValueNotifier<AppUiTheme?>> {
  UiThemeScope({
    super.key,
    ValueNotifier<AppUiTheme?>? notifier,
    required super.child,
  }) : super(notifier: notifier ?? uiThemeNotifier);

  /// The active look's flags. Subscribes [context] to changes when a scope is
  /// present; without one (some tests) it reads the global notifier.
  static UiThemeSpec specOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiThemeScope>();
    final theme = (scope?.notifier ?? uiThemeNotifier).value;
    return (theme ?? kDefaultUiTheme).spec;
  }
}
