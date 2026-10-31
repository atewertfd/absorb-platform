import 'dart:io' as io;

import 'package:absorb/utils/web_safe_platform.dart';
import 'package:flutter_test/flutter_test.dart';

/// Files on the web's startup, sign-in, library and playback paths. Each one
/// must read the web-safe [Platform] (dart:io's throws "Unsupported
/// operation: Platform._operatingSystem" on the web), so an upstream merge
/// that brings back a bare `import 'dart:io';` fails here instead of in the
/// browser console.
const _webReachable = <String>[
  'lib/main.dart',
  'lib/screens/app_shell.dart',
  'lib/screens/backup_sync_screen.dart',
  'lib/screens/chapter_editor_screen.dart',
  'lib/screens/settings_screen.dart',
  'lib/screens/settings_search_index.dart',
  'lib/services/_audio_player.dart',
  'lib/services/android_auto_service.dart',
  'lib/services/audio_player_service.dart',
  'lib/services/chromecast_service.dart',
  'lib/services/clip_export_service.dart',
  'lib/services/dictionary_service.dart',
  'lib/services/download_service.dart',
  'lib/services/episode_notification_service.dart',
  'lib/services/home_widget_service.dart',
  'lib/services/quick_actions_service.dart',
  'lib/services/translate_service.dart',
  'lib/services/up_next_narration.dart',
  'lib/widgets/audible_series_sheet.dart',
  'lib/widgets/bookmark_detail_dialog.dart',
  'lib/widgets/card_button_config.dart',
  'lib/widgets/ebook_reader_view.dart',
  'lib/widgets/equalizer_sheet.dart',
];

void main() {
  test('answers exactly like dart:io on native platforms', () {
    expect(Platform.isAndroid, io.Platform.isAndroid);
    expect(Platform.isIOS, io.Platform.isIOS);
    expect(Platform.isWindows, io.Platform.isWindows);
    expect(Platform.isLinux, io.Platform.isLinux);
    expect(Platform.isMacOS, io.Platform.isMacOS);
  });

  test('web-reachable files use the web-safe Platform', () {
    final dartIoPlatform = RegExp(
      r"^import 'dart:io'(?! hide Platform)(?! show (?![^;]*\bPlatform\b))",
      multiLine: true,
    );
    for (final path in _webReachable) {
      final source = io.File(path).readAsStringSync();
      expect(source, contains('web_safe_platform.dart'), reason: path);
      expect(dartIoPlatform.hasMatch(source), isFalse, reason: path);
    }
  });
}
