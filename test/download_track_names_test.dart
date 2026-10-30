import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  late DownloadService service;
  late ApiService api;

  setUp(() {
    service = DownloadService.forTesting(initialize: () async {});
    api = ApiService(
      baseUrl: 'https://audiobookshelf.example',
      token: 'test-token',
      httpClient: MockClient(
        (_) async => throw StateError('Unexpected request'),
      ),
    );
  });

  tearDown(() => service.dispose());

  Map<String, dynamic> track(String ino, String filename) => {
        'contentUrl': '/api/items/book-1/file/$ino',
        'metadata': {'filename': filename},
      };

  List<String> names(List<Map<String, dynamic>> tracks) => [
        for (final f in service.debugResolveDurableFiles(
          api: api,
          itemId: 'book-1',
          audioTracks: tracks,
        ))
          f.filename,
      ];

  test('distinct track names are kept as they are', () {
    expect(
      names([track('1', '01.mp3'), track('2', '02.mp3')]),
      ['01.mp3', '02.mp3'],
    );
  });

  test('multi-disc tracks sharing a base name get distinct files', () {
    final result = names([
      track('1', '01.mp3'),
      track('2', '02.mp3'),
      track('3', '01.mp3'),
      track('4', '02.MP3'),
    ]);

    expect(result.toSet(), hasLength(4));
    expect(result.map((n) => n.toLowerCase()).toSet(), hasLength(4));
    expect(result.take(2), ['01.mp3', '02.mp3']);
    expect(result[2], '003 - 01.mp3');
    expect(result[3], '004 - 02.MP3');
  });

  test('names equal after sanitizing and truncation do not collide', () {
    final long = 'A' * 120;
    final result = names([
      track('1', '${long}1.m4b'),
      track('2', '${long}2.m4b'),
    ]);

    expect(result.toSet(), hasLength(2));
  });

  test('a prefixed name that is itself taken still ends up unique', () {
    final result = names([
      track('1', '01.mp3'),
      track('2', '003 - 01.mp3'),
      track('3', '01.mp3'),
    ]);

    expect(result.take(2), ['01.mp3', '003 - 01.mp3']);
    expect(result.map((n) => n.toLowerCase()).toSet(), hasLength(3));
  });
}
