import 'dart:async';
import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/progress_sync_service.dart';
import 'package:absorb/services/scoped_prefs.dart';
import 'package:absorb/services/user_account_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A flush (or its scheduled retry) that spans an account switch must not
/// push the next account's queue through the old account's session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const server = 'https://audiobookshelf.example';
  const scopeA = 'audiobookshelf.example_alice';
  const scopeB = 'audiobookshelf.example_bob';

  Future<void> seedAccounts() async {
    SharedPreferences.setMockInitialValues({
      'saved_accounts': jsonEncode([
        {'serverUrl': server, 'username': 'alice', 'token': 'a-token'},
        {'serverUrl': server, 'username': 'bob', 'token': 'b-token'},
      ]),
      'active_account_scope': scopeA,
    });
    await UserAccountService().init();
    expect(UserAccountService().activeScopeKey, scopeA);
  }

  Future<List<String>> pendingFor(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(ScopedPrefs.keyForScope(scope, 'pending_syncs')) ??
        const [];
  }

  http.Response itemFixture(http.Request request) => http.Response(
        jsonEncode({
          'media': {'duration': 1000},
        }),
        200,
      );

  test('an account switch mid-flush stops the push', () async {
    await seedAccounts();
    final service = ProgressSyncService();
    await service.saveLocal(
        itemId: 'shared-book', currentTime: 50, duration: 1000, speed: 1);

    final progressRead = Completer<void>();
    final releaseRead = Completer<void>();
    final patches = <String>[];
    final api = ApiService(
      baseUrl: server,
      token: 'a-token',
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/me/progress/shared-book') {
          progressRead.complete();
          await releaseRead.future;
          return http.Response(jsonEncode({'currentTime': 1}), 200);
        }
        if (request.method == 'GET') return itemFixture(request);
        patches.add(request.url.path);
        return http.Response('{}', 200);
      }),
    );

    final flush = service.flushPendingSync(api: api);
    await progressRead.future;
    // Bob signs in while Alice's server read is in flight, with his own
    // pending position for the same book id.
    UserAccountService().switchTo(server, 'bob');
    await service.saveLocal(
        itemId: 'shared-book', currentTime: 700, duration: 1000, speed: 1);
    releaseRead.complete();
    await flush;

    expect(patches, isEmpty);
    expect(await pendingFor(scopeB), ['shared-book']);
    expect(await pendingFor(scopeA), ['shared-book']);
  });

  test('a retry scheduled before an account switch does not run', () async {
    await seedAccounts();
    final service = ProgressSyncService();
    await service.saveLocal(
        itemId: 'book-1', currentTime: 10, duration: 1000, speed: 1);
    await service.saveLocal(
        itemId: 'book-2', currentTime: 20, duration: 1000, speed: 1);

    final patches = <String>[];
    final api = ApiService(
      baseUrl: server,
      token: 'a-token',
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.startsWith('/api/me/progress/')) {
          return http.Response(jsonEncode({'currentTime': 1}), 200);
        }
        if (request.method == 'GET') return itemFixture(request);
        patches.add(request.url.path);
        return http.Response('{}', 200);
      }),
    );

    // One item per batch: the second is left for the fast (250 ms) retry.
    await service.flushPendingSync(api: api, maxItems: 1);
    expect(patches, ['/api/me/progress/book-1']);

    UserAccountService().switchTo(server, 'bob');
    await service.saveLocal(
        itemId: 'book-2', currentTime: 900, duration: 1000, speed: 1);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(patches, ['/api/me/progress/book-1']);
    expect(await pendingFor(scopeB), ['book-2']);
  });

  test('saves made during a flush keep their pending mark', () async {
    await seedAccounts();
    final service = ProgressSyncService();
    await service.saveLocal(
        itemId: 'book-1', currentTime: 10, duration: 1000, speed: 1);

    final api = ApiService(
      baseUrl: server,
      token: 'a-token',
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.startsWith('/api/me/progress/')) {
          return http.Response(jsonEncode({'currentTime': 1}), 200);
        }
        if (request.method == 'GET') return itemFixture(request);
        return http.Response('{}', 200);
      }),
    );

    // The removal of book-1 and the add of book-2 race on one list.
    final flush = service.flushPendingSync(api: api, maxItems: 1);
    final saves = Future.wait([
      for (var i = 0; i < 5; i++)
        service.saveLocal(
            itemId: 'book-${i + 2}', currentTime: 30, duration: 1000, speed: 1),
    ]);
    await Future.wait([flush, saves]);

    final pending = await pendingFor(scopeA);
    for (var i = 2; i <= 6; i++) {
      expect(pending, contains('book-$i'));
    }
    // Stop the follow-up retry from running into the next test.
    UserAccountService().switchTo(server, 'bob');
  });
}
