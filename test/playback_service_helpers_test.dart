import 'package:absorb/services/android_auto_service.dart';
import 'package:absorb/services/audio_player_service.dart';
import 'package:absorb/services/sleep_timer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AudioPlayerService.calculateAutoRewind', () {
    double rewind(Duration pause, {double delay = 0}) =>
        AudioPlayerService.calculateAutoRewind(
          pause,
          2,
          30,
          activationDelay: delay,
        );

    test('grows linearly from min to max over an hour of pause', () {
      expect(rewind(Duration.zero), 2);
      expect(rewind(const Duration(minutes: 30)), closeTo(16, 1e-9));
      expect(rewind(const Duration(hours: 1)), 30);
      expect(rewind(const Duration(hours: 5)), 30);
    });

    test('pauses shorter than the activation delay never rewind', () {
      expect(rewind(const Duration(seconds: 9), delay: 10), 0);
      // At the delay the ramp starts from the minimum.
      expect(rewind(const Duration(seconds: 10), delay: 10), 2);
      expect(
        rewind(const Duration(seconds: 10 + 1800), delay: 10),
        closeTo(16, 1e-9),
      );
    });

    test('only whole seconds of pause count', () {
      expect(rewind(const Duration(milliseconds: 9999), delay: 10), 0);
    });
  });

  group('AutoMediaIds', () {
    test('builds and parses item ids', () {
      expect(AutoMediaIds.itemId('abc'), 'item:abc');
      expect(AutoMediaIds.absItemId('item:abc'), 'abc');
      expect(AutoMediaIds.absItemId('series:abc@lib'), isNull);
    });

    test('series, author and show ids round trip', () {
      expect(AutoMediaIds.parseSeries(AutoMediaIds.seriesId('s1', 'L')), (
        seriesId: 's1',
        libId: 'L',
      ));
      expect(AutoMediaIds.parseAuthor(AutoMediaIds.authorId('a1', 'L')), (
        authorId: 'a1',
        libId: 'L',
      ));
      expect(AutoMediaIds.parseShow(AutoMediaIds.showId('p1', 'L')), (
        showId: 'p1',
        libId: 'L',
      ));
    });

    test('collections and playlists round trip', () {
      expect(
        AutoMediaIds.parseGroup(
          AutoMediaIds.collectionId('c1', 'L'),
          AutoMediaIds.collectionPrefix,
        ),
        (id: 'c1', libId: 'L'),
      );
      expect(
        AutoMediaIds.parseGroup(
          AutoMediaIds.playlistId('p1', 'L'),
          AutoMediaIds.playlistPrefix,
        ),
        (id: 'p1', libId: 'L'),
      );
      expect(
        AutoMediaIds.parseGroup(
          AutoMediaIds.playlistId('p1', 'L'),
          AutoMediaIds.collectionPrefix,
        ),
        isNull,
      );
    });

    test('ids without a library or with the wrong prefix do not parse', () {
      expect(AutoMediaIds.parseSeries('series:s1'), isNull);
      expect(AutoMediaIds.parseSeries('author:a1@L'), isNull);
      expect(AutoMediaIds.parseAuthor('author:a1'), isNull);
      expect(AutoMediaIds.parseShow('item:x'), isNull);
    });

    test('library ids and sub-categories', () {
      expect(AutoMediaIds.parseLibId(AutoMediaIds.libId('L')), 'L');
      expect(AutoMediaIds.parseLibSub(AutoMediaIds.libId('L')), isNull);
      expect(AutoMediaIds.parseLibId(AutoMediaIds.libBooks('L')), 'L');
      expect(AutoMediaIds.parseLibSub(AutoMediaIds.libBooks('L')), 'books');
      expect(
        AutoMediaIds.parseLibSub(AutoMediaIds.libBookPrefix('L', 'A')),
        'p:A',
      );
      expect(AutoMediaIds.parseLibId('item:x'), isNull);
      expect(AutoMediaIds.parseLibSub('item:x'), isNull);
    });
  });

  group('AutoSleepSettings', () {
    int minutesOfDay(DateTime t) => t.hour * 60 + t.minute;
    AutoSleepSettings window(int startMinutes, int endMinutes) {
      final s = startMinutes % 1440, e = endMinutes % 1440;
      return AutoSleepSettings(
        enabled: true,
        startHour: s ~/ 60,
        startMinute: s % 60,
        endHour: e ~/ 60,
        endMinute: e % 60,
      );
    }

    test('a window around now (same-day or overnight) contains now', () {
      final now = minutesOfDay(DateTime.now());
      expect(window(now - 60, now + 60).isInWindow(), isTrue);
    });

    test('a window later today (or tomorrow) does not contain now', () {
      final now = minutesOfDay(DateTime.now());
      expect(window(now + 60, now + 120).isInWindow(), isFalse);
      expect(window(now - 120, now - 60).isInWindow(), isFalse);
    });

    test('an empty window never matches', () {
      final now = minutesOfDay(DateTime.now());
      expect(window(now + 60, now + 60).isInWindow(), isFalse);
    });

    test('labels use a 12-hour clock', () {
      const s = AutoSleepSettings(
        startHour: 22,
        startMinute: 5,
        endHour: 0,
        endMinute: 30,
      );
      expect(s.startLabel, '10:05 PM');
      expect(s.endLabel, '12:30 AM');
      expect(const AutoSleepSettings(startHour: 12).startLabel, '12:00 PM');
      expect(const AutoSleepSettings(endHour: 6).endLabel, '6:00 AM');
    });

    test('copyWith changes only the given fields', () {
      const base = AutoSleepSettings();
      final changed = base.copyWith(enabled: true, durationMinutes: 45);
      expect(changed.enabled, isTrue);
      expect(changed.durationMinutes, 45);
      expect(changed.startHour, base.startHour);
      expect(changed.endHour, base.endHour);
      expect(changed.useEndOfChapter, base.useEndOfChapter);
    });

    test(
      'defaults when nothing is saved, and a save/load round trip',
      () async {
        SharedPreferences.setMockInitialValues({});
        final defaults = await AutoSleepSettings.load();
        expect(defaults.enabled, isFalse);
        expect(defaults.startHour, 22);
        expect(defaults.endHour, 6);
        expect(defaults.durationMinutes, 30);

        await const AutoSleepSettings(
          enabled: true,
          startHour: 21,
          startMinute: 15,
          endHour: 7,
          endMinute: 45,
          durationMinutes: 20,
          useEndOfChapter: true,
        ).save();
        final loaded = await AutoSleepSettings.load();
        expect(loaded.enabled, isTrue);
        expect(loaded.startHour, 21);
        expect(loaded.startMinute, 15);
        expect(loaded.endHour, 7);
        expect(loaded.endMinute, 45);
        expect(loaded.durationMinutes, 20);
        expect(loaded.useEndOfChapter, isTrue);
      },
    );
  });
}
