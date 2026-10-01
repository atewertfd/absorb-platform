# Absorb desktop ports

Unofficial cross-platform desktop and web ports of [Absorb](https://github.com/pounat/absorb), the Audiobookshelf client.

> [!WARNING]
> These ports are experimental and were substantially AI-generated with human direction and verification. They are not official Absorb releases. Review and test changes carefully before relying on them with production data.

## What this project provides

- Native Windows x64 and Linux desktop executables built with Flutter
- Browser build for modern web browsers
- Audiobookshelf server connectivity
- Library browsing, covers, metadata, search, playback, seeking, and playback speed support as the primary targets
- Resizable desktop application window

## Downloads

Download desktop builds from the [Releases](../../releases) page. Extract the Windows or Linux archive and run the included executable. The hosted web build is available at the project’s [GitHub Pages site](https://atewertfd.github.io/absorb-ports/).

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

## Limitations

Android-only or mobile-specific features are not included in desktop/web targets, including Android Auto, Chromecast, home-screen widgets, Android background services, and APK self-updating. Some features require platform-specific implementations and further testing. Linux builds are produced in CI when a native Linux toolchain is not available.

## Attribution

This project is derived from the upstream [pounat/absorb](https://github.com/pounat/absorb) repository. Android and iOS development remains upstream. Please report desktop/web port issues here and direct Android/iOS issues to the original project.

## License

Absorb is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
