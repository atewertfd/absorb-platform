// Windows runner probe: starts the native pieces the real app starts (libmpv
// playback, SMTC, optionally a WebView2 view and the Windows shell channel)
// without signing in or reading account data, then waits for the window to
// be closed so tool/verify-windows-shell.ps1 can time the process exit.
//
// Build: flutter build windows --release --no-pub -t tool/windows_shell_probe.dart
// Run:   absorb.exe --probe [audio] [play] [webview] [shell] [flush=<file>]
// The harness rebuilds lib/main.dart afterwards.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:absorb/services/_audio_player.dart';
import 'package:absorb/services/audio_player_service.dart';
import 'package:absorb/services/desktop_audio.dart';
import 'package:absorb/services/windows_shell.dart';

void main(List<String> args) {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final options = args.toSet();
      final flushArg = args.firstWhere(
        (a) => a.startsWith('flush='),
        orElse: () => '',
      );
      WidgetsBinding.instance.addObserver(
        _ProbeObserver(flushArg.isEmpty ? null : flushArg.substring(6)),
      );
      runApp(_ProbeApp(webview: options.contains('webview')));
      if (options.contains('audio')) {
        await _startAudio(
          play: options.contains('play'),
          stream: options.contains('stream'),
          httpArt: options.contains('httpart'),
          fileArt: options.contains('fileart'),
        );
      }
      if (options.contains('shell')) {
        await _checkShell(
          flushFile: flushArg.isEmpty ? null : flushArg.substring(6),
          tray: options.contains('tray'),
          autostart: options.contains('autostart'),
        );
      }
      stdout.writeln('PROBE READY');
    },
    (error, stack) {
      stdout.writeln('PROBE FAIL: $error\n$stack');
      exit(3);
    },
  );
}

const _shellChannel = MethodChannel('absorb/windows_shell');

Future<Map<Object?, Object?>> _probe([Map<String, Object?>? args]) async =>
    (await _shellChannel.invokeMapMethod<Object?, Object?>('probe', args))!;

void _check(bool ok, String what) {
  stdout.writeln('${ok ? 'PROBE CHECK PASS' : 'PROBE CHECK FAIL'} $what');
}

