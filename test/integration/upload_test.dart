// Uploads through the same ApiService calls the admin upload screen uses
// (path check, multipart upload), against the throwaway server. Every
// uploaded book is hard-deleted again at the end.
// Run with .\tool\dev.ps1 itest (see abs_test_server.dart).
@Tags(['abs-server'])
library;

import 'dart:typed_data';

import 'package:absorb/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'abs_test_server.dart';

/// A short real MP3 taken from the seeded book, without its ID3 tags so the
/// server names the upload after its folder rather than the seeded album.
Future<Uint8List> _untaggedMp3(AbsTestServer server, ApiService api) async {
  final book = await server.book(api, multiFileBookTitle);
  final item = await api.getLibraryItem(book['id'] as String);
  final ino = (item!['media']['audioFiles'] as List).first['ino'] as String;
  final r = await http.get(Uri.parse(api.buildFileUrl(book['id'] as String, ino)));
  expect(r.statusCode, 200, reason: 'download the seeded MP3');
  var bytes = r.bodyBytes;
  if (bytes.length > 10 && String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3') {
    final size = (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
    bytes = bytes.sublist(10 + size);
  }
  if (bytes.length > 128 && String.fromCharCodes(bytes.sublist(bytes.length - 128, bytes.length - 125)) == 'TAG') {
    bytes = bytes.sublist(0, bytes.length - 128);
  }
  return bytes;
}

/// Scans the library until an item whose folder is [relDir] shows up.
Future<Map<String, dynamic>?> _findUploaded(ApiService api, String libraryId, String relDir) async {
  await api.scanLibrary(libraryId);
  return eventually(() async {
    final page = await api.getLibraryItems(libraryId, limit: 100);
    for (final r in (page?['results'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final rel = (r['relPath'] as String? ?? '').replaceAll('\\', '/');
      if (rel == relDir) return r;
    }
    return null;
  });
}

void main() {
  final cleanup = <Future<void> Function()>[];
  tearDown(() async {
    for (final step in cleanup.reversed) {
      await step();
    }
    cleanup.clear();
  });

  test('admin upload: path check, multipart upload, scanned in, deleted', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;
    final api = await server.api();
    final lib = await server.testLibrary(api);
    final libraryId = lib['id'] as String;
    final folder = (lib['folders'] as List).first as Map<String, dynamic>;
    final bytes = await _untaggedMp3(server, api);

    final request = MediaUploadRequest(
      libraryId: libraryId,
      folderId: folder['id'] as String,
      mediaType: 'book',
      title: 'Itest Upload ${DateTime.now().millisecondsSinceEpoch}',
      author: 'Absorb Upload Author',
      files: [MediaUploadFile(name: 'upload.mp3', size: bytes.length, bytes: bytes)],
    );
    final folderPath = folder['fullPath'] as String;

    final before = await api.checkUploadPathExists(directory: request.directory, folderPath: folderPath);
    expect(before.success, isTrue, reason: before.error);
    expect(before.exists, isFalse);

    var lastProgress = (0, 0);
    final result = await api.uploadMedia(request, onProgress: (sent, total) => lastProgress = (sent, total));
    expect(result.success, isTrue, reason: result.error);
    expect(lastProgress.$1, lastProgress.$2);
    expect(lastProgress.$2, greaterThanOrEqualTo(bytes.length));

    final after = await api.checkUploadPathExists(directory: request.directory, folderPath: folderPath);
    expect(after.exists, isTrue);

    final item = await _findUploaded(api, libraryId, request.directory);
    expect(item, isNotNull, reason: 'the scanner should pick up ${request.directory}');
    cleanup.add(() async {
      expect(await api.deleteLibraryItem(item!['id'] as String, hard: true), 200);
    });
    expect(item!['media']['metadata']['title'], request.title);
  });

  test('a non-admin account without upload permission is refused', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;
    if (server.username2.isEmpty) {
      markTestSkipped('ABS_TEST_USER2 not set: re-run dev.ps1 server seed');
      return;
    }
    final root = await server.api();
    final lib = await server.testLibrary(root);
    final folder = (lib['folders'] as List).first as Map<String, dynamic>;
    final listener = await server.api(second: true);

    final result = await listener.uploadMedia(MediaUploadRequest(
      libraryId: lib['id'] as String,
      folderId: folder['id'] as String,
      mediaType: 'book',
      title: 'Itest Refused ${DateTime.now().millisecondsSinceEpoch}',
      author: 'Absorb Upload Author',
      files: [MediaUploadFile(name: 'x.mp3', size: 3, bytes: Uint8List.fromList([1, 2, 3]))],
    ));
    expect(result.success, isFalse);
    expect(result.isPermissionDenied, isTrue, reason: 'HTTP ${result.statusCode}: ${result.error}');
  });
}
