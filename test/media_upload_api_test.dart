import 'dart:io';
import 'dart:typed_data';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/libation_import_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaUploadRequest _request(List<MediaUploadFile> files) => MediaUploadRequest(
  libraryId: 'books',
  folderId: 'folder',
  mediaType: 'book',
  title: 'Fixture title',
  author: 'Fixture author',
  files: files,
);

void main() {
  test(
    'tracks path, bytes and stream payloads with accurate byte totals',
    () async {
      final temp = await Directory.systemTemp.createTemp('absorb-upload-test-');
      addTearDown(() => temp.delete(recursive: true));
      final file = await File(
        '${temp.path}/chapter.mp3',
      ).writeAsBytes([1, 2, 3]);
      final progress = <(int, int)>[];
      var sends = 0;
      final client = MockClient((request) async {
        sends++;
        expect(request.url.path, '/api/upload');
        expect(request.headers['authorization'], 'Bearer fake-token');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        final body = request.body;
        expect(body, contains('Fixture title'));
        expect(body, contains('filename="chapter.mp3"'));
        expect(body, contains('filename="cover.jpg"'));
        expect(body, contains('filename="chapter2.mp3"'));
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final api = ApiService(
        baseUrl: 'https://example.invalid',
        token: 'fake-token',
        httpClient: client,
      );
      final result = await api.uploadMedia(
        _request([
          MediaUploadFile(name: 'chapter.mp3', size: 999, path: file.path),
          MediaUploadFile(
            name: 'cover.jpg',
            size: 999,
            bytes: Uint8List.fromList([4, 5]),
          ),
          MediaUploadFile(
            name: 'chapter2.mp3',
            size: 4,
            readStream: Stream.fromIterable([
              [6, 7],
              [8, 9],
            ]),
          ),
        ]),
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(result.success, isTrue);
      expect(result.statusCode, 200);
      expect(result.isPermissionDenied, isFalse);
      expect(sends, 1);
      expect(progress.first, (0, 9));
      expect(progress.last, (9, 9));
      expect(progress.map((p) => p.$1), containsAllInOrder([0, 3, 5, 7, 9]));
      expect(progress.every((p) => p.$2 == 9 && p.$1 <= 9), isTrue);
    },
  );

  for (final status in [401, 403, 500]) {
    test(
      'HTTP $status is reported without automatic multipart replay',
      () async {
        var sends = 0;
        final client = MockClient((request) async {
          sends++;
          return http.Response('fixture rejection', status);
        });
        addTearDown(client.close);
        final api = ApiService(
          baseUrl: 'https://example.invalid',
          token: 'fake',
          httpClient: client,
        );
        final result = await api.uploadMedia(
          _request([
            MediaUploadFile(
              name: 'book.m4b',
              size: 1,
              bytes: Uint8List.fromList([1]),
            ),
          ]),
        );
        expect(result.success, isFalse);
        expect(result.error, 'fixture rejection');
        expect(result.statusCode, status);
        expect(result.isPermissionDenied, status == 401 || status == 403);
        expect(sends, 1);
      },
    );
  }

  test('checkUploadPathExists flags HTTP 403 as permission denied', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/filesystem/pathexists');
      return http.Response('Forbidden', 403);
    });
    addTearDown(client.close);
    final api = ApiService(
      baseUrl: 'https://example.invalid',
      token: 'fake',
      httpClient: client,
    );
    final result = await api.checkUploadPathExists(
      directory: 'Fixture author/Fixture title',
      folderPath: '/audiobooks',
    );
    expect(result.success, isFalse);
    expect(result.statusCode, 403);
    expect(result.isPermissionDenied, isTrue);
  });

  test('unreadable file fails before sending a request', () async {
    var sends = 0;
    final client = MockClient((request) async {
      sends++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    final api = ApiService(
      baseUrl: 'https://example.invalid',
      token: 'fake',
      httpClient: client,
    );
    final result = await api.uploadMedia(
      _request([const MediaUploadFile(name: 'book.m4b', size: 100)]),
    );
    expect(result.success, isFalse);
    expect(sends, 0);
  });

  test(
    'scanLibationExportDirectory discovers exported books and skips account/DRM sidecars',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'absorb-libation-scan-',
      );
      addTearDown(() => temp.delete(recursive: true));

      final bookOneDir = await Directory(
        '${temp.path}/Jane Doe/First Book [B001234567]',
      ).create(recursive: true);
      await File(
        '${bookOneDir.path}/02 - Chapter Two.mp3',
      ).writeAsBytes([1, 2]);
      await File(
        '${bookOneDir.path}/01 - Chapter One.mp3',
      ).writeAsBytes([3, 4, 5]);
      await File('${bookOneDir.path}/cover.jpg').writeAsBytes([6]);
      await File(
        '${bookOneDir.path}/AccountsSettings.json',
      ).writeAsString('{}');
      await File('${bookOneDir.path}/raw.aax').writeAsBytes([7, 8]);

      final bookTwoDir = await Directory(
        '${temp.path}/John Smith/Second Book',
      ).create(recursive: true);
      await File(
        '${bookTwoDir.path}/Second Book [B009876543].m4b',
      ).writeAsBytes([1, 2, 3, 4]);

      final candidates = await scanLibationExportDirectory(temp.path);
      expect(candidates, hasLength(2));

      final first = candidates.firstWhere((c) => c.title == 'First Book');
      expect(first.author, 'Jane Doe');
      expect(first.skippedFilesCount, 2);
      expect(first.files.map((f) => f.name), [
        '01 - Chapter One.mp3',
        '02 - Chapter Two.mp3',
        'cover.jpg',
      ]);
      expect(first.totalBytes, 6);

      final second = candidates.firstWhere((c) => c.title == 'Second Book');
      expect(second.author, 'John Smith');
      expect(second.files.map((f) => f.name), ['Second Book [B009876543].m4b']);
    },
  );

  test(
    'scanLibationExportDirectory lists the newest export first past alphabetical order',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'absorb-libation-order-',
      );
      addTearDown(() => temp.delete(recursive: true));

      final base = DateTime(2026, 1, 1);
      Future<void> book(String name, DateTime modified) async {
        final dir = await Directory(
          '${temp.path}/$name [B00000000${name.length}]',
        ).create(recursive: true);
        final file = File('${dir.path}/$name.m4b');
        await file.writeAsBytes([1]);
        await file.setLastModified(modified);
      }

      await book('Alpha', base);
      await book('Mid', base.add(const Duration(days: 1)));
      await book('Zulu Newest', base.add(const Duration(days: 30)));

      final candidates = await scanLibationExportDirectory(temp.path);
      expect(candidates.map((c) => c.title), ['Zulu Newest', 'Mid', 'Alpha']);
      expect(candidates.first.modified, base.add(const Duration(days: 30)));
    },
  );

  test('single-file title inference strips a trailing Libation ASIN tag', () {
    expect(
      inferTitleFromSelectedFiles([
        MediaUploadFile(name: 'Project Hail Mary [B08G9PRS1K].m4b', size: 1),
      ]),
      'Project Hail Mary',
    );
    expect(
      inferTitleFromSelectedFiles([
        MediaUploadFile(name: 'Book [Part 1].m4b', size: 1),
      ]),
      'Book [Part 1]',
    );
  });

  test(
    'launchLibationExecutable rejects non-existent or non-executable files',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'absorb-libation-launch-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final jsonFile = await File(
        '${temp.path}/AccountsSettings.json',
      ).writeAsString('{}');
      expect(await launchLibationExecutable(''), isFalse);
      expect(await launchLibationExecutable(jsonFile.path), isFalse);
      expect(
        await launchLibationExecutable('${temp.path}/missing.exe'),
        isFalse,
      );
    },
  );

  test('libationAsinFrom reads the ASIN tag from folders and files', () {
    expect(libationAsinFrom('Project Hail Mary [B08G9PRS1K]'), 'B08G9PRS1K');
    expect(
      libationAsinFrom('Project Hail Mary [B08G9PRS1K].m4b'),
      'B08G9PRS1K',
    );
    expect(libationAsinFrom('Dr. Who and Friends [B012345678]'), 'B012345678');
    expect(libationAsinFrom('Book [Part 1]'), isNull);
    expect(libationAsinFrom('No Tag'), isNull);

    final candidate = LibationBookCandidate(
      directoryPath: '/out/Untagged Folder',
      title: 'Untagged Folder',
      files: [MediaUploadFile(name: 'Book [B0ABCDEFGH].mp3', size: 1)],
    );
    expect(candidate.asin, 'B0ABCDEFGH');
  });

  group('newLibationExports', () {
    final now = DateTime(2026, 10, 29, 12);
    LibationBookCandidate at(String name, DateTime? modified) =>
        LibationBookCandidate(
          directoryPath: '/out/$name',
          title: name,
          files: const [],
          modified: modified,
        );

    test('first run only counts recent exports', () {
      final fresh = newLibationExports(
        [
          at('recent', now.subtract(const Duration(days: 1))),
          at('old', now.subtract(const Duration(days: 30))),
          at('undated', null),
        ],
        importedFolders: const {},
        lastSeen: null,
        now: now,
      );
      expect(fresh.map((c) => c.title), ['recent']);
    });

    test('skips imported folders and anything already seen', () {
      final lastSeen = now.subtract(const Duration(days: 10));
      final fresh = newLibationExports(
        [
          at('after', now.subtract(const Duration(days: 2))),
          at('before', now.subtract(const Duration(days: 20))),
          at('imported', now.subtract(const Duration(days: 1))),
        ],
        importedFolders: {libationFolderKey('/out/imported')},
        lastSeen: lastSeen,
        now: now,
      );
      expect(fresh.map((c) => c.title), ['after']);
    });
  });

  test('matchingLibraryBookTitle matches by ASIN, then normalized title', () {
    Map<String, dynamic> result(List<Map<String, String>> books) => {
      'book': [
        for (final metadata in books)
          {
            'libraryItem': {
              'media': {'metadata': metadata},
            },
          },
      ],
    };
    final candidate = LibationBookCandidate(
      directoryPath: '/out/Project Hail Mary [B08G9PRS1K]',
      title: 'Project Hail Mary',
      files: const [],
    );

    expect(
      matchingLibraryBookTitle(
        result([
          {'title': 'Project Hail Mary', 'asin': ''},
          {'title': 'PHM (Unabridged)', 'asin': 'b08g9prs1k'},
        ]),
        candidate,
      ),
      'PHM (Unabridged)',
    );
    expect(
      matchingLibraryBookTitle(
        result([
          {'title': 'project hail-mary'},
        ]),
        candidate,
      ),
      'project hail-mary',
    );
    expect(
      matchingLibraryBookTitle(
        result([
          {'title': 'Artemis', 'asin': 'B0OTHER000'},
        ]),
        candidate,
      ),
      isNull,
    );
    expect(matchingLibraryBookTitle(null, candidate), isNull);
    expect(matchingLibraryBookTitle({'book': 'bad'}, candidate), isNull);
  });

  test('import history is bounded and last-seen only moves forward', () async {
    SharedPreferences.setMockInitialValues({
      kLibationImportedFoldersPref: [
        for (var i = 0; i < kLibationImportedFoldersLimit; i++) '/old/$i',
      ],
    });
    await LibationImportHistory.recordImported('/out/New Book');
    final prefs = await SharedPreferences.getInstance();
    final folders = prefs.getStringList(kLibationImportedFoldersPref)!;
    expect(folders, hasLength(kLibationImportedFoldersLimit));
    expect(folders.first, '/old/1');
    expect(folders.last, libationFolderKey('/out/New Book'));

    await LibationImportHistory.markSeen(DateTime(2026, 10, 2));
    await LibationImportHistory.markSeen(DateTime(2026, 10, 1));
    final history = await LibationImportHistory.load();
    expect(history.lastSeen, DateTime(2026, 10, 2));
    expect(
      history.importedFolders,
      contains(libationFolderKey('/out/New Book')),
    );
  });

  test('saved-folder count is zero without a saved folder', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    expect(await countNewExportsInSavedLibationFolder(), 0);
  });
}
