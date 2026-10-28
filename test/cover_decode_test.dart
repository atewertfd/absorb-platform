import 'package:flutter_test/flutter_test.dart';

import 'package:absorb/widgets/cover_decode.dart';

void main() {
  test('uses the largest displayed dimension and device pixel ratio', () {
    expect(coverDecodeWidth(width: 120, height: 180, devicePixelRatio: 2), 360);
  });

  test('keeps tiny displays at a useful minimum decode size', () {
    expect(coverDecodeWidth(width: 10, height: 12, devicePixelRatio: 1), 64);
  });

  test('caps very large or unbounded displays', () {
    expect(
      coverDecodeWidth(
        width: double.infinity,
        height: double.infinity,
        devicePixelRatio: 4,
      ),
      1024,
    );
  });
}
