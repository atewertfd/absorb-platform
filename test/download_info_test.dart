import 'package:flutter_test/flutter_test.dart';

import 'package:absorb/services/download_service.dart';

void main() {
  test('persists download telemetry across serialization', () {
    final original = DownloadInfo(
      itemId: 'book-123',
      status: DownloadStatus.downloading,
      progress: 0.625,
      bytesDone: 150000000,
      bytesTotal: 240000000,
      speedBytesPerSecond: 5200000.5,
      etaSeconds: 18,
      activeTrack: 2,
      trackCount: 8,
      title: 'Example audiobook',
      author: 'Example author',
      libraryId: 'library-1',
    );

    final restored = DownloadInfo.fromJson(original.toJson());

    expect(restored.itemId, original.itemId);
    expect(restored.status, DownloadStatus.downloading);
    expect(restored.progress, original.progress);
    expect(restored.bytesDone, original.bytesDone);
    expect(restored.bytesTotal, original.bytesTotal);
    expect(restored.speedBytesPerSecond, original.speedBytesPerSecond);
    expect(restored.etaSeconds, original.etaSeconds);
    expect(restored.activeTrack, original.activeTrack);
    expect(restored.trackCount, original.trackCount);
    expect(restored.title, original.title);
    expect(restored.author, original.author);
    expect(restored.libraryId, original.libraryId);
  });
}
