import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:absorb/services/api_service.dart';

void main() {
  test('token diagnostics never contain full credentials or suffixes', () {
    expect(ApiService.tokenFp(null), 'none');
    expect(ApiService.tokenFp(''), 'none');
    for (final token in ['tiny', 'fixture-long-token-secret-suffix']) {
      expect(ApiService.tokenFp(token), 'present');
    }
  });
  test(
    'refreshes once after a 401 and retries the Audiobookshelf request',
    () async {
      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);

        if (request.url.path == '/auth/refresh') {
          expect(request.headers['x-refresh-token'], 'refresh-old');
          return http.Response(
            jsonEncode({
              'accessToken': 'access-new',
              'refreshToken': 'refresh-new',
            }),
            200,
          );
        }

        if (request.url.path == '/api/me' &&
            requests.where((r) => r.url.path == '/api/me').length == 1) {
          expect(request.headers['authorization'], 'Bearer access-old');
          return http.Response('{}', 401);
        }

        if (request.url.path == '/api/me') {
          expect(request.headers['authorization'], 'Bearer access-new');
          return http.Response(jsonEncode({'username': 'reader'}), 200);
        }

        return http.Response('not found', 404);
      });

      final service = ApiService(
        baseUrl: 'https://audiobookshelf.example',
        token: 'access-old',
        refreshToken: 'refresh-old',
        httpClient: client,
      );

      final user = await service.getMe();

      expect(user, {'username': 'reader'});
      expect(service.token, 'access-new');
      expect(service.hasRefreshToken, isTrue);
      expect(requests.map((request) => request.url.path), [
        '/api/me',
        '/auth/refresh',
        '/api/me',
      ]);
    },
  );

  test(
    'retries a transient refresh failure without expiring the session',
    () async {
      var refreshAttempts = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshAttempts++;
          if (refreshAttempts == 1) return http.Response('server busy', 503);
          return http.Response(
            jsonEncode({
              'accessToken': 'access-recovered',
              'refreshToken': 'refresh-recovered',
            }),
            200,
          );
        }

        if (request.url.path == '/api/me' &&
            request.headers['authorization'] == 'Bearer access-old') {
          return http.Response('{}', 401);
        }

        expect(request.headers['authorization'], 'Bearer access-recovered');
        return http.Response(jsonEncode({'username': 'reader'}), 200);
      });

      var expired = false;
      final service = ApiService(
        baseUrl: 'https://audiobookshelf.example',
        token: 'access-old',
        refreshToken: 'refresh-old',
        httpClient: client,
        refreshRetryDelay: Duration.zero,
        onAuthExpired: () => expired = true,
      );

      expect(await service.getMe(), {'username': 'reader'});
      expect(refreshAttempts, 2);
      expect(expired, isFalse);
      expect(service.token, 'access-recovered');
    },
  );

  test('retries a transient GET transport failure once', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      if (requests == 1) throw TimeoutException('fixture offline');
      return http.Response(jsonEncode({'username': 'reader'}), 200);
    });

    final service = ApiService(
      baseUrl: 'https://audiobookshelf.example',
      token: 'access-token',
      httpClient: client,
      networkRetryDelay: Duration.zero,
    );

    expect(await service.getMe(), {'username': 'reader'});
    expect(requests, 2);
  });

  test('does not replay an HTTP error as a network retry', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('server unavailable', 503);
    });

    final service = ApiService(
      baseUrl: 'https://audiobookshelf.example',
      token: 'access-token',
      httpClient: client,
      networkRetryDelay: Duration.zero,
    );

    expect(await service.getMe(), isNull);
    expect(requests, 1);
  });
}
