// Sign-in, token refresh, libraries and items against the throwaway server.
// Run with .\tool\dev.ps1 itest (see abs_test_server.dart).
@Tags(['abs-server'])
library;

import 'package:absorb/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'abs_test_server.dart';

void main() {
  test('login returns an access and refresh token pair and getMe works', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;

    final tokens = await server.login(fresh: true);
    expect(tokens.accessToken, isNotNull);
    expect(tokens.refreshToken, isNotNull);
    expect(tokens.isLegacy, isFalse);

    final api = await server.api();
    final me = await api.getMe();
    expect(me?['username'], server.username);
    expect(me?['type'], 'root');
  });

  test('wrong password is rejected with 401', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;

    final (data, status) = await ApiService.login(
      serverUrl: server.url,
      username: server.username,
      password: 'definitely-not-the-password',
    );
    expect(data, isNull);
    expect(status, 401);
  });

  test('a rejected access token is refreshed once and the call retried', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;

    final tokens = await server.login(fresh: true);
    final refreshed = <(String, String?)>[];
    var expired = false;
    final api = ApiService(
      baseUrl: server.url,
      token: 'not-a-valid-access-token',
      refreshToken: tokens.refreshToken,
      onTokensRefreshed: (access, refresh) {
        refreshed.add((access, refresh));
        return true;
      },
      onAuthExpired: () => expired = true,
    );

    final me = await api.getMe();
    expect(me?['username'], server.username, reason: 'the retried call should succeed');
    expect(refreshed, hasLength(1));
    expect(api.token, isNot('not-a-valid-access-token'));
    expect(refreshed.single.$1, api.token);
    expect(refreshed.single.$2, isNotNull);
    expect(expired, isFalse);
  });

  test('a rejected refresh token expires the session', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;

    var expired = false;
    final api = ApiService(
      baseUrl: server.url,
      token: 'not-a-valid-access-token',
      refreshToken: 'not-a-valid-refresh-token',
      onAuthExpired: () => expired = true,
      refreshRetryDelay: Duration.zero,
    );
    expect(await api.getMe(), isNull);
    expect(expired, isTrue);
  });

  test('libraries and items: the seeded library holds both test books', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;
    final api = await server.api();

    final lib = await server.testLibrary(api);
    expect(lib['mediaType'], 'book');

    final page = await api.getLibraryItems(lib['id'] as String, limit: 50, sort: 'media.metadata.title', desc: 0);
    expect(page, isNotNull);
    final titles = (page!['results'] as List).map((r) => r['media']['metadata']['title']).toList();
    expect(titles, containsAll([chapteredBookTitle, multiFileBookTitle]));
    expect(page['total'], greaterThanOrEqualTo(2));
  });

  test('item details: three MP3 tracks, and an M4B with two chapters', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;
    final api = await server.api();

    final mp3 = await api.getLibraryItem((await server.book(api, multiFileBookTitle))['id'] as String);
    expect(mp3, isNotNull);
    expect((mp3!['media']['audioFiles'] as List), hasLength(3));
    expect((mp3['media']['duration'] as num).toDouble(), closeTo(30, 2));

    final m4b = await api.getLibraryItem((await server.book(api, chapteredBookTitle))['id'] as String);
    expect(m4b, isNotNull);
    final chapters = (m4b!['media']['chapters'] as List).cast<Map<String, dynamic>>();
    expect(chapters.map((c) => c['title']), ['Chapter One', 'Chapter Two']);
    expect((chapters[1]['start'] as num).toDouble(), closeTo(15, 0.5));
  });
}
