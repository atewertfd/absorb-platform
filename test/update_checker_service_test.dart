import 'dart:async';
import 'dart:io';

import 'package:absorb/services/update_checker_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Streams whatever the test adds. Closing it fails the open response the way
/// a real client does: with a ClientException, not a clean end.
class _ClosableStreamingClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  int statusCode = 200;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body.stream, statusCode, contentLength: 100);

  @override
  void close() {
    if (closed) return;
    closed = true;
    if (!body.isClosed) {
      body.addError(http.ClientException('Connection closed'));
      body.close();
    }
  }
}

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('absorb_update_test');
    file = File('${dir.path}/Absorb-1.12.1-Setup.exe');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final url = Uri.parse('https://example.invalid/Absorb-1.12.1-Setup.exe');

  test('cancel mid-download is a cancellation, not a failure, and cleans up',
      () async {
    final client = _ClosableStreamingClient();
    final download = UpdateDownload(client);
    final firstChunk = Completer<void>();

    final run = download.run(url, file, (_, __) {
      if (!firstChunk.isCompleted) firstChunk.complete();
    });
    client.body.add(List<int>.filled(40, 1));
    await firstChunk.future;
    expect(file.existsSync(), isTrue);

    download.cancel();

    Object? error;
    try {
      await run;
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(error, isNot(isA<http.ClientException>()));
    expect(UpdateDownload.isCancellation(error!), isTrue);
    expect(file.existsSync(), isFalse);
    expect(client.closed, isTrue);
  });

  test('a real failure stays a failure and still deletes the partial file',
      () async {
    final client = _ClosableStreamingClient();
    final download = UpdateDownload(client);
    final firstChunk = Completer<void>();

    final run = download.run(url, file, (_, __) {
      if (!firstChunk.isCompleted) firstChunk.complete();
    });
    client.body.add(List<int>.filled(40, 1));
    await firstChunk.future;
    client.body.addError(http.ClientException('reset by peer'));

    await expectLater(run, throwsA(isA<http.ClientException>()));
    expect(file.existsSync(), isFalse);
  });

  test('a finished download keeps the file', () async {
    final client = _ClosableStreamingClient();
    final download = UpdateDownload(client);

    final run = download.run(url, file, (_, __) {});
    client.body.add(List<int>.filled(100, 1));
    await client.body.close();

    expect(await run, file);
    expect(file.lengthSync(), 100);
  });

  test('cancel before the request starts never touches the network',
      () async {
    final client = _ClosableStreamingClient();
    final download = UpdateDownload(client)..cancel();

    Object? error;
    try {
      await download.run(url, file, (_, __) {});
    } catch (e) {
      error = e;
    }
    expect(UpdateDownload.isCancellation(error!), isTrue);
    expect(file.existsSync(), isFalse);
  });

  group('in-flight checks', () {
    final original = UpdateCheckerService.runCheck;
    tearDown(() => UpdateCheckerService.runCheck = original);

    test('a manual check is not handed the running automatic result',
        () async {
      SharedPreferences.setMockInitialValues({});
      final automaticGate = Completer<void>();
      final calls = <bool>[];
      UpdateCheckerService.runCheck = ({
        required bool force,
        required bool includePreReleases,
        Duration? cooldown,
      }) async {
        calls.add(force);
        if (!force) {
          await automaticGate.future;
          return const UpdateCheckResult(UpdateCheckStatus.skipped);
        }
        return const UpdateCheckResult(UpdateCheckStatus.upToDate);
      };

      final automatic = UpdateCheckerService.checkAutomatically();
      while (calls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final manual = UpdateCheckerService.check(force: true);

      expect((await manual).status, UpdateCheckStatus.upToDate);
      expect(calls, [false, true]);
      automaticGate.complete();
      expect(await automatic, isNull);
    });

    test('simultaneous manual checks still share one request', () async {
      final gate = Completer<void>();
      var calls = 0;
      UpdateCheckerService.runCheck = ({
        required bool force,
        required bool includePreReleases,
        Duration? cooldown,
      }) async {
        calls++;
        await gate.future;
        return const UpdateCheckResult(UpdateCheckStatus.upToDate);
      };

      final first = UpdateCheckerService.check(force: true);
      final second = UpdateCheckerService.check(force: true);
      gate.complete();
      await Future.wait([first, second]);
      expect(calls, 1);
    });
  });
}
