import 'package:absorb/services/chapter_lookup.dart';
import 'package:absorb/services/cold_start_play_policy.dart';
import 'package:absorb/services/now_playing_layout.dart';
import 'package:absorb/services/playback_error_policy.dart';
import 'package:absorb/services/sleep_timer_tick_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sleepTimerTickAction', () {
    SleepTimerTickAction tick(
      Duration remaining, {
      bool active = true,
      bool pauseRequested = false,
    }) => sleepTimerTickAction(
      timeRemaining: remaining,
      isPlaybackActive: active,
      isPauseRequested: pauseRequested,
    );

    test('counts down while playing', () {
      expect(tick(const Duration(minutes: 5)), SleepTimerTickAction.countDown);
      expect(tick(const Duration(seconds: 1)), SleepTimerTickAction.countDown);
    });

    test('triggers once the time is up', () {
      expect(tick(Duration.zero), SleepTimerTickAction.trigger);
      expect(tick(const Duration(seconds: -3)), SleepTimerTickAction.trigger);
    });

    test('waits while paused or pausing, even when the time is up', () {
      expect(
        tick(const Duration(minutes: 5), active: false),
        SleepTimerTickAction.wait,
      );
      expect(tick(Duration.zero, active: false), SleepTimerTickAction.wait);
      expect(
        tick(Duration.zero, pauseRequested: true),
        SleepTimerTickAction.wait,
      );
      expect(
        tick(const Duration(minutes: 1), pauseRequested: true),
        SleepTimerTickAction.wait,
      );
    });
  });

  group('PlaybackErrorPolicy', () {
    test('recognises source errors', () {
      expect(
        PlaybackErrorPolicy.isSourceError(Exception('Source error')),
        isTrue,
      );
      expect(
        PlaybackErrorPolicy.isSourceError('ExoPlaybackException: TYPE_SOURCE'),
        isTrue,
      );
      expect(
        PlaybackErrorPolicy.isSourceError(
          PlatformException(code: '0', message: 'Source error: 404'),
        ),
        isTrue,
      );
    });

    test('a platform exception needs code 0 and a source-error message', () {
      expect(
        PlaybackErrorPolicy.isSourceError(
          PlatformException(code: '1', message: 'Source error'),
        ),
        isFalse,
      );
      expect(
        PlaybackErrorPolicy.isSourceError(
          PlatformException(code: '0', message: 'Connection aborted'),
        ),
        isFalse,
      );
      expect(
        PlaybackErrorPolicy.isSourceError(PlatformException(code: '0')),
        isFalse,
      );
    });

    test('other errors are not source errors', () {
      expect(PlaybackErrorPolicy.isSourceError(Exception('timeout')), isFalse);
      expect(
        PlaybackErrorPolicy.isSourceError(StateError('disposed')),
        isFalse,
      );
    });

    test('decoder failures and source errors retry with transcoding', () {
      for (final text in [
        'MediaCodecAudioRenderer error',
        'AudioTrack init failed',
        'No decoder for audio/x-ape',
        'FORMAT_SUPPORTED=NO_UNSUPPORTED_TYPE',
        'Source error',
      ]) {
        expect(
          PlaybackErrorPolicy.shouldRetryWithTranscode(Exception(text)),
          isTrue,
          reason: text,
        );
      }
      expect(
        PlaybackErrorPolicy.shouldRetryWithTranscode(
          PlatformException(code: '0', message: 'Source error'),
        ),
        isTrue,
      );
    });

    test('network and state errors do not trigger transcoding', () {
      expect(
        PlaybackErrorPolicy.shouldRetryWithTranscode(
          Exception('SocketException: Connection refused'),
        ),
        isFalse,
      );
      expect(
        PlaybackErrorPolicy.shouldRetryWithTranscode(StateError('disposed')),
        isFalse,
      );
    });
  });

  group('ColdStartPlayPolicy', () {
    test('a loaded item always plays', () {
      expect(
        ColdStartPlayPolicy.decide(currentItemId: 'a', lastPlayedItemId: 'b'),
        ColdStartPlayDecision.playCurrent,
      );
      expect(
        ColdStartPlayPolicy.decide(currentItemId: 'a', lastPlayedItemId: null),
        ColdStartPlayDecision.playCurrent,
      );
    });

    test('with nothing loaded the last played item is restored', () {
      expect(
        ColdStartPlayPolicy.decide(currentItemId: null, lastPlayedItemId: 'b'),
        ColdStartPlayDecision.restoreLastPlayed,
      );
      expect(
        ColdStartPlayPolicy.decide(currentItemId: '', lastPlayedItemId: 'b'),
        ColdStartPlayDecision.restoreLastPlayed,
      );
    });

    test('with nothing to restore the request is ignored', () {
      expect(
        ColdStartPlayPolicy.decide(currentItemId: null, lastPlayedItemId: null),
        ColdStartPlayDecision.nothing,
      );
      expect(
        ColdStartPlayPolicy.decide(currentItemId: '', lastPlayedItemId: ''),
        ColdStartPlayDecision.nothing,
      );
    });
  });

  group('ChapterLookup', () {
    final chapters = <dynamic>[
      {'start': 0, 'end': 100.0},
      {'start': 100.0, 'end': 250},
      {'start': 250, 'end': 400.0},
    ];

    test('finds the chapter with start inclusive and end exclusive', () {
      expect(ChapterLookup.indexAt(chapters, 0, 400), 0);
      expect(ChapterLookup.indexAt(chapters, 99.9, 400), 0);
      expect(ChapterLookup.indexAt(chapters, 100, 400), 1);
      expect(ChapterLookup.indexAt(chapters, 399.9, 400), 2);
    });

    test('positions outside every chapter have no chapter', () {
      expect(ChapterLookup.indexAt(chapters, 400, 400), isNull);
      expect(ChapterLookup.indexAt(chapters, -1, 400), isNull);
      expect(ChapterLookup.indexAt(const [], 10, 400), isNull);
    });

    test('missing start and end fall back to 0 and the total duration', () {
      final loose = <dynamic>[
        {'end': 50},
        {'start': 50},
      ];
      expect(ChapterLookup.indexAt(loose, 0, 120), 0);
      expect(ChapterLookup.indexAt(loose, 119, 120), 1);
      expect(ChapterLookup.indexAt(loose, 120, 120), isNull);
    });

    test('a short overrun past the last chapter keeps the last chapter', () {
      expect(ChapterLookup.indexAtWithGrace(chapters, 400, 400), 2);
      expect(
        ChapterLookup.indexAtWithGrace(
          chapters,
          400 + ChapterLookup.graceSeconds,
          400,
        ),
        2,
      );
      expect(
        ChapterLookup.indexAtWithGrace(
          chapters,
          400 + ChapterLookup.graceSeconds + 1,
          800,
        ),
        isNull,
      );
      expect(ChapterLookup.indexAtWithGrace(chapters, 120, 400), 1);
      expect(ChapterLookup.indexAtWithGrace(const [], 10, 400), isNull);
    });

    test('next skip target is the next chapter start more than 1 s ahead', () {
      expect(ChapterLookup.nextSkipTarget(chapters, 10, 400), (
        seconds: 100.0,
        finishesItem: false,
      ));
      // Within a second of the next start: skip to the one after.
      expect(ChapterLookup.nextSkipTarget(chapters, 99.5, 400), (
        seconds: 250.0,
        finishesItem: false,
      ));
    });

    test('from the last chapter the skip finishes the item', () {
      expect(ChapterLookup.nextSkipTarget(chapters, 300, 400), (
        seconds: 400.0,
        finishesItem: true,
      ));
      // Unknown total duration: the last chapter's end.
      expect(ChapterLookup.nextSkipTarget(chapters, 300, 0), (
        seconds: 400.0,
        finishesItem: true,
      ));
    });

    test('no chapters or no known end means no skip target', () {
      expect(ChapterLookup.nextSkipTarget(const [], 10, 400), isNull);
      expect(
        ChapterLookup.nextSkipTarget(
          <dynamic>[
            {'start': 0},
          ],
          10,
          0,
        ),
        isNull,
      );
    });
  });

  group('NowPlayingLayout', () {
    const values = NowPlayingValues(
      title: 'Dune',
      author: 'Frank Herbert',
      chapter: ' Chapter 3 ',
      narrator: 'Scott Brick',
      percent: '42%',
    );

    test('standard: the chapter on top, author and title beneath', () {
      final text = NowPlayingLayout.standard.build(values);
      expect(text.title, 'Chapter 3');
      expect(text.subtitle, 'Frank Herbert · Dune');
      expect(NowPlayingLayout.standard.isStandard, isTrue);
    });

    test('an empty top line falls back and drops that piece below', () {
      const noChapter = NowPlayingValues(
        title: 'Dune',
        author: 'Frank Herbert',
      );
      final text = NowPlayingLayout.standard.build(noChapter);
      expect(text.title, 'Dune');
      expect(text.subtitle, 'Frank Herbert');
    });

    test('empty pieces are skipped when joining a line', () {
      const layout = NowPlayingLayout(
        top: [NowPlayingPiece.title, NowPlayingPiece.series],
        second: [
          NowPlayingPiece.narrator,
          NowPlayingPiece.timeLeft,
          NowPlayingPiece.percent,
        ],
      );
      final text = layout.build(values);
      expect(text.title, 'Dune');
      expect(text.subtitle, 'Scott Brick · 42%');
      expect(layout.isStandard, isFalse);
      expect(layout.uses(NowPlayingPiece.series), isTrue);
      expect(layout.unused, isNot(contains(NowPlayingPiece.narrator)));
      expect(layout.unused, contains(NowPlayingPiece.chapter));
    });

    test('JSON round trip keeps the order', () {
      const layout = NowPlayingLayout(
        top: [NowPlayingPiece.title],
        second: [NowPlayingPiece.chapterNumber, NowPlayingPiece.author],
      );
      final back = NowPlayingLayout.fromJson(layout.toJson());
      expect(back.top, layout.top);
      expect(back.second, layout.second);
    });

    test('unreadable, empty or top-less JSON gives the standard layout', () {
      for (final raw in [
        null,
        '',
        'not json',
        '[]',
        '{"top":[],"second":["title"]}',
        '{"top":["nope"]}',
      ]) {
        expect(NowPlayingLayout.fromJson(raw).isStandard, isTrue, reason: raw);
      }
    });

    test('unknown names are dropped and each piece shows only once', () {
      final layout = NowPlayingLayout.fromJson(
        '{"top":["title","bogus","title"],"second":["title","author"]}',
      );
      expect(layout.top, [NowPlayingPiece.title]);
      expect(layout.second, [NowPlayingPiece.author]);
    });
  });
}
