import 'dart:io' show Directory, File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../build_info.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../utils/fork_branding.dart';
import '../utils/fork_platform.dart';
import 'overlay_toast.dart';

/// Absorb Plus: the support rows in Settings (owner decision, 2026-10-30).
///
/// "Bugs & feature requests" and "Contact" open the Absorb Plus GitHub issues.
/// "Send logs" saves the log file on desktop (to attach to an issue) and
/// keeps the share sheet on Android, without upstream's support address.
/// Kept out of the upstream LogService so settings_screen only gains hooks.
abstract final class SupportActions {
  /// The folder LogService writes `absorb_logs.txt` into (LogService.init).
  @visibleForTesting
  static Future<Directory> Function() logsDirectory =
      getApplicationDocumentsDirectory;

  /// Asks where to save the log file; null when cancelled. Tests replace it.
  @visibleForTesting
  static Future<String?> Function(String dialogTitle, String fileName)
      pickSavePath = _pickSavePath;

  static Future<String?> _pickSavePath(String dialogTitle, String fileName) =>
      FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        lockParentWindow: true,
      );

  /// Desktop saves the log to a file; Android shares it.
  static bool get savesLogsToFile =>
      !ForkPlatform.isWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> openIssues() async {
    await ForkPlatform.openExternal(Uri.parse(ForkBranding.issuesUrl));
  }

  static Future<void> openProject() async {
    await ForkPlatform.openExternal(Uri.parse(ForkBranding.repoUrl));
  }

  /// Device details put at the top of a log report.
  static String reportHeader({String? serverVersion, DateTime? now}) {
    final buf = StringBuffer()
      ..writeln('${ForkBranding.appName} log report')
      ..writeln('Report issues at: ${ForkBranding.issuesUrl}')
      ..writeln()
      ..writeln('App Version: ${versionWithBeta(ApiService.appVersionFull)}')
      ..writeln(
          'Device: ${ApiService.deviceManufacturer} ${ApiService.deviceModel}')
      ..writeln('Device ID: ${ApiService.deviceId}');
    if (serverVersion != null) buf.writeln('Server Version: $serverVersion');
    buf.writeln('Timestamp: ${(now ?? DateTime.now()).toIso8601String()}');
    return buf.toString();
  }

  /// The log text (already sanitized line by line by LogService when it was
  /// written), or null when there is no log yet.
  static Future<String?> _readLog() async {
    final dir = await logsDirectory();
    final file = File('${dir.path}/absorb_logs.txt');
    if (!await file.exists() || await file.length() == 0) return null;
    return file.readAsString();
  }

  static String _reportText(String header, String? log) =>
      '$header\n${log ?? '(No log file found. Is logging on?)\n'}';

  /// "Send logs": save to a file on desktop, share on Android. Share errors
  /// are rethrown for the caller's existing "Failed to share" toast; desktop
  /// save results are shown here.
  static Future<void> sendLogs(
    BuildContext context, {
    String? serverVersion,
    Rect? sharePositionOrigin,
  }) async {
    final header = reportHeader(serverVersion: serverVersion);
    if (savesLogsToFile) {
      await _saveLogs(context, header);
      return;
    }
    final log = await _readLog();
    final subject = '${ForkBranding.appName} log report';
    if (log == null) {
      await Share.share(_reportText(header, null),
          subject: subject, sharePositionOrigin: sharePositionOrigin);
      return;
    }
    final dir = await logsDirectory();
    final copy = File('${dir.path}/absorb_logs_share.txt');
    await copy.writeAsString(_reportText(header, log));
    await Share.shareXFiles([XFile(copy.path)],
        subject: subject,
        text: 'Report issues at: ${ForkBranding.issuesUrl}',
        sharePositionOrigin: sharePositionOrigin);
  }

  static Future<void> _saveLogs(BuildContext context, String header) async {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final fileName = 'absorb-plus-logs-${now.year}${two(now.month)}'
        '${two(now.day)}-${two(now.hour)}${two(now.minute)}.txt';
    try {
      final path = await pickSavePath(l.supportSaveLogsDialogTitle, fileName);
      if (path == null) return;
      final log = await _readLog();
      await File(path).writeAsString(_reportText(header, log));
      if (context.mounted) {
        showOverlayToast(context, l.supportLogsSaved(path),
            icon: Icons.check_circle_outline_rounded);
      }
    } catch (e) {
      if (context.mounted) {
        showOverlayToast(context, l.supportLogsSaveFailed(e.toString()),
            icon: Icons.error_outline_rounded);
      }
    }
  }

  /// Opens the folder holding the log file in the system file manager.
  static Future<void> openLogsFolder(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    var ok = false;
    try {
      final dir = await logsDirectory();
      ok = await ForkPlatform.openExternal(Uri.directory(dir.path));
    } catch (e) {
      debugPrint('[Support] Could not open logs folder: $e');
    }
    if (!ok && context.mounted) {
      showOverlayToast(context, l.supportOpenLogsFolderFailed,
          icon: Icons.error_outline_rounded);
    }
  }
}

/// Desktop-only Settings row under "Send logs".
class OpenLogsFolderTile extends StatelessWidget {
  const OpenLogsFolderTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListTile(
      leading: Icon(Icons.folder_open_rounded, color: cs.primary),
      title: Text(l.supportOpenLogsFolder),
      subtitle: Text(l.supportOpenLogsFolderSubtitle,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => SupportActions.openLogsFolder(context),
    );
  }
}
