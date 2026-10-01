# Absorb for Windows

An unofficial native Windows x64 port of [Absorb](https://github.com/pounat/absorb), the Audiobookshelf client.

> [!WARNING]
> This Windows port is experimental and was substantially AI-generated with human direction and verification. It is not an official Absorb release. Review and test changes carefully before relying on it with production data.

## What this project provides

- Native Windows x64 executable built with Flutter
- Audiobookshelf server connectivity
- Library browsing, covers, metadata, search, playback, seeking, and playback speed support as the primary targets
- Resizable desktop application window

## Download

Download the latest Windows build from the [Releases](../../releases) page, extract the ZIP, and run `absorb.exe`.

## Build requirements

- Windows 10 or 11 x64
- Flutter stable with Windows desktop support
- Visual Studio with the **Desktop development with C++** workload
- Windows Developer Mode enabled, or an elevated build environment for plugin symlinks
- NuGet CLI available on `PATH` for the WebView plugin

## Build

```powershell
flutter pub get
flutter build windows --release
```

The executable is produced under `build/windows/x64/runner/Release/`.

## Limitations

Android-only or mobile-specific features are not included in the Windows target, including Android Auto, Chromecast, home-screen widgets, Android background services, and APK self-updating. Some features require Windows-specific implementations and further testing.

## Attribution

This project is derived from the upstream [pounat/absorb](https://github.com/pounat/absorb) repository. Android and iOS development remains upstream. Please report Windows-port issues here and direct Android/iOS issues to the original project.

## License

Absorb is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
