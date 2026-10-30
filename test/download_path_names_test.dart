import 'dart:io';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/download_service.dart';
import 'package:absorb/services/download_track_names.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Names that work on Windows today; every helper must return them unchanged.
  const validNames = [
    'Brandon Sanderson',
    'Martin Luther King Jr.',
    'a.b.',
    'Vol. 1',
    '.hidden',
    'CONTROL',
    'Console',
    'COM10',
    'LPT0',
    'NULL.mp3',
    'Con Man',
    'Unknown',
    'Émile Zola — Œuvres',
    '日本語のタイトル',
  ];

  group('windowsSafeName', () {
    test('keeps valid names byte-identical', () {
      for (final n in validNames) {
        expect(windowsSafeName(n, windows: true), n, reason: n);
      }
    });

    test('changes nothing off Windows', () {
      for (final n in ['CON', 'nul.txt', 'a\x01b', 'COM1']) {
        expect(windowsSafeName(n, windows: false), n);
      }
    });

    test('suffixes reserved device names, any case, with or without extension', () {
      expect(windowsSafeName('CON', windows: true), 'CON_');
      expect(windowsSafeName('nul', windows: true), 'nul_');
      expect(windowsSafeName('Aux.part1', windows: true), 'Aux_.part1');
      expect(windowsSafeName('PRN.epub', windows: true), 'PRN_.epub');
      expect(windowsSafeName('NUL .x', windows: true), 'NUL_ .x');
      for (final d in ['COM1', 'com9', 'LPT1', 'lpt9', 'COM¹', 'LPT³']) {
        expect(windowsSafeName(d, windows: true), '${d}_');
      }
    });

    test('turns control characters into spaces', () {
      expect(windowsSafeName('a\x01b', windows: true), 'a b');
      expect(windowsSafeName('a \x1F\x00 b', windows: true), 'a b');
      expect(windowsSafeName('\x1Ftitle\x02', windows: true), 'title');
      expect(windowsSafeName('\x01\x02', windows: true), 'Unknown');
      expect(windowsSafeName('NUL\x1F', windows: true), 'NUL_');
    });

    test('is idempotent', () {
      for (final n in [...validNames, 'CON', 'nul.txt', 'a\x01b', 'NUL\x1F', '\x01']) {
        final once = windowsSafeName(n, windows: true);
        expect(windowsSafeName(once, windows: true), once, reason: n);
      }
    });
  });

  group('safeDownloadFolder', () {
    test('keeps valid folders byte-identical', () {
      for (final n in validNames) {
        expect(safeDownloadFolder('$n/Title', windows: true), '$n/Title');
        expect(safeDownloadFolder('Author/$n', windows: true), 'Author/$n');
      }
      // A single final dot works on Windows and stays.
      expect(safeDownloadFolder('Martin Luther King Jr./Why We Can.', windows: true),
          'Martin Luther King Jr./Why We Can.');
    });

    test('drops a trailing run of dots and spaces Windows cannot create', () {
      expect(safeDownloadFolder('Author/Wait...', windows: true), 'Author/Wait');
      expect(safeDownloadFolder('Author/Wait..', windows: true), 'Author/Wait');
      expect(safeDownloadFolder('Vol 1 ./Title', windows: true), 'Vol 1/Title');
      expect(safeDownloadFolder('Author/a. .', windows: true), 'Author/a');
      expect(safeDownloadFolder('Author/...', windows: true), 'Author/Unknown');
      expect(safeDownloadFolder('NUL../Title', windows: true), 'NUL_/Title');
    });

    test('keeps trailing dots off Windows, where they are valid', () {
      expect(safeDownloadFolder('Author/Wait...', windows: false), 'Author/Wait...');
      expect(safeDownloadFolder('.../Title', windows: false), '.../Title');
    });

    test('never lets a folder be "." or ".." on any system', () {
      for (final windows in [true, false]) {
        expect(safeDownloadFolder('../Title', windows: windows), 'Unknown/Title');
        expect(safeDownloadFolder('Author/..', windows: windows), 'Author/Unknown');
        expect(safeDownloadFolder('.', windows: windows), 'Unknown');
      }
    });

    test('is idempotent', () {
      for (final n in [...validNames, 'Wait...', 'a .', '...', '..', 'NUL..', 'a. .']) {
        for (final windows in [true, false]) {
          final once = safeDownloadFolder('$n/$n', windows: windows);
          expect(safeDownloadFolder(once, windows: windows), once, reason: n);
        }
      }
    });
  });

  group('download names use the helper', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUp(() => SharedPreferences.setMockInitialValues({}));

    late DownloadService service;
    late ApiService api;

    setUp(() {
      service = DownloadService.forTesting(initialize: () async {});
      api = ApiService(
        baseUrl: 'https://audiobookshelf.example',
        token: 'test-token',
        httpClient: MockClient((_) async => throw StateError('Unexpected request')),
      );
    });

    tearDown(() => service.dispose());

    List<String> names(List<String> filenames) => [
          for (final f in service.debugResolveDurableFiles(
            api: api,
            itemId: 'book-1',
            audioTracks: [
              for (var i = 0; i < filenames.length; i++)
                {
                  'contentUrl': '/api/items/book-1/file/$i',
                  'metadata': {'filename': filenames[i]},
                },
            ],
          ))
            f.filename,
        ];

    test('track names are made Windows-safe on Windows only', () {
      final w = Platform.isWindows;
      expect(
        names(['CON.mp3', 'a\x01b.mp3', 'So it begins...mp3', '01.mp3']),
        [w ? 'CON_.mp3' : 'CON.mp3', w ? 'a b.mp3' : 'a\x01b.mp3', 'So it begins...mp3', '01.mp3'],
      );
    });
  });
}
