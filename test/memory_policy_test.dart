import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:absorb/utils/memory_policy.dart';

class _RecordingImageCache extends ImageCache {
  int clearCalls = 0;
  int clearLiveImagesCalls = 0;

  @override
  void clear() {
    clearCalls++;
  }

  @override
  void clearLiveImages() {
    clearLiveImagesCalls++;
  }
}

void main() {
  test('uses conservative decoded image cache limits', () {
    expect(kAbsorbImageCacheMaximumBytes, 64 * 1024 * 1024);
    expect(kAbsorbImageCacheMaximumEntries, 500);
  });

  test('applies both limits without clearing the cache', () {
    final cache = ImageCache();

    configureImageCache(cache);

    expect(cache.maximumSizeBytes, kAbsorbImageCacheMaximumBytes);
    expect(cache.maximumSize, kAbsorbImageCacheMaximumEntries);
  });

  test('background trim clears non-live entries but keeps live images', () {
    final cache = _RecordingImageCache();

    trimDecodedImageCacheForBackground(cache);

    expect(cache.clearCalls, 1);
    expect(cache.clearLiveImagesCalls, 0);
  });
}
