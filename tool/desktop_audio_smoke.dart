// Build with flutter build windows -t tool/desktop_audio_smoke.dart --release,
// then run the executable (or use Linux). No server or user data is needed.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show AppExitType;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:absorb/services/_audio_player.dart';
import 'package:absorb/services/audio_player_service.dart';
import 'package:absorb/services/desktop_audio.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const SizedBox.shrink());
      final watchdog = Timer(const Duration(seconds: 60), () {
        stderr.writeln('DESKTOP_AUDIO_SMOKE FAIL: timed out');
        exit(1);
      });
      try {
        if (const bool.fromEnvironment('AUDIO_SMOKE_LIFECYCLE_ONLY')) {
          stdout.writeln('LIFECYCLE ONLY: playback checks skipped');
        } else {
          await _verify();
          stdout.writeln('DESKTOP_AUDIO_SMOKE PASS');
        }
        // Let Flutter tear down native plugins through the normal window close.
        await ServicesBinding.instance.exitApplication(AppExitType.required);
        watchdog.cancel();
      } catch (error, stack) {
        stderr.writeln('DESKTOP_AUDIO_SMOKE FAIL: $error\n$stack');
        exit(1);
      }
    },
    (error, stack) {
      stderr.writeln('DESKTOP_AUDIO_SMOKE FAIL (async): $error\n$stack');
      exit(1);
    },
  );
}

Future<void> _verify() async {
  if (!Platform.isWindows && !Platform.isLinux) {
    throw UnsupportedError('This test requires native Windows or Linux.');
  }
  final directory = await Directory.systemTemp.createTemp(
    'absorb-audio-smoke-',
  );
  final mediaErrors = <Object>[];
  final errorSubscription = AudioService.asyncError.listen(mediaErrors.add);
  AudioPlayerHandler? handler;
  try {
    final file = File('${directory.path}/silence.wav');
    await file.writeAsBytes(_silentWav());
    initializeDesktopAudio();
    handler = await AudioService.init<AudioPlayerHandler>(
      builder: AudioPlayerHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.absorb.plus.audio.smoke',
        androidNotificationChannelName: 'Absorb Plus audio test',
      ),
    );
    stdout.writeln('PASS native media service initialization');
    final player = handler.player;
    await player.setVolume(0);
    final duration = await player.setAudioSource(AudioSource.uri(file.uri));
    _expect(duration != null && duration.inSeconds == 12, 'WAV duration');
    handler.mediaItem.add(
      MediaItem(
        id: file.uri.toString(),
        title: 'Absorb Plus silent playback test',
        artist: 'Local generated fixture',
        duration: duration,
      ),
    );
    stdout.writeln('PASS file decoding and media metadata submission');
    unawaited(handler.play());
    await _until(() => player.position.inMilliseconds >= 500);
    await handler.pause();
    _expect(!player.playing, 'paused state');
    final pausedPosition = player.position;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _expect(
      (player.position - pausedPosition).inMilliseconds.abs() < 150,
      'position remains paused',
    );
    stdout.writeln('PASS playback advances and pause holds position');
    await handler.seek(const Duration(seconds: 4));
    await _until(() => (player.position.inMilliseconds - 4000).abs() < 300);
    await player.setSpeed(1.5);
    _expect(player.speed == 1.5, 'speed changes');
    unawaited(handler.play());
    final start = player.position;
    final elapsed = Stopwatch()..start();
    await _until(() => (player.position - start).inMilliseconds >= 1500);
    elapsed.stop();
    _expect(elapsed.elapsedMilliseconds < 1400, 'speed affects playback clock');
    await handler.pause();
    stdout.writeln('PASS seek and 1.5x playback clock');
    await _verifyStreaming(player);
    await player.setAudioSource(
      ConcatenatingAudioSource(
        children: [AudioSource.uri(file.uri), AudioSource.uri(file.uri)],
      ),
    );
    for (var attempt = 0; attempt < 6; attempt++) {
      final index = (attempt + 1) % 2;
      await player.seek(const Duration(seconds: 2), index: index);
      await _until(
        () =>
            player.currentIndex == index &&
            (player.position.inMilliseconds - 2000).abs() < 300,
      );
      // A stale optimistic position must not count as a successful native seek.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _expect(
        (player.position.inMilliseconds - 2000).abs() < 300,
        'cross-file position remains correct after loading',
      );
    }
    await player.setAudioSource(
      AudioSource.uri(file.uri),
      initialPosition: const Duration(seconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _expect(
      (player.position.inMilliseconds - 5000).abs() < 300,
      'saved starting position is applied after loading',
    );
    stdout.writeln(
      'PASS repeated multi-file seeking and saved starting position',
    );
    await handler.stop();
    _expect(!player.playing, 'stopped state');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _expect(mediaErrors.isEmpty, 'native media service errors: $mediaErrors');
  } finally {
    await handler?.player.dispose();
    await errorSubscription.cancel();
    // Only the unique directory created by this test is removed.
    await directory.delete(recursive: true);
  }
}

Future<void> _verifyStreaming(AudioPlayer player) async {
  final bytes = _silentWav();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var authorizedRequests = 0;
  final subscription = server.listen((request) async {
    // Deliberately fake token. Never read or use the user's credentials.
    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer absorb-smoke-fixture') {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    authorizedRequests++;
    var start = 0;
    var end = bytes.length - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final match = range == null
        ? null
        : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (match != null) {
      start = int.parse(match[1]!);
      if (match[2]!.isNotEmpty) end = int.parse(match[2]!);
      if (start > end || start >= bytes.length) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }
      end = end.clamp(start, bytes.length - 1);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${bytes.length}',
      );
    }
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.contentType = ContentType('audio', 'wav');
    request.response.contentLength = end - start + 1;
    if (request.method != 'HEAD')
      request.response.add(bytes.sublist(start, end + 1));
    await request.response.close();
  });
  try {
    final duration = await player.setAudioSource(
      AudioSource.uri(
        Uri.parse('http://127.0.0.1:${server.port}/fixture.wav'),
        headers: {'Authorization': 'Bearer absorb-smoke-fixture'},
      ),
    );
    _expect(
      duration?.inSeconds == 12 && authorizedRequests > 0,
      'HTTP decoding with authorization header',
    );
    await player.seek(const Duration(seconds: 3));
    unawaited(player.play());
    await _until(() => player.position.inMilliseconds >= 3500);
    await player.pause();
    stdout.writeln('PASS authenticated loopback HTTP playback and seeking');
  } finally {
    await player.stop();
    await server.close(force: true);
    await subscription.cancel();
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for playback state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void _expect(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Uint8List _silentWav() {
  const sampleRate = 22050;
  const dataLength = sampleRate * 12 * 2;
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
