import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/progress_sync_service.dart';
import 'package:absorb/services/scoped_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ApiService apiWith({required int playStatus, required int syncStatus}) =>
      ApiService(
        baseUrl: 'https://audiobookshelf.example',
        token: 'fixture-token',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (request.method == 'GET' && path.startsWith('/api/me/progress/')) {
            return http.Response(jsonEncode({'currentTime': 0}), 200);
          }
          if (request.method == 'POST' && path.endsWith('/play')) {
            return http.Response(
              jsonEncode({'id': 'session-1', 'audioTracks': []}),
              playStatus,
            );
          }
          if (request.method == 'POST' && path.endsWith('/sync')) {
            return http.Response('{}', syncStatus);
          }
          if (request.method == 'POST' && path.endsWith('/close')) {
            return http.Response('{}', 200);
          }
          return http.Response('unexpected fixture request', 404);
        }),
      );

  Future<int?> ledger(String itemId) =>
      ScopedPrefs.getInt('offline_listening_$itemId');

  test('keeps offline listening when the session cannot be opened', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ProgressSyncService();
    await service.addOfflineListeningTime('book-a', 120);

    await service.flushOfflineListeningTime(
      api: apiWith(playStatus: 500, syncStatus: 200),
    );

    expect(await ledger('book-a'), 120);
    expect(
      await ScopedPrefs.getStringList('pending_offline_listening'),
      contains('book-a'),
    );
  });

  test('keeps offline listening when the sync is rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ProgressSyncService();
    await service.addOfflineListeningTime('book-b', 90);

    await service.flushOfflineListeningTime(
      api: apiWith(playStatus: 200, syncStatus: 500),
    );

    expect(await ledger('book-b'), 90);
    expect(
      await ScopedPrefs.getStringList('pending_offline_listening'),
      contains('book-b'),
    );
  });

  test('clears offline listening once the server accepted it', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ProgressSyncService();
    await service.addOfflineListeningTime('book-c', 60);

    await service.flushOfflineListeningTime(
      api: apiWith(playStatus: 200, syncStatus: 200),
    );

    expect(await ledger('book-c'), isNull);
    expect(
      await ScopedPrefs.getStringList('pending_offline_listening'),
      isNot(contains('book-c')),
    );
  });

  test('an item the server refuses does not hold back the rest', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ProgressSyncService();
    await service.addOfflineListeningTime('book-gone', 30);
    await service.addOfflineListeningTime('book-d', 45);

    await service.flushOfflineListeningTime(
      api: ApiService(
        baseUrl: 'https://audiobookshelf.example',
        token: 'fixture-token',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.contains('book-gone')) {
            return http.Response('not found', 404);
          }
          if (request.method == 'GET') {
            return http.Response(jsonEncode({'currentTime': 0}), 200);
          }
          if (path.endsWith('/play')) {
            return http.Response(
              jsonEncode({'id': 'session-1', 'audioTracks': []}),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      ),
    );

    expect(await ledger('book-gone'), 30);
    expect(await ledger('book-d'), isNull);
    final pending = await ScopedPrefs.getStringList(
      'pending_offline_listening',
    );
    expect(pending, contains('book-gone'));
    expect(pending, isNot(contains('book-d')));
  });
}
