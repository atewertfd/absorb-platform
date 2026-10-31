import 'package:absorb/utils/cover_palette.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('palette source decodes the cover small', () {
    const cover = AssetImage('assets/icon/app_icon.png');
    final source = paletteSource(cover);
    expect(source, isA<ResizeImage>());
    expect((source as ResizeImage).width, coverPaletteWidth);
    expect(source.imageProvider, cover);
  });
}
