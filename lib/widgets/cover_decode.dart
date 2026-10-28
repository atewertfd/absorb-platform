const int minCoverDecodeWidth = 64;
const int maxCoverDecodeWidth = 1024;

/// Blur-only cover layers do not need foreground detail. Keeping their source
/// small avoids retaining a second full-resolution bitmap just to blur it.
const int blurCoverDecodeWidth = 32;

/// Returns a bounded physical-pixel decode size for a displayed cover.
///
/// Card covers should not retain a full server-resolution bitmap when their
/// largest on-screen dimension is small. Unbounded constraints use the safe
/// maximum rather than guessing from the source image size.
int coverDecodeWidth({
  required double width,
  required double height,
  required double devicePixelRatio,
}) {
  if (!width.isFinite || !height.isFinite) return maxCoverDecodeWidth;
  final largestDimension = width > height ? width : height;
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final physicalWidth = (largestDimension * dpr).round();
  return physicalWidth.clamp(minCoverDecodeWidth, maxCoverDecodeWidth);
}
