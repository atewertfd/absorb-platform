class UpdateReleaseAsset {
  final String name;
  final String downloadUrl;

  const UpdateReleaseAsset({required this.name, required this.downloadUrl});
}

const supportedAndroidUpdateAbis = <String>{
  'armeabi-v7a',
  'arm64-v8a',
  'x86_64',
};

UpdateReleaseAsset? selectAndroidUpdateAsset({
  required List<UpdateReleaseAsset> assets,
  required List<String> supportedAbis,
}) {
  final apks = assets
      .where((asset) => asset.name.toLowerCase().endsWith('.apk'))
      .toList();

  for (final abi in supportedAbis.map((value) => value.toLowerCase())) {
    if (!supportedAndroidUpdateAbis.contains(abi)) continue;
    for (final asset in apks) {
      if (_hasFilenameToken(asset.name, abi)) return asset;
    }
  }

  for (final asset in apks) {
    if (_hasFilenameToken(asset.name, 'universal')) return asset;
  }

  if (apks.length == 1 &&
      !supportedAndroidUpdateAbis.any(
        (abi) => _hasFilenameToken(apks.single.name, abi),
      )) {
    return apks.single;
  }
  return null;
}

/// Selects the installer asset for the Windows desktop build.
///
/// Release pages may also contain portable archives and Android APKs. The
/// installed Windows app must use the Inno Setup executable so an update keeps
/// the existing install registration and user data intact.
UpdateReleaseAsset? selectWindowsUpdateAsset({
  required List<UpdateReleaseAsset> assets,
}) {
  final installers = assets.where((asset) {
    final name = asset.name.toLowerCase();
    return name.endsWith('.exe') &&
        (name.contains('setup') || name.contains('installer'));
  }).toList();
  if (installers.length == 1) return installers.single;
  if (installers.isEmpty) return null;

  // Prefer the conventional name if a release contains multiple installer
  // builds, then fall back to the first deterministic result.
  for (final asset in installers) {
    if (asset.name.toLowerCase().contains('setup')) return asset;
  }
  return installers.first;
}

String currentUpdateVersion({
  required String versionName,
  required String packageBuildNumber,
  int? baseBuildNumber,
}) {
  final build = baseBuildNumber != null && baseBuildNumber > 0
      ? baseBuildNumber.toString()
      : packageBuildNumber;
  return '$versionName+$build';
}

int compareUpdateVersions(String a, String b) {
  final (aSem, aBuild) = _parseVersion(a);
  final (bSem, bBuild) = _parseVersion(b);
  for (int i = 0; i < 3; i++) {
    if (aSem[i] != bSem[i]) return aSem[i] - bSem[i];
  }
  if (aBuild != null && bBuild != null) return aBuild - bBuild;
  return 0;
}

/// Picks the release to offer from GitHub's release list (newest created
/// first). GitHub orders by creation date rather than version, and a
/// tag-triggered release exists for several minutes before CI attaches the
/// Windows installer, so choose the highest-version published release and,
/// when [preferWindowsInstaller], one that already carries the installer.
Map<String, dynamic>? pickUpdateRelease(
  List<Map<String, dynamic>> releases, {
  bool preferWindowsInstaller = false,
}) {
  final published = releases
      .where(
        (release) =>
            release['draft'] != true &&
            (release['tag_name'] as String? ?? '').isNotEmpty,
      )
      .toList();

  // A tag without a trailing build (`v1.11.1-288-web-x86`) ranks below any
  // tag of the same version that has one; ties keep GitHub's newest-first.
  int rank(Map<String, dynamic> a, Map<String, dynamic> b) {
    final (aSem, aBuild) = _parseVersion(a['tag_name'] as String);
    final (bSem, bBuild) = _parseVersion(b['tag_name'] as String);
    for (int i = 0; i < 3; i++) {
      if (aSem[i] != bSem[i]) return aSem[i] - bSem[i];
    }
    return (aBuild ?? -1) - (bBuild ?? -1);
  }

  Map<String, dynamic>? newest(Iterable<Map<String, dynamic>> candidates) {
    Map<String, dynamic>? best;
    for (final release in candidates) {
      if (best == null || rank(release, best) > 0) best = release;
    }
    return best;
  }

  if (preferWindowsInstaller) {
    final withInstaller = newest(
      published.where(
        (release) =>
            selectWindowsUpdateAsset(assets: releaseAssetsOf(release)) != null,
      ),
    );
    if (withInstaller != null) return withInstaller;
  }
  return newest(published);
}

List<UpdateReleaseAsset> releaseAssetsOf(Map<String, dynamic> release) {
  final assets = <UpdateReleaseAsset>[];
  for (final rawAsset in release['assets'] as List<dynamic>? ?? const []) {
    if (rawAsset is! Map<String, dynamic>) continue;
    final name = rawAsset['name'] as String? ?? '';
    final url = rawAsset['browser_download_url'] as String? ?? '';
    if (name.isNotEmpty && url.isNotEmpty) {
      assets.add(UpdateReleaseAsset(name: name, downloadUrl: url));
    }
  }
  return assets;
}

String androidUpdatePackageLabel(UpdateReleaseAsset asset) {
  var packageKind = 'Universal';
  for (final abi in supportedAndroidUpdateAbis) {
    if (_hasFilenameToken(asset.name, abi)) {
      packageKind = abi;
      break;
    }
  }

  final build = RegExp(
    r'-(\d+)-(?:universal|armeabi-v7a|arm64-v8a|x86_64)(?:-pre)?\.apk$',
    caseSensitive: false,
  ).firstMatch(asset.name)?.group(1);
  return build == null ? '$packageKind APK' : '$packageKind APK • build $build';
}

bool _hasFilenameToken(String filename, String token) {
  final pattern = RegExp(
    '(^|[-_.])${RegExp.escape(token)}(?=[-_.]|\$)',
    caseSensitive: false,
  );
  return pattern.hasMatch(filename);
}

(List<int>, int?) _parseVersion(String version) {
  final sem = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(version);
  final parts = [for (var i = 1; i <= 3; i++) int.parse(sem?.group(i) ?? '0')];
  final build = RegExp(r'[-+](\d+)$').firstMatch(version);
  return (parts, build == null ? null : int.parse(build.group(1)!));
}
