# Audit 09: native code, vendored packages, dependencies, tests, tooling, CI, docs

Read-only audit, 2026-10-30, branch `claude/slim` at `61554b8c` (201 commits ahead of `origin/main` `2940f1f4`, 0 behind).
Ownership checked with `git cat-file -e origin/main:<path>`. "Fork" means upstream doesn't have the path, so it can change freely. "Upstream" means every edit costs merge effort.

Work in progress by other agents, not audited as finished code:
- untracked `lib/services/windows_shell.dart` (still a placeholder);
- `tool/windows_shell_probe.dart` and `tool/verify-windows-shell.ps1`;
- `lib/widgets/text_scale_room.dart` and `test/ui_overflow_sweep_test.dart`.

---

# PART 1: MAP

## 1. Native platforms

| Area | Owner | What's there | Traps |
|---|---|---|---|
| `windows/` (19 files) | **fork** (upstream has no `windows/`) | Standard Flutter runner. `main.cpp` titles the window "Absorb Plus" and calls `SetQuitOnClose(true)`, then on exit `window.Destroy()` and `CoUninitialize()`. `cmake/webview_shutdown.cmake` is a build-time overlay patch of `flutter_inappwebview_windows` 0.6.0's `in_app_webview_manager.cpp`: it releases Composition resources at plugin teardown, is SHA256-pinned, and fails with FATAL_ERROR when the source changes. `Runner.rc` holds the version from pubspec. | The hash pin makes any `flutter_inappwebview_windows` bump fail the Windows build until someone reviews it. That's intended, but it surfaces first in `release.yml`, because CI never builds Windows. No single-instance guard: a second launch opens a second process on the same prefs. `Runner.rc` says `CompanyName "com.barnabas"` and `"Copyright (C) 2026 com.barnabas. All rights reserved."`, which is wrong for a GPL fork. |
| `windows/flutter/generated_*` | fork | Generated plugin registrant and list | The committed list has `jni` in `FLUTTER_FFI_PLUGIN_LIST`, but **`pubspec.lock` has no `jni` package** (and neither do `origin/main`, `e6a4bfa6` or `6c7e67d1`). The files are stale; it isn't this machine's Flutter dropping it (finding D2). |
| `linux/` (10 files) | **fork** | GTK runner, title "Absorb Plus", `APPLICATION_ID "com.barnabas.absorb"` | The `.deb` desktop entry made in `release.yml` has no `StartupWMClass` and the control file has no `Depends:` (finding N3). |
| `web/` (7 files) | **fork** | `index.html` (`$FLUTTER_BASE_HREF`), PWA manifest, icons | Pages builds use `--base-href /absorb-plus/`; the release web ZIP uses `/`. Both are intended. |
| `android/` (233 files) | **upstream** | Fork changes: `applicationId = "com.barnabas.absorb.plus"` plus the icon PNGs (listed in `tool/fork-overrides.txt`). Flavors github, playstore, dev, fdroid. GMS Kotlin under `src/gms`. Whisper compat lib via `:whisper_ggml_plus_compat`. | Gradle wrapper 8.14 and AGP 8.11.1: Flutter already warns that support "will soon be dropped", so 9.1+ is needed (`build/dev-logs/apk-warmup.log`). `android/build/reports/problems/problems-report.html` (148 KB) is a tracked build artifact, but upstream tracks it too. `resValue app_name "Absorb"` means the fork shows up as "Absorb" next to the official app. Shared `absorb://` schemes (finding N4). |
| `installer/Absorb.iss` | fork | Inno Setup: AppId, `PrivilegesRequired=lowest`, `CloseApplications=yes` | Fine. |

## 2. Vendored packages (`packages/`, 687 tracked files)

