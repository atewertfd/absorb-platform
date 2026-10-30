import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

const String kLibationExecutablePathPref = 'libation_executable_path';
const String kLibationOutputFolderPref = 'libation_output_folder_path';
const String kLibationImportedFoldersPref = 'libation_imported_folders';
const String kLibationLastSeenExportPref = 'libation_last_seen_export_ms';

/// Bound on remembered imported folders so the preference stays small.
const int kLibationImportedFoldersLimit = 1000;

/// Without a saved "last seen" time, only exports this recent count as new,
/// so a first scan of a large library doesn't report hundreds of new books.
const Duration kLibationFirstRunNewWindow = Duration(days: 3);

const Set<String> kLibationAudioExtensions = <String>{
  'm4b',
  'mp3',
  'm4a',
  'flac',
  'opus',
  'ogg',
  'oga',
  'mp4',
  'aac',
  'wma',
  'aiff',
  'aif',
  'wav',
  'webm',
  'webma',
  'mka',
  'awb',
  'caf',
  'mpeg',
  'mpg',
};

const Set<String> kLibationCoverExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'webp',
};

/// Export handoff only: never select Libation account/configuration files or
/// protected containers.
const Set<String> kLibationExportExtensions = <String>{
  ...kLibationAudioExtensions,
  ...kLibationCoverExtensions,
};

final RegExp _trailingAsinTagPattern = RegExp(
  r'\s*\[[A-Za-z0-9_-]{8,14}\]\s*$',
);

final RegExp _asinPattern = RegExp(r'\[([A-Z0-9]{10})\]\s*$');

/// The Audible ASIN from a Libation folder or file name such as
/// `Title [B08G9PRS1K]`, or null when the name carries none.
String? libationAsinFrom(String name) {
  final trimmed = name.trim();
  // Only drop a real audio extension: folder names like "Dr. Who [B0…]" keep
  // their dots.
  final base = isLibationAudioFile(trimmed)
      ? stripFileExtension(trimmed)
      : trimmed;
  return _asinPattern.firstMatch(base.trim())?.group(1);
}

String libationFileExtension(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return '';
  return filename.substring(dot + 1).toLowerCase();
}

bool isLibationAudioFile(String filename) =>
    kLibationAudioExtensions.contains(libationFileExtension(filename));

bool isLibationCoverFile(String filename) =>
    kLibationCoverExtensions.contains(libationFileExtension(filename));

bool isLibationExportFile(String filename) =>
    kLibationExportExtensions.contains(libationFileExtension(filename));

String stripFileExtension(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot > 0 ? filename.substring(0, dot) : filename;
}

