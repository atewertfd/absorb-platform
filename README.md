# Absorb Plus

An unofficial enhanced cross-platform edition of [Absorb](https://github.com/pounat/absorb), the Audiobookshelf client, for Windows, Linux, and the web.

> [!WARNING]
> These ports are experimental and were substantially AI-generated with human direction and verification. They are not official Absorb releases. Review and test changes carefully before relying on them with production data.

## What this project provides

- Native Windows x64 and Linux desktop executables built with Flutter
- Browser build for modern web browsers
- Desktop keyboard controls: Space play/pause, Left/Right rewind or fast-forward, Ctrl+F search, Ctrl+L Library, and Ctrl+N Now Playing
- Tab-accessible queue, stop, refresh, and offline header controls with visible focus and Enter/Space activation
- Audiobookshelf server connectivity
- Library browsing, covers, metadata, search, playback, seeking, and playback speed support as the primary targets
- Resizable desktop application window
- Download/offline playback tools with byte progress, transfer speed, estimated time remaining, and persistent retryable failures
- Persistent download failure explanations for missing files, full storage, and permission problems
- Listening statistics, custom themes, playlists/queue controls, and optional on-device Whisper bookmark transcription

## Plus features

Absorb Plus builds on the upstream client with desktop-first controls and cross-platform improvements. Existing upstream features remain the foundation; platform-specific features are enabled where the target supports them. Windows and Linux playback use libmpv through `just_audio_media_kit`; Android, iOS, and web retain their existing playback implementations. Windows system media controls use SMTC and Linux uses MPRIS. Physical media-key behavior still needs verification on each desktop environment; this is not a claim of complete platform parity. Optional Whisper transcription is unavailable on the web, and its desktop audio-extraction path still needs implementation/verification.

## Audible and Libation workflow

Absorb Plus connects to Audiobookshelf; it does not currently sign in to Audible, store Audible credentials, remove DRM, or bypass Audible protections. If you already have compatible exported files from [Libation](https://github.com/rmcrackan/Libation), open **Manage → Upload → Import Libation exports**. Select audio files for one book and its cover, review the title and server destination, then explicitly select **Upload**. After Audiobookshelf indexes the book, refresh your library. This preserves Audiobookshelf as the source of truth for metadata, playback position, statistics, and downloads.

The exporter handoff is distinct from the requested future **Connect Audible** feature, which would work without a separate Libation installation. That integration is not implemented; its authentication, licensing, platform and content-access constraints are documented in the [feasibility record](docs/AUDIBLE-INTEGRATION.md). Other software integrations are deferred.

The exact formats and export options depend on the titles and rights available in your Audible/Libation setup. Absorb Plus does not attempt to automate protected Audible downloads.

See [import verification](docs/IMPORT-VERIFICATION.md) for tests, visual checks, and remaining limits. File imports currently handle one book at a time, require server upload permissions, and do not provide folder scanning, a batch queue, or resumable uploads.

## Downloads

Download desktop builds from the [Releases](../../releases) page. The manually dispatched [Windows Desktop Build workflow](../../actions/workflows/windows-build.yml) also produces a portable Windows archive and an optional **Absorb-*-Setup.exe** installer artifact; the installer creates desktop and Start-menu shortcuts, contains the complete Flutter bundle, and can be removed from Windows Apps. Extract the **entire** portable archive if you use that option, and keep its libraries and data alongside it. Windows bundles its native audio decoder. Linux requires a system libmpv runtime (`libmpv1` on Ubuntu 22.04, `libmpv2` on Ubuntu 24.04) and a desktop session bus for MPRIS controls. The hosted web build is available at the project’s [GitHub Pages site](https://atewertfd.github.io/absorb-platform/).

## Build requirements

- Flutter stable with the desired desktop/web support enabled
- Windows: Visual Studio with the **Desktop development with C++** workload, Windows Developer Mode, and NuGet CLI
- Linux: GTK 3 development packages, CMake, Ninja, Clang, pkg-config, libmpv-dev, and WebKitGTK 4.0 development packages (CI uses Ubuntu 22.04)
- Web: Flutter web support and a modern browser

## Build

```powershell
flutter pub get
flutter build windows --release
flutter build linux --release
flutter build web --release
```

Outputs are produced under `build/windows/x64/runner/Release/`, `build/linux/x64/release/bundle/`, and `build/web/`. Every push to `main` rebuilds the web site through GitHub Actions and deploys it to GitHub Pages.

Run the local regression tests with:

```powershell
flutter test
```

The web build and Pages deployment also run analysis and regression tests before publishing. Coverage includes token refresh recovery, failed-download persistence and retry rejection, and keyboard/screen-reader behavior for the compact header controls. These checks do not replace playback testing against a real server on each platform.

### Native audio smoke test

See the [verification record](docs/DESKTOP-AUDIO-VERIFICATION.md) for tested behavior, fixed failures, and remaining gaps.

Build the isolated test target on the target desktop, then run the generated executable:

```powershell
flutter build windows --release -t tool/desktop_audio_smoke.dart
# Run build/windows/x64/runner/Release/absorb.exe
# On Linux: flutter build linux --release -t tool/desktop_audio_smoke.dart
```

On Windows, `pwsh -File tool/verify-desktop-audio.ps1` automates the build/run checks and restores the normal application build afterward. Pass `-Flutter C:\path\to\flutter.bat` if Flutter is not on PATH. Run on a desktop with an audio output device; headless CI is not a substitute for that check.

The test generates a silent WAV in a unique temporary directory, initializes the real audio handler/native media service, and checks local playback, pause, seeking, speed, multi-file playlist selection, and HTTP playback against a loopback-only fixture with a fake authorization header. It removes its fixture afterward and requires both `DESKTOP_AUDIO_SMOKE PASS` and a clean process exit. It does not use Audiobookshelf credentials or library data, and does not prove audible speaker output, physical media keys, server synchronization, or codec compatibility beyond WAV. Rebuild the normal application afterward with `flutter build windows --release -t lib/main.dart` (or `linux`); **do not distribute the smoke-test executable**.

## Limitations

Android-only or mobile-specific features are not included in desktop/web targets, including Android Auto, Chromecast, home-screen widgets, Android background services, and APK self-updating. Some features require platform-specific implementations and further testing. Linux builds are produced in CI when a native Linux toolchain is not available.

The desktop audio backend does not implement the mobile equalizer or silence skipping. Windows SMTC integration does not currently expose OS timeline scrubbing; use the app's seek controls. Real Audiobookshelf playback, reconnect/sync behavior, physical media keys, and Linux runtime audio still need end-to-end verification. A successful build alone is not evidence that those flows work.

Windows media integration includes a [small vendored patch](packages/audio_service_win/PATCHES.md) for native-object cleanup and platform-thread callback delivery. Desktop cross-file seeking reloads the selected file before applying its position to avoid an adapter timing race; this can introduce a brief pause when crossing file boundaries.

Windows builds also apply a scoped WebView shutdown fix for [upstream issue #2733](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2733). CMake compiles a patched copy in the build directory, without changing the shared Pub cache. It verifies the original source hash and requires review if an upstream update changes that file.

## Attribution

This project is derived from the upstream [pounat/absorb](https://github.com/pounat/absorb) repository. Android and iOS development remains upstream. Please report desktop/web port issues here and direct Android/iOS issues to the original project.

## License

Absorb is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
