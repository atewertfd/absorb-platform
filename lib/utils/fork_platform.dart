import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Same as `comicEbookFormats` in services/ebook_cache.dart (kept here so this
/// helper stays free of service imports; a test checks they match).
const _comicFormats = {'cbz', 'cbr', 'cb7'};

/// Which Absorb features work on the platform this build runs on.
///
/// Upstream Absorb targets Android and iOS; several features call
/// Android-only plugins or method channels. Absorb Plus also ships Windows,
/// Linux and web, so upstream screens ask here (a one-line hook each) before
/// offering such a feature.
///
/// Uses [defaultTargetPlatform] rather than dart:io so it is web-safe and
/// widget tests can switch platforms with `debugDefaultTargetPlatformOverride`.
abstract final class ForkPlatform {
  /// Tests set this to pretend to be (or not be) the web build.
  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get isWeb => debugIsWebOverride ?? kIsWeb;
  static bool get isAndroid =>
      !isWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isLinux =>
      !isWeb && defaultTargetPlatform == TargetPlatform.linux;

  /// The native desktop builds (not web, where the browser owns right-click,
  /// F5 and the back button). Mouse and keyboard extras check this, so
  /// Android and touch behave exactly as upstream.
  static bool get isDesktop =>
      !isWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
  static bool get isWindows =>
      !isWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// `webview_flutter` has only Android (and iOS) implementations in this
  /// build, so an in-app web view would crash on Windows, Linux and web.
  static bool get hasInAppWebView => isAndroid;

  /// Whisper transcription needs the Android audio extractor channel.
  static bool get supportsTranscription => isAndroid;

  /// Clip export uses the Android `com.absorb.clip` channel.
  static bool get supportsClipExport => isAndroid;

  /// Chromecast is wired up only on Android.
  static bool get supportsCast => isAndroid;

  /// Home-screen widgets and Android Auto exist only on Android.
  static bool get hasHomeWidgets => isAndroid;

  // Settings that only do something on a phone. Settings and its search
  // index hide them elsewhere (owner decision, 2026-10-30).

  /// Android Auto: car autoplay, car browse order, car-mode screen.
  static bool get hasCarMode => isAndroid;

  /// Desktop windows and the browser don't rotate.
  static bool get supportsOrientationLock => isAndroid;

  /// Shake-to-reset needs the phone's accelerometer.
  static bool get supportsShakeToReset => isAndroid;

  /// The headphone-button wind-down reset is wired to Android's media session.
  static bool get supportsHeadsetSleepButton => isAndroid;

  /// The Android media notification and Android Auto (chapter progress in
  /// the notification, locked notification seek bar).
  static bool get hasMediaNotification => isAndroid;

  /// The Permissions section (notifications, battery) is Android-only.
  static bool get hasPermissionSettings => isAndroid;

  /// Downloads can go to a plain folder the user picks (Windows, Linux).
  /// Android uses the system folder picker (SAF) instead.
  static bool get supportsDesktopDownloadFolder => isWindows || isLinux;

  /// Whether a reader for ebook format [ext] (lower-case, no dot) works here.
  /// - Web: no reader works (they need local files or a loopback server).
  /// - Linux: `flutter_inappwebview` has no Linux implementation, so the
  ///   EPUB/MOBI readers can't render; PDF and comics are drawn by Flutter.
  /// - Everywhere else: every format the readers support.
  static bool canOpenEbookFormat(String ext) {
    if (isWeb) return false;
    if (isLinux) return ext == 'pdf' || _comicFormats.contains(ext);
    return true;
  }

  /// Card button ids to hide on this platform, on top of upstream's list.
  /// The equalizer stays: it gets a real Windows version later.
  static Set<String> hiddenCardButtons() => {
        if (!supportsCast) 'cast',
        if (!supportsTranscription) 'lyrics',
      };

  /// Opens a link in the system browser. Tests replace it.
  @visibleForTesting
  static Future<bool> Function(Uri uri) launcher = _launchExternal;

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Opens [uri] outside the app (browser, file manager, mail).
  static Future<bool> openExternal(Uri uri) => launcher(uri);

  /// Where there is no in-app web view, opens [url] in the system browser and
  /// returns true, so the caller skips its in-app web view route. Returns
  /// false (and does nothing) where the in-app view works.
  static bool openInBrowserInstead(String url) {
    if (hasInAppWebView) return false;
    final uri = Uri.tryParse(url);
    if (uri != null) unawaited(_launchQuietly(uri));
    return true;
  }

  static Future<void> _launchQuietly(Uri uri) async {
    try {
      await launcher(uri);
    } catch (e) {
      debugPrint('[ForkPlatform] Could not open browser: $e');
    }
  }
}
