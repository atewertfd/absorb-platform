import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'update_check_policy.dart';
import 'update_policy.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool isPreRelease;
  final bool isDirectApk;
  final bool isWindowsInstaller;
  final String? packageLabel;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    this.releaseNotes = '',
    this.isPreRelease = false,
    this.isDirectApk = true,
    this.isWindowsInstaller = false,
    this. packageLabel,
  });

  bool get hasUpdate =>
      compareUpdateVersions(latestVersion, currentVersion) > 0;

  /// Which beta the release is, read from the "## Beta N" heading the release
  /// notes open with. Null for full releases or notes without that line.
  int? get latestBetaNumber => betaNumberFromReleaseNotes(releaseNotes);
}

enum UpdateCheckStatus {
  updateAvailable,
  upToDate,

  /// GitHub could not be reached or answered with an error.
  failed,

  /// Not checked: inside the cooldown, or the update was dismissed.
  skipped,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateInfo? info;

  /// Installed version (`1.11.1+300`), when it was read.
  final String? currentVersion;

  const UpdateCheckResult(this.status, {this.info, this.currentVersion});
}

/// Pulls N out of a "## Beta N" heading in GitHub release notes.
int? betaNumberFromReleaseNotes(String notes) {
  final m = RegExp(r'^#+\s*Beta\s+(\d+)\b', multiLine: true, caseSensitive: false)
      .firstMatch(notes);
  return m == null ? null : int.tryParse(m.group(1)!);
}

class UpdateCheckerService {
  // Keep the fork updater on the fork's releases. The distinct application ID
  // prevents Android from offering these APKs as updates to official Absorb.
  static const _repo = 'atewertfd/absorb-platform';
  static const _checkInterval = Duration(hours: 12);
  static const _dismissedKey = 'update_dismissed_version';
  static const _lastCheckKey = 'update_last_check';
  static const _updateChannel = MethodChannel('com.absorb.update');
  static final InFlightUpdateCheck<UpdateCheckResult> _inFlightCheck =
      InFlightUpdateCheck<UpdateCheckResult>();
  // A manual "Check for update" must not be handed a running automatic
  // check's result, which can be `skipped` (cooldown or dismissed version).
  static final InFlightUpdateCheck<UpdateCheckResult> _inFlightForcedCheck =
      InFlightUpdateCheck<UpdateCheckResult>();

  /// The check itself; tests swap it to observe how calls are shared.
  @visibleForTesting
  static Future<UpdateCheckResult> Function({
    required bool force,
    required bool includePreReleases,
    Duration? cooldown,
  }) runCheck = _checkInternal;

  /// Whether this Windows copy was installed by the Inno Setup installer;
  /// a portable copy updates from the release page instead.
  @visibleForTesting
  static bool Function() isInstalledWindowsCopy = () => isInnoSetupInstall(
        Platform.resolvedExecutable,
        (path) => File(path).existsSync(),
      );

