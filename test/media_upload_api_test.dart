import 'dart:io';
import 'dart:typed_data';

import 'package:absorb/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
        expect(sends, 1);
      },
    );
  }

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
}
