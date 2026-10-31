import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The home shelves (Audiobookshelf's personalized view) from the last
/// successful load, kept on disk per account and library so a cold start
/// paints Home at once instead of a spinner. The server's answer replaces
/// them as soon as it arrives (`loadPersonalizedView`).
///
/// Stored in app support storage (not prefs: the view can be a few hundred
/// KB), decoded off the UI thread. Never on web. A missing or unreadable
/// snapshot is just a normal cold start.
class HomeShelfSnapshot {
  HomeShelfSnapshot({Future<Directory> Function()? baseDirectory})
      : _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  static final HomeShelfSnapshot instance = HomeShelfSnapshot();

  final Future<Directory> Function() _baseDirectory;

  /// Snapshots older than this aren't shown: the shelves would be too far
  /// from the truth to be worth the flash of old content.
  static const maxAge = Duration(days: 14);

  Future<File> _file(String scope, String libraryId) async {
    final base = await _baseDirectory();
    final name = sha1.convert(utf8.encode('$scope|$libraryId')).toString();
    return File('${base.path}${Platform.pathSeparator}home_shelves'
        '${Platform.pathSeparator}$name.json');
  }

  Future<List<dynamic>?> load(String scope, String libraryId) async {
    if (kIsWeb) return null;
    try {
      final file = await _file(scope, libraryId);
      if (!await file.exists()) return null;
      final age = DateTime.now().difference(await file.lastModified());
      if (age > maxAge) return null;
      final text = await file.readAsString();
      final decoded = await compute(_decodeList, text);
      return decoded;
    } catch (e) {
      debugPrint('[HomeSnapshot] load failed: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> save(
      String scope, String libraryId, List<dynamic> sections) async {
    if (kIsWeb) return;
    try {
      final text = await compute(jsonEncode, sections);
      final file = await _file(scope, libraryId);
      await file.parent.create(recursive: true);
      // Write then rename, so a crash mid-write never leaves half a file.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[HomeSnapshot] save failed: ${e.runtimeType}');
    }
  }
}

List<dynamic>? _decodeList(String text) {
  final value = jsonDecode(text);
  return value is List ? value : null;
}
