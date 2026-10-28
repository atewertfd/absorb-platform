import 'dart:async';

import 'package:absorb/services/update_check_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub builds default to the beta update channel', () {
    expect(
      defaultIncludePreReleases(
        isGithubBuild: true,
        savedPreference: null,
      ),
      isTrue,
    );
    expect(
      defaultIncludePreReleases(
        isGithubBuild: false,
        savedPreference: null,
      ),
      isFalse,
    );
  });

  test('an explicit update-channel preference is preserved', () {
    expect(
      defaultIncludePreReleases(
        isGithubBuild: true,
        savedPreference: false,
      ),
      isFalse,
    );
    expect(
      defaultIncludePreReleases(
        isGithubBuild: false,
        savedPreference: true,
      ),
      isTrue,
    );
  });

  test('serializes supported frequencies and falls back safely', () {
    for (final frequency in UpdateCheckFrequency.values) {
      final key = updateCheckFrequencyKey(frequency);
      expect(updateCheckFrequencyFromKey(key), frequency);
    }
    expect(
      updateCheckFrequencyFromKey('unknown'),
      UpdateCheckFrequency.everyTwelveHours,
    );
    expect(
      updateCheckFrequencyFromKey(null),
      UpdateCheckFrequency.everyTwelveHours,
    );
  });

  test('uses the expected automatic intervals', () {
    expect(
      updateCheckInterval(UpdateCheckFrequency.startup),
      const Duration(hours: 12),
    );
    expect(
      updateCheckInterval(UpdateCheckFrequency.everySixHours),
      const Duration(hours: 6),
    );
    expect(
      updateCheckInterval(UpdateCheckFrequency.everyTwelveHours),
      const Duration(hours: 12),
    );
    expect(
      updateCheckInterval(UpdateCheckFrequency.daily),
      const Duration(hours: 24),
    );
    expect(updateCheckInterval(UpdateCheckFrequency.never), isNull);
  });

  test('only reports an automatic check as due after its interval', () {
    final now = DateTime(2026, 10, 28, 12);
    expect(
      isUpdateCheckDue(
        frequency: UpdateCheckFrequency.everySixHours,
        now: now,
        lastChecked: null,
      ),
      isTrue,
    );
    expect(
      isUpdateCheckDue(
        frequency: UpdateCheckFrequency.everySixHours,
        now: now,
        lastChecked: now.subtract(const Duration(hours: 5, minutes: 59)),
      ),
      isFalse,
    );
    expect(
      isUpdateCheckDue(
        frequency: UpdateCheckFrequency.everySixHours,
        now: now,
        lastChecked: now.subtract(const Duration(hours: 6)),
      ),
      isTrue,
    );
    expect(
      isUpdateCheckDue(
        frequency: UpdateCheckFrequency.never,
        now: now,
        lastChecked: null,
      ),
      isFalse,
    );
  });

  test('shares an in-flight check and allows a later check', () async {
    final guard = InFlightUpdateCheck<int>();
    var calls = 0;
    final gate = Completer<void>();

    final first = guard.run(() async {
      calls++;
      await gate.future;
      return 7;
    });
    final second = guard.run(() async {
      calls++;
      return 8;
    });

    expect(identical(first, second), isTrue);
    gate.complete();
    expect(await first, 7);
    expect(calls, 1);
    expect(
      await guard.run(() async {
        calls++;
        return 9;
      }),
      9,
    );
    expect(calls, 2);
  });
}
