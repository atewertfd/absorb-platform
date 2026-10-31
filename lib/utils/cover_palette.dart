import 'package:flutter/painting.dart';

/// Width covers are decoded at for colour extraction. palette_generator walks
/// every pixel of the image it gets on the UI thread: about 0.5 s for an
/// 800 px cover (measured in the log), a few milliseconds at this size, with
/// the same accent colour.
const coverPaletteWidth = 112;

/// [cover] decoded small, for `PaletteGenerator.fromImageProvider`.
ImageProvider paletteSource(ImageProvider cover) =>
    ResizeImage(cover, width: coverPaletteWidth);
