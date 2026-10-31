import 'package:flutter/foundation.dart';

/// Absorb Plus: asks the Stats screen to reload when its tab is opened.
///
/// Stats stays alive in the app shell's IndexedStack and otherwise reloads
/// only through pull-to-refresh, which a mouse can't start on desktop. With
/// the app living in the tray, its numbers could be days old. The app shell
/// calls [tabActivated] on every switch to (or re-tap of) the Stats tab; the
/// Stats screen listens and reloads, at most once per [minInterval].
class StatsTabRefresh extends ChangeNotifier {
  StatsTabRefresh({
    this.minInterval = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static final StatsTabRefresh instance = StatsTabRefresh();

  final Duration minInterval;
  final DateTime Function() _clock;
  DateTime? _last;

  /// The Stats tab became active. Notifies listeners unless it already did
  /// within [minInterval]. (On the first switch the Stats screen doesn't
  /// exist yet, so nobody listens; it loads in initState instead.)
  void tabActivated() {
    final now = _clock();
    final last = _last;
    if (last != null && now.difference(last) < minInterval) return;
    _last = now;
    notifyListeners();
  }
}