  static Future<String> currentInstalledVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    int? baseBuildNumber;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        baseBuildNumber =
            await _updateChannel.invokeMethod<int>('getBaseBuildNumber');
      } catch (error) {
        debugPrint('[UpdateChecker] Base build lookup failed: $error');
      }
    }
    return currentUpdateVersion(
      versionName: packageInfo.version,
      packageBuildNumber: packageInfo.buildNumber,
      baseBuildNumber: baseBuildNumber,
    );
  }

  /// Check for updates, reporting whether an update exists, the app is up to
  /// date, or GitHub couldn't be reached. Respects a 12-hour cooldown and
  /// dismissed versions unless [force]. When [includePreReleases] is true,
  /// pre-release builds are also considered.
  static Future<UpdateCheckResult> check({bool force = false, bool includePreReleases = false, }) {
    return (force ? _inFlightForcedCheck : _inFlightCheck).run(
      () =>
          runCheck(force: force, includePreReleases: includePreReleases),
    );
  }

  /// Checks according to the saved automatic schedule. Manual calls to
  /// [check] remain independent and can always bypass the schedule.
  static Future<UpdateInfo?> checkAutomatically({
    bool includePreReleases = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final frequency = updateCheckFrequencyFromKey(
      prefs.getString(updateCheckFrequencyPreferenceKey),
    );
    final lastCheck = prefs.getInt(_lastCheckKey);
    final lastChecked = lastCheck == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastCheck);
    final interval = updateCheckInterval(frequency);
    if (!isUpdateCheckDue(
      frequency: frequency,
      now: DateTime.now(),
      lastChecked: lastChecked,
    )) {
      return null;
    }

    final result = await _inFlightCheck.run(
      () => runCheck(
        force: false,
        includePreReleases: includePreReleases,
        cooldown: interval,
      ),
    );
    return result.info;
  }

  static Future<UpdateCheckResult> _checkInternal({
    required bool force,
    required bool includePreReleases,
    Duration? cooldown,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Cooldown check (skip if forced)
      if (!force) {
        final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheck;
        final effectiveCooldown = cooldown ?? _checkInterval;
        if (elapsed < effectiveCooldown.inMilliseconds) {
          return const UpdateCheckResult(UpdateCheckStatus.skipped);
      }

      }

      final target = kIsWeb
          ? UpdateTarget.other
          : Platform.isAndroid
          ? UpdateTarget.android
          : Platform.isWindows
          ? (isInstalledWindowsCopy()
              ? UpdateTarget.windowsInstalled
              : UpdateTarget.windowsPortable)
          : UpdateTarget.other;
      List<String> supportedAbis = const [];
      if (target == UpdateTarget.android) {
        try {
          supportedAbis =
              (await DeviceInfoPlugin().androidInfo).supportedAbis;
        } catch (error) {
          debugPrint('[UpdateChecker] ABI detection failed: $error');
        }
      }
      bool hasPlatformAsset(List<UpdateReleaseAsset> assets) =>
          releaseHasUpdateAsset(
            target: target,
            assets: assets,
            supportedAbis: supportedAbis,
          );

      Map<String, dynamic>? data;

      if (includePreReleases) {
        // Fetch recent releases and pick the highest version, which may be a
        // pre-release.
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=10'),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          return const UpdateCheckResult(UpdateCheckStatus.failed);
        }
        // Only start the automatic cooldown after GitHub answered. A
        // transient offline/5xx response should be retried on the next app
        // start instead of suppressing checks for the full interval.
        await prefs.setInt(
          _lastCheckKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        final releases = (jsonDecode(response.body) as List<dynamic>).whereType< Map<String, dynamic>>()
            .toList();
      data = pickUpdateRelease(
          releases,
          hasPlatformAsset: hasPlatformAsset,
        );
        if (data == null) {
          return UpdateCheckResult(
            UpdateCheckStatus.upToDate,
            currentVersion: await currentInstalledVersion(),
          );
        }
      } else {
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          return const UpdateCheckResult(UpdateCheckStatus.failed);
        }
        // Only start the automatic cooldown after GitHub answered. A
        // transient offline/5xx response should be retried on the next app
        // start instead of suppressing checks for the full interval.
        await prefs.setInt(
          _lastCheckKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        data = jsonDecode(response.body) as Map<String, dynamic>;
        // CI creates the release before it uploads the files; offer it on
        // the next check, once this platform's file is there.
        if (!hasPlatformAsset(releaseAssetsOf(data))) {
          return UpdateCheckResult(
            UpdateCheckStatus.upToDate,
            currentVersion: await currentInstalledVersion(),
          );
        }
      }

      final tagName = data['tag_name'] as String? ?? '';
      final body = data['body'] as String? ?? '';
      final isPreRelease = data['prerelease'] as bool? ?? false;

      final releaseAssets = releaseAssetsOf(data);

      // Only Android gets an APK and only an installed Windows copy gets the
      // installer; everything else opens the release page.
      final platformAsset = selectUpdateAsset(
        target: target,
        assets: releaseAssets,
        supportedAbis: supportedAbis,
      );
      final selectedAsset =
          target == UpdateTarget.android ? platformAsset : null;
      final selectedWindowsAsset =
          target == UpdateTarget.windowsInstalled ? platformAsset : null;
      final selectedDirectAsset = selectedWindowsAsset ?? selectedAsset;
      final currentVersion = await currentInstalledVersion();
      final downloadUrl = selectedDirectAsset?.downloadUrl ??
          data['html_url'] as String? ??
          '';
      if (selectedDirectAsset != null) {
        debugPrint(
          '[UpdateChecker] Selected ${selectedDirectAsset.name} for '
          '${selectedWindowsAsset != null ? 'Windows' : supportedAbis.join(', ')}',
        );
      }

      final info = UpdateInfo(
        latestVersion: tagName,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl,
        releaseNotes: body,
        isPreRelease: isPreRelease,
        isDirectApk: selectedAsset != null,
        isWindowsInstaller: selectedWindowsAsset != null,
        packageLabel: selectedDirectAsset == null
            ? null
            : selectedWindowsAsset != null
            ? 'Windows installer'
            : androidUpdatePackageLabel(selectedAsset!),
      );

      if (!info.hasUpdate) {
        return UpdateCheckResult(
          UpdateCheckStatus.upToDate,
          currentVersion: currentVersion,
        );

      }

      // Check if user dismissed this version
      if (!force) {
        final dismissed = prefs.getString(_dismissedKey);
        if (dismissed == tagName) {
          return const UpdateCheckResult(UpdateCheckStatus.skipped);
      }

      }

      return UpdateCheckResult(
        UpdateCheckStatus.updateAvailable,
        info: info,
        currentVersion: currentVersion,
      );
    } catch (e) {
      debugPrint('[UpdateChecker] Error: $e');
      return const UpdateCheckResult(UpdateCheckStatus.failed);
    }
  }

  /// Dismiss the update prompt for a specific version.
  static Future<void> dismiss(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, version);
  }
}