| Package | Owner | Tracked size | Why it's vendored | Unused parts |
|---|---|---|---|---|
| `audio_service` 0.18.18 | upstream | 735 KB | Upstream's Android patches: Android Auto and Bluetooth pause fix, rebuilding the player after a long pause. There's no PATCHES.md; the reasons are only in git log. | `example/` (351 KB) and `darwin/` (28 KB); pubspec still declares ios/macos |
| `audio_service_win` 0.0.3 | **fork** | 27 KB | `PATCHES.md`: SMTC cleanup while COM is alive, events forwarded on the platform thread, artwork null fix | none |
| `flutter_chrome_cast` 1.4.1 | upstream | 459 KB | Vendored without iOS (Cast SDK wants iOS 16) | Its barrel pulls in `get` and `marquee` (used only by its bundled widgets) |
| `flutter_epub_viewer` 1.2.8 | upstream | 2.1 MB | Streams the book in chunks (upstream ran out of memory on a 322 MB epub), plus reader features | pubspec declares ios |
| `just_audio` 0.9.46 | upstream | 425 KB | Android loudness boost and rebuild fixes | `darwin/` (114 KB) |
| `whisper_ggml_plus` 1.5.2 | upstream (fork edits: web stubs, CMake, Apple trees removed) | 13 MB | arm64 dotprod/fp16 kernels, `no_fallback`, timing | See below |

whisper_ggml_plus details:
- `macos/Classes` (5.8 MB) stays, because `windows/CMakeLists.txt` compiles the shared ggml sources from it.
- `linux/` ships prebuilt `.so` files (1 MB).
- `assets/models/ggml-silero-v6.2.0.bin` (885 KB) is bundled into **every** platform's assets, but all four transcription call sites pass `vadMode: WhisperVadMode.disabled` (`lib/services/transcription_service.dart:599,691,790,838`).
- Its pubspec depends on `flutter_riverpod`, `freezed_annotation` and `json_annotation`. **`riverpod` isn't imported anywhere** in `packages/whisper_ggml_plus/lib`, so the app resolves Riverpod for nothing.
- Its pubspec still declares ios and macos ffiPlugin.
- On disk only, git-ignored: `android/.cxx` and `android_compat/.cxx` take 215 MB of local CMake caches.

## 3. Dependencies (`pubspec.yaml`)

Imports were counted as files under `lib/` and under `test/`+`tool/`.

The fork **added**:
- `just_audio_media_kit`, `media_kit_libs_windows_audio` and `media_kit_libs_linux`: native libs, so 0 imports is expected;
- `audio_service_win`: federated, 1 test;
- `audio_service_mpris`: federated through dartPluginClass, 0 imports is expected;
- the dev dependency `audio_service_platform_interface`: 1 test.

The fork **removed** `flutter_carplay`. `lib/services/carplay_service.dart` is a no-op stub that keeps upstream's call sites compiling (fork-override).

| Dependency | lib / test+tool | Verdict |
|---|---|---|
| `mocktail` (dev) | 0 / 0 | **Unused.** Upstream has no tests at all, and the fork's tests use hand-written fakes. |
| `change_app_package_name`, `rename_app` (dev) | 0 / 0 | **Unused** one-shot CLIs from upstream's setup |
| `flutter_launcher_icons` (dev) + its pubspec block | 0 / 0 | **A trap.** `tool/make_icons.py` now renders every icon. Running `dart run flutter_launcher_icons` would overwrite the fork's icons with ones made from `app_icon.png`. Same risk with `flutter_native_splash:create` (the package itself is used at runtime in `main.dart:270`). |
| `palette_generator` | 5 / 0 | **Discontinued** on pub (`flutter-pub-get.log`: "1 package is discontinued") |
| `webview_flutter` | 2 / 0 | Only Android and iOS implementations are in the lock (`webview_flutter_android`, `_wkwebview`). It's used ungated on desktop and web (finding N1). It duplicates `flutter_inappwebview`, which has a Windows implementation. |
| `flutter_inappwebview` | 2 / 1 | No Linux implementation in the lock (android, ios, macos, web, windows only), so the foliate and epub readers on Linux probably can't work. Not traced; verify. |
| `in_app_review` | 1 / 0 | `isAvailable()` is false for sideloaded and desktop installs, so it's harmless. Dead weight for a fork that never ships to Play. |
| `workmanager`, `home_widget`, `quick_actions`, `vibration`, `sensors_plus`, `open_filex`, `flutter_local_notifications`, `background_downloader`, `flutter_chrome_cast` | 1–4 | Mobile-only. They compile **no** native code into Windows: the committed Windows plugin list is app_links, audio_service_win, connectivity_plus, desktop_webview_window, flutter_inappwebview_windows, media_kit_libs_windows_audio, permission_handler_windows, share_plus, url_launcher_windows and window_to_front. Only the Dart side ships. Not worth removing (upstream-owned). |
| `intl: any` | 22 | Unpinned (upstream) |
| `NotoSansJP` font (assets) | — | 4.4 MB in every build, used only for the Japanese CJK fallback (`main.dart:389`). Upstream. |

