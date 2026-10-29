import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_service.dart';

const String kLibationExecutablePathPref = 'libation_executable_path';
const String kLibationOutputFolderPref = 'libation_output_folder_path';

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
/// - Single primary file: strips the file extension (preserving exact
///   single-file behavior).
/// - Multiple primary files sharing a parent directory path: uses the cleaned
///   parent folder name.
String? inferTitleFromSelectedFiles(List<MediaUploadFile> primaryFiles) {
  if (primaryFiles.isEmpty) return null;
  if (primaryFiles.length == 1) {
    return stripFileExtension(primaryFiles.single.name);
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

  const LibationBookCandidate({
    required this.directoryPath,
    required this.title,
    this.author,
    required this.files,
    this.skippedFilesCount = 0,
  });

  int get audioFileCount =>
      files.where((file) => isLibationAudioFile(file.name)).length;

  int get totalBytes => files.fold<int>(0, (sum, file) => sum + file.size);
}

/// Scan a user-selected directory for exported Libation audiobooks.
///
/// Safety guarantees:
/// - Only inspects the directory explicitly provided by the caller.
/// - Never opens or reads the contents of any file during scanning.
/// - Filters out account/configuration files (`.json`, `.db`, etc.) and
///   protected containers (`.aax`, `.aaxc`, `.voucher`, etc.) by extension.
Future<List<LibationBookCandidate>> scanLibationExportDirectory(
  String directoryPath, {
  int maxDepth = 3,
  int maxCandidates = 200,
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
        if (parentNormalized.isNotEmpty &&
            parentNormalized != rootNormalized) {
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
  return candidates;
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
