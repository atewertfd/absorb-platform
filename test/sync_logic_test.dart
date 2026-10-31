import 'package:absorb/services/sync_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncLogic.backoffDelay', () {
    test('retries fast first, then doubles from 5 s', () {
      expect(SyncLogic.backoffDelay(0), const Duration(milliseconds: 250));
      expect(SyncLogic.backoffDelay(1), const Duration(seconds: 5));
      expect(SyncLogic.backoffDelay(2), const Duration(seconds: 10));
      expect(SyncLogic.backoffDelay(3), const Duration(seconds: 20));
      expect(SyncLogic.backoffDelay(4), const Duration(seconds: 40));
      expect(SyncLogic.backoffDelay(5), const Duration(seconds: 80));
      expect(SyncLogic.backoffDelay(6), const Duration(seconds: 160));
    });

    // ProgressSyncService stops retrying after 10 consecutive failures, so
    // only small counts are reachable. (From 64 on, the shift inside
    // backoffDelay overflows and the delay drops back to 5 s.)
    test('caps at maxRetryDelay', () {
      expect(SyncLogic.maxRetryDelay, const Duration(minutes: 5));
      for (final failures in [7, 8, 10, 12, 30]) {
        expect(
          SyncLogic.backoffDelay(failures),
          SyncLogic.maxRetryDelay,
          reason: '$failures failures',
        );
      }
    });

    test('never shrinks as failures grow', () {
      var previous = Duration.zero;
      for (var failures = 0; failures <= 30; failures++) {
        final delay = SyncLogic.backoffDelay(failures);
        expect(delay >= previous, isTrue, reason: '$failures failures');
        expect(delay <= SyncLogic.maxRetryDelay, isTrue);
        previous = delay;
      }
    });

    test('negative counts are treated like no failures', () {
      expect(SyncLogic.backoffDelay(-1), const Duration(milliseconds: 250));
    });
  });

  group('SyncLogic.shouldPullServer', () {
    bool decide({
      int serverTimestamp = 2000,
      double serverTime = 100,
      int localTimestamp = 1000,
      double localTime = 90,
      bool hasOfflineListening = false,
    }) => SyncLogic.shouldPullServer(
      serverTimestamp: serverTimestamp,
      serverTime: serverTime,
      localTimestamp: localTimestamp,
      localTime: localTime,
      hasOfflineListening: hasOfflineListening,
    );

    test('local wins when its timestamp is newer or equal', () {
      expect(decide(serverTimestamp: 1000, localTimestamp: 2000), isFalse);
      expect(decide(serverTimestamp: 1500, localTimestamp: 1500), isFalse);
    });

    test('same position means nothing to pull', () {
      expect(decide(serverTime: 100, localTime: 100), isFalse);
    });

    test('newer server at or ahead of local is pulled', () {
      expect(decide(serverTime: 100, localTime: 90), isTrue);
      expect(
        decide(serverTime: 100, localTime: 90, hasOfflineListening: true),
        isTrue,
      );
    });

    test('newer server behind local: offline listening keeps local', () {
      expect(
        decide(serverTime: 80, localTime: 100, hasOfflineListening: true),
        isFalse,
      );
      expect(decide(serverTime: 80, localTime: 100), isTrue);
    });

    test('local far ahead always wins, even against a newer server', () {
      // Exactly the safety margin is not "far ahead".
      expect(decide(serverTime: 100, localTime: 130), isTrue);
      expect(decide(serverTime: 100, localTime: 130.5), isFalse);
      expect(decide(serverTime: 0, localTime: 3600), isFalse);
    });
  });

  group('SyncLogic.shouldAdoptServerAtCachedStart', () {
    bool decide({
      int serverTimestamp = 2000,
      double serverTime = 200,
      int localTimestampAtStart = 1000,
      double localTimeAtStart = 100,
      double currentPlaybackTime = 101,
    }) => SyncLogic.shouldAdoptServerAtCachedStart(
      serverTimestamp: serverTimestamp,
      serverTime: serverTime,
      localTimestampAtStart: localTimestampAtStart,
      localTimeAtStart: localTimeAtStart,
      currentPlaybackTime: currentPlaybackTime,
    );

    test('a newer server position well ahead is adopted', () {
      expect(decide(), isTrue);
    });

    test('an older or equally old server position is ignored', () {
      expect(decide(serverTimestamp: 1000), isFalse);
      expect(decide(serverTimestamp: 999), isFalse);
    });

    test('small forward differences are normal drift', () {
      expect(decide(serverTime: 105), isFalse); // exactly the threshold
      expect(decide(serverTime: 105.5, currentPlaybackTime: 100), isTrue);
    });

    test('playback that already passed the server position keeps going', () {
      expect(decide(serverTime: 200, currentPlaybackTime: 196), isFalse);
      expect(decide(serverTime: 200, currentPlaybackTime: 194), isTrue);
    });

    test('a server position behind the starting point is ignored', () {
      expect(decide(serverTime: 50, currentPlaybackTime: 0), isFalse);
    });
  });
}