String pathBasename(String path) {
  final normalized = path.replaceAll(RegExp(r'[\\/]+$'), '');
  if (normalized.isEmpty) return '';
  final slash = normalized.lastIndexOf(RegExp(r'[\\/]'));
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

String pathDirname(String path) {
  final normalized = path.replaceAll(RegExp(r'[\\/]+$'), '');
  if (normalized.isEmpty) return '';
  final slash = normalized.lastIndexOf(RegExp(r'[\\/]'));
  return slash <= 0 ? '' : normalized.substring(0, slash);
}

/// Clean a folder or file name produced by Libation (such as stripping a
/// trailing `[B000123456]` ASIN tag) without losing the human-readable title.
String cleanLibationBookTitle(String rawName) {
  final trimmed = rawName.trim();
  if (trimmed.isEmpty) return '';
  final withoutTag = trimmed.replaceFirst(_trailingAsinTagPattern, '').trim();
  return withoutTag.isEmpty ? trimmed : withoutTag;
}

/// Infer a book title from selected primary files.
/// - Single primary file: strips the file extension and any trailing
///   Libation `[ASIN]` tag.
/// - Multiple primary files sharing a parent directory path: uses the cleaned
///   parent folder name.
String? inferTitleFromSelectedFiles(List<MediaUploadFile> primaryFiles) {
  if (primaryFiles.isEmpty) return null;
  if (primaryFiles.length == 1) {
    return cleanLibationBookTitle(stripFileExtension(primaryFiles.single.name));
  }
  String? sharedParent;
  for (final file in primaryFiles) {
    final filePath = file.path;
    if (filePath == null || filePath.isEmpty) return null;
    final parent = pathDirname(filePath);
    if (parent.isEmpty) return null;
    if (sharedParent == null) {
      sharedParent = parent;
    } else if (sharedParent != parent) {
      return null;
    }
  }
  if (sharedParent == null) return null;
  final folderTitle = cleanLibationBookTitle(pathBasename(sharedParent));
  return folderTitle.isEmpty ? null : folderTitle;
}

class LibationBookCandidate {
  final String directoryPath;
  final String title;
  final String? author;
  final List<MediaUploadFile> files;
  final int skippedFilesCount;

  /// Newest modification time among the book's audio files, used to list the
  /// most recent Libation export first.
  final DateTime? modified;

  const LibationBookCandidate({
    required this.directoryPath,
    required this.title,
    this.author,
    required this.files,
    this.skippedFilesCount = 0,
    this.modified,
  });

  int get audioFileCount =>
      files.where((file) => isLibationAudioFile(file.name)).length;

  int get totalBytes => files.fold<int>(0, (sum, file) => sum + file.size);

  /// ASIN from the export folder name, else from the first audio file name.
  String? get asin {
    final fromFolder = libationAsinFrom(pathBasename(directoryPath));
    if (fromFolder != null) return fromFolder;
    for (final file in files) {
      if (isLibationAudioFile(file.name)) return libationAsinFrom(file.name);
    }
    return null;
  }
}

/// Folder-path key used to remember imported exports (case-insensitive on
/// Windows, separator-agnostic).
String libationFolderKey(String directoryPath) =>
    _normalizeComparePath(directoryPath);

/// Exports to call out as new: not imported through Absorb yet, and written
/// after [lastSeen] (or within [kLibationFirstRunNewWindow] of [now] when the
/// picker has never been opened).
List<LibationBookCandidate> newLibationExports(
  List<LibationBookCandidate> candidates, {
  required Set<String> importedFolders,
  required DateTime? lastSeen,
  required DateTime now,
}) {
  final threshold = lastSeen ?? now.subtract(kLibationFirstRunNewWindow);
  return candidates.where((candidate) {
    final modified = candidate.modified;
    if (modified == null || !modified.isAfter(threshold)) return false;
    return !importedFolders.contains(
      libationFolderKey(candidate.directoryPath),
    );
  }).toList();
}

class LibationImportHistory {
  final Set<String> importedFolders;
  final DateTime? lastSeen;

  const LibationImportHistory({required this.importedFolders, this.lastSeen});

  static Future<LibationImportHistory> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenMs = prefs.getInt(kLibationLastSeenExportPref);
      return LibationImportHistory(
        importedFolders: {
          ...?prefs.getStringList(kLibationImportedFoldersPref),
        },
        lastSeen: lastSeenMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastSeenMs),
      );
    } catch (_) {
      return const LibationImportHistory(importedFolders: <String>{});
    }
  }

  /// Remember an export folder after Audiobookshelf accepted its upload.
  static Future<void> recordImported(String directoryPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = libationFolderKey(directoryPath);
      final folders = [...?prefs.getStringList(kLibationImportedFoldersPref)]
        ..remove(key);
      folders.add(key);
      final start = folders.length > kLibationImportedFoldersLimit
          ? folders.length - kLibationImportedFoldersLimit
          : 0;
      await prefs.setStringList(
        kLibationImportedFoldersPref,
        folders.sublist(start),
      );
    } catch (_) {}
  }

  /// Mark exports up to [newest] as seen once the user has been shown them.
  static Future<void> markSeen(DateTime newest) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(kLibationLastSeenExportPref) ?? 0;
      final next = newest.millisecondsSinceEpoch;
      if (next > current) {
        await prefs.setInt(kLibationLastSeenExportPref, next);
      }
    } catch (_) {}
  }
}

