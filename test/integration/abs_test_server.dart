// Shared setup for the abs-server integration suites.
//
// The suites talk to the throwaway Audiobookshelf server in tool/test-server
// (`dev.ps1 server up`, `dev.ps1 server seed`, `dev.ps1 itest`). Credentials
// come from environment variables that `dev.ps1 itest` reads from
// tool/test-server/.env. Only a loopback URL is accepted, so these tests can
// never reach a real server.
//
// Use plain test(), never testWidgets(): the widget binding replaces
// HttpClient with one that answers 400 to everything.

import 'dart:io';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/auth_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const testLibraryName = 'Absorb Test Books';
const multiFileBookTitle = 'Multi File Book';
const chapteredBookTitle = 'Chaptered Book';

class AbsTestServer {
  AbsTestServer._({
    required this.url,
    required this.username,
    required this.password,
    required this.username2,
    required this.password2,
  });

  final String url;
  final String username;
  final String password;
  final String username2;
  final String password2;

  static Future<(AbsTestServer?, String?)>? _probe;

  /// The server, or null after marking the current test skipped with the
  /// reason (missing credentials, non-loopback URL, server not answering).
  static Future<AbsTestServer?> orSkip() async {
    final (server, reason) = await (_probe ??= _connect());
    if (server == null) markTestSkipped(reason!);
    return server;
  }

  static Future<(AbsTestServer?, String?)> _connect() async {
    // ApiService touches SharedPreferences for its server-version cache;
    // keep that in memory and off the real plugin.
    SharedPreferences.setMockInitialValues({});
    ApiService.deviceId = 'absorb-itest';
    ApiService.deviceModel = 'integration test';

    final env = Platform.environment;
    final url = env['ABS_TEST_URL'] ?? '';
    final user = env['ABS_TEST_USER'] ?? '';
    final pass = env['ABS_TEST_PASSWORD'] ?? '';
    if (url.isEmpty || user.isEmpty || pass.isEmpty) {
      return (null, 'ABS_TEST_URL/USER/PASSWORD not set: run .\\tool\\dev.ps1 server up, server seed, then itest');
    }
    final host = Uri.tryParse(url)?.host;
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') {
      return (null, 'ABS_TEST_URL must be a loopback address (got host "$host"); never a real server');
    }
    try {
      final r = await http.get(Uri.parse('$url/ping')).timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return (null, 'Test server at $url answered ${r.statusCode} to /ping');
    } catch (e) {
      return (null, 'Test server at $url is not reachable ($e): run .\\tool\\dev.ps1 server up');
    }
    return (
      AbsTestServer._(
        url: url,
        username: user,
        password: pass,
        username2: env['ABS_TEST_USER2'] ?? '',
        password2: env['ABS_TEST_PASSWORD2'] ?? '',
      ),
      null,
    );
  }

  // One real login per account per test file; the server limits logins.
  static final Map<String, AuthTokens> _sessions = {};

  /// Signs in through the app's own login call and returns the tokens.
  /// [fresh] forces a new login (for tests about login itself).
  Future<AuthTokens> login({bool second = false, bool fresh = false}) async {
    final key = '$url|${second ? username2 : username}';
    final cached = _sessions[key];
    if (!fresh && cached != null) return cached;
    final (data, status) = await ApiService.login(
      serverUrl: url,
      username: second ? username2 : username,
      password: second ? password2 : password,
    );
    expect(status, 200, reason: 'login as ${second ? username2 : username}');
    return _sessions[key] = AuthTokens.fromResponse(data!);
  }

  /// A signed-in ApiService, built the way the app builds one.
  Future<ApiService> api({bool second = false}) async {
    final tokens = await login(second: second);
    return ApiService(
      baseUrl: url,
      token: tokens.token!,
      refreshToken: tokens.refreshToken,
      isLegacyToken: tokens.isLegacy,
    );
  }

  Future<Map<String, dynamic>> testLibrary(ApiService api) async {
    final libs = await api.getLibraries();
    return libs.cast<Map<String, dynamic>>().firstWhere(
          (l) => l['name'] == testLibraryName,
          orElse: () => fail('library "$testLibraryName" missing: run dev.ps1 server seed'),
        );
  }

  /// The seeded book with [title], as the library listing returns it.
  Future<Map<String, dynamic>> book(ApiService api, String title) async {
    final lib = await testLibrary(api);
    final page = await api.getLibraryItems(lib['id'] as String, limit: 100);
    final results = (page?['results'] as List? ?? const []).cast<Map<String, dynamic>>();
    return results.firstWhere(
      (r) => r['media']?['metadata']?['title'] == title,
      orElse: () => fail('book "$title" missing: run dev.ps1 server seed'),
    );
  }
}

/// Polls [check] until it returns a non-null value or [timeout] passes.
Future<T?> eventually<T>(
  Future<T?> Function() check, {
  Duration timeout = const Duration(seconds: 60),
  Duration interval = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final value = await check();
    if (value != null) return value;
    if (DateTime.now().isAfter(deadline)) return null;
    await Future<void>.delayed(interval);
  }
}
