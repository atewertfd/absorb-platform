# Audit 06: other screens (`lib/screens/`)

Read-only audit, 2026-10-30, branch `claude/slim` (working tree had uncommitted edits by other sessions; none in the files below except as noted). Upstream reference: `origin/main` @ 2940f1f4.

**Covered (39 files, ~33,900 lines):** achievements, admin_api_keys, admin_auth_settings, admin_email, admin_libraries, admin_library_edit, admin_missing_items, admin_podcasts, admin_rmab, admin, admin_server_logs, admin_server_settings, admin_sessions, admin_stats, admin_upload, admin_users, app_shell_navigation_policy, auth_sessions, backup_sync, book_edit, book_request_release, book_requests, bookmarks, bookorbit_admin, bookorbit_libraries, bookorbit_set_password, bookorbit_users, car_mode, change_password, chapter_editor, downloads, login, podcast_edit, reading_log, server_health, server_notifications, smart_scope_editor, sync_connection, transcription_settings, upcoming_releases (all `*_screen.dart` except where the name has no suffix).

**Not covered (other auditors):** absorbing, home, library, settings, settings_search_index, stats, app_shell. (`settings_search.dart` does not exist in `lib/screens`.)

**Method:**
- Ownership came from `git cat-file -e origin/main:<path>` plus `git diff origin/main`.
- Reachability came from grepping every public class and `show*` function across `lib/`, `test/` and `tool/`.
- I ran `dart analyze` on a scratch copy of `lib/` with `use_build_context_synchronously` turned on (the repo turns it off) and filtered to these files.
- I also ran scripted scans for undisposed controllers, timers, `setState` after `await`, `dart:io` on web paths, and non-lazy lists.
- Then I read the hot spots by hand.

---

## PART 1: Code map

### Ownership summary

Only one file is fork-owned: `server_health_screen.dart`. Every other file exists upstream. These upstream files carry fork edits:

| File | Fork diff vs upstream | What the fork changed |
|---|---|---|
| `admin_upload_screen.dart` | +690 / −91 | Libation export import, existing-book target, duplicate check, index wait, `canUpload` guard |
| `downloads_screen.dart` | +157 / −3 | Failed-download section with retry/dismiss, bytes/rate/ETA line, semantics |
| `admin_screen.dart` | +2 / −79 | RMAB tile removed (moved to Settings → Advanced); passes `canUpload` |
| `book_requests_screen.dart` | +6 / −1 | Stops the load-more spinner when a refresh replaced the list |
| `backup_sync_screen.dart`, `chapter_editor_screen.dart` | +2 / −1 each | Web-safe `Platform` import; one `mounted` check |
| `login_screen.dart` | +1 | One `mounted` check |

All other files are byte-identical to upstream, so any change there costs merge effort.

### Admin (Audiobookshelf server admin). All upstream, all need `isAdmin`.

