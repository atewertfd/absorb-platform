import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../build_info.dart';
import '../services/whats_new_notes.dart';
import 'welcome_sheet.dart';
import 'whats_new_sheet.dart';

/// The release tag of a build. Fork releases, stable ones included, are
/// always tagged `vX.Y.Z-N` (see .github/workflows/release.yml).
String whatsNewReleaseTag(String version, int build) => 'v$version-$build';

/// After an update, shows the new build's release notes ([WhatsNewSheet]).
class WhatsNewPrompt {
  static const _lastBuildKey = 'whats_new_last_build';
  static const _enabledKey = 'whats_new_enabled';
  static const _isDevBuild = bool.fromEnvironment('DEV_BUILD');

  /// Some people read the release notes on GitHub anyway, so the prompt can
  /// be turned off, from the prompt itself or in Settings.
  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;

  static Future<void> setEnabled(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(_enabledKey, on);

  /// Call before [WelcomeSheet.showIfNeeded]: a fresh install hasn't seen the
  /// welcome yet, and that's how it's told apart from an update.
  static Future<void> showIfUpdated(BuildContext context) async {
    if (kIsWeb || _isDevBuild) return;
    final prefs = await SharedPreferences.getInstance();
    final freshInstall = prefs.getBool(WelcomeSheet.prefKey) != true;
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber);
    if (build == null) return;
    final lastBuild = prefs.getInt(_lastBuildKey);
    await prefs.setInt(_lastBuildKey, build);
    final previous = await WhatsNewHistory.record(prefs,
        version: info.version, build: build,
        beta: betaNumberFor(info.version), lastBuild: lastBuild);
    if (freshInstall || (lastBuild != null && build <= lastBuild)) return;
    if (prefs.getBool(_enabledKey) == false) return;

    // Let launch settle so this doesn't land on top of the first frames.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!context.mounted) return;
    await WhatsNewSheet.show(context,
        version: info.version, build: build, previous: previous);
  }
}
