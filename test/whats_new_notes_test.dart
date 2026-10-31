import 'dart:convert';
import 'dart:io';

import 'package:absorb/services/whats_new_notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fixture(String name) =>
    File('test/fixtures/whats_new/$name').readAsStringSync();

List<String> _titles(WhatsNewNotes n) => [for (final s in n.sections) s.title];

void main() {
  group('parseWhatsNewNotes, real notes', () {
    test('Beta 10 release body', () {
      final notes = parseWhatsNewNotes(_fixture('beta-10.md'),
          releaseName: 'Absorb Plus 1.11.1-300 (Beta 10)');
      expect(notes.title, 'Beta 10');
      expect(notes.intro, hasLength(1));
      expect(notes.intro.single, startsWith('Pre-release for testing.'));
      expect(_titles(notes), [
        'Libation import (Settings → Advanced → Import Libation exports)',
        'ReadMeABook',
        'Updates',
        'Performance (no visual changes)',
      ]);
      expect([for (final s in notes.sections) s.kind], [
        WhatsNewKind.other,
        WhatsNewKind.other,
        WhatsNewKind.other,
        WhatsNewKind.faster,
      ]);
      expect([for (final s in notes.sections) s.items.length], [8, 1, 2, 3]);
      // Downloads (installer file names) and the footer never show up.
      final all = [
        ...notes.intro,
        for (final s in notes.sections) ...s.items.map((i) => i.text),
      ].join('\n');
      expect(all, isNot(contains('Setup.exe')));
      expect(all, isNot(contains('Source commit')));
      expect(all, isNot(contains('SHA-256')));
    });

    test('Beta 11 notes', () {
      final notes = parseWhatsNewNotes(_fixture('beta-11.md'));
      expect(notes.title, 'Beta 11');
      expect(notes.intro.single, startsWith('The biggest Absorb Plus update'));
      expect(_titles(notes), [
        'New: choose your look',
        'Smoother and lighter',
        'Fixes',
        'From upstream Absorb',
      ]);
      expect([for (final s in notes.sections) s.kind], [
        WhatsNewKind.newStuff,
        WhatsNewKind.faster,
        WhatsNewKind.fixed,
        WhatsNewKind.other,
      ]);
      expect([for (final s in notes.sections) s.items.length], [6, 5, 16, 6]);
      expect(notes.sections.first.items.first.text, startsWith('**Three looks:**'));
    });
  });

  group('parseWhatsNewNotes, edge cases', () {
    test('empty body', () {
      final notes = parseWhatsNewNotes('');
      expect(notes.isEmpty, isTrue);
      expect(notes.title, isNull);
    });

    test('no headings at all: paragraphs become intro', () {
      final notes = parseWhatsNewNotes('First line\nsame paragraph.\n\nSecond one.');
      expect(notes.title, isNull);
      expect(notes.intro, ['First line same paragraph.', 'Second one.']);
      expect(notes.sections, isEmpty);
    });

    test('title without sections keeps the list as intro', () {
      final notes = parseWhatsNewNotes('## Beta 3\n\nHello.\n- one\n- two\n');
      expect(notes.title, 'Beta 3');
      expect(notes.intro, ['Hello.', 'one', 'two']);
    });

    test('title from the release name when the body has none', () {
      expect(parseWhatsNewNotes('Text', releaseName: 'Absorb Plus 1.11.1-300 (Beta 10)').title,
          'Beta 10');
      expect(parseWhatsNewNotes('Text', releaseName: 'Absorb Plus 1.12.0').title,
          'Absorb Plus 1.12.0');
      expect(parseWhatsNewNotes('## Highlights\nText', releaseName: 'X (Beta 4)').title,
          'Beta 4');
    });

    test('CRLF, * bullets, nesting and continuation lines', () {
      const body = '## Beta 2\r\n\r\nIntro.\r\n\r\n### Fixed things\r\n'
          '* top one\r\n  * nested\r\n* wraps onto\r\nthe next line\r\n\r\n'
          'A loose paragraph.\r\n';
      final notes = parseWhatsNewNotes(body);
      expect(notes.intro, ['Intro.']);
      final s = notes.sections.single;
      expect(s.kind, WhatsNewKind.fixed);
      expect([for (final i in s.items) i.text],
          ['top one', 'nested', 'wraps onto the next line', 'A loose paragraph.']);
      expect([for (final i in s.items) i.depth], [0, 1, 0, 0]);
    });

    test('stops at the --- footer', () {
      final notes = parseWhatsNewNotes('### New\n- a\n  ---  \n- b\nSource commit: x');
      expect(notes.sections.single.items.map((i) => i.text), ['a']);
    });

    test('skips Download sections and empty sections', () {
      final notes = parseWhatsNewNotes(
          '### downloads\n- file.exe\n### Empty\n\n### Fixes\n- one');
      expect(_titles(notes), ['Fixes']);
    });

    test('never throws on odd input', () {
      for (final body in ['---', '#', '###', '- ', '**', '`', '[x](', '\n\n\n', '#### deep\n- x']) {
        expect(() => parseWhatsNewNotes(body), returnsNormally, reason: body);
      }
    });
  });

  test('kinds by keyword', () {
    expect(whatsNewKindFor('New: choose your look'), WhatsNewKind.newStuff);
    expect(whatsNewKindFor('Features'), WhatsNewKind.newStuff);
    expect(whatsNewKindFor('Fixes'), WhatsNewKind.fixed);
    expect(whatsNewKindFor('Bug fixes'), WhatsNewKind.fixed);
    expect(whatsNewKindFor('Smoother and lighter'), WhatsNewKind.faster);
    expect(whatsNewKindFor('PERFORMANCE'), WhatsNewKind.faster);
    expect(whatsNewKindFor('Renewed sync'), WhatsNewKind.other);
    expect(whatsNewKindFor('Updates'), WhatsNewKind.other);
  });

  group('parseWhatsNewInline', () {
    test('bold, code, links and bare URLs', () {
      final spans = parseWhatsNewInline(
          '**Windows:** run `Setup.exe`, see [the docs](https://example.com/d) or https://example.com/x.');
      expect(spans.map((s) => s.text).join(),
          'Windows: run Setup.exe, see the docs or https://example.com/x.');
      expect(spans.first.bold, isTrue);
      expect(spans.firstWhere((s) => s.text == 'Setup.exe').code, isTrue);
      expect(spans.firstWhere((s) => s.text == 'the docs').link,
          Uri.parse('https://example.com/d'));
      expect(spans.firstWhere((s) => s.text == 'https://example.com/x').link,
          Uri.parse('https://example.com/x'));
      expect(spans.last.text, '.');
    });

    test('bold link and italics', () {
      final spans = parseWhatsNewInline('**[Docs](https://e.com)** and *this*');
      expect(spans.first.bold && spans.first.link != null, isTrue);
      expect(spans.last.italic, isTrue);
      expect(spans.last.text, 'this');
    });

    test('only http(s) links are tappable', () {
      final spans = parseWhatsNewInline('[x](javascript:alert(1))');
      expect(spans.every((s) => s.link == null), isTrue);
    });

    test('plain text and multiplication stay as they are', () {
      expect(whatsNewPlainText('2 * 3 = 6'), '2 * 3 = 6');
      expect(whatsNewPlainText('CD1/01.mp3'), 'CD1/01.mp3');
    });
  });

  group('WhatsNewNotesService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('fetches, caches, and falls back to the cache offline', () async {
      var online = true;
      final service = WhatsNewNotesService(fetch: (tag) async {
        if (!online) throw const SocketException('offline');
        return WhatsNewRelease('## Beta 11\n\nHi.\n### Fixes\n- one', name: 'n');
      });
      final first = await service.load('v1.12.1-318');
      expect(first.source, WhatsNewSource.network);
      expect(first.notes!.title, 'Beta 11');

      online = false;
      final second = await service.load('v1.12.1-318');
      expect(second.source, WhatsNewSource.cache);
      expect(second.notes!.sections.single.items.single.text, 'one');

      final other = await service.load('v1.12.1-319');
      expect(other.failed, isTrue);
    });

    test('a missing release (404) uses the cache too', () async {
      var release = true;
      final service = WhatsNewNotesService(
          fetch: (_) async => release ? const WhatsNewRelease('Intro') : null);
      await service.load('t');
      release = false;
      expect((await service.load('t')).source, WhatsNewSource.cache);
    });

    test('keeps only the newest releases', () async {
      final service = WhatsNewNotesService(fetch: (tag) async => WhatsNewRelease(tag));
      for (var i = 0; i < WhatsNewNotesService.cacheLimit + 2; i++) {
        await service.load('t$i');
      }
      expect(await WhatsNewNotesService.cachedRelease('t0'), isNull);
      expect((await WhatsNewNotesService.cachedRelease('t6'))!.body, 't6');
      final prefs = await SharedPreferences.getInstance();
      final list = jsonDecode(prefs.getString(WhatsNewNotesService.cacheKey)!) as List;
      expect(list, hasLength(WhatsNewNotesService.cacheLimit));
    });

    test('GitHub fetcher: URL, headers and status handling', () async {
      final requests = <http.Request>[];
      var status = 200;
      final client = MockClient((r) async {
        requests.add(r);
        return http.Response(
            jsonEncode({'body': '## Beta 11\n\nHi.', 'name': 'Absorb Plus (Beta 11)'}),
            status);
      });
      final service = WhatsNewNotesService(client: client);
      final ok = await service.load('v1.12.1-318');
      expect(ok.source, WhatsNewSource.network);
      expect(requests.single.url.toString(),
          'https://api.github.com/repos/atewertfd/absorb-platform/releases/tags/v1.12.1-318');
      expect(requests.single.headers['Accept'], 'application/vnd.github.v3+json');

      status = 404;
      expect((await service.load('v9.9.9-1')).failed, isTrue);
      status = 500;
      expect((await service.load('v9.9.9-2')).failed, isTrue);
    });
  });

  group('WhatsNewHistory', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('remembers the build before this one', () async {
      final prefs = await SharedPreferences.getInstance();
      // First launch with history: only the prompt's old build number exists.
      var prev = await WhatsNewHistory.record(prefs,
          version: '1.11.1', build: 300, beta: 10, lastBuild: 290);
      expect(prev!.build, 290);
      expect(prev.beta, isNull);

      // Relaunching the same build changes nothing.
      prev = await WhatsNewHistory.record(prefs,
          version: '1.11.1', build: 300, beta: 10, lastBuild: 300);
      expect(prev!.build, 290);

      prev = await WhatsNewHistory.record(prefs,
          version: '1.12.1', build: 318, beta: 11, lastBuild: 300);
      expect(prev!.beta, 10);
      expect(prev.version, '1.11.1');
    });

    test('fresh install has no previous build', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
          await WhatsNewHistory.record(prefs, version: '1.12.1', build: 318),
          isNull);
    });
  });
}
