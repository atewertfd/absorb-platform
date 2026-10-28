import 'package:flutter_test/flutter_test.dart';

import 'package:absorb/widgets/library_item_snapshot.dart';

void main() {
  test('equal rendered item state compares equal for provider selectors', () {
    const first = LibraryItemSnapshot(
      coverUrl: 'https://example.test/cover',
      progress: 0.25,
      isFinished: false,
      isPodcastLibrary: false,
      isSubscribed: false,
      unfinishedCount: 0,
      mediaHeaders: {'Authorization': 'Bearer token'},
    );
    const second = LibraryItemSnapshot(
      coverUrl: 'https://example.test/cover',
      progress: 0.25,
      isFinished: false,
      isPodcastLibrary: false,
      isSubscribed: false,
      unfinishedCount: 0,
      mediaHeaders: {'Authorization': 'Bearer token'},
    );

    expect(first, second);
  });

  test('a rendered progress change produces a different snapshot', () {
    const first = LibraryItemSnapshot(
      coverUrl: 'https://example.test/cover',
      progress: 0.25,
      isFinished: false,
      isPodcastLibrary: false,
      isSubscribed: false,
      unfinishedCount: 0,
      mediaHeaders: {},
    );
    const second = LibraryItemSnapshot(
      coverUrl: 'https://example.test/cover',
      progress: 0.5,
      isFinished: false,
      isPodcastLibrary: false,
      isSubscribed: false,
      unfinishedCount: 0,
      mediaHeaders: {},
    );

    expect(first, isNot(second));
  });
}
