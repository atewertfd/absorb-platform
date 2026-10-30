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

  bool Function(List<UpdateReleaseAsset>) hasAssetFor(
    UpdateTarget target, {
    List<String> supportedAbis = const [],
  }) => (assets) => releaseHasUpdateAsset(
    target: target,
    assets: assets,
    supportedAbis: supportedAbis,
  );

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
    final windows = hasAssetFor(UpdateTarget.windowsInstalled);
    expect(
      pickUpdateRelease(releases, hasPlatformAsset: windows)?['tag_name'],
      'v1.11.1-297',
    );
    expect(pickUpdateRelease(releases)?['tag_name'], 'v1.11.1-300');
    // No release has the installer yet: offer nothing rather than a tag
    // that "Later" would then dismiss for good.
    expect(
      pickUpdateRelease([release('v1.11.1-300')], hasPlatformAsset: windows),
      isNull,
    );
  });

  test('Android waits for a release that already has an APK it can use', () {
    final releases = [
      release('v1.12.1-311', assets: ['Absorb-1.12.1-Setup.exe']),
      release(
        'v1.12.1-309',
        assets: ['absorb-1.12.1-309-android-arm64-v8a.apk'],
      ),
    ];
    final android = hasAssetFor(
      UpdateTarget.android,
      supportedAbis: ['arm64-v8a'],
    );
    expect(
      pickUpdateRelease(releases, hasPlatformAsset: android)?['tag_name'],
      'v1.12.1-309',
    );
    expect(
      pickUpdateRelease([releases.first], hasPlatformAsset: android),
      isNull,
    );
    // An x86_64 device can't use the arm64 build and there's no universal.
    expect(
      pickUpdateRelease(
        releases,
        hasPlatformAsset: hasAssetFor(
          UpdateTarget.android,
          supportedAbis: ['x86_64'],
        ),
      ),
      isNull,
    );
  });

  test('a portable Windows copy waits for the portable ZIP', () {
    final portable = hasAssetFor(UpdateTarget.windowsPortable);
    expect(portable([]), isFalse);
    expect(
      portable(const [
        UpdateReleaseAsset(
          name: 'absorb-1.12.1-311-windows-portable.zip',
          downloadUrl: 'https://example.invalid/portable.zip',
        ),
      ]),
      isTrue,
    );
    expect(hasAssetFor(UpdateTarget.other)([]), isTrue);
  });

  const fullRelease = [
    UpdateReleaseAsset(
      name: 'Absorb-1.12.1-Setup.exe',
      downloadUrl: 'https://example.invalid/setup.exe',
    ),
    UpdateReleaseAsset(
      name: 'absorb-1.12.1-311-windows-portable.zip',
      downloadUrl: 'https://example.invalid/portable.zip',
    ),
    UpdateReleaseAsset(
      name: 'absorb-1.12.1-311-android-universal.apk',
      downloadUrl: 'https://example.invalid/universal.apk',
    ),
    UpdateReleaseAsset(
      name: 'absorb-1.12.1-311-android-arm64-v8a.apk',
      downloadUrl: 'https://example.invalid/arm64.apk',
    ),
  ];

  test('only Android is ever handed an APK', () {
    expect(
      selectUpdateAsset(
        target: UpdateTarget.android,
        assets: fullRelease,
        supportedAbis: ['arm64-v8a'],
      )?.name,
      'absorb-1.12.1-311-android-arm64-v8a.apk',
    );
    expect(
      selectUpdateAsset(
        target: UpdateTarget.windowsInstalled,
        assets: fullRelease,
      )?.name,
      'Absorb-1.12.1-Setup.exe',
    );
    // A release still missing its installer must not fall back to an APK.
    expect(
      selectUpdateAsset(
        target: UpdateTarget.windowsInstalled,
        assets: fullRelease.where((a) => !a.name.endsWith('.exe')).toList(),
      ),
      isNull,
    );
    expect(
      selectUpdateAsset(target: UpdateTarget.other, assets: fullRelease),
      isNull,
    );
  });

  test('a portable Windows copy opens the release page, not the installer', () {
    expect(
      selectUpdateAsset(
        target: UpdateTarget.windowsPortable,
        assets: fullRelease,
      ),
      isNull,
    );
  });

  test('a Windows copy counts as installed only with unins000.exe beside it',
      () {
    final files = <String>{};
    bool exists(String path) => files.contains(path);
    const exe = r'C:\Program Files\Absorb Plus\absorb.exe';

    expect(isInnoSetupInstall(exe, exists), isFalse);
    files.add(r'C:\Program Files\Absorb Plus\unins000.exe');
    expect(isInnoSetupInstall(exe, exists), isTrue);
    expect(
      isInnoSetupInstall(r'D:\Portable\Absorb\absorb.exe', exists),
      isFalse,
    );
    expect(isInnoSetupInstall('absorb.exe', exists), isFalse);
  });

  test('labels the APK names release CI actually publishes', () {
    UpdateReleaseAsset apk(String name) => UpdateReleaseAsset(
      name: name,
      downloadUrl: 'https://example.invalid/$name',
    );
    expect(
      androidUpdatePackageLabel(apk('absorb-1.12.1-311-android-arm64-v8a.apk')),
      'arm64-v8a APK \u2022 build 311',
    );
    expect(
      androidUpdatePackageLabel(apk('absorb-1.12.1-311-android-universal.apk')),
      'Universal APK \u2022 build 311',
    );
    expect(
      androidUpdatePackageLabel(apk('absorb-1.12.1-311-arm64-v8a.apk')),
      'arm64-v8a APK \u2022 build 311',
    );
    expect(
      androidUpdatePackageLabel(apk('absorb-1.12.1-311-all-universal.apk')),
      'Universal APK \u2022 build 311',
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