enum ApkInstallStatus {
  ok,
  downloadFailed,
  permissionDenied,
  launchFailed,
  cancelled,
}

class ApkInstallResult {
  final ApkInstallStatus status;
  final String? message;
  const ApkInstallResult(this.status, [this.message]);
}

/// Downloads the APK in-app and hands it to the system installer.
///
/// Why: launching the URL in a browser leaves Chrome holding the APK in its
/// SafeBrowsing "scanning" limbo - the download bar hits 100% and never
/// finalises. Pulling the bytes ourselves and opening the file with
/// open_filex bypasses the browser entirely.
class ApkUpdater {
  static UpdateDownload? _active;

  static Future<ApkInstallResult> downloadAndInstall(
    UpdateInfo info, {
    required void Function(int received, int total) onProgress,
  }) async {
    if (!Platform.isAndroid) {
      return const ApkInstallResult(ApkInstallStatus.launchFailed, 'Android only');
    }

    // Registered before the first await so Cancel always reaches it.
    final download = UpdateDownload(http.Client());
    _active = download;
    final perm = await Permission.requestInstallPackages.request();
    if (!perm.isGranted) {
      if (identical(_active, download)) _active = null;
      download.cancel();
      return const ApkInstallResult(ApkInstallStatus.permissionDenied);
    }

    final File file;
    try {
      file = await _download(download, info, onProgress);
    } on _CancelledException {
      return const ApkInstallResult(ApkInstallStatus.cancelled);
    } catch (e) {
      debugPrint('[ApkUpdater] Download failed: $e');
      return ApkInstallResult(ApkInstallStatus.downloadFailed, e.toString());
    }

    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      debugPrint('[ApkUpdater] OpenFilex failed: ${result.type} ${result.message}');
      return ApkInstallResult(ApkInstallStatus.launchFailed, result.message);
    }
    return const ApkInstallResult(ApkInstallStatus.ok);
  }

  /// Cancel an in-flight download started by [downloadAndInstall].
  static void cancel() {
    _active?.cancel();
    _active = null;
  }

  static Future<File> _download(
    UpdateDownload download,
    UpdateInfo info,
    void Function(int, int) onProgress,
  ) async {
    try {
    final dir = await getTemporaryDirectory();
    final filename = Uri.parse(info.downloadUrl).pathSegments.last;
    final file = File('${dir.path}/$filename');
      return await download.run(Uri.parse(info.downloadUrl), file, onProgress);
    } finally {
      if (identical(_active, download)) _active = null;
      download.close();
    }
  }
}

