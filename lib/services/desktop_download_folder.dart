import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../utils/fork_platform.dart';
import 'download_track_names.dart' show folderIdSuffix;

/// The download folder a Windows or Linux user picks (Absorb Plus).
///
/// Android picks its folder through the system picker (SAF) and keeps that in
/// `DownloadService.customDownloadUri`. Desktop has plain paths instead, so
/// this keeps one absolute folder path. Only **new** downloads use it:
/// existing downloads keep their saved absolute paths and stay where they are.
/// Nothing is moved, and with no folder picked downloads go where they always
/// went (the app's documents folder).
abstract final class DesktopDownloadFolder {
  /// SharedPreferences key for the picked folder (absent = default folder).
  static const prefKey = 'desktop_download_dir';

  /// Shows the system folder picker. Tests replace it.
  @visibleForTesting
  static Future<String?> Function({String? title, String? initialDirectory})
  picker = _pickWithFilePicker;

  static Future<String?> _pickWithFilePicker({
    String? title,
    String? initialDirectory,
  }) => FilePicker.platform.getDirectoryPath(
    dialogTitle: title,
    initialDirectory: initialDirectory,
    lockParentWindow: true,
  );

  /// Lets the user choose a folder. Null when they cancel.
  static Future<String?> pick({String? title, String? initialDirectory}) =>
      picker(title: title, initialDirectory: initialDirectory);

  /// The folder new downloads go to, or null for the default location:
  /// - on Android, iOS and web this is always null (they don't use it);
  /// - a saved folder that no longer exists (an unplugged drive, a deleted
  ///   folder) also gives null, so downloads fall back to the default folder
  ///   instead of failing or recreating the path on another drive.
  static String? activeRoot(String? saved) {
    if (!ForkPlatform.supportsDesktopDownloadFolder) return null;
    if (saved == null || saved.trim().isEmpty) return null;
    try {
      return Directory(saved).existsSync() ? saved : null;
    } catch (_) {
      return null;
    }
  }

  /// Where a new book goes inside the picked [root]: `root/Author/Title`.
  ///
  /// The picked folder can be one the user already keeps audiobooks in. When
  /// a non-empty folder of that name is already there, the book gets its own
  /// `Title (id)` folder instead, so deleting the download later can never
  /// remove files the app didn't put there.
  static String bookDirPath(String root, String nestedName, String itemId) {
    final path = '$root/$nestedName';
    try {
      final dir = Directory(path);
      if (dir.existsSync() && dir.listSync().isNotEmpty) {
        return '$path (${folderIdSuffix(itemId)})';
      }
    } catch (_) {}
    return path;
  }

  /// True when [path] is the picked download folder itself. Cleanup that
  /// removes empty parent folders must leave the picked folder alone.
  static bool isRoot(String path, String? root) {
    if (root == null || root.isEmpty) return false;
    return _normalize(path) == _normalize(root);
  }

  static String _normalize(String path) {
    var p = path.replaceAll('\\', '/');
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return ForkPlatform.isWindows ? p.toLowerCase() : p;
  }

  /// True when [path] is on a Windows drive that isn't there right now (an
  /// unplugged USB disk). Startup checks skip such downloads instead of
  /// forgetting them, so they work again once the drive is back.
  static bool isOnMissingDrive(String path, {bool Function(String)? exists}) {
    if (!ForkPlatform.isWindows) return false;
    final m = RegExp(r'^([A-Za-z]):[\\/]').firstMatch(path);
    if (m == null) return false;
    final root = '${m.group(1)}:\\';
    try {
      return !(exists ?? (p) => Directory(p).existsSync())(root);
    } catch (_) {
      return false;
    }
  }

  /// [path] the way the system shows it (backslashes on Windows).
  static String displayPath(String path) =>
      ForkPlatform.isWindows ? path.replaceAll('/', '\\') : path;

  /// Whether the app can create and delete a file in [path]. Checked before a
  /// picked folder is saved, so downloads don't fail later.
  static Future<bool> isWritable(String path) async {
    final probe = File(
      '$path${Platform.pathSeparator}.absorb_write_test_${Random().nextInt(1 << 30)}',
    );
    try {
      if (!await Directory(path).exists()) return false;
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (e) {
      debugPrint('[DesktopDownloadFolder] folder is not writable: $e');
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Opens [path] in Explorer (Windows) or the file manager (Linux).
  static Future<bool> open(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      return await ForkPlatform.openExternal(Uri.directory(path));
    } catch (e) {
      debugPrint('[DesktopDownloadFolder] could not open the folder: $e');
      return false;
    }
  }
}
