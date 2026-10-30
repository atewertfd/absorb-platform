import 'package:flutter/painting.dart';

import '../ui_themes/ui_theme.dart';

/// Maximum number of decoded image bytes retained by Flutter's shared cache.
///
/// This limits decoded bitmaps, not the on-disk HTTP cache. Keeping the limit
/// moderate prevents a large library browse from retaining full-resolution
/// covers indefinitely while still leaving room for smooth scrolling.
const int kAbsorbImageCacheMaximumBytes = 64 * 1024 * 1024;

/// Maximum number of decoded image entries retained by Flutter's shared cache.
const int kAbsorbImageCacheMaximumEntries = 500;

/// Flutter's own [ImageCache] defaults, used by looks that keep them
/// ([UiThemeSpec.defaultImageCache], e.g. Classic).
const int kFlutterDefaultImageCacheMaximumBytes = 100 << 20;
const int kFlutterDefaultImageCacheMaximumEntries = 1000;

ImageCache? _configuredCache;
bool _followingUiTheme = false;

/// Applies Absorb's conservative decoded-image cache limits, or Flutter's
/// defaults when the active UI theme asks for them. The limits follow later
/// UI theme changes.
///
/// The cache evicts its oldest eligible entries as it crosses either limit.
/// Live images are not cleared here, so this does not interrupt images that
/// are currently being displayed.
void configureImageCache(ImageCache cache) {
  _configuredCache = cache;
  _applyImageCacheLimits(cache);
  if (!_followingUiTheme) {
    _followingUiTheme = true;
    uiThemeNotifier.addListener(() {
      final current = _configuredCache;
      if (current != null) _applyImageCacheLimits(current);
    });
  }
}

void _applyImageCacheLimits(ImageCache cache) {
  if (currentUiThemeSpec.defaultImageCache) {
    cache.maximumSizeBytes = kFlutterDefaultImageCacheMaximumBytes;
    cache.maximumSize = kFlutterDefaultImageCacheMaximumEntries;
  } else {
    cache.maximumSizeBytes = kAbsorbImageCacheMaximumBytes;
    cache.maximumSize = kAbsorbImageCacheMaximumEntries;
  }
}

/// Releases decoded images that are no longer attached to a live widget,
/// unless the active UI theme keeps Flutter's default cache.
///
/// Live images are deliberately retained so returning from the background
/// does not flash blank covers. This helper is also intentionally independent
/// of audio and platform channels.
void trimDecodedImageCacheForBackground(ImageCache cache) {
  if (currentUiThemeSpec.defaultImageCache) return;
  cache.clear();
}
