import 'package:absorb/services/queue_download_policy.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Book = ({
  String id,
  String library,
  bool podcast,
  bool finished,
  String mode,
  double? sequence,
  String? series,
});

void main() {
  const books = <_Book>[
    (
      id: 'a',
      library: 'fiction',
      podcast: false,
      finished: true,
      mode: 'off',
      sequence: 1,
      series: 's',
    ),
    (
      id: 'b',
      library: 'fiction',
      podcast: false,
      finished: false,
      mode: 'auto_next',
      sequence: 2,
      series: 's',
    ),
    (
      id: 'c',
      library: 'nonfiction',
      podcast: false,
      finished: false,
      mode: 'playlist',
      sequence: null,
      series: null,
    ),
    (
      id: 'd',
      library: 'fiction',
      podcast: true,
      finished: false,
      mode: 'auto_next',
      sequence: null,
      series: null,
    ),
    (
      id: 'e',
      library: 'fiction',
      podcast: false,
      finished: false,
      mode: 'off',
      sequence: 3,
      series: 's',
    ),
  ];

  test(
    'source queue settings override global setting only for active sources',
    () {
      expect(
        resolveQueueAutoDownloadEnabled(
          queueMode: 'playlist',
          globalEnabled: false,
          activeSourceId: 'playlist-1',
          activeSourceEnabled: true,
        ),
        isTrue,
      );
      expect(
        resolveQueueAutoDownloadEnabled(
          queueMode: 'manual',
          globalEnabled: true,
          activeSourceId: null,
          activeSourceEnabled: false,
        ),
        isTrue,
      );
      expect(
        resolveQueueAutoDownloadEnabled(
          queueMode: 'collection',
          globalEnabled: true,
          activeSourceId: null,
          activeSourceEnabled: false,
        ),
        isTrue,
      );
    },
  );

  test('keys distinguish podcast episodes from their library item', () {
    expect(queueItemKey(libraryItemId: 'book'), 'book');
    expect(
      queueItemKey(libraryItemId: 'show', episodeId: 'episode-2'),
      'show-episode-2',
    );
  });

  test('manual queue keeps the current tail and applies merge filters', () {
    final merged = manualQueueTail(
      items: books,
      currentKey: 'b',
      keyOf: (book) => book.id,
      isFinished: (book) => book.finished,
      isPodcast: (book) => book.podcast,
      queueMode: (book) => book.mode,
      libraryId: (book) => book.library,
      merged: true,
      currentIsPodcast: false,
      currentLibraryId: 'fiction',
    );
    expect(merged.map((book) => book.id), ['b', 'c', 'd']);

    final filtered = manualQueueTail(
      items: books,
      currentKey: 'b',
      keyOf: (book) => book.id,
      isFinished: (book) => book.finished,
      isPodcast: (book) => book.podcast,
      queueMode: (book) => book.mode,
      libraryId: (book) => book.library,
      merged: false,
      currentIsPodcast: false,
      currentLibraryId: 'fiction',
    );
    expect(filtered.map((book) => book.id), ['b']);
  });

  test('podcast tail sorts by publish time in the selected direction', () {
    const episodes = [
      (id: 'old', published: 1),
      (id: 'new', published: 3),
      (id: 'middle', published: 2),
    ];
    final newest = podcastQueueTail(
      episodes: episodes,
      currentEpisodeId: 'new',
      idOf: (episode) => episode.id,
      publishedAt: (episode) => episode.published,
      newestFirst: true,
    );
    expect(newest.map((episode) => episode.id), ['new', 'middle', 'old']);
    final oldest = podcastQueueTail(
      episodes: episodes,
      currentEpisodeId: 'middle',
      idOf: (episode) => episode.id,
      publishedAt: (episode) => episode.published,
      newestFirst: false,
    );
    expect(oldest.map((episode) => episode.id), ['middle', 'new']);
  });

  test(
    'series tail ignores earlier, unrelated and duplicate sequence entries',
    () {
      const current = (id: 'current', series: 's', sequence: 2.0);
      const candidates = [
        (id: 'third', series: 's', sequence: 3.0),
        (id: 'fifth', series: 's', sequence: 5.0),
        (id: 'earlier', series: 's', sequence: 1.0),
        (id: 'other', series: 'other', sequence: 4.0),
        (id: 'duplicate', series: 's', sequence: 3.0),
      ];
      final result = seriesQueueTail(
        current: current,
        books: [current, ...candidates],
        currentKey: 'current',
        currentSeriesId: 's',
        currentSequence: 2,
        keyOf: (book) => book.id,
        seriesId: (book) => book.series,
        sequence: (book) => book.sequence,
      );
      expect(result.map((book) => book.id), [
        'current',
        'third',
        'duplicate',
        'fifth',
      ]);
    },
  );

  test('download window deduplicates and excludes completed items', () {
    expect(
      queueDownloadWindow(
        items: ['a', 'b', 'b', '', 'c', 'd'],
        count: 3,
        keyOf: (id) => id,
        isFinished: (id) => id == 'b',
      ),
      ['a', 'c', 'd'],
    );
    expect(
      queueItemsNeedingDownload(
        items: ['a', 'b', 'c'],
        count: 3,
        keyOf: (id) => id,
        isFinished: (_) => false,
        isAvailable: (id) => id == 'b',
      ),
      ['a', 'c'],
    );
  });
}
