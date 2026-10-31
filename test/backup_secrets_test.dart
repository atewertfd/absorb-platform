import 'package:absorb/services/backup_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A settings-only backup is a file people hand around: it must not carry the
/// ReadMeABook token or any custom auth headers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      packageInfo,
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
      'rmab_base_url': 'https://rmab.example',
      'rmab_api_token': 'rmab-fixture-token',
      'rmab_custom_headers': '{"CF-Access-Client-Secret":"fixture"}',
      'settingsSyncUrl': 'https://dav.example/absorb',
      'settingsSyncUser': 'reader',
      'settingsSyncPass': 'fixture-password',
      'settingsSyncHeaders': '{"X-Proxy-Key":"fixture"}',
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfo, null);
  });

  test('a settings-only backup leaves tokens and headers out', () async {
    final data = await BackupService.exportSettings(includeAccounts: false);

    final rmab = data['rmab'] as Map<String, dynamic>;
    expect(rmab['baseUrl'], 'https://rmab.example');
    expect(rmab, isNot(contains('apiToken')));
    expect(rmab, isNot(contains('customHeaders')));
    final sync = data['settingsSync'] as Map<String, dynamic>;
    expect(sync['url'], 'https://dav.example/absorb');
    expect(sync, isNot(contains('headers')));
    expect(sync, isNot(contains('password')));
  });

  test('a backup with accounts keeps them', () async {
    final data = await BackupService.exportSettings(includeAccounts: true);

    final rmab = data['rmab'] as Map<String, dynamic>;
    expect(rmab['apiToken'], 'rmab-fixture-token');
    expect(rmab['customHeaders'], contains('CF-Access-Client-Secret'));
    final sync = data['settingsSync'] as Map<String, dynamic>;
    expect(sync['headers'], contains('X-Proxy-Key'));
    expect(sync['password'], 'fixture-password');
  });

  test('settings sync opt-in still carries the RMAB token', () async {
    final data = await BackupService.exportSettings(
        includeAccounts: false, includeRmabSecrets: true);

    final rmab = data['rmab'] as Map<String, dynamic>;
    expect(rmab['apiToken'], 'rmab-fixture-token');
    final sync = data['settingsSync'] as Map<String, dynamic>;
    expect(sync, isNot(contains('headers')));
  });
}
