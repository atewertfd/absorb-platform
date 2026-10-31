import 'package:absorb/screens/stats_tab_refresh.dart';
import 'package:absorb/services/download_service.dart';
import 'package:absorb/widgets/item_download_watch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Stats reloads when its tab opens, at most once a minute', () {
    var now = DateTime(2026, 10, 30, 12);
    final refresh = StatsTabRefresh(clock: () => now);
    var reloads = 0;
    refresh.addListener(() => reloads++);

    refresh.tabActivated();
    expect(reloads, 1);

    now = now.add(const Duration(seconds: 30));
    refresh.tabActivated();
    expect(reloads, 1, reason: 'throttled within 60 s');

    now = now.add(const Duration(seconds: 31));
    refresh.tabActivated();
    expect(reloads, 2);
    refresh.dispose();
  });

  test('a card rebuilds only when its own download state changes', () {
    // No downloads exist in a fresh test process.
    expect(DownloadService().isDownloaded('book-a'), isFalse);
    var key = 'book-a';
    final watch = ItemDownloadWatch(() => key);

    expect(watch.changed(), isTrue, reason: 'first call');
    expect(watch.changed(), isFalse, reason: "another book's progress tick");
    expect(watch.changed(), isFalse);

    key = 'book-b';
    expect(watch.changed(), isTrue, reason: 'the card now shows another book');
    expect(watch.changed(), isFalse);
  });
}
