# Code audit

A full, read-only audit of Absorb Plus (about 190,000 lines of Dart plus native code, vendored packages, tools, tests and CI), done on 2026-10-30 by 9 parallel auditors. Every finding below was checked against the code; confidence is noted in the area reports.

Each area report has two parts:

1. **Code map:** what every file does, how data flows, entry points and traps. Future AI sessions should read the relevant report before working in that area.
2. **Findings:** bugs, dead code, duplication, slow spots and risky patterns, each marked fork (our code) or upstream (costs merge effort to change).

| # | Area | Report | Headline findings |
|---|---|---|---|
| 1 | Playback (player engine, desktop audio, sleep timer, media controls, cast, car) | [01-playback.md](01-playback.md) | Stop or sign-out during a load lets the old load start playing. Cast podcast episodes use the show's progress key. Equalizer and Cast do nothing on desktop. The Android Auto list refreshes from the server on desktop. No cover art in the Windows media popup. |
| 2 | Server, sign-in and sync | [02-server-sync.md](02-server-sync.md) | A scheduled retry can send progress with the old account after a switch. 401/403/429 replies drop queued positions. A fallback can count listening time many times over. Settings sync retries a rejected password every 45 s. Two token/cookie log leaks. |
| 3 | Downloads and other services | [03-downloads-other-services.md](03-downloads-other-services.md) | Downloads and logs go into Documents (OneDrive). Logs are on by default and capture the sign-in cookie and code. Quitting mid-download hangs the next start. Short BookOrbit ids crash folder naming. Transcription and clip export offered on desktop where they can't work. |
| 4 | App core (startup, app shell, library and auth state, utils, looks) | [04-app-core.md](04-app-core.md) | Offline covers on Windows fail: paths are checked with `startsWith('/')`, about 30 places. Switching accounts keeps the old account's look. Startup can hang on a corrupt prefs file. The old account keeps running after a switch. |
| 5 | Main screens (Home, Library, Absorbing, Settings, Stats) | [05-main-screens.md](05-main-screens.md) | The Windows Settings section was unreachable (being fixed). Bug-report, contact and Discord links go to upstream's developer. Settings and Stats rebuild far more than needed. Stats can't be refreshed with a mouse. |
| 6 | Other screens (admin, sign-in, readers, editors) | [06-other-screens.md](06-other-screens.md) | ReadMeABook browser and Audible reviews crash on Windows/web (Android-only webview). Transcription settings spin forever on web. Backup and export fail on web. Chapter-editor preview race. |
| 7 | Player and book widgets | [07-player-book-widgets.md](07-player-book-widgets.md) | The Absorb button can stay stuck when offline. The animated tab icon redrew at full frame rate (fixed). Player cards repaint 10× a second. Blur keeps ~6 MB per cover. |
| 8 | Readers and remaining widgets | [08-readers-other-widgets.md](08-readers-other-widgets.md) | Read buttons show where readers can't work (web, Linux). No keyboard page turning in any reader. The MOBI reader's local server is readable by any website. "Updated from match" is shown even when it failed. |
| 9 | Native code, vendored packages, dependencies, tests, CI, tools, docs | [09-native-packages-tests-ci.md](09-native-packages-tests-ci.md) | 120 MB stray debug file in the beta folder (fixed). Broken local APK paths (fixed). Docs claim a tray that doesn't exist. Unused dev dependencies. Playback, sleep timer and sync logic have almost no tests. |

Already fixed during the audit: the 120 MB stray file, the `apk -Local` paths, the tab icon's frame rate, and the web `Platform` crashes (separate commit).

## Cleanup plan

Ranked by value for the effort and merge cost. Items marked **(engine)** touch playback, downloads or sync internals: under the release rules they ship only after the owner tries a Windows test build.

### Batch A: safe fixes (small, low risk, no decisions needed)