All the other dependencies are used. pub reports "133 packages have newer versions incompatible with dependency constraints".

## 4. Tests (`test/`, all fork-owned: upstream has no `test/`)

- 47 unit and widget files plus 4 integration files, about 10,000 lines.
- A local run is **fast**: 326 pass, 4 skipped, in about 12 s (`build/dev-logs/flutter-test-expanded.log`). The skips are 3 integration suites and the `IMPORT_SCREENSHOTS` screenshot test.
- No goldens.
- Real `HttpServer` loopback is used in `media_upload_api_test` (4), `admin_upload_screen_test` (2), `update_checker_service_test` and `absorb_plus_logo_test`. It's fine, but it's the most timing-sensitive part of the suite.

| Feature | Tests | Gap |
|---|---|---|
| UI looks (Standard, Frosted, Midnight, Try it) | ui_theme_* (4 files, about 2,800 lines) | Well covered, arguably over-weighted |
| Libation and admin upload | admin_upload_screen, media_upload_api, integration/upload | Good |
| Updates and What's new | update_*, whats_new_* (8 files) | Good |
| Downloads | download_info, path_names, recovery, telemetry, track_names, queue_download_policy | Policy and naming are covered; the transfer engine isn't |
| Progress sync | progress_sync_transport, local_session_flush, offline_listening_flush | **`lib/services/sync_logic.dart` (89 lines, pure, and its header says "Extracted so the math can be unit-tested") has no test** |
| Auth and token refresh | api_service_test (401 and 503 rotation), integration/auth_library | No unit tests for `AuthProvider` multi-account or sign-out |
| Playback (`audio_player_service.dart`, about 7,000 lines; libmpv backend) | none. `tool/verify-desktop-audio.ps1` is a manual smoke test only | **Highest risk** |
| Sleep timer (948 lines), socket service (691), session_cache (109), library_cache (57), server_health (106), transcription, BookOrbit, read-along | none | |
| Android Kotlin | `android/app/src/test/.../CoverRefreshTokensTest.kt` | Never run by CI (no Gradle `test` task) |
| Integration (`test/integration`, tag `abs-server`) | real ApiService against Docker ABS 2.37.2 | Local only (`dev.ps1 itest`), never in CI |

## 5. `tool/` (fork-owned)

| Script | Purpose | State |
|---|---|---|
| `dev.ps1` (373 lines) | check, build, beta-sync, apk (CI or `-Local`), bump, footprint, merge, server, itest | **The `apk -Local` path is corrupted** (finding T1). Log naming is odd: `test --reporter expanded` logs to `flutter-test-expanded.log`, because non-dash words are taken as the name. The "tray" comments are wrong (finding D1). |
| `claude_hooks.py` (584) + tests | session-start, pre-shell (push to upstream, reset --hard, junction deletes, dart format, gh release, tags), pre-edit, post-edit (gen-l10n), stop | Correct; tested |
| `upstream_merge.py` + tests, `check_fork_removed.py`, `fork-removed-paths.txt`, `fork-overrides.txt` | Merge rules | OK. `check_fork_removed.py` has no unit test (trivial). |
| `align_with_upstream.py` | Undo formatting churn | OK; no tests |
| `fork_lints.py` + tests | `use_build_context_synchronously` on fork-only files | OK; costs one extra analyzer run in CI and check |
| `make_icons.py` | Every icon, via headless Edge | OK |
| `measure-windows-usage.ps1` | Read-only process counters | OK |
| `verify-desktop-audio.ps1` + `desktop_audio_smoke.dart` | libmpv smoke test | **Overwrites the owner's Release folder, then rebuilds it without `--dart-define=GITHUB_BUILD=true`** (finding T2) |
| `verify-windows-shell.ps1` + `windows_shell_probe.dart` (untracked, new) | Exit-time probe | Also targets `build\windows\x64\runner\Release\absorb.exe` (same risk as T2). The Release folder is **holding a probe build right now**: `data\app.so` is 6.2 MB at 17:40, against 25 MB in the beta copy. |
| `android-signing-setup.ps1`, `ci/verify_apk_signature.py`, `ci/patch_webview_linux.py` | Signing and CI helpers | OK. The Linux patch handles 3 states and fails on an unknown 4th. |
| `test-server/` (compose + seed.py) | Throwaway ABS on 127.0.0.1:13378 | OK |
| `scripts/` (build-github-apks, crowdin-merge.py, gen_speed_badges.js) | **upstream** | Only `build-github-apks` is used (release.yml) |

