import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'audio_player_service.dart';
import 'download_service.dart';
import 'user_account_service.dart';

/// Listening to downloads after the session expired. The account stays saved
/// with its token cleared and remains the active scope, so progress and
/// listening sessions queue under it exactly like offline listening, and
/// signing back into it sends them up.
class SignedOutPlayback {
  SignedOutPlayback._();

  static bool _active = false;
  static bool get active => _active;

  /// The account whose session ran out, or null when there isn't one (a
  /// fresh install, or the user signed out and removed the account).
  static SavedAccount? expiredAccount() {
    final accounts = UserAccountService();
    final scope = accounts.activeScopeKey;
    if (scope.isEmpty) return null;
    for (final account in accounts.accounts) {
      if (account.scopeKey == scope && account.token.isEmpty) return account;
    }
    return null;
  }

  static bool get available =>
      expiredAccount() != null && DownloadService().downloadedItems.isNotEmpty;

  /// Every server call fails straight away as unreachable, which the sync
  /// paths already treat as offline: kept, and sent after the next sign-in.
  static ApiService api() =>
      ApiService(baseUrl: 'http://signed-out.invalid', token: '');

  static void started() {
    if (!_active) {
      debugPrint(
          '[SignedOut] Playing downloads signed out, listening queues for ${expiredAccount()?.username}');
    }
    _active = true;
    UserAccountService.beforeAccountChange = end;
  }

  /// Stops signed-out playback before another sign-in changes the active
  /// account, so its listening is saved under the account it belongs to.
  static Future<void> end() async {
    if (!_active) return;
    _active = false;
    debugPrint('[SignedOut] Signing in, stopping signed-out playback first');
    UserAccountService.beforeAccountChange = null;
    final player = AudioPlayerService();
    if (player.hasBook) {
      await player.pause();
      await player.stop();
    }
  }
}