/// Counts new exports in the saved Libation output folder. Returns 0 when no
/// folder is saved, on web, or when the folder can't be read. Only lists
/// directories and file sizes/dates; never opens a file.
Future<int> countNewExportsInSavedLibationFolder({DateTime? now}) async {
  if (kIsWeb) return 0;
  try {
    final prefs = await SharedPreferences.getInstance();
    final folder = prefs.getString(kLibationOutputFolderPref)?.trim() ?? '';
    if (folder.isEmpty) return 0;
    final history = await LibationImportHistory.load();
    final candidates = await scanLibationExportDirectory(folder);
    return newLibationExports(
      candidates,
      importedFolders: history.importedFolders,
      lastSeen: history.lastSeen,
      now: now ?? DateTime.now(),
    ).length;
  } catch (_) {
    return 0;
  }
}

String _normalizeLibraryTitle(String title) => cleanLibationBookTitle(
  title,
).toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
// Letters and digits of any script count, so a Hebrew or Cyrillic title is
// not reduced to nothing (or to a bare number that matches other books).

/// The title of a book in an Audiobookshelf library search result
/// (`{book: [{libraryItem: {media: {metadata: {...}}}}]}`) that matches
/// [candidate] by ASIN, or else by normalized title. Null when none match.
String? matchingLibraryBookTitle(
  Map<String, dynamic>? searchResult,
  LibationBookCandidate candidate, {
  String? title,
}) {
  final books = searchResult?['book'];
  if (books is! List) return null;
  final asin = candidate.asin?.toUpperCase();
  final wantedTitle = _normalizeLibraryTitle(title ?? candidate.title);
  String? titleMatch;
  for (final entry in books) {
    if (entry is! Map) continue;
    final item = entry['libraryItem'];
    final media = item is Map ? item['media'] : null;
    final metadata = media is Map ? media['metadata'] : null;
    if (metadata is! Map) continue;
    final bookTitle = metadata['title']?.toString() ?? '';
    final bookAsin = metadata['asin']?.toString().trim().toUpperCase() ?? '';
    if (asin != null && bookAsin.isNotEmpty && bookAsin == asin) {
      return bookTitle.isEmpty ? candidate.title : bookTitle;
    }
    if (titleMatch == null &&
        wantedTitle.isNotEmpty &&
        _normalizeLibraryTitle(bookTitle) == wantedTitle) {
      titleMatch = bookTitle;
    }
  }
  return titleMatch;
}

