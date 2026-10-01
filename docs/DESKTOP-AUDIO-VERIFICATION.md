# Desktop audio verification — 2026-10-01

## Verified locally on Windows x64

- `flutter analyze --no-pub`: clean.
- `flutter test --no-pub`: 16 tests passed, including three Windows artwork metadata tests.
- `tool/verify-desktop-audio.ps1`: passed its native fixture checks and required process exit code 0; rebuilt the normal `lib/main.dart` release executable afterward.
- An isolated lifecycle-only run also exited with code 0.

The native check uses the app's actual `AudioPlayerHandler` and platform-aware player, plus native SMTC registration and libmpv decoding. It checks a generated silent 12-second WAV, advancing playback, a stable paused position, seeking, a 1.5x playback clock, loopback HTTP with a fake bearer header, six alternating playlist-index seeks, and a saved starting position. No Audiobookshelf server, credentials, settings, or user media are used. It tests the handler directly, not the complete authenticated application flow.

## Bugs exposed and addressed

1. Windows/Linux had no registered native playback backend. Added desktop-only libmpv registration and SMTC/MPRIS packages.
2. An AVPlayer-only buffering option caused `UnimplementedError` during desktop source loading. It is now restricted to Apple platforms.
3. The adapter could apply a cross-file seek before the new file was ready. Desktop track changes now load while paused before seeking and restoring playback; initial saved positions are also applied after loading.
4. Programmatic Windows exit could leave controller destruction until scope teardown, allowing window messages into a partially destroyed view. The runner now destroys it explicitly before COM cleanup and guards font-change messages during teardown.
5. A separate exit crash came from static Composition objects in `flutter_inappwebview_windows` 0.6.0, matching [upstream #2733](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2733). A hash-checked CMake overlay releases shared graphics resources when the final manager is destroyed. The Pub cache is not modified.
6. The Windows media plugin now owns native cleanup/artwork tasks, delivers media-button events on Flutter's platform thread, and avoids trying to load artwork from a literal `null` path. Its original MIT license is retained in the vendored package.

## Not proven by these checks

- Audible output from physical speakers/headphones (the fixture is intentionally silent).
- Physical media keys, OS artwork appearance, and Windows timeline scrubbing (the latter is not implemented).
- Linux runtime audio/MPRIS behavior; Linux builds need system libmpv and a desktop session bus.
- Real Audiobookshelf login, codecs other than WAV, long listening sessions, playback synchronization, stats, reconnect recovery, and real offline downloads.
- Desktop equalizer, silence skipping, and Whisper audio extraction.

The native backend still logs optional `osc` property and FFmpeg file-cache warnings during successful fixture playback. Do not interpret passing playback checks as verification of streaming disk-cache behavior. Multi-file changes currently reload the selected source and may briefly pause at file boundaries.

Re-run the smoke script after changing native dependencies or the Windows runner. Require both its PASS marker and a zero process exit; earlier failing runs printed PASS before crashing on shutdown, so the marker alone is insufficient.
