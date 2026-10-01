# Absorb Desktop and Web Ports

This repository contains experimental desktop and web builds of Absorb from the official `pounat/absorb` source repository.

> **AI-port warning:** These ports were substantially AI-generated with human direction and verification. They are unofficial and experimental. Review and test changes carefully; do not assume feature parity with the upstream Android/iOS applications.

## Build

- Flutter: 3.47.3 stable
- Targets: Windows x64, Linux x64, and web
- Visual Studio: Community 2022 C++ desktop workload
- Build command: `flutter build windows --release`

## Current status

The Flutter project has Windows, Linux, and web targets. The Windows executable is in `build/windows/x64/runner/Release/absorb.exe`; Linux builds are produced by GitHub Actions; the web build is deployed to GitHub Pages.

The desktop and web builds need further runtime testing against an Audiobookshelf server. Mobile-only features such as Android Auto, Chromecast, Android background services, widgets, and APK updating are not expected to work without platform-specific replacements.

The vendored Whisper/ggml CMake install rules were adjusted for Windows so the native plugin can be packaged correctly.
