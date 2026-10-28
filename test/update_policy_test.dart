import 'package:flutter_test/flutter_test.dart';

import 'package:absorb/services/update_policy.dart';

void main() {
  test('selects the Windows setup executable over portable archives', () {
    final selected = selectWindowsUpdateAsset(
      assets: const [
        UpdateReleaseAsset(
          name: 'absorb-1.11.1-289-windows-portable.zip',
          downloadUrl: 'https://example.invalid/portable.zip',
        ),
        UpdateReleaseAsset(
          name: 'Absorb-1.11.1-Setup.exe',
          downloadUrl: 'https://example.invalid/setup.exe',
        ),
        UpdateReleaseAsset(
          name: 'absorb-1.11.1-289-arm64.apk',
          downloadUrl: 'https://example.invalid/app.apk',
        ),
      ],
    );

    expect(selected?.name, 'Absorb-1.11.1-Setup.exe');
  });

  test('does not treat an arbitrary executable as an installer', () {
    final selected = selectWindowsUpdateAsset(
      assets: const [
        UpdateReleaseAsset(
          name: 'absorb-helper.exe',
          downloadUrl: 'https://example.invalid/helper.exe',
        ),
      ],
    );

    expect(selected, isNull);
  });
}
