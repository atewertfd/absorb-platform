import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:absorb/utils/memory_policy.dart';

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
}
