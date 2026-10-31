import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:absorb/services/settings_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsSyncService sync;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => {
            'appName': 'Absorb',
            'packageName': 'com.example.absorb',
            'version': 'fixture',
            'buildNumber': '1',
            'buildSignature': '',
            'installerStore': null,
          },
        );
    SharedPreferences.setMockInitialValues({
      'settingsSyncEnabled': true,
      'settingsSyncUrl': 'https://dav.example/absorb',
      'settingsSyncUser': 'reader',
      'settingsSyncPass': 'fixture-password',
    });
    sync = SettingsSyncService();
    SettingsSyncService.testClient = null;
  });

  tearDown(() {
    SettingsSyncService.testClient = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          null,
        );
  });

  test(
    'push sends an allowlisted payload without account credentials',
    () async {
      http.Request? request;
      SettingsSyncService.testClient = MockClient((incoming) async {
        request = incoming;
        return http.Response('', 201);
      });

      final result = await sync.push();

      expect(result.ok, isTrue);
      expect(request, isNotNull);
      expect(request!.url.path, endsWith('.json'));
      expect(request!.url.path, contains('/absorb-settings-'));
      expect(request!.headers['content-type'], contains('application/json'));
      final auth = request!.headers['authorization']!;
      expect(
        utf8.decode(base64.decode(auth.substring('Basic '.length))),
        'reader:fixture-password',
      );
      final payload = jsonDecode(request!.body) as Map<String, dynamic>;
      expect(payload['syncedAt'], isA<int>());
      expect(payload, isNot(contains('accounts')));
      expect(payload, isNot(contains('token')));
      expect(payload, isNot(contains('refreshToken')));
    },
  );


  test('a refused PUT pauses automatic pushes until the sign-in changes',
      () async {
    sync.debugResetBackoff();
    var puts = 0;
    var status = 401;
    SettingsSyncService.testClient = MockClient((incoming) async {
      if (incoming.method == 'PUT') puts++;
      return http.Response('', status);
    });

    final first = await sync.pushIfChanged();
    expect(first.status, SyncStatus.authFailed);
    expect(puts, 1);

    // The 45 s tick and coming back to the app must not retry the password.
    final tick = await sync.pushIfChanged();
    expect(tick.status, SyncStatus.authFailed);
    expect(puts, 1);
    await sync.onAppForegrounded();
    await sync.onAppBackgrounded(); // also cancels the tick timer
    expect(puts, 1);

    // The Sync button still tries.
    status = 201;
    final manual = await sync.pushIfChanged(ignoreBackoff: true);
    expect(manual.ok, isTrue);
    expect(puts, 2);
  });

  test('new credentials lift the pause after a refused PUT', () async {
    sync.debugResetBackoff();
    var puts = 0;
    SettingsSyncService.testClient = MockClient((incoming) async {
      if (incoming.method != 'PUT') return http.Response('', 404);
      puts++;
      final auth = incoming.headers['authorization']!;
      final creds = utf8.decode(base64.decode(auth.substring('Basic '.length)));
      return http.Response('', creds.endsWith(':new-password') ? 201 : 403);
    });

    expect((await sync.pushIfChanged()).status, SyncStatus.authFailed);
    expect(puts, 1);
    await sync.setPassword('new-password');
    expect((await sync.pushIfChanged()).ok, isTrue);
    expect(puts, 2);
  });

  test('any other refused PUT backs off instead of retrying each tick',
      () async {
    sync.debugResetBackoff();
    var puts = 0;
    SettingsSyncService.testClient = MockClient((incoming) async {
      if (incoming.method == 'PUT') puts++;
      return http.Response('', 507);
    });

    expect((await sync.pushIfChanged()).status, SyncStatus.network);
    expect(puts, 1);
    final tick = await sync.pushIfChanged();
    expect(tick.message, 'waiting to retry');
    expect(puts, 1);
  });
}
