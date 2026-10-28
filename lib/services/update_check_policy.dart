import 'dart:async';

/// Automatic update-check frequencies supported by the desktop settings.
enum UpdateCheckFrequency {
  startup,
  everySixHours,
  everyTwelveHours,
  daily,
  never,
}

/// GitHub-distributed builds are intentionally on the beta channel. New
/// installs should therefore check GitHub pre-releases by default, while a
/// user's explicit preference still wins once it has been saved.
bool defaultIncludePreReleases({
  required bool isGithubBuild,
  required bool? savedPreference,
}) {
  return savedPreference ?? isGithubBuild;
}

const updateCheckFrequencyPreferenceKey = 'update_check_frequency';

String updateCheckFrequencyKey(UpdateCheckFrequency frequency) {
  switch (frequency) {
    case UpdateCheckFrequency.startup:
      return 'startup';
    case UpdateCheckFrequency.everySixHours:
      return '6h';
    case UpdateCheckFrequency.everyTwelveHours:
      return '12h';
    case UpdateCheckFrequency.daily:
      return '24h';
    case UpdateCheckFrequency.never:
      return 'never';
  }
}

UpdateCheckFrequency updateCheckFrequencyFromKey(String? key) {
  switch (key) {
    case 'startup':
      return UpdateCheckFrequency.startup;
    case '6h':
      return UpdateCheckFrequency.everySixHours;
    case '12h':
      return UpdateCheckFrequency.everyTwelveHours;
    case '24h':
      return UpdateCheckFrequency.daily;
    case 'never':
      return UpdateCheckFrequency.never;
    default:
      return UpdateCheckFrequency.everyTwelveHours;
  }
}

Duration? updateCheckInterval(UpdateCheckFrequency frequency) {
  switch (frequency) {
    case UpdateCheckFrequency.startup:
    case UpdateCheckFrequency.everyTwelveHours:
      return const Duration(hours: 12);
    case UpdateCheckFrequency.everySixHours:
      return const Duration(hours: 6);
    case UpdateCheckFrequency.daily:
      return const Duration(hours: 24);
    case UpdateCheckFrequency.never:
      return null;
  }
}

bool isUpdateCheckDue({
  required UpdateCheckFrequency frequency,
  required DateTime now,
  required DateTime? lastChecked,
}) {
  final interval = updateCheckInterval(frequency);
  if (interval == null) return false;
  if (lastChecked == null) return true;
  if (now.isBefore(lastChecked)) return false;
  return now.difference(lastChecked) >= interval;
}

/// Shares one asynchronous update request among simultaneous callers.
class InFlightUpdateCheck<T> {
  Future<T>? _active;

  Future<T> run(Future<T> Function() operation) {
    final active = _active;
    if (active != null) return active;

    final future = Future<T>.sync(operation);
    _active = future;
    unawaited(
      future.then<void>(
        (_) => _clear(future),
        onError: (Object _, StackTrace __) => _clear(future),
      ),
    );
    return future;
  }

  void _clear(Future<T> completed) {
    if (identical(_active, completed)) _active = null;
  }
}
