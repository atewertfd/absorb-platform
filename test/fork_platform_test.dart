import 'package:absorb/services/ebook_cache.dart';
import 'package:absorb/utils/fork_platform.dart';
import 'package:absorb/widgets/ebook_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _ebook(String format) => {'ebookFormat': format};

void main() {
  final defaultLauncher = ForkPlatform.launcher;

  void onPlatform(TargetPlatform p, {bool web = false}) {
    debugDefaultTargetPlatformOverride = p;
    ForkPlatform.debugIsWebOverride = web;
  }

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    ForkPlatform.debugIsWebOverride = null;
    ForkPlatform.launcher = defaultLauncher;
  });

  group('ebook readers are offered only where they work', () {
    test('Windows and Android keep every format', () {
      for (final p in [TargetPlatform.windows, TargetPlatform.android]) {
        onPlatform(p);
        for (final f in ['epub', 'pdf', 'cbz', 'mobi', 'azw3']) {
          expect(canReadEbook(_ebook(f)), isTrue, reason: '$p $f');
        }
      }
    });

    test('Linux reads PDF and comics only (no inappwebview there)', () {
      onPlatform(TargetPlatform.linux);
      expect(canReadEbook(_ebook('pdf')), isTrue);
      expect(canReadEbook(_ebook('cbz')), isTrue);
      expect(canReadEbook(_ebook('epub')), isFalse);
      expect(canReadEbook(_ebook('mobi')), isFalse);
      expect(canReadEbook(_ebook('azw3')), isFalse);
      // The helper's comic list must match the cache's.
      for (final f in comicEbookFormats) {
        expect(ForkPlatform.canOpenEbookFormat(f), isTrue, reason: f);
      }
    });

    test('web offers no reader', () {
      onPlatform(TargetPlatform.windows, web: true);
      for (final f in ['epub', 'pdf', 'cbz', 'mobi']) {
        expect(canReadEbook(_ebook(f)), isFalse, reason: f);
      }
    });
  });

  group('Android-only features', () {
    test('cast and live transcript buttons are hidden off Android', () {
      onPlatform(TargetPlatform.windows);
      expect(ForkPlatform.hiddenCardButtons(), {'cast', 'lyrics'});
      expect(ForkPlatform.supportsTranscription, isFalse);
      expect(ForkPlatform.supportsClipExport, isFalse);

      onPlatform(TargetPlatform.android);
      expect(ForkPlatform.hiddenCardButtons(), isEmpty);
      expect(ForkPlatform.supportsTranscription, isTrue);
    });

    test('the equalizer is never hidden', () {
      for (final p in TargetPlatform.values) {
        onPlatform(p);
        expect(ForkPlatform.hiddenCardButtons(), isNot(contains('equalizer')));
      }
    });
  });

  group('web pages without an in-app web view', () {
    test('Windows opens the external browser instead', () async {
      onPlatform(TargetPlatform.windows);
      final opened = <Uri>[];
      ForkPlatform.launcher = (uri) async {
        opened.add(uri);
        return true;
      };
      expect(
          ForkPlatform.openInBrowserInstead(
              'https://www.audible.com/pd/B0TEST#customer-reviews'),
          isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(opened.single.toString(),
          'https://www.audible.com/pd/B0TEST#customer-reviews');
    });

    test('web and Linux also use the browser', () {
      ForkPlatform.launcher = (_) async => true;
      onPlatform(TargetPlatform.linux);
      expect(ForkPlatform.openInBrowserInstead('https://rmab.example'), isTrue);
      onPlatform(TargetPlatform.android, web: true);
      expect(ForkPlatform.openInBrowserInstead('https://rmab.example'), isTrue);
    });

    test('Android keeps the in-app view', () {
      onPlatform(TargetPlatform.android);
      var launched = false;
      ForkPlatform.launcher = (_) async => launched = true;
      expect(ForkPlatform.openInBrowserInstead('https://rmab.example'), isFalse);
      expect(launched, isFalse);
    });

    test('a launcher failure is swallowed', () async {
      onPlatform(TargetPlatform.windows);
      ForkPlatform.launcher = (_) async => throw Exception('no browser');
      expect(ForkPlatform.openInBrowserInstead('https://rmab.example'), isTrue);
      await Future<void>.delayed(Duration.zero);
    });
  });
}
