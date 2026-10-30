import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/local_session_service.dart';
import 'package:absorb/services/scoped_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalSessionService().debugReset();
  });
  tearDown(() => LocalSessionService().debugReset());

  Map<String, dynamic> session(String id, String itemId) => {
        'id': id,
        'progressKey': itemId,
        'libraryItemId': itemId,
        'episodeId': null,
        'mediaType': 'book',
        'duration': 3600,
        'startTime': 0,
        'currentTime': 600,
        'timeListening': 600,
        'startedAt': 1,
        'updatedAt': 2,
        'date': '2026-10-29',
        'dayOfWeek': 'Thursday',
      };

  ApiService api(
    Future<http.Response> Function(http.Request request) handler,
  ) =>
      ApiService(
        baseUrl: 'https://audiobookshelf.example',
        token: 'fixture-token',
        httpClient: MockClient(handler),
      );

  Future<List<String>> pendingIds() async => [
        for (final raw
            in await ScopedPrefs.getStringList('local_session_pending'))
          (jsonDecode(raw) as Map<String, dynamic>)['id'] as String,
      ];

  test('legacy flush keeps sessions the server did not take', () async {
    await LocalSessionService().queue(session('s-1', 'book-1'));

    await LocalSessionService().flushPending(
      api: api((request) async {
        final path = request.url.path;
        // An old server without the local-session endpoints, now unreachable
        // for the /play fallback.
        if (path == '/api/session/local-all') return http.Response('', 404);
        if (path.endsWith('/play')) return http.Response('', 503);
        return http.Response('unexpected fixture request', 404);
      }),
    );

    expect(await pendingIds(), ['s-1']);
  });

  test('legacy flush drops only the sessions it sent', () async {
    await LocalSessionService().queue(session('s-1', 'book-1'));
    await LocalSessionService().queue(session('s-2', 'book-2'));

    await LocalSessionService().flushPending(
      api: api((request) async {
        final path = request.url.path;
        if (path == '/api/session/local-all') return http.Response('', 404);
        if (path == '/api/items/book-1/play') {
          return http.Response(jsonEncode({'id': 'play-1'}), 200);
        }
        if (path == '/api/items/book-2/play') return http.Response('', 503);
        if (path.endsWith('/sync') || path.endsWith('/close')) {
          return http.Response('{}', 200);
        }
        return http.Response('unexpected fixture request', 404);
      }),
    );

    expect(await pendingIds(), ['s-2']);
  });

  test('a session queued during a flush survives it', () async {
    await LocalSessionService().queue(session('s-1', 'book-1'));

    await LocalSessionService().flushPending(
      api: api((request) async {
        if (request.url.path == '/api/session/local-all') {
          // Reading time logged while the batch is on the wire.
          await LocalSessionService().queue(session('s-2', 'book-2'));
          return http.Response('{}', 200);
        }
        return http.Response('unexpected fixture request', 404);
      }),
    );

    expect(await pendingIds(), ['s-2']);
  });
}