/// Scan a user-selected directory for exported Libation audiobooks.
///
/// Safety guarantees:
/// - Only inspects the directory explicitly provided by the caller.
/// - Never opens or reads the contents of any file during scanning.
/// - Filters out account/configuration files (`.json`, `.db`, etc.) and
///   protected containers (`.aax`, `.aaxc`, `.voucher`, etc.) by extension.
///
/// Results are ordered newest export first, so a book just downloaded in
/// Libation is at the top even in a large output folder.
Future<List<LibationBookCandidate>> scanLibationExportDirectory(
  String directoryPath, {
  int maxDepth = 3,
  int maxCandidates = 2000,
}) async {
  if (kIsWeb || directoryPath.trim().isEmpty) {
    return const <LibationBookCandidate>[];
  }
  final rootDir = Directory(directoryPath);
  if (!await rootDir.exists()) {
    return const <LibationBookCandidate>[];
  }

  final rootNormalized = _normalizeComparePath(rootDir.path);
  final candidates = <LibationBookCandidate>[];

  Future<void> visit(Directory dir, int depth) async {
    if (candidates.length >= maxCandidates || depth > maxDepth) return;

    List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: false).toList();
    } catch (_) {
      return;
    }

    final audioFiles = <MediaUploadFile>[];
    final coverFiles = <MediaUploadFile>[];
    final subdirs = <Directory>[];
    var skipped = 0;
    DateTime? newestAudio;

    for (final entity in entities) {
      final name = pathBasename(entity.path);
      if (name.isEmpty || name.startsWith('.')) continue;
      if (entity is Directory) {
        subdirs.add(entity);
      } else if (entity is File) {
        if (isLibationAudioFile(name)) {
          try {
            final stat = await entity.stat();
            audioFiles.add(
              MediaUploadFile(name: name, size: stat.size, path: entity.path),
            );
            if (newestAudio == null || stat.modified.isAfter(newestAudio)) {
              newestAudio = stat.modified;
            }
          } catch (_) {}
        } else if (isLibationCoverFile(name)) {
          try {
            final stat = await entity.stat();
            coverFiles.add(
              MediaUploadFile(name: name, size: stat.size, path: entity.path),
            );
          } catch (_) {}
        } else {
          skipped++;
        }
      }
    }

    if (audioFiles.isNotEmpty) {
      audioFiles.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      coverFiles.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      final folderTitle = cleanLibationBookTitle(pathBasename(dir.path));
      final singleFileTitle = audioFiles.length == 1
          ? cleanLibationBookTitle(stripFileExtension(audioFiles.single.name))
          : '';
      final resolvedTitle = singleFileTitle.isNotEmpty
          ? singleFileTitle
          : (folderTitle.isNotEmpty ? folderTitle : 'Audiobook');

      String? inferredAuthor;
      final dirNormalized = _normalizeComparePath(dir.path);
      if (dirNormalized != rootNormalized) {
        final parentPath = pathDirname(dir.path);
        final parentNormalized = _normalizeComparePath(parentPath);
        if (parentNormalized.isNotEmpty && parentNormalized != rootNormalized) {
          final parentName = cleanLibationBookTitle(pathBasename(parentPath));
          if (parentName.isNotEmpty && parentName != resolvedTitle) {
            inferredAuthor = parentName;
          }
        }
      }

      candidates.add(
        LibationBookCandidate(
          directoryPath: dir.path,
          title: resolvedTitle,
          author: inferredAuthor,
          files: <MediaUploadFile>[...audioFiles, ...coverFiles],
          skippedFilesCount: skipped,
          modified: newestAudio,
        ),
      );
    }

    if (depth < maxDepth && candidates.length < maxCandidates) {
      subdirs.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      for (final subdir in subdirs) {
        if (candidates.length >= maxCandidates) break;
        await visit(subdir, depth + 1);
      }
    }
  }

  await visit(rootDir, 0);
  candidates.sort(compareLibationCandidatesNewestFirst);
  return candidates;
}

/// Newest export first; undated candidates last; ties keep path order.
int compareLibationCandidatesNewestFirst(
  LibationBookCandidate a,
  LibationBookCandidate b,
) {
  final am = a.modified;
  final bm = b.modified;
  if (am != null && bm != null) {
    final byDate = bm.compareTo(am);
    if (byDate != 0) return byDate;
  } else if (am != null) {
    return -1;
  } else if (bm != null) {
    return 1;
  }
  return a.directoryPath.toLowerCase().compareTo(b.directoryPath.toLowerCase());
}

String _normalizeComparePath(String path) {
  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '').replaceAll('\\', '/');
  return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
}

/// Launch a user-selected Libation desktop executable without arguments,
/// credential inspection, or environment modification.
Future<bool> launchLibationExecutable(String executablePath) async {
  if (kIsWeb) return false;
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return false;
  }
  final trimmed = executablePath.trim();
  if (trimmed.isEmpty) return false;

  final ext = libationFileExtension(trimmed);
  if (Platform.isWindows && ext != 'exe') {
    return false;
  }
  const forbiddenExtensions = <String>{
    'json',
    'db',
    'sqlite',
    'txt',
    'ini',
    'config',
    'xml',
    'aax',
    'aaxc',
    'voucher',
    ...kLibationExportExtensions,
  };
  if (forbiddenExtensions.contains(ext)) {
    return false;
  }

  final file = File(trimmed);
  if (!await file.exists()) return false;

  try {
    await Process.start(
      file.path,
      const <String>[],
      workingDirectory: file.parent.path,
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (e) {
    debugPrint('[Libation] Failed to launch executable: $e');
    return false;
  }
}
