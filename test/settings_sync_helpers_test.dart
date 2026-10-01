import 'package:absorb/services/settings_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom WebDAV header parser preserves values containing colons', () {
    expect(
      SettingsSyncService.parseHeaderLines('''
      X-Access: bearer abc:def
      Empty:
      Invalid line
      X-Access: replacement
    '''),
      {'X-Access': 'replacement', 'Empty': ''},
    );
  });

  test(
    'header serialization round-trips arbitrary header names and values',
    () {
      const headers = {
        'X-Access': 'bearer abc:def',
        'X-Trace': 'value with spaces',
      };
      expect(
        SettingsSyncService.parseHeaderLines(
          SettingsSyncService.headerLines(headers),
        ),
        headers,
      );
    },
  );

  test('invalid header lines are ignored instead of becoming credentials', () {
    expect(
      SettingsSyncService.parseHeaderLines(
        'Authorization\n: missing-name\n  :\n',
      ),
      isEmpty,
    );
  });
}