| File | Lines | Purpose | Reached from | State / services | Notes and traps |
|---|---|---|---|---|---|
| `admin_screen.dart` | 1175 | Admin hub: server card, library cards with stats/issue counts, scans, task tracker, links to sub-pages | `settings_screen.dart:2096`; `app_shell.dart:1384,1502` (desktop workspace `admin:` ids) | `ServerTaskTracker` (owned unless injected), `SocketService` items listener, 2 s issue debounce, **3 s task poll** (`:153`) | Polls `/api/tasks` every 3 s while mounted, even under pushed sub-pages; it pauses on app lifecycle. Desktop exit guard via `DesktopWorkspaceNavigator`. |
| `admin_users_screen.dart` | 1443 | Users list with online state; user editor (permissions, libraries, tags); setup-file/link export | admin_screen, app_shell | `AuthProvider`, `LibraryProvider`, `BackupService`, `SetupLinkService` | Setup export **creates a server API key** per file (`createApiKey`, ~`:846`), but only on explicit admin action. `urlCtrl` (`:809`) is never disposed. `_saveSetupFile` has no try/catch, and `saveFile` throws on web. |
| `admin_sessions_screen.dart` | 314 | Paged listening sessions | admin_screen, app_shell | ScrollController + load-more | OK |
| `admin_stats_screen.dart` | 264 | Server-wide listening stats | admin_screen, app_shell | | OK |
| `admin_server_settings_screen.dart` | 318 | Server settings toggles | admin_screen, app_shell | | OK |
| `admin_server_logs_screen.dart` | 663 | Live server log stream with level filter and export | admin_screen, app_shell | `SocketService` server-log listener, `ServerLogExportService`; cap 5000 lines | Copies the whole list and rebuilds once per incoming line (`:144`). See P3. |
| `admin_email_screen.dart` | 485 | SMTP settings and e-reader devices | admin_screen, app_shell | | `nameCtrl`/`emailCtrl` in the device editor (`:157`) are never disposed |
| `admin_api_keys_screen.dart` | 416 | List/create/revoke API keys | admin_screen, app_shell | | Context read after a dialog (`:178`), harmless |
| `admin_auth_settings_screen.dart` | 547 | Password/OIDC auth settings (GET/PATCH `/api/auth-settings`) | admin_screen, app_shell | | OK |
| `admin_libraries_screen.dart` | 169 | Library list with delete; opens the editor | admin_screen, app_shell | | |
| `admin_library_edit_screen.dart` | 1558 | Create/edit a library: folders, settings, scan schedule (cron), metadata-file cleanup | admin_libraries_screen | | About 8 hard-coded English strings (upstream) |
| `admin_missing_items_screen.dart` | 358 | Missing/invalid items with delete | admin_screen | `SocketService` items listener | |
| `admin_podcasts_screen.dart` | 2822 | Podcast admin: feeds, episode download/check, settings; also exports `showAddPodcastSheet` and `showPodcastAdminSettings` | admin_screen; `library_screen.dart`; `widgets/episode_list_sheet.dart` | 5 States; `SocketService` item-updated listener; TabController | Largest file in scope; reachable from the library too, not only admin |
| `podcast_edit_screen.dart` | 336 | Podcast metadata and cover edit | admin_podcasts_screen | | The cover picker uses `files.single.path`, which throws on web (`:90-93`) |
| `admin_upload_screen.dart` | 2084 | Upload files to a library folder; **fork: Libation export import** (scan folder, pick book, ASIN duplicate check, import history, launch Libation exe), add to an existing book | admin_screen, app_shell, `settings_screen` (Libation tile); `test/admin_upload_screen_test.dart` | Many injectable seams (picker, scanner, uploader, clock); `LibationImportHistory`, `SharedPreferences` | Biggest fork hotspot inside an upstream file. `_submit` (`:948-1184`) has broken indentation from merges. Desktop-only Libation is gated by `_desktopLibationEnabled` (`:256`). |
| `admin_rmab_screen.dart` | 106 | ReadMeABook site in an in-app **`webview_flutter`** WebView | `app_shell.dart:1523` (nav-hold `rmabWeb`); `widgets/rmab_config_sheet.dart:356` ("Open in browser view", admins only) | `WebViewController` | **No Windows, Linux or web implementation of webview_flutter is in pubspec.lock.** See B1. |

### BookOrbit backend screens. Upstream; used only when the account's backend is BookOrbit.

