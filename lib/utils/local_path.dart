import 'package:flutter/foundation.dart';

/// Tests set this to pretend to be the web build.
@visibleForTesting
bool? debugLocalPathIsWebOverride;

final _windowsDrive = RegExp(r'^[A-Za-z]:[\\/]');

/// Whether [path] points at a file on this device rather than a URL.
///
/// Offline, `LibraryProvider.getCoverUrl` returns the downloaded cover's
/// file path. Upstream checks that with `startsWith('/')`, which misses
/// Windows paths (`C:\...`, `\\server\share\...`), so offline covers on
/// Windows went to the network image loader and showed placeholders.
///
/// Accepts POSIX paths, Windows drive and UNC paths, and `file://` URIs.
/// Always false on the web, which has no local files.
bool isLocalFilePath(String? path) {
  if (path == null || path.isEmpty) return false;
  if (debugLocalPathIsWebOverride ?? kIsWeb) return false;
  return path.startsWith('/') ||
      path.startsWith(r'\\') ||
      _windowsDrive.hasMatch(path) ||
      path.startsWith('file://');
}

/// [path] as a plain file path: a `file://` URI becomes the OS path, anything
/// else is returned unchanged. (No cover source produces `file://` today;
/// this is for callers that may receive one.)
String localFilePath(String path) {
  if (!path.startsWith('file://')) return path;
  try {
    return Uri.parse(path).toFilePath();
  } catch (_) {
    return path;
  }
}

/// The cover-specific name for [isLocalFilePath].
bool isLocalCoverPath(String? coverUrl) => isLocalFilePath(coverUrl);