## 6. CI (`.github/workflows`, fork-owned)

- `_checks.yml`: pub get, analyze `--no-fatal-infos`, flutter test, tool tests, removed-paths, fork lints. ubuntu, Flutter from `.flutter-version` (**3.47.0**; the local SDK is **3.47.3**).
- `ci.yml`:
  - Checks run on every push to any branch and on every PR, so a PR branch runs twice.
  - On `main` pushes, PRs and dispatch: web, Linux and Pages.
  - Android (signed arm64) runs on **every main push** and on dispatch, in parallel with checks. It has Gradle, NDK and ccache caches.
- `release.yml`, on `v*` tags:
  - `prepare` creates the GitHub release **before** checks run;
  - then come checks, Windows (Inno Setup plus ZIP), Linux (tar and deb), web ZIP and Android (universal and split, through upstream's script);
  - the Android release job has no ccache and runs `build-github-apks` without `--no-pub`.

## 7. Docs and agent config

| Doc | Owner | State |
|---|---|---|
| `README.md` | fork (override) | "Choose your look" names **Absorb Plus / Classic / Frosted**. Today's looks are **Standard / Frosted / Midnight**; Classic was retired into "Look details" switches (see ARCHITECTURE.md). |
| `docs/ARCHITECTURE.md` | fork | dev.ps1 row lists `check, build, bump, footprint, server, itest`; it's missing `beta-sync`, `apk` and `merge`. The skills row is missing `/upstream-merge`. The Playback row lists `carplay_service.dart` as if it were real (it's a no-op stub). |
| `docs/COMPATIBILITY.md` | fork | Says the "all-platform release workflow also publishes … **SHA-256 checksums**". In fact no checksums are published (owner rule), `all-release.yml` was removed, and CI builds only web and Linux, not "desktop builds". The verification commands miss `--no-fatal-infos`. |
| `docs/ABSORB-PLUS-ROADMAP.md` | fork | "manually dispatched Inno Setup installer artifact": `release.yml` builds it on every tag now. Largely superseded by CLAUDE.md and memory. |
| `docs/DESKTOP-AUDIO-VERIFICATION.md` | fork | Dated 2026-10-01 ("16 tests passed"); historical |
| `AGENTS.md` | fork | `dev.ps1 bump  # next build number + beta number`: **wrong**. bump keeps `kBetaNumber`; only `-NextBeta` or `-Beta N` changes it. |
| `CLAUDE.md` | fork | Tray claim (D1), jni hazard (D2), and a corrupted `tool\a…` at line 67 (T1) |
| `.claude/skills/build-verify` | fork | Says `bump  # pubspec build +1 and kBetaNumber +1` (wrong). Says "The owner runs …\Release\absorb.exe" when the owner now tests from `Desktop\Absorb Plus Beta\Windows`. Says to ask before `-CloseRunning`, when CLAUDE.md gives a standing OK (2026-10-30). Contradicts CLAUDE.md three times. |
| `.claude/skills/release`, `status`, `upstream-merge`, agents | fork | Consistent with CLAUDE.md |

---

# PART 2: FINDINGS

Confidence: **H** = verified directly, **M** = strong evidence but not executed, **L** = plausible, needs checking.

## Build output and size

