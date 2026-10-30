import 'package:absorb/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Sync and sign-in failures used to be swallowed without a trace. They now
// leave one log line each, with the same return values as before, and never
// the account's tokens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() => debugPrint = originalDebugPrint);

  ApiService unreachableServer() => ApiService(
        baseUrl: 'https://audiobookshelf.example',
        token: 'fixture-token',
        httpClient: MockClient((request) async {
          throw http.ClientException('Connection refused', request.url);
        }),
      );

  test('a failed session sync is logged and still returns null', () async {
    final api = unreachableServer();

    final status = await api.syncPlaybackSessionStatus(
      'session-1',
      currentTime: 10,
      duration: 100,
    );

    expect(status, isNull);
    expect(
      logs.where((l) => l.contains('[API] syncPlaybackSession session-1 error')),
      isNotEmpty,
    );
    expect(logs.where((l) => l.contains('fixture-token')), isEmpty);
  });

  test('a failed local session upload is logged and reports not ok', () async {
    final api = unreachableServer();

    final result = await api.syncLocalSession({
      'id': 'local-1',
      'libraryItemId': 'book-1',
    });

    expect(result.ok, isFalse);
    expect(result.serverTooOld, isFalse);
    expect(
      logs.where((l) => l.contains('[API] syncLocalSession local-1 error')),
      isNotEmpty,
    );
  });

  test('a failed progress read is logged and still returns null', () async {
    final api = unreachableServer();

    expect(await api.getItemProgress('book-1'), isNull);
    expect(
      logs.where((l) => l.contains('[API] getItemProgress book-1 error')),
      isNotEmpty,
    );
  });

  test('a login failure logs only the error type, never the reply', () async {
    const secret = 'leaky-refresh-token-value';
    final result = await http.runWithClient(
      () => ApiService.login(
        serverUrl: 'https://audiobookshelf.example',
        username: 'reader',
        password: 'fixture-password',
      ),
      // A truncated reply makes jsonDecode throw a FormatException that
      // quotes the body, tokens included.
      () => MockClient(
        (request) async =>
            http.Response('{"user":{"refreshToken":"$secret"', 200),
      ),
    );

    expect(result.$1, isNull);
    expect(result.$2, 0);
    expect(logs.where((l) => l.contains('[API] login failed')), isNotEmpty);
    expect(logs.where((l) => l.contains(secret)), isEmpty);
    expect(logs.where((l) => l.contains('fixture-password')), isEmpty);
  });
}
