# Absorb desktop ports

Unofficial native Windows, Linux, and web ports of [Absorb](https://github.com/pounat/absorb), the Audiobookshelf client.

> [!WARNING]
> This Windows port is experimental and was substantially AI-generated with human direction and verification. It is not an official Absorb release. Review and test changes carefully before relying on it with production data.

## What this project provides

- Native Windows x64 and Linux desktop executables built with Flutter
- Browser build for modern web browsers
- Audiobookshelf server connectivity
- Library browsing, covers, metadata, search, playback, seeking, and playback speed support as the primary targets
- Resizable desktop application window

## Downloads

Download desktop builds from the [Releases](../../releases) page. Extract the Windows or Linux archive and run the included executable. Web builds are published as static files and can be hosted by any static web server.

## Build requirements

- Flutter stable with Windows desktop support
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

Outputs are produced under `build/windows/x64/runner/Release/`, `build/linux/x64/release/bundle/`, and `build/web/`.

## Limitations

Android-only or mobile-specific features are not included in desktop/web targets, including Android Auto, Chromecast, home-screen widgets, Android background services, and APK self-updating. Some features require platform-specific implementations and further testing. The Linux build is produced in CI because the native Linux toolchain is not available on a normal Windows host.

## Attribution

This project is derived from the upstream [pounat/absorb](https://github.com/pounat/absorb) repository. Android and iOS development remains upstream. Please report Windows-port issues here and direct Android/iOS issues to the original project.

## License

Absorb is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
