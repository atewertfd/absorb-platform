import 'package:flutter_test/flutter_test.dart';
import 'package:absorb/widgets/stable_cached_network_image.dart';

void main() {
  test('keeps the stable cover widget gapless on URL changes', () {
    final image = StableCachedNetworkImage(
      imageUrl: 'https://example.test/cover.jpg',
      cacheKey: 'cover',
    );

    expect(image.useOldImageOnUrlChange, isTrue);
  });
}