/// Exercises the runner's shell channel and reports each result.
Future<void> _checkShell({
  String? flushFile,
  required bool tray,
  required bool autostart,
}) async {
  final shell = WindowsShell.withSources(
    channel: _shellChannel,
    playback: _ProbePlayback(flushFile),
    downloads: _NoDownloads(),
  );
  await shell.start();
  // Let the first frame show the window and the taskbar button appear.
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final start = await _probe();
  stdout.writeln('PROBE SHELL start $start');
  final dpi = start['dpi']! as int;
  final rect = start['windowRect']! as List;

  // Minimum size: ask for 100x100 and see what Windows allows.
  final small = await _probe({'resizeWidth': 100, 'resizeHeight': 100});
  final smallRect = small['windowRect']! as List;
  final monitor = small['monitorRect']! as List;
  final minW = (400 * dpi / 96).floor().clamp(0, (monitor[2] as int) * 9 ~/ 10);
  final minH = (600 * dpi / 96).floor().clamp(0, (monitor[3] as int) * 9 ~/ 10);
  _check((smallRect[2] as int) >= minW - 1 && (smallRect[3] as int) >= minH - 1,
      'minimum size ${smallRect[2]}x${smallRect[3]} >= ${minW}x$minH');
  await _probe({'resizeWidth': rect[2], 'resizeHeight': rect[3]});

  // Always on top, persisted and applied.
  var settings = await shell.setAlwaysOnTop(true);
  _check(settings!.alwaysOnTop && (await _probe())['topmost'] == true,
      'always on top on');
  settings = await shell.setAlwaysOnTop(false);
  _check(!settings!.alwaysOnTop && (await _probe())['topmost'] == false,
      'always on top off');

  // Full screen covers the monitor without a caption, then restores.
  final before = (await _probe())['windowRect'];
  await shell.toggleFullScreen();
  final full = await _probe();
  _check(
      full['fullScreen'] == true &&
          full['caption'] == false &&
          '${full['windowRect']}' == '${full['monitorRect']}',
      'full screen ${full['windowRect']} on ${full['monitorRect']}');
  await shell.toggleFullScreen();
  final back = await _probe();
  _check(back['fullScreen'] == false && back['caption'] == true &&
          '${back['windowRect']}' == '$before',
      'full screen restored ${back['windowRect']} == $before');

  // Keep awake: playing holds the system (not the display); Keep screen on
  // holds both.
  const esSystem = 0x1, esDisplay = 0x2;
  var es = (await _probe())['executionState']! as int;
  _check(es & esSystem != 0 && es & esDisplay == 0,
      'playing keeps the system awake, display free (0x${es.toRadixString(16)})');
  await const MethodChannel('com.absorb.screen_wake')
      .invokeMethod('set', {'on': true});
  es = (await _probe())['executionState']! as int;
  _check(es & esDisplay != 0, 'keep screen on holds the display');
  await const MethodChannel('com.absorb.screen_wake')
      .invokeMethod('set', {'on': false});
  settings = await shell.setKeepAwake(false);
  es = (await _probe())['executionState']! as int;
  _check(es & (esSystem | esDisplay) == 0,
      'keep awake off releases the system (0x${es.toRadixString(16)})');
  await shell.setKeepAwake(true);

  // Taskbar thumbnail buttons and progress.
  final taskbar = await _probe();
  _check(taskbar['taskbar'] == true && taskbar['thumbButtons'] == true &&
          taskbar['taskbarResult'] == 0,
      'taskbar buttons and progress (result ${taskbar['taskbarResult']})');

  if (autostart) {
    // Probe-only Run value "Absorb Plus (probe)"; removed again right away.
    settings = await shell.setStartWithWindows(true);
    await shell.setStartMinimized(true);
    final command = (await _probe())['runCommand']! as String;
    _check(settings!.startWithWindows &&
            command.contains('absorb.exe"') &&
            command.contains('--minimized'),
        'start with Windows registers $command');
    await shell.setStartMinimized(false);
    settings = await shell.setStartWithWindows(false);
    _check(!settings!.startWithWindows &&
            ((await _probe())['runCommand']! as String).isEmpty,
        'start with Windows removed');
  }

  if (tray) {
    settings = await shell.setCloseToTray(true);
    _check(settings!.closeToTray && (await _probe())['trayIcon'] == true,
        'tray icon shown');
  }
}

class _ProbePlayback extends ChangeNotifier implements WindowsShellPlayback {
  _ProbePlayback(this.flushFile);

  final String? flushFile;

  @override
  bool get hasBook => true;
  @override
  bool get isPlaying => true;
  @override
  double get progress => 0.25;
  @override
  Future<void> playPause() async => stdout.writeln('PROBE ACTION playPause');
  @override
  Future<void> rewind() async => stdout.writeln('PROBE ACTION rewind');
  @override
  Future<void> forward() async => stdout.writeln('PROBE ACTION forward');

  @override
  Future<void> saveForExit() async {
    // Stands in for the player's pause-and-save.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final path = flushFile;
    if (path != null) {
      await File(path).writeAsString('saved ${DateTime.now()}', flush: true);
    }
    stdout.writeln('PROBE FLUSHED');
  }
}

class _NoDownloads extends ChangeNotifier implements WindowsShellDownloads {
  @override
  bool get busy => false;
}

class _ProbeObserver with WidgetsBindingObserver {
  _ProbeObserver(this.flushFile);

