import '../services/download_service.dart';

/// Absorb Plus: tells a widget listening to [DownloadService] whether *its*
/// item's download state changed.
///
/// `DownloadService` notifies every listener up to four times a second per
/// active download. A card that only shows "saved / streaming" for its own
/// book doesn't need to rebuild for another book's progress ticks.
class ItemDownloadWatch {
  ItemDownloadWatch(this.keyOf);

  /// The download key (item id, or `itemId-episodeId`) currently shown.
  final String Function() keyOf;
  Object? _last;

  /// True when the item's download status (or the item itself) changed since
  /// the last call. The first call is always true.
  bool changed() {
    final ds = DownloadService();
    final key = keyOf();
    final snap = (key, ds.getInfo(key).status, ds.isDownloaded(key));
    if (snap == _last) return false;
    _last = snap;
    return true;
  }
}