enum WindowsInstallStatus { ok, downloadFailed, launchFailed, cancelled }

class WindowsInstallResult {
  final WindowsInstallStatus status;
  final String? message;

  const WindowsInstallResult(this.status, [this.message]);
}

/// Downloads and launches the Inno Setup installer for a Windows update.
///
/// Absorb exits after starting the detached installer so the installer can
/// replace the running executable. Inno Setup reuses the existing AppId and
/// install directory, preserving the application registration and user data.
class WindowsUpdater {
  static UpdateDownload? _active;

  static Future<WindowsInstallResult> downloadAndLaunch(
    UpdateInfo info, {
    required void Function(int received, int total) onProgress,
  }) async {
    if (!Platform.isWindows) {
      return const WindowsInstallResult(
        WindowsInstallStatus.launchFailed,
        'Windows only',
      );
    }

    final download = UpdateDownload(http.Client());
    _active = download;
    final File file;
    try {
      file = await _download(download, info, onProgress);
    } on _CancelledException {
      return const WindowsInstallResult(WindowsInstallStatus.cancelled);
    } catch (error) {
      debugPrint('[WindowsUpdater] Download failed: $error');
      return WindowsInstallResult(
        WindowsInstallStatus.downloadFailed,
        error.toString(),
      );
    }

    try {
      await Process.start(
        file.path,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      debugPrint('[WindowsUpdater] Installer launch failed: $error');
      return WindowsInstallResult(
        WindowsInstallStatus.launchFailed,
        error.toString(),
      );
    }

    // Give the detached installer time to open before the Flutter process
    // exits. The installer owns the rest of the update flow.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(0);
  }

  static void cancel() {
    _active?.cancel();
    _active = null;
  }

  static Future<File> _download(
    UpdateDownload download,
    UpdateInfo info,
    void Function(int, int) onProgress,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final rawName = Uri.parse(info.downloadUrl).pathSegments.last;
      final filename = rawName.isEmpty ? 'Absorb-Update-Setup.exe' : rawName;
      final file = File('${dir.path}/$filename');
      return await download.run(Uri.parse(info.downloadUrl), file, onProgress);
    } finally {
      if (identical(_active, download)) _active = null;
      download.close();
    }
  }
}

/// One cancellable download of an update file.
///
/// [cancel] closes the HTTP client, which makes the response stream fail with
/// a `ClientException` rather than stopping cleanly. The cancelled flag turns
/// any such failure back into a cancellation, so the dialog doesn't treat it
/// as a failed download and open the browser. A partial file is deleted on
/// failure or cancel.
class UpdateDownload {
  UpdateDownload(this._client);

  final http.Client _client;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Whether [error], thrown by [run], means the user cancelled.
  @visibleForTesting
  static bool isCancellation(Object error) => error is _CancelledException;

  void cancel() {
    _cancelled = true;
    _client.close();
  }

  void close() => _client.close();

  Future<File> run(
    Uri url,
    File file,
    void Function(int received, int total) onProgress,
  ) async {
    try {
      if (_cancelled) throw const _CancelledException();
      if (await file.exists()) await file.delete();

    final response = await _client.send(http.Request('GET', url));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          if (_cancelled)
            throw const _CancelledException();
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      // Cancel pressed as the last bytes arrived: still a cancel, so the
      // installer isn't launched behind the closed dialog.
      if (_cancelled) throw const _CancelledException();
      return file;
    } catch (_) {
      try {
      if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[UpdateDownload] Could not delete partial file: $error');
      }
      if (_cancelled) throw const _CancelledException();
      rethrow;
    } finally {
      _client.close();
    }
  }
}

class _CancelledException implements Exception {
  const _CancelledException();
}