| File | Lines | Purpose | Reached from | Notes |
|---|---|---|---|---|
| `bookorbit_admin_screen.dart` | 200 | BookOrbit admin hub; exports `showBoAdminError` and `boAdminApi` | `settings_screen.dart:2143` | |
| `bookorbit_users_screen.dart` | 964 | BookOrbit users CRUD and setup links | bookorbit_admin | Several controller listeners → `setState` |
| `bookorbit_libraries_screen.dart` | 888 | BookOrbit libraries, folders, scans | bookorbit_admin | 5 s poll only while a scan runs (`:65-87`), self-cancelling |
| `bookorbit_set_password_screen.dart` | 242 | Forced/new password for BookOrbit sign-in | `login_screen.dart:375`, `widgets/setup_link_login.dart` | |
| `book_requests_screen.dart` | 1447 | Book requests (search, request, admin review); static `open()` | app_shell, library_screen, server_notifications, settings | Fork fix at `:890` |
| `book_request_release_screen.dart` | 612 | Manual release pick for a request | book_requests_screen | |
| `smart_scope_editor_screen.dart` | 984 | Create/edit a BookOrbit Smart Scope (rule tree) | library_screen, `widgets/collection_detail_sheet.dart` | |
| `achievements_screen.dart` | 738 | BookOrbit achievements grid with a detail sheet | settings, server_notifications | `AchievementDetailSheet` is public but only used in this file |
| `server_notifications_screen.dart` | 588 | BookOrbit notification list, settings sheet, and an incoming toast (`showIncomingNotificationToast`) | settings; toast from app_shell | `BookOrbitNotificationSocket` streams, cancelled in dispose |
| `reading_log_screen.dart` | 1312 | Per-book reading sessions, chart, records (BookOrbit API) | `widgets/book_detail_sheet.dart:431` (only when `isBookOrbit`) | Paged; the top-level ListView is not lazy, but its content is bounded |

### Account, sign-in and server

| File | Lines | Owner | Purpose | Reached from | Notes |
|---|---|---|---|---|---|
| `login_screen.dart` | 1617 | upstream (+1) | Sign-in: ABS and BookOrbit, password, API key, magic link, OIDC, custom headers, saved-account quick switch, restore from backup | `main.dart`, settings (add account), `widgets/sign_in_again.dart` | Debounced server ping with stale-result guard. Restore path: see B4 and W1. No credential logging found. |
| `auth_sessions_screen.dart` | 291 | upstream | Saved accounts and sessions | settings | `AuthSessionTile` is public but used only here |
| `change_password_screen.dart` | 163 | upstream | Change the ABS password | settings | |
| `server_health_screen.dart` | 167 | **fork** | Read-only health check: ping, version, `getMe`, libraries | `settings_screen.dart` ("Issues and support") | **All strings are hard-coded English**, and the title says "Audiobookshelf compatibility" even on BookOrbit. Has no try/catch, but the service catches internally. |

### Backup and settings sync

| File | Lines | Purpose | Reached from | Notes |
|---|---|---|---|---|
| `backup_sync_screen.dart` | 621 | Export/import `.absorb` backups and the settings-sync status | `settings_screen.dart:4927` | Uses `File`/`path` and `saveFile`, so it is broken on web (W1). Restore applies appearance piece by piece (B4). |
| `sync_connection_screen.dart` | 240 | WebDAV-style sync connection form with a test | backup_sync_screen | Password field is obscured; controllers are disposed |

### Playback and content

| File | Lines | Owner | Purpose | Reached from | Notes |
|---|---|---|---|---|---|
| `downloads_screen.dart` | 988 | upstream (+157) | Active, queued, failed, completed downloads and kept ebooks; multi-select delete | app_shell, settings, `services/quick_actions_service.dart` | Non-lazy `ListView` of every download (`:417`). `existsSync()` in cover builds. `context.watch` on the outer context inside a `ListenableBuilder` (`:376`). Fork strings are not localized (L1). |
| `bookmarks_screen.dart` | 1545 | upstream | All bookmarks and ebook highlights across books; search, sort, multi-select | app_shell, settings, quick_actions | Covers use `startsWith('/')` (B3) |
| `car_mode_screen.dart` | 621 | upstream | Big-button driving UI | `widgets/card_buttons.dart:2314` (card button `car`); **offered on every platform, including Windows and web** | 1 s whole-screen `setState` tick while playing, plus a `setState` on every player notify. Local cover detection is POSIX-only (B3). Restores the orientation lock in dispose. |
| `chapter_editor_screen.dart` | 2043 | upstream (+2) | Chapter editor with audio preview, cut scrubbing, start-finder, numbering | `ChapterEditBody` via `widgets/edit_metadata_sheet.dart` | **`ChapterEditorScreen` (`:39`) is never referenced, upstream included.** Preview race (B2). |
| `book_edit_screen.dart` | 69 | upstream | Wrapper hosting the metadata editor | `widgets/book_detail_sheet.dart`, `widgets/edit_metadata_sheet.dart` | |
| `upcoming_releases_screen.dart` | 2213 | upstream | Audible series scan for upcoming and missing books; removed/skipped sheets; RMAB request | app_shell, library_screen, `services/episode_notification_service.dart` | Service listener removed in all 3 States. Leaves a `debugPrint('[RMAB] ...')` per open (`:66`). |
| `transcription_settings_screen.dart` | 483 | upstream | Whisper model download/delete, read-along options | Settings → Advanced (`settings_screen.dart:4866-4872`), **not gated on web** | Infinite spinner on web (B5) |