**S1. A stale 120 MB `kernel_blob.bin` ships in the owner's Release and beta folders. (H)**
- What's there: `build/flutter_assets/kernel_blob.bin` is 125,875,248 bytes, dated 10-29 20:25, which matches `build/dev-logs/debug-build.log`. Identical copies sit in `build\windows\x64\runner\Release\data\flutter_assets\` and in `Desktop\Absorb Plus Beta\Windows\data\flutter_assets\`.
- Why it keeps coming back: a debug build left it in `build/flutter_assets`. Release builds don't delete it, and the runner's install step copies that whole directory. `Update-BetaFolder` uses `robocopy /E`, which never deletes anything, so the file would stay in the beta folder even after a clean build.
- Effect: AOT release builds never use it (they run `app.so`), so it's 120 of the beta folder's 206 MB (about 60%), and 129 MB of `flutter_assets`.
- Not affected: CI releases build from a clean checkout.
- Fix: delete it in all three places, and have `dev.ps1 build` remove `build\flutter_assets\kernel_blob.bin` before building and `data\flutter_assets\kernel_blob.bin` from the beta copy.

**S2. The whisper VAD model is bundled but never used. (H)**
- 885 KB in every platform build, web included, while all call sites disable VAD.
- Removing the `assets:` line from the vendored whisper pubspec is a one-line edit to an upstream-owned file.
- Low value; do it only alongside a whisper change.

**S3. `flutter_riverpod` is a dead transitive dependency through whisper_ggml_plus. (H)**
- No imports in whisper's lib. It only costs resolution and pub time (tree-shaken out of the binary).
- Upstream-owned; low value.

**S4. Dead weight in upstream-owned trees. (H)**
- Package examples and darwin folders: audio_service `example/` 351 KB, plus `darwin/` 28 KB and 114 KB.
- `android/build/reports/problems/problems-report.html` 148 KB.
- Adding these to `fork-removed-paths.txt` is cheap: `upstream_merge.py` re-deletes removed paths automatically. But the savings are repo-only (none of it reaches a build). Low value.

## Unused dependencies

