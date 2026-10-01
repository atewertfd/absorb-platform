# Absorb Plus

An unofficial enhanced cross-platform edition of [Absorb](https://github.com/pounat/absorb), the Audiobookshelf client, for Windows, Linux, and the web.

> [!WARNING]
> These ports are experimental and were substantially AI-generated with human direction and verification. They are not official Absorb releases. Review and test changes carefully before relying on them with production data.

## What this project provides

- Native Windows x64 and Linux desktop executables built with Flutter
- Browser build for modern web browsers
- Desktop keyboard controls: Space play/pause, Left/Right rewind or fast-forward, Ctrl+F search, Ctrl+L Library, and Ctrl+N Now Playing
- Audiobookshelf server connectivity
- Library browsing, covers, metadata, search, playback, seeking, and playback speed support as the primary targets
- Resizable desktop application window
- Download/offline playback tools with byte progress, transfer speed, estimated time remaining, and persistent retryable failures
- Listening statistics, custom themes, playlists/queue controls, and optional on-device Whisper bookmark transcription

## Plus features

Absorb Plus builds on the upstream client with desktop-first controls and cross-platform improvements. Existing upstream features remain the foundation; platform-specific features are enabled where the target supports them. Media-key behavior depends on the operating system and browser, while optional Whisper transcription is currently native-only and is intentionally unavailable in the web build.

## Audible and Libation workflow

Absorb Plus connects to Audiobookshelf; it does not sign in to Audible, store Audible credentials, remove DRM, or bypass Audible protections. If you use [Libation](https://github.com/rmcrackan/Libation), keep that workflow separate: export or organize media with Libation according to its documentation, place the resulting compatible audiobook files in the Audiobookshelf library or ingest location, let Audiobookshelf scan the files, and then refresh Absorb Plus. This preserves Audiobookshelf as the source of truth for metadata, playback position, statistics, and downloads.

The exact formats and export options depend on the titles and rights available in your Audible/Libation setup. Absorb Plus does not attempt to automate protected Audible downloads.

## Downloads

Download desktop builds from the [Releases](../../releases) page. Extract the Windows or Linux archive and run the included executable. The hosted web build is available at the project’s [GitHub Pages site](https://atewertfd.github.io/absorb-platform/).

## Build requirements

- Flutter stable with the desired desktop/web support enabled
- Windows: Visual Studio with the **Desktop development with C++** workload, Windows Developer Mode, and NuGet CLI
- Linux: GTK 3 development packages, CMake, Ninja, Clang, and pkg-config
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

## Limitations

Android-only or mobile-specific features are not included in desktop/web targets, including Android Auto, Chromecast, home-screen widgets, Android background services, and APK self-updating. Some features require platform-specific implementations and further testing. Linux builds are produced in CI when a native Linux toolchain is not available.

## Attribution

This project is derived from the upstream [pounat/absorb](https://github.com/pounat/absorb) repository. Android and iOS development remains upstream. Please report desktop/web port issues here and direct Android/iOS issues to the original project.

## License

Absorb is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
