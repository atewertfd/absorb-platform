# Absorb Plus implementation roadmap

This port keeps the upstream Absorb visual language and adds cross-platform behavior in small, testable pieces.

## Implemented

- Windows, Linux, and web Flutter targets
- Resizable desktop window and desktop keyboard controls
- Focusable queue, stop, refresh, and offline header actions with Enter/Space activation and a visible keyboard focus outline
- Audiobookshelf library, playback, seeking, playback speed, covers, metadata, and statistics
- Playlists, queue modes, auto-downloads, offline playback, and custom themes
- Download byte progress, transfer speed, estimated time remaining, and accessible progress announcements
- Persistent failed-download records with retry and dismiss controls, metadata recovery tests, and screen-reader summaries
- Failed downloads retain their library filter and remain retryable when downloader startup is rejected; service-level regression tests cover both cases
- Missing-file, disk-full, and permission failures retain a localized explanation after restart; tests simulate downloader failure callbacks and persisted records (not a real disk-full device)
- Audiobookshelf token-refresh recovery coverage for both 401 rotation and transient 503 retry, plus an app-shell widget smoke test
- Global media controls where the host platform exposes them
- Optional native Whisper bookmark transcription
- GitHub Pages web deployment and release-oriented desktop builds
- Analysis and regression tests gate web artifacts and Pages publication

## Stability-focused next work

- Expand integration coverage around API errors, reconnects, and offline-to-online synchronization
- Add more download recovery tests for interrupted files and low-storage conditions
- Improve accessibility coverage for queue, playlist, and player actions across keyboard and screen readers
- Continue platform-specific verification for Windows and Linux media keys, audio focus, and window resizing

## Deliberate boundary

Audible/Libation support is an import handoff through Audiobookshelf. The app does not collect Audible credentials, bypass DRM, or copy protected content. See the main README for the supported workflow.