**U1. Unused dev dependencies: `mocktail`, `change_app_package_name`, `rename_app`. (H, 0 imports anywhere)**
- `flutter_launcher_icons` is also unused, and its config is a trap (it would overwrite the fork's icons).
- Every line is upstream-owned, in the `dev_dependencies` block the fork already edits (`audio_service_platform_interface`).
- Gain: a smaller pub resolve. Merge cost: small.

**U2. `palette_generator` is discontinued. (H)**
- Upstream's decision, so leave it alone for now. Flag it if it ever breaks on a Flutter upgrade (the replacement is to compute colors in-house).

**U3. Two webview stacks: `webview_flutter` and `flutter_inappwebview`, plus `desktop_webview_window` transitively through `flutter_web_auth_2`. (H)**
- See N1 for the bug this causes.

## Native and platform bugs

**N1. `webview_flutter` has no Windows, Linux or web implementation, yet two features call it ungated. (H, static)**
- The calls:
  - `book_detail_sheet.dart` `_showAudibleReviews` runs `WebViewController()` (line 2929), reached by tapping the Audible rating or badge whenever an ASIN exists, which is common for Libation imports;
  - `app_shell.dart:1523` and `rmab_config_sheet.dart` open `AdminRmabScreen`, which also uses `WebViewController`.
- The lock contains only `webview_flutter_android` and `webview_flutter_wkwebview`. With no platform instance registered, the controller throws, so on the owner's main platform the tap does nothing and logs an exception (not executed here).
- Fix (fork hook in upstream files, M merge cost): on non-Android, open the URL with `url_launcher` (`LaunchMode.externalApplication`), or port both to `flutter_inappwebview`, which already has the Windows patch.

**N2. Linux probably has no webview at all. (L)**
- `flutter_inappwebview` has no Linux implementation in the lock, and there's no `isLinux` gating near the reader views. The foliate and epub readers likely fail on Linux.
- Linux is CI-only, so nobody would notice. Verify with a grep of the reader entry points before acting.

**N3. The `.deb` package (in `release.yml`, fork) is missing two lines. (H)**
- No `Depends:` line: `dpkg -i` succeeds even without libmpv, GTK or WebKitGTK, and the app then fails to start. README even says libmpv is needed.
- The `.desktop` file has no `StartupWMClass=com.barnabas.absorb`, so GNOME and KDE docks may not match the window to its launcher icon. (M)
- Fix: `Depends: libgtk-3-0, libmpv2 | libmpv1, libwebkit2gtk-4.0-37` and the WMClass line.

**N4. Installing the fork beside upstream Absorb breaks URL routing. (M)**
- The applicationId was changed so the fork installs "beside the official Absorb app" (`build.gradle.kts` comment). But both apps register `absorb://oauth` (the `flutter_web_auth_2` CallbackActivity) and `absorb://setup`. With both installed, OIDC sign-in returns to a chooser or to the wrong app.
- The Wear OS bridge can't pair either, since the Data Layer needs the same applicationId and signing key as the watch app.
- Owner decision. A fork-specific scheme means changing upstream files (manifest, `oidc_service.dart`, `admin_auth_settings_screen.dart`) plus a server-side redirect URI change for users.

**N5. `windows/runner/Runner.rc` copyright and company say "com.barnabas … All rights reserved". (H)**
- Fork file; a 2-line fix.

**N6. No single-instance guard on Windows. (H, by design or not)**
- Two copies share SharedPreferences and the download folders.
- Worth a named-mutex check in `main.cpp` (fork file, S) only if the owner wants it. Coordinate with the agent working on `windows/runner`.

**N7. Gradle 8.14 and AGP 8.11.1 are close to Flutter's support floor. (H, warning in apk-warmup.log)**
- Upstream-owned; wait for upstream's bump, but don't let a Flutter upgrade outrun it.

## Tooling bugs

**T1. `dev.ps1 apk -Local` can never find its APK. (H)**
- Lines 237, 241 and 251 contain control characters (the heredoc backslash hazard): `tool<BEL>ndroid-signing-setup.ps1` and `'build<BEL>pp\outputs<FF>lutter-apk'`. `cat -A` shows `^G` and `^L`.
- So `Get-ChildItem` looks in a nonexistent folder and `-Local` always throws "The build produced no APK", now that the SDK is installed and `-Local` is the documented path.
- `CLAUDE.md` line 67 has the same `^G` in `tool\android-signing-setup.ps1`.
- Fix with the Edit tool: `build\app\outputs\flutter-apk` and `tool\android-signing-setup.ps1`.

**T2. `verify-desktop-audio.ps1` leaves the owner's Release folder in a different build flavor. (H)**
- It builds the smoke target into the owner's Release folder, then "restores" it with `flutter build windows --release -t lib/main.dart`: no `--dart-define=GITHUB_BUILD=true`, so the update checker and GitHub-flavor settings are off in the restored build.
- It also uses bare `flutter`, not `$env:FLUTTER`, and doesn't restore the generated plugin files.
- The same pattern is in the new `verify-windows-shell.ps1`.
- Fix: build probes into a separate output (a worktree, or copy the exe out), or at least reuse `dev.ps1 build`.

**T3. The generated plugin files are permanently dirty. (H)**
- The committed `windows/linux/flutter/generated_plugins.cmake` lists `jni`, which isn't in `pubspec.lock`, so every `pub get` shows 6 modified files. `Restore-Generated` exists only to put the stale version back.
- Fix: commit the regenerated files once. CI regenerates them anyway on `pub get`, and the files are fork-owned. Then `Restore-Generated` and the CLAUDE.md hazard text can be simplified.

**T4. Flutter version drift: `.flutter-version` is 3.47.0 (CI), the local SDK 3.47.3. (H)**
- Pin both to the same version.

**T5. `dev.ps1` log naming. (H, cosmetic)**
- `Invoke-Flutter` names logs from the first two non-dash words, so `test --no-pub --reporter expanded` becomes `flutter-test-expanded.log`. Stale `flutter-test---no-pub.log` and `flutter-analyze---no-pub.log` files from older naming also sit next to the new ones.

## Stale or contradictory docs (with the correct statement)

**D1. Tray. (H)** CLAUDE.md lines 45 and 89, `dev.ps1` lines 153 and 164.
- They say: "Closing Absorb's window only hides it to the tray", "hidden in the tray", "(maybe in the tray)".
- In fact: Absorb has **no tray**. `windows/runner/main.cpp` calls `window.SetQuitOnClose(true)`, and nothing in `lib/` or `windows/runner` mentions a tray or close interception.
- Correct statement: "Closing the window quits Absorb. `-CloseRunning` sends WM_CLOSE (`CloseMainWindow`) and waits up to 15 s for it to exit."
- Recheck if the windows_shell work adds a tray.

**D2. jni. (H)** CLAUDE.md line 87 says "The committed list names `jni`, which this machine's Flutter drops".
- Correct statement: "The committed list is stale: `jni` isn't in pubspec.lock on any branch. Regenerate and commit the files" (T3).

**D3. `bump`. (H)** AGENTS.md and the build-verify skill say "build number + beta number" / "kBetaNumber +1".
- Correct statement: "`bump` = build +1 only. `bump -NextBeta` after publishing."

**D4. build-verify skill. (H)** Says the owner runs `build\…\Release`, and to ask before `-CloseRunning`.
- Correct statement: the owner runs `Desktop\Absorb Plus Beta\Windows`, and `-CloseRunning` has a standing OK (CLAUDE.md, 2026-10-30).

**D5. README looks. (H)** Says Absorb Plus / Classic / Frosted.
- Correct statement: Standard / Frosted / Midnight, plus "Look details" switches (Classic behaviors) and three glass strengths for Frosted.

**D6. COMPATIBILITY.md. (H)** Mentions SHA-256 checksums and the all-platform workflow.
- Correct statement: "release.yml publishes the Windows installer and portable ZIP, Linux tar.gz and .deb, the web ZIP and Android APKs. No checksum files. CI builds web and Linux on main; Windows is built locally and on tags."

**D7. ARCHITECTURE.md. (H)**
- Add `beta-sync`, `apk [-Local]` and `merge` to the dev.ps1 row, and `/upstream-merge` to skills.
- Mark `carplay_service.dart` as a no-op stub.

**D8. ROADMAP. (H)** "manually dispatched Inno Setup installer".
- Correct statement: built on every `v*` tag by `release.yml`. Consider archiving the roadmap; CLAUDE.md and memory carry the plan now.

**D9. `dart_test.yaml` comment. (L)** Says integration suites are neither compiled nor run.
- The test log shows them reported as skipped suites. Low importance; just say "skipped".

## Test gaps, ranked by risk ÷ effort

1. **Playback handler and libmpv backend:** no automated tests. Highest risk, but large effort. Start with the pure parts (queue index math, seek clamping, resume position) through injectable fakes. M–L.
2. **`sync_logic.dart`:** pure, already extracted for testing, zero tests. Backoff schedule, cap and decisions. **S, high value.**
3. **Sleep timer (948 lines):** end-of-chapter, shake extend, auto-sleep windows. Inject the clock. M.
4. **AuthProvider multi-account and sign-out:** prefs isolation through `ScopedPrefs`, token clearing. M.
5. **`session_cache` and `library_cache`:** offline correctness. S.
6. **Integration suites in CI:** run `tool/test-server` as a Docker service on ubuntu in a nightly or dispatch job. That turns the real-API checks (login, refresh, progress, uploads) from "when someone remembers" into a gate. M.
7. **Kotlin unit test:** add `./gradlew testGithubReleaseUnitTest` to the Android CI job (it already has Gradle set up). S.
8. **Flakiness watch:** the loopback `HttpServer` tests are fine today (12 s total). `test/ui_overflow_sweep_test.dart` (untracked) currently gives a dead-code **warning** at line 723. `flutter analyze --no-fatal-infos` still fails on warnings, so CI goes red if it's committed as is.

## CI waste

**C1. Android runs on every `main` push. (H)**
- About 10–15 runner-minutes per push, and every change is pushed.
- Phone APKs are batched and fetched on demand by `dev.ps1 apk` through `workflow_dispatch`, and releases build their own. Restricting the job to `workflow_dispatch` drops the per-push cost with no loss.

**C2. Doc-only and `.claude`-only pushes run the full pipeline. (H)**
- On main that means checks, web, Linux, Android and a Pages redeploy.
- Add `paths-ignore: ['**/*.md', 'docs/**', '.claude/**', 'tool/tests/**']` to the push trigger, or a cheap changes job.

**C3. `push: ['**']` plus `pull_request` means PR branches run checks twice. (H)** Low impact while PRs are rare.

**C4. Linux installs both WebKitGTK 4.0 and 4.1 plus libsoup-3.0-dev. (L)** Only `desktop_webview_window` (4.0 with soup 2.4) is in the Linux plugin list. Try dropping 4.1 and soup3.

**C5. The release Android job builds twice (universal plus split) with no ccache and with a second `pub get`. (H)** This is the slowest release job. Reuse ci.yml's ccache and `--no-pub`.

**C6. `prepare` publishes the release before checks and builds. (H)**
- A failed run leaves a visible, empty pre-release. The updater filters by platform asset (`releaseHasUpdateAsset`), so users aren't offered it, but the release page is wrong.
- Create it as `--draft` and publish (`gh release edit --draft=false`) in a final job that needs all builds.

**C7. Windows is never compiled in CI outside releases. (H)**
- This is acceptable, because the owner's PC builds every change. But the `webview_shutdown.cmake` hash pin or a native break would first fail at tag time.
- Optional: a weekly or dispatch Windows build job.

---

# Recommended actions

Ranked by value ÷ (effort + merge cost). Tags: owner (fork or upstream file), size (S/M/L), risk.

| # | Action | Owner | Size | Risk |
|---|---|---|---|---|
| 1 | Delete the stale `kernel_blob.bin` from `build\flutter_assets`, the Release folder and the beta folder; make `dev.ps1 build` remove it before copying (S1) | fork | S | low |
| 2 | Fix the corrupted `dev.ps1 apk -Local` paths (lines 237/241/251) and CLAUDE.md line 67, using the Edit tool (T1) | fork | S | low |
| 3 | Fix the stale docs D1–D8: tray (CLAUDE.md and dev.ps1 messages), jni, bump in AGENTS.md and build-verify, build-verify owner folder and `-CloseRunning`, README looks, COMPATIBILITY, ARCHITECTURE, ROADMAP | fork | S | none |
| 4 | Commit the regenerated `generated_plugins*` files without `jni`; simplify `Restore-Generated` and the hazard text (T3) | fork | S | low (CI regenerates anyway) |
| 5 | CI: Android job only on `workflow_dispatch`; `paths-ignore` for docs and `.claude` (C1, C2) | fork | S | low |
| 6 | Add `sync_logic` unit tests; then session_cache and library_cache | fork (tests) | S | none |
| 7 | Gate `webview_flutter` uses on non-Android: open Audible reviews and ReadMeABook externally with `url_launcher` on Windows, Linux and web (N1) | fork hook in upstream files | S–M | low |
| 8 | Make `verify-desktop-audio.ps1` and `verify-windows-shell.ps1` stop clobbering the owner's Release build, or at least restore it with `GITHUB_BUILD=true` through `dev.ps1 build` (T2) | fork | S | low |
| 9 | `.deb`: add `Depends:` and `StartupWMClass` (N3); `Runner.rc` copyright (N5) | fork | S | low |
| 10 | Release: create as draft, publish after all builds; ccache and `--no-pub` for Android (C5, C6) | fork | S–M | low (releases are gated) |
| 11 | Align `.flutter-version` and the local SDK (T4) | fork | S | low |
| 12 | Integration tests as a nightly or dispatch CI job with the Docker ABS service; run the Kotlin unit test in the Android job | fork | M | low |
| 13 | Sleep timer and AuthProvider tests with an injected clock and prefs | fork | M | none |
| 14 | Drop the unused dev dependencies (`mocktail`, `change_app_package_name`, `rename_app`) and the `flutter_launcher_icons` block (U1) | upstream pubspec | S | merge: small conflict in the dev_dependencies block |
| 15 | Verify Linux webview and reader behavior (N2); gate or hide reader entry points on Linux if broken | fork hook | M | low |
| 16 | Owner decision: fork-specific URL scheme and app label for side-by-side installs (N4) | upstream files | M | medium (OIDC redirect change for users) |
| 17 | Remove the whisper VAD model asset, the riverpod dependency, and the example and darwin folders (S2–S4) | upstream packages | S | merge cost on each upstream whisper or audio_service update; do it only alongside other changes there |
| 18 | Plan Gradle 9.x / AGP when upstream moves; track `palette_generator`'s replacement (N7, U2) | upstream | M | medium |
