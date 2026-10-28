import 'package:flutter_test/flutter_test.dart';
import 'package:absorb/widgets/cover_decode.dart';
import 'package:absorb/widgets/stable_cached_network_image.dart';

void main() {
  test('bounds stable cover decoding by default', () {
    final image = StableCachedNetworkImage(
      imageUrl: 'https://example.test/cover.jpg',
      cacheKey: 'cover',
    );

    expect(image.memCacheWidth, maxCoverDecodeWidth);
  });

  test('preserves a caller-provided smaller decode width', () {
    final image = StableCachedNetworkImage(
      imageUrl: 'https://example.test/cover.jpg',
      cacheKey: 'cover',
      memCacheWidth: 320,
      memCacheHeight: 480,
    );

    expect(image.memCacheWidth, 320);
    expect(image.memCacheHeight, 480);
  });
}
