// Progress round trips, two-account isolation and a playback session
// (open, sync, close) against the throwaway server.
// Run with .\tool\dev.ps1 itest (see abs_test_server.dart).
@Tags(['abs-server'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'abs_test_server.dart';

void main() {
  test('progress round trip: update, read back, mark finished, unfinish', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;
    final api = await server.api();
    final book = await server.book(api, multiFileBookTitle);
    final itemId = book['id'] as String;
    final duration = (book['media']['duration'] as num).toDouble();

    expect(await api.updateProgress(itemId, currentTime: 12.5, duration: duration), isTrue);
    final saved = await api.getItemProgress(itemId);
    expect(saved, isNotNull);
    expect((saved!['currentTime'] as num).toDouble(), closeTo(12.5, 0.01));
    expect(saved['isFinished'], isFalse);
    expect((saved['progress'] as num).toDouble(), closeTo(12.5 / duration, 0.01));

    await api.markFinished(itemId, duration);
    expect((await api.getItemProgress(itemId))?['isFinished'], isTrue);

    expect(await api.updateProgress(itemId, currentTime: 0, duration: duration, isFinished: false), isTrue);
    expect((await api.getItemProgress(itemId))?['isFinished'], isFalse);
  });

  test('two accounts keep separate progress for the same book', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;
    if (server.username2.isEmpty) {
      markTestSkipped('ABS_TEST_USER2 not set: re-run dev.ps1 server seed');
      return;
    }
    final root = await server.api();
    final listener = await server.api(second: true);
    expect((await listener.getMe())?['username'], server.username2);

    final book = await server.book(root, chapteredBookTitle);
    final itemId = book['id'] as String;
    final duration = (book['media']['duration'] as num).toDouble();

    expect(await root.updateProgress(itemId, currentTime: 20, duration: duration), isTrue);
    expect(await listener.updateProgress(itemId, currentTime: 5, duration: duration), isTrue);

    expect((await root.getItemProgress(itemId))?['currentTime'], closeTo(20, 0.01));
    expect((await listener.getItemProgress(itemId))?['currentTime'], closeTo(5, 0.01));
  });

  test('playback session: open, sync, close, and the sync lands in progress', () async {
    final server = await AbsTestServer.orSkip();
    if (server == null) return;
    final api = await server.api();
    final book = await server.book(api, chapteredBookTitle);
    final itemId = book['id'] as String;

    final session = await api.startPlaybackSession(itemId);
    expect(session, isNotNull, reason: 'POST /api/items/:id/play');
    final sessionId = session!['id'] as String;
    final duration = (session['duration'] as num).toDouble();
    expect(duration, closeTo(30, 2));
    expect(session['playMethod'], 0, reason: 'direct play');
    expect(session['chapters'], hasLength(2));
    final tracks = (session['audioTracks'] as List).cast<Map<String, dynamic>>();
    expect(tracks, hasLength(1));

    // The track URL the player would open must actually serve audio.
    final trackUrl = api.buildTrackUrl(
      tracks.first['contentUrl'] as String,
      sessionId: sessionId,
      trackIndex: tracks.first['index'] as int?,
      playMethod: session['playMethod'] as int?,
    );
    expect(Uri.parse(trackUrl).host, Uri.parse(server.url).host);
    final audio = await http.get(
      Uri.parse(trackUrl),
      headers: {...api.playbackSessionHeaders, 'Range': 'bytes=0-1023'},
    );
    expect(audio.statusCode, anyOf(200, 206), reason: trackUrl.replaceAll(RegExp(r'token=[^&]+'), 'token=***'));
    expect(audio.bodyBytes, isNotEmpty);

    expect(await api.syncPlaybackSessionStatus(sessionId, currentTime: 17.25, duration: duration, timeListened: 5), 200);
    final progress = await api.getItemProgress(itemId);
    expect((progress?['currentTime'] as num?)?.toDouble(), closeTo(17.25, 0.01));

    await api.closePlaybackSession(sessionId);
    expect(
      await api.syncPlaybackSessionStatus(sessionId, currentTime: 18, duration: duration),
      404,
      reason: 'a closed session is gone on the server',
    );
  });
}
