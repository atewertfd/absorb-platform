import 'package:absorb/services/player_settings.dart';
import 'package:absorb/services/update_check_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'uses twelve hours by default and round-trips valid frequencies',
    () async {
      SharedPreferences.setMockInitialValues({});

      expect(
        await PlayerSettings.getUpdateCheckFrequency(),
        UpdateCheckFrequency.everyTwelveHours,
      );

      await PlayerSettings.setUpdateCheckFrequency(
        UpdateCheckFrequency.everySixHours,
      );
      expect(
        await PlayerSettings.getUpdateCheckFrequency(),
        UpdateCheckFrequency.everySixHours,
      );
    },
  );

  test('unknown stored frequency falls back to twelve hours', () async {
    SharedPreferences.setMockInitialValues({
      updateCheckFrequencyPreferenceKey: 'not-a-frequency',
    });

    expect(
      await PlayerSettings.getUpdateCheckFrequency(),
      UpdateCheckFrequency.everyTwelveHours,
    );
  });
}
