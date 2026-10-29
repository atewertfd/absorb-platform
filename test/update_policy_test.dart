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

  Map<String, dynamic> release(
    String tag, {
    bool draft = false,
    bool prerelease = true,
    List<String> assets = const [],
  }) => {
    'tag_name': tag,
    'draft': draft,
    'prerelease': prerelease,
    'assets': [
      for (final name in assets)
        {'name': name, 'browser_download_url': 'https://example.invalid/$name'},
    ],
  };

  test('beta tags compare against the installed version and build', () {
    expect(compareUpdateVersions('v1.11.1-300', '1.11.1+299'), greaterThan(0));
    expect(compareUpdateVersions('v1.11.1-300', '1.11.1+300'), 0);
    expect(compareUpdateVersions('v1.11.1-297', '1.11.1+300'), lessThan(0));
    expect(compareUpdateVersions('v1.11.2', '1.11.1+300'), greaterThan(0));
    expect(compareUpdateVersions('v1.11.1', '1.11.1+300'), 0);
    expect(compareUpdateVersions('v1.11.1-288-web-x86', '1.11.1+300'), 0);
  });

  test('picks the highest published version, not the newest created', () {
    final picked = pickUpdateRelease([
      release('v1.11.1-288-web-x86'),
      release('v1.11.1-301', draft: true),
      release('v1.11.1-300'),
      release('v1.11.1-297'),
    ]);
    expect(picked?['tag_name'], 'v1.11.1-300');
    expect(pickUpdateRelease([]), isNull);
    expect(pickUpdateRelease([release('', prerelease: false)]), isNull);
  });

  test('Windows waits for a release that already has its installer', () {
    final releases = [
      release('v1.11.1-300', assets: ['absorb-1.11.1-300-web.zip']),
      release(
        'v1.11.1-297',
        assets: [
          'Absorb-1.11.1-Setup.exe',
          'Absorb-1.11.1-297-windows-portable.zip',
        ],
      ),
    ];
    expect(
      pickUpdateRelease(releases, preferWindowsInstaller: true)?['tag_name'],
      'v1.11.1-297',
    );
    expect(pickUpdateRelease(releases)?['tag_name'], 'v1.11.1-300');
    expect(
      pickUpdateRelease([
        release('v1.11.1-300'),
      ], preferWindowsInstaller: true)?['tag_name'],
      'v1.11.1-300',
    );
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
