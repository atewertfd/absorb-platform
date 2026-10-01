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
}
