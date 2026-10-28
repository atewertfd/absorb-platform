import 'package:flutter/foundation.dart';

/// The provider state that changes how one library item is rendered.
///
/// Keeping this value object small lets cards use `context.select` instead of
/// rebuilding for every unrelated library notification.
class LibraryItemSnapshot {
  final String? coverUrl;
  final double progress;
  final bool isFinished;
  final bool isPodcastLibrary;
  final bool isSubscribed;
  final int unfinishedCount;
  final Map<String, String> mediaHeaders;

  const LibraryItemSnapshot({
    required this.coverUrl,
    required this.progress,
    required this.isFinished,
    required this.isPodcastLibrary,
    required this.isSubscribed,
    required this.unfinishedCount,
    required this.mediaHeaders,
  });

  @override
  bool operator ==(Object other) {
    return other is LibraryItemSnapshot &&
        other.coverUrl == coverUrl &&
        other.progress == progress &&
        other.isFinished == isFinished &&
        other.isPodcastLibrary == isPodcastLibrary &&
        other.isSubscribed == isSubscribed &&
        other.unfinishedCount == unfinishedCount &&
        mapEquals(other.mediaHeaders, mediaHeaders);
  }

  @override
  int get hashCode {
    final headerHashes = mediaHeaders.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hash(
      coverUrl,
      progress,
      isFinished,
      isPodcastLibrary,
      isSubscribed,
      unfinishedCount,
      Object.hashAll(
        headerHashes.map((entry) => Object.hash(entry.key, entry.value)),
      ),
    );
  }
}
