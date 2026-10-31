import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/progress_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flushes local progress through the real progress transport', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.BaseRequest>[];
    http.Request? patchRequest;
    final service = ProgressSyncService();
    final api = ApiService(
      baseUrl: 'https://audiobookshelf.example',
      token: 'fixture-token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/api/me/progress/book-1') {
          return http.Response(
            jsonEncode({'currentTime': 5, 'lastUpdate': 1}),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/items/book-1') {
          return http.Response(
            jsonEncode({
              'media': {'duration': 100},
            }),
            200,
          );
        }
        if (request.method == 'PATCH' &&
            request.url.path == '/api/me/progress/book-1') {
          patchRequest = request;
          return http.Response('{}', 200);
        }
        return http.Response('unexpected fixture request', 404);
      }),
    );

    await service.saveLocal(
      itemId: 'book-1',
      currentTime: 42,
      duration: 90,
      speed: 1,
    );
    expect(await service.hasPendingSync('book-1'), isTrue);

    await service.flushPendingSync(api: api);

    expect(await service.hasPendingSync('book-1'), isFalse);
    expect(
      requests.where((request) => request.method == 'PATCH'),
      hasLength(1),
    );
    final body = jsonDecode(patchRequest!.body) as Map<String, dynamic>;
    expect(body['currentTime'], 42);
    expect(body['duration'], 100);
    expect(body['progress'], closeTo(0.42, 0.001));
  });

  test('keeps local progress queued when the server returns 5xx', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ProgressSyncService();
    final api = ApiService(
      baseUrl: 'https://audiobookshelf.example',
      token: 'fixture-token',
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/me/progress/book-2') {
          return http.Response(jsonEncode({'currentTime': 1}), 200);
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/items/book-2') {
          return http.Response(
            jsonEncode({
              'media': {'duration': 100},
            }),
            200,
          );
        }
        if (request.method == 'PATCH' &&
            request.url.path == '/api/me/progress/book-2') {
          return http.Response('server busy', 503);
        }
        return http.Response('unexpected fixture request', 404);
      }),
    );

    await service.saveLocal(
      itemId: 'book-2',
      currentTime: 18,
      duration: 80,
      speed: 1,
    );
    await service.flushPendingSync(api: api);

    expect(await service.hasPendingSync('book-2'), isTrue);
  });


  for (final status in [401, 403, 429]) {
    test('keeps local progress queued when the server answers $status',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = ProgressSyncService();
      final api = ApiService(
        baseUrl: 'https://audiobookshelf.example',
        // A legacy token: no refresh round trip, the reply comes back as is.
        token: 'fixture-token',
        httpClient: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/me/progress/book-$status') {
            return http.Response(jsonEncode({'currentTime': 1}), 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/items/book-$status') {
            return http.Response(
              jsonEncode({
                'media': {'duration': 100},
              }),
              200,
            );
          }
          if (request.method == 'GET' && request.url.path == '/api/me') {
            // The revoked-key probe after a 401 still finds the user.
            return http.Response(jsonEncode({'id': 'user-1'}), 200);
          }
          if (request.method == 'PATCH' &&
              request.url.path == '/api/me/progress/book-$status') {
            return http.Response('refused', status);
          }
          return http.Response('unexpected fixture request', 404);
        }),
      );

      await service.saveLocal(
        itemId: 'book-$status',
        currentTime: 18,
        duration: 80,
        speed: 1,
      );
      await service.flushPendingSync(api: api);

      expect(await service.hasPendingSync('book-$status'), isTrue);
    });
  }

  test('drops a queued position the server answers 404 for', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ProgressSyncService();
    final api = ApiService(
      baseUrl: 'https://audiobookshelf.example',
      token: 'fixture-token',
      // No server progress, no item details, and the PATCH 404s: gone.
      httpClient: MockClient((request) async => http.Response('Not found', 404)),
    );

    await service.saveLocal(
      itemId: 'gone-book',
      currentTime: 18,
      duration: 80,
      speed: 1,
    );
    await service.flushPendingSync(api: api);

    expect(await service.hasPendingSync('gone-book'), isFalse);
  });

  test('progressPatchSettled is 2xx or 404 only', () {
    for (final ok in [200, 204, 404]) {
      expect(ApiService.progressPatchSettled(ok), isTrue, reason: '$ok');
    }
    for (final keep in [400, 401, 403, 408, 409, 429, 500, 503]) {
      expect(ApiService.progressPatchSettled(keep), isFalse, reason: '$keep');
    }
  });
}
