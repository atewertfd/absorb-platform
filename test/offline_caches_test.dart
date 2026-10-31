import 'dart:convert';

import 'package:absorb/services/library_cache.dart';
import 'package:absorb/services/session_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// No account is signed in during these tests, so the cache keys carry no
// account scope prefix.
void main() {
  group('LibraryCache', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('save and load keep id, name and media type', () async {
      await LibraryCache.save([
        {'id': 'lib1', 'name': 'Books', 'mediaType': 'book', 'extra': 1},
        {'id': 'lib2', 'name': 'Shows', 'mediaType': 'podcast'},
      ]);
      expect(await LibraryCache.load(), [
        {'id': 'lib1', 'name': 'Books', 'mediaType': 'book'},
        {'id': 'lib2', 'name': 'Shows', 'mediaType': 'podcast'},
      ]);
    });

    test('nothing saved loads as an empty list', () async {
      expect(await LibraryCache.load(), isEmpty);
    });

    test('decode drops entries without an id and fills in defaults', () {
      final raw = jsonEncode([
        {'id': 'a'},
        {'id': '', 'name': 'no id'},
        {'name': 'missing id'},
        'not a map',
        {'id': 7},
        {'id': 'b', 'name': '', 'mediaType': ''},
      ]);
      expect(LibraryCache.decode(raw), [
        {'id': 'a', 'name': 'Library', 'mediaType': 'book'},
        {'id': 'b', 'name': 'Library', 'mediaType': 'book'},
      ]);
    });

    test('decode tolerates missing, empty and corrupt values', () {
      expect(LibraryCache.decode(null), isEmpty);
      expect(LibraryCache.decode(''), isEmpty);
      expect(LibraryCache.decode('{"id":"a"}'), isEmpty);
      expect(LibraryCache.decode('[{"id":'), isEmpty);
    });
  });

  group('SessionCache', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> save(String itemId, {String? episodeId, double total = 60}) =>
        SessionCache.save(
          itemId: itemId,
          episodeId: episodeId,
          audioTracks: [
            {'index': 1, 'contentUrl': '/s/item/$itemId/1.mp3'},
          ],
          chapters: [
            {'id': 0, 'start': 0, 'end': total},
          ],
          totalDuration: total,
        );

    test('round trip keeps tracks, chapters and duration', () async {
      await save('item1', total: 123.5);
      final loaded = await SessionCache.load(itemId: 'item1');
      expect(loaded, isNotNull);
      expect(loaded!['totalDuration'], 123.5);
      expect(loaded['audioTracks'], [
        {'index': 1, 'contentUrl': '/s/item/item1/1.mp3'},
      ]);
      expect((loaded['chapters'] as List).single['end'], 123.5);
      expect(loaded['savedAt'], isA<int>());
    });

    test('books and episodes of the same item are kept apart', () async {
      await save('show', total: 10);
      await save('show', episodeId: 'ep1', total: 20);
      expect((await SessionCache.load(itemId: 'show'))!['totalDuration'], 10);
      expect(
        (await SessionCache.load(
          itemId: 'show',
          episodeId: 'ep1',
        ))!['totalDuration'],
        20,
      );
      expect(await SessionCache.load(itemId: 'show', episodeId: 'ep2'), isNull);
    });

    test(
      'clearing an item also clears its episodes, not other items',
      () async {
        await save('show');
        await save('show', episodeId: 'ep1');
        await save('other');
        await SessionCache.clear(itemId: 'show');
        expect(await SessionCache.load(itemId: 'show'), isNull);
        expect(
          await SessionCache.load(itemId: 'show', episodeId: 'ep1'),
          isNull,
        );
        expect(await SessionCache.load(itemId: 'other'), isNotNull);
      },
    );

    test('clearing one episode keeps the rest', () async {
      await save('show');
      await save('show', episodeId: 'ep1');
      await save('show', episodeId: 'ep2');
      await SessionCache.clear(itemId: 'show', episodeId: 'ep1');
      expect(await SessionCache.load(itemId: 'show', episodeId: 'ep1'), isNull);
      expect(
        await SessionCache.load(itemId: 'show', episodeId: 'ep2'),
        isNotNull,
      );
      expect(await SessionCache.load(itemId: 'show'), isNotNull);
    });

    test('clearAll removes only session cache entries', () async {
      SharedPreferences.setMockInitialValues({'unrelated': 'keep'});
      await save('a');
      await save('b', episodeId: 'e');
      await SessionCache.clearAll();
      expect(await SessionCache.load(itemId: 'a'), isNull);
      expect(await SessionCache.load(itemId: 'b', episodeId: 'e'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('unrelated'), 'keep');
    });

    test('a corrupt entry loads as null instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        'session_cache_bad': '{not json',
      });
      expect(await SessionCache.load(itemId: 'bad'), isNull);
    });
  });
}
