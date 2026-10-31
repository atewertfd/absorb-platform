import 'dart:async';

import 'package:absorb/l10n/app_localizations.dart';
import 'package:absorb/services/windows_shell.dart';
import 'package:absorb/widgets/windows_settings_tiles.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlayback extends ChangeNotifier implements WindowsShellPlayback {
  @override
  bool hasBook = false;
  @override
  bool isPlaying = false;
  @override
  double progress = 0;
  final calls = <String>[];
  Completer<void>? saveGate;

  void set({bool? book, bool? playing, double? at}) {
    hasBook = book ?? hasBook;
    isPlaying = playing ?? isPlaying;
    progress = at ?? progress;
    notifyListeners();
  }

  @override
  Future<void> playPause() async => calls.add('playPause');
  @override
  Future<void> rewind() async => calls.add('rewind');
  @override
  Future<void> forward() async => calls.add('forward');
  @override
  Future<void> saveForExit() async {
    calls.add('save');
    await saveGate?.future;
  }
}

class _FakeDownloads extends ChangeNotifier implements WindowsShellDownloads {
  @override
  bool busy = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('absorb/windows_shell');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> sent;
  late Map<String, Object?> nativeState;

  setUp(() {
    sent = [];
    nativeState = {
      'closeToTray': false,
      'startMinimized': false,
      'startWithWindows': false,
      'startWithWindowsThisCopy': false,
      'startWithWindowsCommand': '',
      'alwaysOnTop': false,
      'keepAwake': true,
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      if (call.method.startsWith('set') &&
          call.arguments is Map &&
          (call.arguments as Map).containsKey('enabled')) {
        final key = call.method.substring(3, 4).toLowerCase() +
            call.method.substring(4);
        nativeState[key] = (call.arguments as Map)['enabled'];
        if (key == 'startWithWindows') {
          nativeState['startWithWindowsThisCopy'] = nativeState[key];
          nativeState['startWithWindowsCommand'] =
              nativeState[key] == true ? '"C:\\Apps\\absorb.exe"' : '';
        }
      }
      if (call.method == 'getState' || call.arguments is Map &&
          (call.arguments as Map).containsKey('enabled')) {
        return Map<String, Object?>.from(nativeState);
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> nativeCalls(String method, [Object? arguments]) async {
    final completer = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      completer.complete,
    );
    await completer.future;
  }

  group('TaskbarProgressThrottle', () {
    test('state changes go out at once, progress at most once a second', () {
      var now = DateTime(2026);
      final throttle = TaskbarProgressThrottle(clock: () => now);
      expect(throttle.shouldSend(TaskbarPlayback.playing, 0.10), isTrue);
      now = now.add(const Duration(milliseconds: 300));
      expect(throttle.shouldSend(TaskbarPlayback.playing, 0.20), isFalse,
          reason: 'too soon');
      expect(throttle.shouldSend(TaskbarPlayback.paused, 0.20), isTrue,
          reason: 'state change');
      now = now.add(const Duration(seconds: 2));
      expect(throttle.shouldSend(TaskbarPlayback.paused, 0.203), isFalse,
          reason: 'moved less than 0.5%');
      expect(throttle.shouldSend(TaskbarPlayback.paused, 0.206), isTrue);
    });
  });

  group('WindowsShell', () {
    late _FakePlayback playback;
    late _FakeDownloads downloads;
    late WindowsShell shell;
    late DateTime now;

    setUp(() {
      playback = _FakePlayback();
      downloads = _FakeDownloads();
      now = DateTime(2026);
      shell = WindowsShell.withSources(
        channel: channel,
        playback: playback,
        downloads: downloads,
        clock: () => now,
      );
    });

    tearDown(() => shell.stop());

    test('start sends labels, playback state and the settings', () async {
      await shell.start();
      final methods = sent.map((c) => c.method).toList();
      expect(methods, containsAll(['setStrings', 'setPlayback', 'getState']));
      final strings = sent.firstWhere((c) => c.method == 'setStrings');
      expect((strings.arguments as Map)['quit'], 'Quit Absorb Plus');
      expect(shell.settings.value?.keepAwake, isTrue);
      final playbackCall = sent.firstWhere((c) => c.method == 'setPlayback');
      expect(playbackCall.arguments, {'state': 'none', 'progress': 0.0});
    });

    test('playing or downloading asks the PC to stay awake', () async {
      await shell.start();
      sent.clear();
      playback.set(book: true, playing: true, at: 0.5);
      expect(
        sent.where((c) => c.method == 'setBusy').map((c) => c.arguments),
        [
          {'busy': true}
        ],
      );
      expect(sent.firstWhere((c) => c.method == 'setPlayback').arguments,
          {'state': 'playing', 'progress': 0.5});
      sent.clear();
      playback.set(playing: false);
      expect(sent.map((c) => c.arguments), contains(equals({'busy': false})));
    });

    testWidgets('progress ticks while playing are throttled', (tester) async {
      await shell.start();
      playback.set(book: true, playing: true, at: 0.10);
      sent.clear();
      playback.progress = 0.101; // less than 0.5%
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(sent.where((c) => c.method == 'setPlayback'), isEmpty);
      playback.progress = 0.12;
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(sent.where((c) => c.method == 'setPlayback').length, 1);
      playback.set(playing: false);
      sent.clear();
      playback.progress = 0.5;
      await tester.pump(const Duration(seconds: 5));
      expect(sent.where((c) => c.method == 'setPlayback'), isEmpty,
          reason: 'no polling while paused');
      shell.stop();
    });

    test('taskbar and tray buttons run the player actions', () async {
      await shell.start();
      await nativeCalls('action', 'playPause');
      expect(playback.calls, isEmpty, reason: 'nothing loaded');
      playback.set(book: true);
      await nativeCalls('action', 'playPause');
      await nativeCalls('action', 'rewind');
      await nativeCalls('action', 'forward');
      expect(playback.calls, ['playPause', 'rewind', 'forward']);
    });

    test('quitting while playing saves the position first', () async {
      await shell.start();
      playback.set(book: true, playing: true);
      await nativeCalls('prepareToExit');
      expect(playback.calls, ['save']);
    });

    test('quitting while paused does not touch the player', () async {
      await shell.start();
      playback.set(book: true, playing: false);
      await nativeCalls('prepareToExit');
      expect(playback.calls, isEmpty);
    });

    testWidgets('a stuck save cannot hold the quit forever', (tester) async {
      await shell.start();
      playback.set(book: true, playing: true);
      playback.saveGate = Completer<void>();
      var done = false;
      unawaited(shell.prepareToExit().then((_) => done = true));
      await tester.pump(const Duration(seconds: 2));
      expect(done, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(done, isTrue);
      shell.stop();
    });

    test('settings setters return the runner state', () async {
      final result = await shell.setCloseToTray(true);
      expect(result?.closeToTray, isTrue);
      expect(sent.last.method, 'setCloseToTray');
      expect(sent.last.arguments, {'enabled': true});
    });
  });

  test('off Windows the app shell is a no-op', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      // A fresh instance is not available; the shared one was created for
      // the test platform (Android by default), so it does nothing.
      expect(WindowsShell.instance.isSupported, isFalse);
      await WindowsShell.instance.start();
      expect(await WindowsShell.instance.refresh(), isNull);
      expect(sent, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('settings tiles show and change the runner settings',
      (tester) async {
    final shell = WindowsShell.withSources(
      channel: channel,
      playback: _FakePlayback(),
      downloads: _FakeDownloads(),
    );
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: WindowsSettingsTiles(shell: shell)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Close to tray'), findsOneWidget);
    expect(find.text('Keep PC awake while playing or downloading'),
        findsOneWidget);

    // Start minimized only applies to starting with Windows.
    final minimized = find.widgetWithText(SwitchListTile, 'Start minimized');
    expect(tester.widget<SwitchListTile>(minimized).onChanged, isNull);

    await tester.tap(find.text('Start with Windows'));
    await tester.pumpAndSettle();
    expect(sent.last.method, 'setStartWithWindows');
    expect(find.textContaining('absorb.exe'), findsOneWidget,
        reason: 'shows the registered path');
    expect(tester.widget<SwitchListTile>(minimized).onChanged, isNotNull);

    await tester.tap(find.text('Always on top'));
    await tester.pumpAndSettle();
    expect(sent.last.method, 'setAlwaysOnTop');
    expect(sent.last.arguments, {'enabled': true});
  });
}
