import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';

/// Absorb Plus: narrow provider subscriptions for big upstream screens.
///
/// `context.watch<LibraryProvider>()` at the top of Settings or the app shell
/// rebuilds the whole screen on every provider notification (socket progress,
/// downloads, shelves), even while it sits hidden in the IndexedStack. These
/// snapshots list exactly what each screen shows, so it rebuilds only when
/// one of them changes. Records compare field by field.
extension WatchOnly on BuildContext {
  /// Returns the provider like `watch` does, but rebuilds only when
  /// [snapshot] of it changes.
  T watchOnly<T>(Object? Function(T value) snapshot) {
    select<T, Object?>(snapshot);
    return Provider.of<T>(this, listen: false);
  }
}

/// What the Settings screen's build reads from [AuthProvider].
Object? settingsAuthSnapshot(AuthProvider a) => (
      a.isAdmin,
      a.isRoot,
      a.isBookOrbit,
      a.bookOrbitAdmin?.any,
      a.isSignedOut,
      a.serverUrl,
      a.username,
      a.serverVersion,
      a.useLocalServer,
      a.apiService != null,
    );

/// What the Settings screen's build reads from [LibraryProvider], including
/// the auto-download sources list (names resolve later, so they're included).
Object? settingsLibrarySnapshot(LibraryProvider l) => (
      l.libraries,
      l.selectedLibraryId,
      l.selectedLibrary?['name'],
      l
          .enabledAutoDownloadSources()
          .map((s) => '${s['id']}\u0000${s['name']}\u0000${s['kind']}')
          .join('\u0001'),
    );

/// What the app shell's nav bar reads from [LibraryProvider].
Object? appShellNavSnapshot(LibraryProvider l) =>
    (l.libraries, l.selectedLibraryId, l.isPodcastLibrary);