  final String? flushFile;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    stdout.writeln('PROBE LIFECYCLE ${state.name}');
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    stdout.writeln('PROBE EXIT REQUESTED');
    final path = flushFile;
    if (path != null) {
      // Stands in for the player's final progress write.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await File(path).writeAsString('flushed ${DateTime.now()}', flush: true);
      stdout.writeln('PROBE FLUSHED');
    }
    return AppExitResponse.exit;
  }
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp({required this.webview});

  final bool webview;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: webview
            ? InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: '<html><body>Absorb probe</body></html>',
                ),
                onLoadStop: (_, __) => stdout.writeln('PROBE WEBVIEW LOADED'),
              )
            : const Center(child: Text('Absorb Plus shell probe')),
      ),
    );
  }
}

/// A loopback server that behaves like a stalled Audiobookshelf server: the
/// audio route sends the first part of the file and then stops sending
/// without closing, and the cover route never answers.
Future<HttpServer> _stalledServer(Uint8List wav) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/cover.png') return; // never answered
    request.response.headers.contentType = ContentType('audio', 'wav');
    request.response.contentLength = wav.length;
    request.response.add(wav.sublist(0, 22050 * 2 * 8));
    await request.response.flush();
    // Hold the connection open with no more data.
  });
  return server;
}

Future<void> _startAudio({
  required bool play,
  required bool stream,
  required bool httpArt,
  required bool fileArt,
}) async {
  final directory = await Directory.systemTemp.createTemp('absorb-shell-probe-');
  final file = File('${directory.path}/silence.wav');
  final wav = _silentWav();
  await file.writeAsBytes(wav);
  final cover = File('${directory.path}/cover.bmp');
  await cover.writeAsBytes(_tinyBmp());
  HttpServer? server;
  if (stream || httpArt) server = await _stalledServer(wav);
  initializeDesktopAudio();
  final handler = await AudioService.init<AudioPlayerHandler>(
    builder: AudioPlayerHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.absorb.plus.audio.probe',
      androidNotificationChannelName: 'Absorb Plus probe',
    ),
  );
  final player = handler.player;
  await player.setVolume(0);
  final source = stream
      ? Uri.parse('http://127.0.0.1:${server!.port}/audio.wav')
      : file.uri;
  final duration = await player.setAudioSource(AudioSource.uri(source));
  handler.mediaItem.add(
    MediaItem(
      id: source.toString(),
      title: 'Absorb Plus shell probe',
      artist: 'Local generated fixture',
      duration: duration,
      artUri: httpArt
          ? Uri.parse('http://127.0.0.1:${server!.port}/cover.png')
          : fileArt
              ? cover.uri
              : null,
    ),
  );
  if (play) {
    unawaited(handler.play());
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (player.position.inMilliseconds < 300 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    stdout.writeln('PROBE AUDIO PLAYING ${player.position.inMilliseconds}ms');
  } else {
    stdout.writeln('PROBE AUDIO LOADED');
  }
}

Uint8List _tinyBmp() {
  // 2x2 24-bit bitmap.
  final bytes = Uint8List(54 + 16);
  final h = ByteData.sublistView(bytes);
  bytes[0] = 0x42;
  bytes[1] = 0x4D;
  h.setUint32(2, bytes.length, Endian.little);
  h.setUint32(10, 54, Endian.little);
  h.setUint32(14, 40, Endian.little);
  h.setInt32(18, 2, Endian.little);
  h.setInt32(22, 2, Endian.little);
  h.setUint16(26, 1, Endian.little);
  h.setUint16(28, 24, Endian.little);
  h.setUint32(34, 16, Endian.little);
  for (var i = 54; i < bytes.length; i++) {
    bytes[i] = 0x80;
  }
  return bytes;
}

Uint8List _silentWav() {
  const sampleRate = 22050;
  const dataLength = sampleRate * 60 * 2;
  final bytes = Uint8List(44 + dataLength);
  final header = ByteData.sublistView(bytes);
  void tag(int offset, String text) =>
      bytes.setRange(offset, offset + 4, text.codeUnits);
  tag(0, 'RIFF');
  header.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, dataLength, Endian.little);
  return bytes;
}
