# Compatibility and stability

Absorb Plus targets the current stable Flutter toolchain and the supported
Audiobookshelf HTTP API. The app is designed to keep useful local playback and
downloads working when optional platform features are unavailable.

## Supported surfaces

| Surface | Status | Notes |
| --- | --- | --- |
| Android | Primary | Audio focus, notifications, downloads, and background playback are supported. |
| Windows | Supported | Native audio output, resizable desktop window, keyboard shortcuts, and installer build. |
| Linux | Supported build | Desktop audio and MPRIS depend on the desktop environment. |
| Web/PWA | Supported build | Installable in Chromium-based browsers; background download behavior is browser-controlled. |
| iOS/macOS | Supported by upstream Flutter project | Some OS media and background behaviors are platform-controlled. |

## Graceful fallbacks

- If system media controls are unavailable, the in-app player controls remain
  available.
- If a browser does not support persistent storage or service-worker caching,
  the app remains usable online and reports download failures instead of
  silently losing them.
- If the server version is unknown, Absorb uses the most compatible API and
  stream URL forms.
- The Settings > Issues & Support > Server health screen uses only read-only
  `/ping`, `/status`, and authenticated library requests to diagnose a server.

## Release verification

Before publishing, run:

```text
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
flutter build windows --release --no-pub
```

The GitHub Actions workflows run the analyzer/tests, web build, and desktop
builds. The all-platform release workflow also publishes a Windows installer,
portable archive, and SHA-256 checksums alongside the mobile artifacts.

Known limits: physical media keys, browser background execution, and real
Audiobookshelf playback/stat synchronization still require verification on the
target device and server because CI cannot reproduce those external services.