### Navigation helper

| File | Lines | Owner | Purpose |
|---|---|---|---|
| `app_shell_navigation_policy.dart` | 11 | upstream | Pure `shouldRestoreBookLibrary()` used by app_shell. No test. |

### Cross-cutting observations

- **Tests:** only `admin_upload_screen.dart` has widget tests. `test/web_safe_platform_test.dart` lists `backup_sync` and `chapter_editor`. The untracked `test/ui_overflow_sweep_test.dart` covers none of these 39 files.
- **Apple remnants:** only harmless `Platform.isMacOS` / `isIOS` checks remain (`admin_upload:258`, `backup_sync:220`, `chapter_editor:1371`). Nothing is Apple-only in this area, so there is nothing to delete.
- **Dead code:**
  - `ChapterEditorScreen` is unreferenced in the fork and in upstream.
  - `AchievementDetailSheet` and `AuthSessionTile` are public but used only in their own files.
  - All three live in upstream files, so removing them costs merges for no gain. **Leave them.**
- **No screen in this area is unreachable.** `admin_rmab_screen` lost its admin-hub entry (fork removed it) but is still reached from the nav-hold menu and the RMAB config sheet.

---

## PART 2: Findings

Each finding has a severity (High / Med / Low) and a confidence (H / M / L). Every one was checked against `git log`; none of them is already fixed.

### Bugs

**B1. RMAB "browser view" crashes on Windows, Linux and web.** Severity High (Windows is the main platform). Confidence H.
- **Where:** `admin_rmab_screen.dart:22` calls `WebViewController()`.
- **Why it fails:** `pubspec.lock` has `webview_flutter_android` and `webview_flutter_wkwebview` only. There is no Windows, Linux or web implementation, so `WebViewPlatform.instance` is null. The constructor then asserts "A platform implementation for `webview_flutter` has not been set" in debug, or hits a null-check error in release. The route renders an error screen.
- **Trigger:**
  - An admin taps "Open in browser view" in the RMAB sheet (`widgets/rmab_config_sheet.dart:759` → `:339-357`; on desktop it first pops to root).
  - Or any user sets the nav-hold action `rmabWeb` (`widgets/nav_hold_options.dart:37`, `app_shell.dart:1453,1511-1524`). Neither path checks the platform.
