import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:absorb/services/api_service.dart';

void main() {
  test('refreshes once after a 401 and retries the Audiobookshelf request', () async {
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

      if (request.url.path == '/api/me' && requests.where((r) => r.url.path == '/api/me').length == 1) {
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
  });
}
