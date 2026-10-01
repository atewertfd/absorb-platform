# Absorb Windows Port

This is an experimental native Windows x64 build of Absorb from the official `pounat/absorb` source repository.

## Build

- Flutter: 3.47.3 stable
- Target: Windows x64
- Visual Studio: Community 2022 C++ desktop workload
- Build command: `flutter build windows --release`

## Current status

The Flutter project has been given a Windows target and the native release build completes. The app executable is in `build/windows/x64/runner/Release/absorb.exe`.

The Windows build needs further runtime testing against an Audiobookshelf server. Mobile-only features such as Android Auto, Chromecast, Android background services, widgets, and APK updating are not expected to work on Windows without platform-specific replacements.

The vendored Whisper/ggml CMake install rules were adjusted for Windows so the native plugin can be packaged correctly.