- **Same defect elsewhere (other auditor's file):** `widgets/book_detail_sheet.dart:2929` (Audible reviews WebView).
- **Minimal fix (fork-side, small):** on any platform other than Android, open the URL with `url_launcher` in the external browser instead of pushing the screen. Put a guard at the top of `AdminRmabScreen`, or add a `openRmabSite(context, url)` helper that both callers use. `flutter_inappwebview` (already a dependency, with a Windows implementation) is the alternative if an in-app view on Windows matters. Merge cost: about 5 lines in an upstream file, or zero if the helper sits in a fork file and only the two call sites change.

**B2. Race in the chapter-editor audio preview: a quick second tap kills the new preview.** Severity Med. Confidence M-H.
- **Where:** `chapter_editor_screen.dart:492-556` and `_stopPreview` at `:558-578`.
- **What happens:**
  1. Call A creates player A and awaits `setAudioSource`.
  2. Call B (another chapter's play, or a double tap) runs `_stopPreview()`, which disposes A, then creates player B.
  3. A resumes: `seek` or `play` on the disposed player throws, and A's `catch` calls `_stopPreview()`. That now stops and disposes **B** and shows "Could not play preview".
- **Minimal fix:** in the catch, and after each await in the try, bail out when `!identical(_preview, player)`. Stop only your own player. About 4 lines in an upstream file.

**B3. Local covers are never recognised on Windows (`startsWith('/')`).** Severity Med (offline and downloaded books on Windows). Confidence H on the logic, M on how often users hit it.
- **Where:**
  - `car_mode_screen.dart:152-155,361-370`;
  - `bookmarks_screen.dart:1198`;
  - `downloads_screen.dart:806,959` (fallback only: `localCoverPath` is tried first, so downloads mostly work);
  - 39 sites repo-wide, for example `widgets/absorbing_card.dart:186,502,617`.
- **Why:** when offline, `LibraryProvider.getCoverUrl()` returns `dl.localCoverPath` (`providers/_lp_state.dart:407-411`), which on Windows is `C:\...`. These checks then treat it as a URL, so `CachedNetworkImage` fails and the placeholder shows. No drive-letter-aware helper exists (I grepped for `isAbsolute` and `[A-Za-z]:`).
- **Fix:** add a fork util `isLocalFilePath(String)` (`/` prefix, `^[A-Za-z]:[\\/]`, or `\\\\` UNC; never true on web) and swap it in at the sites that matter. Coordinate with the widgets auditor, since most sites are in `lib/widgets`. Each site is a 1-line change to an upstream file.

**B4. Restoring from the login screen doesn't apply the restored look. The backup screen applies only part of it.** Severity Low-Med. Confidence M.
- `login_screen.dart:1246` calls `BackupService.importSettings(data)` and never pushes appearance into the theme notifiers. Theme mode, colours and gradient stay stale until restart.
- `backup_sync_screen.dart:319-327` hand-applies 6 settings plus the orientation lock. `main.dart:222` `applyAppearanceFromPrefs()` exists for exactly this case (its comment says "a settings-sync pull or a restore"), and `settings_sync_service.dart:517` already uses it.
- **Fix:** call `applyAppearanceFromPrefs()` in both places, replacing the piecemeal block. That's 1–7 lines per upstream file.
- **Related (services auditor):** `services/backup_service.dart` exports neither the fork look (`fork_ui_theme`, `fork_ui_glass`, look details) nor e-ink mode, so a restore cannot bring them back.

**B5. Transcription settings spin forever on web.** Severity Med (web). Confidence H.
- **Where:** `transcription_settings_screen.dart:46-58`.
- **Why:** `_load()` awaits `TranscriptionService.isModelDownloaded()`. That calls `_modelFile()`, which builds `File('$dir${Platform.pathSeparator}...')` (`services/transcription_service.dart:248-256`) with bare `dart:io`. On web, `Platform.pathSeparator` and `File` throw, so `_loaded` never becomes true and the body stays a spinner (`:145`). The tile is shown on web (`settings_screen.dart:4866-4872`; the Advanced section has no web gate).
- **Fix:** either hide the tile on web (`if (!kIsWeb)`, in settings_screen, another auditor's file), or make `isModelDownloaded` return false when `kIsWeb` and wrap `_load` in try/finally. Merge cost: 1–3 lines.

**W1. Backup, restore and setup-file save don't work on web.** Severity Med (web). Confidence H. The cause is file_picker 8.3.7:
- `FilePicker.saveFile` is unimplemented on web; it throws `UnimplementedError` (file_picker `lib/src/file_picker.dart:198`).
- `PlatformFile.path` throws on web (`platform_file.dart:42`).

Where it breaks:
- `backup_sync_screen.dart:211` (export) shows "Backup failed: UnimplementedError".
- `backup_sync_screen.dart:244` (restore) shows "Restore failed: …path is unavailable…".
- `login_screen.dart:1199` (the "Restore from backup" chip is visible on web) shows a raw error.
- `admin_users_screen.dart:908` (setup file save) has no catch, so the exception goes unhandled and the user sees nothing.
- `podcast_edit_screen.dart:91` (cover pick) is unhandled.

**Fix:** pick with `withData: true` and decode `files.single.bytes` on web. Hide "save file" on web, or add a tiny fork `web_download.dart` (Blob + anchor via `package:web`). The share and clipboard alternatives already exist for setup links. Merge cost: small per upstream file; it should be one shared fork helper.

### Localization and wording (fork code)

**L1. Fork strings are not in the `.arb` files.** Severity Low. Confidence H.
- `server_health_screen.dart` has every string hard-coded: about 20 literals, including the settings tile text in `settings_screen.dart`.
- `downloads_screen.dart:26-40,903-908` hard-codes "min left", "hr left", "Download progress for", "percent complete", "of".
- The semantics value says "*N min left* remaining", so the word is doubled (`:908`).
- AGENTS.md requires these strings in `app_en.arb`. Both files are fork-owned lines, so there is no merge cost.

### Performance

**P1. The downloads screen rebuilds everything, eagerly.** Severity Low-Med. Confidence M.
- `ListView(children: [...])` (`:417`) builds every download card at once. Each cover build does a synchronous `File.existsSync()` (`:797,808,961`).
- The whole list rebuilds on every `DownloadService` notify, and `context.watch<LibraryProvider>()` uses the State's context inside the builder (`:376`), so every `LibraryProvider` change rebuilds the whole screen as well.
- With hundreds of downloads on Android this costs frame time. Moving to `ListView.builder` / slivers and using `ctx` in the builder fixes it. The structure is upstream, so this is a medium-size merge; do it only if measured (`/perf-measure`).

**P2. Car mode redraws the whole screen every second while playing** (`car_mode_screen.dart:71-73`), and also on every player notify (`:101-105`). The position `StreamBuilder`s already exist. Severity Low; it's a short-lived screen. Leave it unless measured.

**P3. Server logs copy the list on every line.** `admin_server_logs_screen.dart:144` copies up to 5050 entries and calls `setState` once per socket log line; the build then filters 5000 entries (`:77`). With debug-level logs during a scan this can jank. Batching lines on a 100–250 ms timer fixes it. Severity Low (admin only). It's an upstream file, so this is a candidate to upstream.

**P4. The admin hub keeps polling the server every 3 s** (`admin_screen.dart:153`) while any admin sub-page is pushed on top of it. Severity Low; it's upstream design. Pausing via `RouteAware` when covered would cut server load.

### Risky patterns. All low severity.

- **`use_build_context_synchronously`** (it's off in `analysis_options.yaml`). Turning it on flags 15 sites in this area:
  - 7 are real but benign: context read right after a modal dialog closes (`admin_api_keys:178`, `admin_libraries:86`, `admin_podcasts:1844`, `admin_users:1160,1181`, `chapter_editor:714,847`).
  - 8 are false positives (`backup_sync:225-356` passes the State's own context).
  - `chapter_editor_screen.dart:714` calls `showOverlayToast(context,…)` after `await showDialog` with no `mounted` check.
- **Controllers never disposed:** `admin_email_screen.dart:157-158`, `admin_users_screen.dart:809`.
- **Controllers disposed synchronously right after `await showDialog`:** `chapter_editor:711`, `admin_podcasts:~1190`, `login:~1352`, `upcoming_releases:~1932`. The dialog's exit animation can still be using the TextField, which risks a "used after disposed" assert in debug. `book_requests` already uses the post-frame workaround.
- **No unbounded growth found:** server logs are capped at 5000, and sessions, reading log and notifications are paged.
- **Desktop layout:** no fixed-width overflow found by reading. 13 raw `showModalBottomSheet` calls rely on M3's 640 px max width, which is fine. Nothing here is covered by the overflow sweep test.

### Duplication between admin screens

`_section` (4 files), `_cardDeco` (3), `_snk`/`_msg` toasts (5), confirm `showDialog<bool>` boilerplate (11), and byte/duration/time-ago formatters (5) are each re-implemented.
- **Verdict:** do **not** consolidate. Every copy is in an upstream file. Rewriting them adds conflicts on each merge and fixes no bug. Revisit only if upstream does it first.
- The one place where duplication is fork-made is `admin_upload_screen.dart`: a private `_formatBytes` sits beside `downloads_screen`'s new `_formatDownloadBytes`. A shared fork `utils/format_bytes.dart` would serve both fork hunks.

### Merge-cost hotspot

**M1. `admin_upload_screen.dart` carries about 690 fork lines inside an upstream file.**
- The Libation state (about 15 fields), the scanning and picking methods (`:234-358`, `:664-923`), and the history bookkeeping inside `_submit` are interleaved with upstream code.
- `_submit`'s indentation is scrambled (`:984-1157`), which shows earlier conflicts were resolved by hand.
- Moving the Libation logic into a fork `part`/mixin (for example `admin_upload_libation.dart`, next to the existing `libation_import_card.dart` and picker) would leave about 30 hook lines in the upstream file.
- Do this right after the next upstream merge that touches this file, not before. Cost M, risk Low-Med; the existing `test/admin_upload_screen_test.dart` covers it.

---

## Recommended actions

Ranked by value ÷ (effort + merge cost). Effort: S/M/L. "Upstream" means the edit lands in an upstream-owned file.

| # | Action | Files | Tag | Effort | Risk |
|---|---|---|---|---|---|
| 1 | **B1:** open RMAB web (and Audible reviews) in the external browser on non-Android; add a fork helper and use it from the 2–3 call sites | `admin_rmab_screen.dart`, `widgets/rmab_config_sheet.dart`, `app_shell.dart`, `widgets/book_detail_sheet.dart` | fork helper + small upstream hooks | S | Low |
| 2 | **B5:** gate transcription on web (hide the tile, or make `isModelDownloaded` web-safe and put try/finally in `_load`) | `settings_screen.dart` or `services/transcription_service.dart` | upstream (1–3 lines) | S | Low |
| 3 | **L1:** move server-health and download ETA/semantics strings into `app_en.arb`; fix "left remaining" | `server_health_screen.dart`, `downloads_screen.dart` (fork hunks) | fork | S | Low |
| 4 | **B2:** guard the chapter-preview race with an `identical(_preview, player)` check | `chapter_editor_screen.dart` | upstream (about 4 lines; upstream-PR candidate) | S | Low |
| 5 | **B4:** call `applyAppearanceFromPrefs()` after both restores; tell the services auditor about the look and e-ink keys missing from the backup | `login_screen.dart`, `backup_sync_screen.dart` | upstream (small) | S | Low |
| 6 | **B3:** add `isLocalFilePath()` and use it in car mode, bookmarks, and the widget sites (with the widgets auditor) | new `lib/utils/local_path.dart` + about 6 upstream lines in my area | fork util + upstream hooks | S-M | Low |
| 7 | **W1:** web-safe backup, restore and setup-file save: `withData` plus a fork download helper; hide save on web | `backup_sync_screen.dart`, `login_screen.dart`, `admin_users_screen.dart`, `podcast_edit_screen.dart` + new fork util | fork util + upstream hooks | M | Low-Med (touches the restore path: run a Windows build and a web CI build) |
| 8 | Add smoke widget tests: server health (fake service), transcription web guard, RMAB fallback, chapter-preview race (fake player) | `test/` | fork | M | None |
| 9 | **M1:** extract the Libation code from `admin_upload_screen.dart` into a fork part/mixin, after the next merge that touches it | `admin_upload_screen.dart` + new fork file | fork (lowers merge cost) | M | Low-Med |
| 10 | **P1:** make the downloads list lazy and stop the outer `context.watch`, only if `/perf-measure` shows cost | `downloads_screen.dart` | upstream | M | Med (downloads UI) |
| 11 | **P3:** batch server-log lines; **P4:** pause the admin task poll when covered | `admin_server_logs_screen.dart`, `admin_screen.dart` | upstream (upstream-PR candidates) | S-M | Low |
| 12 | Dispose the leaked dialog controllers; defer disposal past dialog close in 4 places | `admin_email`, `admin_users`, `chapter_editor`, `admin_podcasts`, `login`, `upcoming_releases` | upstream | S | Low (bundle with an upstream PR, or skip) |
| — | **Don't do:** consolidate admin helper duplication; delete `ChapterEditorScreen`, `AchievementDetailSheet`, `AuthSessionTile`; reformat upstream screens | — | upstream | — | merge churn for no gain |
