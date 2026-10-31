# Compatibility and stability

Absorb Plus targets the current stable Flutter toolchain and the supported
Audiobookshelf HTTP API. The app is designed to keep useful local playback and
downloads working when optional platform features are unavailable.

## Supported surfaces

| Surface | Status | Notes |
| --- | --- | --- |
| Windows | Primary | Native audio output, resizable desktop window, keyboard shortcuts, optional tray, taskbar controls, and installer build. |
| Android | Supported | Audio focus, notifications, downloads, and background playback are supported. |
| Linux | Supported build | Desktop audio and MPRIS depend on the desktop environment. The `.deb` depends on GTK 3, WebKitGTK 4.1 and libmpv. |
| Web/PWA | Supported build | Installable in Chromium-based browsers; background download behavior is browser-controlled. |
| iOS/macOS | Not built | Apple platforms were removed from Absorb Plus; use upstream Absorb. |

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
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build web --release --no-pub
flutter build windows --release --no-pub --dart-define=GITHUB_BUILD=true
```

On Windows, `tool/dev.ps1 check` and `tool/dev.ps1 build` run these.

GitHub Actions runs the analyzer and tests on every code push, and builds web
and Linux on `main`, pull requests and manual runs (Windows is built locally
for every change). A `v*` tag runs `release.yml`, which publishes the Windows
installer and portable ZIP, the Linux tar.gz and .deb, the web ZIP and the
Android APKs in one release. The release stays a draft until every build is
attached. No checksum files are published.

Known limits: physical media keys, browser background execution, and real
Audiobookshelf playback/stat synchronization still require verification on the
target device and server because CI cannot reproduce those external services.
