import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for cover art. flutter_cache_manager's default keeps only 200
/// files, which a library of a few hundred books (with grid, detail and
/// player sizes of each cover) overflows, so covers kept downloading again.
/// Paired with `stableCoverCacheKey`, which drops the rotating `token` from
/// the key, a cover is fetched once until the book's cover changes.
final CacheManager coverCacheManager = CacheManager(
  Config(
    'absorbCovers',
    maxNrOfCacheObjects: 3000,
    stalePeriod: const Duration(days: 60),
  ),
);