**Sync and accounts**
- Progress counts as saved only on a 2xx reply, so 401/403/429 keep it queued (02 #1).
- Settings sync backs off on errors and pauses after a rejected password (02 #2).
- Account switch:
  - a retry can't use the old account (02 #3);
  - the old account's poll, socket and local probe stop (04 #1);
  - its shelf caches are cleared (04 #5);
  - the new account's look is applied (04 #2).
- Startup always restores the session even if an early step throws (04 #3).
- Backups without accounts no longer export the ReadMeABook token and custom headers (03 #6).

**Privacy**
- The sign-in cookie, callback code, token prefix and `Bearer` values are kept out of the log (02 #4, 03 #2, 02 #12).
- The MOBI reader's local server gets a token like the EPUB one (08 #6).

**Desktop and web correctness**
- ReadMeABook and Audible reviews open in the browser off Android (06 #1, 09 #7).
- Readers are offered only where they work (08 #1).
- Transcription, clip export, the Android Auto refresh and home-widget stats are skipped off Android (03 #4, #5, 01 #3, 06 #2).
- Cast is hidden off Android (01 #2). The equalizer gets a real Windows version instead (owner decision).
- Offline covers work with Windows paths, through one helper used where covers are shown offline (04 #4, 06 #6).

**UI and performance**
- The Absorb button no longer stays stuck (07 #1).
- Blur frees its full-size cover (07 #4).
- Progress bars repaint only themselves (07 #3).
- Cards rebuild only for their own download (03 #8).
- Settings and the app shell rebuild on what they show (05 #3, 04 #6).
- Stats refreshes when its tab opens (05 #5).

**Small bugs**
- Cast podcast progress key (01 #4).
- Player recovery flag (01 #5).
- Playback-event listener leak (01 #7).
- Chime volume restore (01 #9).
- "Updated from match" only on success (08 #2).
- Reader progress saved when the window is hidden (08 #3).
- BookOrbit short-id crash (03 #3).
- Chapter preview race (06 #4).

### Batch B: engine fixes (owner tests a Windows build before release)

- Stop or sign-out during a load cancels it (01 #1).
- Auto-advance into the next item keeps the right state (01 #10).
- Transcode retry uses the normal start path (01 #11).
- Listening time isn't counted many times by the legacy fallback (02 #5).
- Interrupted desktop downloads resume or fail at once instead of hanging the next start (03 #7).
- The download check deletes only files that are definitely missing (03 #9).

### Batch C: tooling, docs, tests (no app behavior change)

- Correct the stale docs: tray, `jni`, bump, README looks, COMPATIBILITY, ARCHITECTURE, ROADMAP (09 #3, 04 #11).
- CI builds the Android APK only on request and skips doc-only pushes (09 #5). Releases are created as drafts and published after all builds (09 #10).
- Verify scripts stop overwriting the Release build (09 #8). The `.deb` declares its dependencies (09 #9). Align the Flutter version (09 #11).
- Tests for `sync_logic`, the playback policies and the sleep timer (09 #6, #13, 01 #8). Integration tests run on request in CI (09 #12).
- Dead fork code:
  - unused strings and `runCritical` (04 #8);
  - a duplicate byte formatter and two unused Libation helpers (03 #13);
  - unused dev dependencies (09 #14);
  - the Siri files, replaced by a stub like CarPlay (03 #10).

### Owner decisions (2026-10-30)

- Batches A and C approved; Batch B waits for the owner's test of a Windows build.
- Support links: "Report a bug" and "Contact" go to the Absorb Plus GitHub issues, Discord is hidden, and "Send logs" saves a file.
- Logging stays on by default in betas, with secrets masked.
- App link scheme stays `absorb://` for now.

### Still open

1. **Where support links go.** "Report a bug", "Contact", "Discord" and "Send logs" point at the original Absorb developer. Options: the fork's GitHub issues, an address of the owner's, or hidden.
2. **Logging in betas.** Logs are on by default in every Absorb Plus build. After the privacy fixes above, keep them on, or off by default?
3. **App link scheme.** Absorb Plus shares `absorb://` links with the original Absorb, so sign-in can open the wrong app when both are installed. A fork scheme (`absorbplus://`) fixes that but changes the OIDC redirect address server admins must allow.
4. **Settings width on desktop.** Settings and Stats stretch across the whole window. A max width would look better on wide screens but changes the layout.
5. **Token storage** (pending since the start): move saved tokens to the OS's secure storage.
6. **Upstream reports.** The original Absorb has most of the bugs in Batches A and B. Send fixes upstream after the owner has tested them?

### Deliberately not doing

- Splitting the giant upstream files (`ebook_reader_view.dart`, `edit_metadata_sheet.dart`, `audio_player_service.dart`).
- Merging upstream's duplicated helpers, readers or admin code.
- Deleting iOS or Siri engine code inside upstream files.

All of these add merge conflicts for little user value. The rule from CLAUDE.md stands: change upstream files only when the gain beats the merge cost.
