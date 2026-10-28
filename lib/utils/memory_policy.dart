import 'package:flutter/painting.dart';

/// Maximum number of decoded image bytes retained by Flutter's shared cache.
///
/// This limits decoded bitmaps, not the on-disk HTTP cache. Keeping the limit
/// moderate prevents a large library browse from retaining full-resolution
/// covers indefinitely while still leaving room for smooth scrolling.
const int kAbsorbImageCacheMaximumBytes = 64 * 1024 * 1024;

/// Maximum number of decoded image entries retained by Flutter's shared cache.
const int kAbsorbImageCacheMaximumEntries = 500;

/// Applies Absorb's conservative decoded-image cache limits.
///
/// The cache evicts its oldest eligible entries as it crosses either limit.
/// Live images are not cleared here, so this does not interrupt images that
/// are currently being displayed.
void configureImageCache(ImageCache cache) {
  cache.maximumSizeBytes = kAbsorbImageCacheMaximumBytes;
  cache.maximumSize = kAbsorbImageCacheMaximumEntries;
}

/// Releases decoded images that are no longer attached to a live widget.
///
/// Live images are deliberately retained so returning from the background
/// does not flash blank covers. This helper is also intentionally independent
/// of audio and platform channels.
void trimDecodedImageCacheForBackground(ImageCache cache) {
  cache.clear();
}
