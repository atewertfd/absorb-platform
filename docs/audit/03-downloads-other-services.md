# Audit 03: downloads and the other services

Read-only audit, 2026-10-30, branch `claude/slim` (others had uncommitted UI edits; `lib/services/windows_shell.dart` was being written during the audit and is only noted).
Ownership: "fork" = missing from `origin/main`; "upstream (+N/-M)" = upstream file with the fork's diff; "upstream" = identical to upstream.
Line numbers are from this checkout and will drift.

## Scope: the files this report covers

`ls lib/services` lists 119 files. Playback (report 01) and server/sync (report 02) own 44 of them. This report covers the other **75**:

- **Downloads and offline:** `download_service.dart`, `download_track_names.dart`, `offline_source.dart`, `queue_download_policy.dart`, `library_cache.dart`, `ebook_cache.dart`, `book_track_resolver.dart`.
- **Narration, ebooks and read-along:** `narration_service.dart`, `narration_stream.dart`, `narration_script.dart`, `narrated_books.dart`, `up_next_narration.dart`, `media_overlay.dart`, `epub_book_text.dart`, `read_along_script.dart`, `image_epub.dart`, `foliate_book_server.dart`, `remote_zip.dart`, `ebook_history.dart`, `ebook_annotation_service.dart`, `find_in_ebook.dart`, `audio_locator.dart`, `reader_font_service.dart`, `volume_key_service.dart`.
- **Transcription:** `transcription_service.dart`, `transcript_chunker.dart`, `transcript_line_store.dart`, `lyrics_service.dart`, `remote_audio_slice.dart`, `audio_file_duration.dart`, `chapter_start_finder.dart`.
- **Clips and bookmarks:** `clip_editor_controller.dart`, `clip_export_service.dart`, `bookmark_preview_player.dart`, `bookmark_service.dart`, `notes_service.dart`, `chapter_lookup.dart`.
- **Stats and BookOrbit models:** `book_stats_service.dart`, `achievements.dart`, `book_requests.dart`, `book_dock.dart`, `server_notifications.dart`, `server_task_tracker.dart`.
- **Logging:** `log_service.dart`, `server_log_export_service.dart`.
- **Metadata and search:** `metadata_override_service.dart`, `book_search_index.dart`, `smart_scope_rules.dart`, `upcoming_releases_service.dart`, `rmab_service.dart`.
- **Platform glue:**
  - Home screen, shortcuts and Siri: `home_widget_service.dart`, `quick_actions_service.dart`, `siri_service.dart`, `siri_matcher.dart`.
  - Episode alerts and store review: `episode_notification_service.dart`, `review_service.dart`, `review_service_stub.dart`.
  - Reader helpers: `translate_service.dart`, `dictionary_service.dart`.
  - System: `device_time_zone.dart`, `screen_wake.dart`, `native_ios_audio_player.dart`.
- **Settings and wording:** `player_settings.dart`, `wording.dart`, `backup_service.dart`.
- **Accounts and backends:** `user_account_service.dart`, `server_backend.dart`, `signed_out_playback.dart`, `setup_link_service.dart`, `oidc_service.dart`, `audiobookshelf_update_service.dart`. All six are also in report 02, so they're only skimmed here.
- **Small player policies:** `now_playing_layout.dart`, `cold_start_play_policy.dart`, `playback_error_policy.dart`, `external_audio_output_types.dart`.
- **Fork-only files:** `desktop_shortcuts.dart`, `libation_import_helper.dart` (removed 2026-10-30), `startup_task_coordinator.dart`, `whats_new_notes.dart`, `windows_shell.dart` (new, still being written).

**Depth of the review:**
- **In depth:** `download_service.dart`, `download_track_names.dart`, `libation_import_helper.dart`, `log_service.dart`, `screen_wake.dart`, `desktop_shortcuts.dart`, `wording.dart`, `ebook_cache.dart` (size helpers), `home_widget_service.dart` (timers and stats), `transcription_service.dart` (platform path), `backup_service.dart` (secrets).
- **Outline only:** everything else.

---

## PART 1: Code map

### 1.1 Downloads

#### `download_service.dart`: upstream (+243/-32), 3,850 lines

**What it is:** a singleton `ChangeNotifier`. It runs book, episode, narration and ebook-only downloads on top of `background_downloader` 9.5.5. 53 files import it.

**Fork changes:**
- `DownloadFailureReason` (:32), with failed records and Retry kept after a restart.
- Speed, ETA and byte fields on `DownloadInfo`.
- Windows-safe names from `download_track_names.dart`.
- Unique track names.
- Extra logging.

**Key pieces:**
- **Data types:**
  - `DownloadInfo` (:56): the persisted record. It holds status, progress, bytes and speed, `localPaths`, `sessionData` (the trimmed play-session JSON used offline), cover, `localDirPath` and `libraryId`.
  - `_QueuedDownload` (:179) waits in the in-memory queue.
  - `_PendingBook` (:203) is a book in flight. It keeps per-track status and progress, expected paths, SAF target and narration flags, and is persisted in the `pending_downloads` pref.
- **Persistence (prefs):**
  - `downloads`, `kept_ebooks` and `download_origins` are written together by `_save()` (:1880).
  - Also: `pending_downloads`, `auto_download_blocked`, `custom_download_uri` and `other_account_reading`.
- **Accounts:** `_origins`, `isFromOtherAccount` (:473) and `_moveOrigins` (:509) handle downloads shared across accounts on one device. `UserAccountService.onScopeMoved` is wired in the constructor (:431).
- **Start-up:**
  - `init()` (:1196) memoizes `_initialize()` (:1217).
  - `_initialize()` loads prefs, runs the iOS path migrations (dead code now), `_detectLegacyExternal`, then an **unconditional `_save()` (:1285)**.
  - It then configures the downloader (:1392; the holding queue is set on **Android only**), subscribes to updates, calls `trackTasks`, `_loadPending`, `_loadAutoDownloadBlocks` and `_rehydratePending` (:3661).
  - Last come `resumeFromBackground`, a 2-minute reconciler (:1306 and :1319), and `_validateDownloads` in the background (:1702).
- **Entry points:**
  - `downloadItem` (:1935) is the manual and automatic entry. It handles Wi-Fi-only, the concurrency queue and auto-download blocks.
  - `enqueueBackgroundDownload` (:2052) is used by the episode-alert background isolate.
  - Also: `retryDownload` (:3356), `cancelDownload` (:3820), `deleteDownload` (:3716), `deleteAudioKeepEbook` (:923), `keepEbook` (:804), `registerEbookDownload` (:991), `registerNarration` (:1049), `catchUpEbookCaches` (:2131) and `enrichMetadata` (:1759).
- **Pipeline:**
  - `_executeDownload` (:2205) picks a source. `_sessionShapedItem` (:2712) builds session-shaped data from `GET item`, so no play session is opened (that used to kill the live stream). It falls back to a real session.
  - `_resolveDurableFiles` (:2772) builds `/api/items/:id/file/:ino` URLs, falling back to the session's temporary links, then calls `uniqueTrackFileNames`.
  - It then works out the folder name `Author/Title`, adding an id suffix when the folder is taken (:2330-2336), caches the cover (:2883) and slims the session (:2358).
  - It persists `_PendingBook` and enqueues one `DownloadTask` per track (:2434-2481), with per-book notifications.
- **Updates:**
  - `_onTaskUpdate` (:2918) handles progress (UI throttled to 250 ms, :3043) and status (`_handleTaskStatus`, :3004).
  - A hard failure cancels the sibling tasks (:3029).
  - `_checkBookTerminal` (:3067) then routes to `_finalizeSuccess` (:3224), `_failBook` (:3301) or `_handleCanceled` (:3401).
- **Finalize:**
  - Checks that every expected file exists.
  - For a narration book, runs `_finishNarration` (:2667).
  - For an SAF folder, runs `_moveBookToSaf` (:3190).
  - Writes the `downloaded` record, saves, deletes the DB records, then calls `AudioPlayerService().switchToLocal(itemId)` to hot-swap a book that is streaming.
- **Cleanup:**
  - `_cleanupBookDir` (:3528) deletes the book folder and its empty parent, unless `_dirSharedWithOther` (:3566) says another book uses it.
  - `deleteDownload` removes the files (skipping paths shared with other books), the folder (or the legacy `downloads/<id>` folder), the cover folder and the cached ebook.

**Platforms:**
- iOS-only code is dead: `_iosAppGroupAudioBase` :751, `_excludeFromBackup` :735, `_migrateIOSPaths` :1450, `_migrateIOSAudioToAppGroup` :1517 and the iOS task branches. That's about 240 lines.
- SAF custom folders are Android only (`com.absorb.storage`).
- **Desktop and Linux use `getApplicationDocumentsDirectory()`.** On Windows that is the user's **Documents** folder (`Documents\downloads\Author\Title`), and covers go to `Documents\downloads\<itemId>\cover.jpg`.
- On desktop, `background_downloader` runs tasks in-process, so they die with the app.

**Traps:**
- The service broadcasts every change to every listener; there is no per-item notification.
- Records are rebuilt as new `DownloadInfo` objects all over the file (more than 10 hand-written copies).
- A pending entry with `finalizing` set is skipped by cancel and by the reconciler. `_failBook` returns early if `finalizing` is already set (see the comments at :1356 and :3699).
- Episodes use the key `podcastId-episodeId`, and code elsewhere infers "episode" from `itemId.length > 36`.

**Callers:**
- Library provider: `_lp_core.dart`, with 8 call sites including automatic planners at :3069, :3758, :3859, :3900, :3958 and :3988.
- Widgets: `card_buttons`, `absorbing_shared`, `episode_*`, `book_detail_sheet`, `desktop_batch_actions`, `narration_download_dialog`, `transcription_download_prompt`.
- Screens: `downloads_screen`.
- Services: `episode_notification_service`.
- The player reads `getLocalPaths` and `getCachedSessionData`.

#### Other download files

- **`download_track_names.dart`** (fork, 81 lines):
  - `windowsSafeName` (:23) handles control characters and reserved device names.
  - `safeDownloadFolder` (:45) handles `.`/`..` and trailing dots or spaces.
  - `uniqueTrackFileNames` (:62) puts the track number in front of clashing names, compared case-insensitively.
  - Pure functions, tested in `test/download_path_names_test.dart`.
- **`offline_source.dart`** (upstream, 29 lines): `isContentUri` and `localAudioSource` (file, content URI or loopback http URL), plus the mp3 index-seek options. 5 importers.
- **`queue_download_policy.dart`** (upstream, 153 lines): pure helpers that decide which queue items to auto-download (`queueDownloadWindow` :121, `queueItemsNeedingDownload` :140). Tested.
- **`ebook_cache.dart`** (upstream, 374 lines): the persistent ebook cache under **ApplicationSupport/** (not Documents).
  - `resolveEbookFile` :38, `fetchEbookToCache` :254, `deleteCachedEbook` :360.
  - Sidecar files `.locations.json` and `.version`.
  - `cachedEbookBytesSync` :83 lists the **whole folder** synchronously on every call.
- **`book_track_resolver.dart`**: playable tracks for a book (local or stream), used by the bookmark preview and clip editor.
- **`library_cache.dart`** (57 lines): the library-items cache for the provider.

### 1.2 Narration, ebooks and transcription (outline)

- **`narration_service.dart`** (816 lines):
  - `readerFile` gets the reader's copy of a narrated EPUB without its audio.
  - `keepFromEpub` (:585) takes the audio out of a downloaded EPUB. The heavy work runs in `compute` or `Isolate.run`.
  - Output goes to ApplicationSupport.
- **`narration_stream.dart`**: loopback streaming of narration audio. It uses `remote_zip.dart` (HTTP range reads of a zip) and `media_overlay.dart` (SMIL clips).
- **Read-along helpers:**
  - `narrated_books.dart` is a device-side set of Audiobookshelf items known to be narrated (15 importers).
  - `up_next_narration.dart`, `read_along_script.dart` and `narration_script.dart` are JavaScript for the web-view readers.
  - `epub_book_text.dart` handles text search in an EPUB.
- **Transcription:**
  - `transcription_service.dart` (979 lines) runs Whisper through `packages/whisper_ggml_plus`.
  - Audio decoding goes through the native channel `com.barnabas.absorb/transcription` → `extractWav` (:139, :955). **Only Android implements it** (`AudioWindowExtractor.kt`); there's nothing in `windows/` or `linux/`.
  - `transcript_chunker`, `transcript_line_store`, `lyrics_service`, `chapter_start_finder` and `remote_audio_slice` sit on top of it.
- **Reader helpers:**
  - `find_in_ebook.dart` and `audio_locator.dart` match audio to text.
  - `ebook_history.dart`, `ebook_annotation_service.dart` (local highlights; the sync side is in report 02), `reader_font_service.dart` (fonts downloaded to ApplicationSupport) and `volume_key_service.dart` (Android volume-key page turns).
- **Clips:**
  - `clip_export_service.dart` uses the channel `com.absorb.clip`, which only Android implements. It catches only `PlatformException`, not `MissingPluginException`.
  - Also `clip_editor_controller.dart`, and `bookmark_preview_player.dart` (a second player for auditioning).

### 1.3 Logging

**`log_service.dart`** (upstream, 316 lines), singleton `LogService`:
- **Start-up:** `init(enabled)` (:32) is called from `main.dart:787`.
  - It writes `Documents/absorb_logs.txt` plus a sidecar file `log_created_at`, starting fresh after 24 h.
  - It replaces the global `debugPrint` with `_interceptedDebugPrint` (:87).
- **Writing:** `_interceptedDebugPrint` does a **synchronous open, append and close for every line**.
  - Every 500 writes, `_rotateIfNeeded` (:128) trims the file to 512 KB once it passes 1 MB.
  - It reads the whole file and rewrites it asynchronously while sync appends continue.
- **Sanitizing:** `_sanitize` (:190) and `_sanitizeUrls` (:204):
  - Only `https?://` URLs get their host replaced with a label.
  - Query parameters named token, code, state and similar are masked.
  - `token=`, `secret=`, `password=`, `authorization=` and `*key=` pairs are masked.
- **Sharing:** `shareLogs` (:268) writes `absorb_logs_share.txt` and opens the share sheet. `contactEmail` (:298) opens a mailto link. Both go to **`supportEmail = 'absorb@barnabashq.com'`** (:15), which is upstream's address.
- **Default on:** `BetaLoggingNotice.applyDefault` (`widgets/beta_logging_notice.dart:18`) turns logging **on by default for beta builds**. `betaNumberFor` (`build_info.dart:9`) treats every odd patch number as a beta, and every Absorb Plus build is `1.12.1`, so logging is on by default for every fork user who never chose.
- **Crashes:** `main.dart:325` and `main.dart:330` send crash text to `LogService().log`.

**Flow:** any `debugPrint` → the console plus a sanitized line appended to the file → the user taps "Send logs" → a sanitized copy goes to the share sheet with upstream's address.

### 1.4 Libation import

**Removed 2026-10-30 (owner decision):** the Libation import, this helper, its widgets and its tests are gone; the notes below describe the code as audited.

**`libation_import_helper.dart`** (fork, 516 lines). Pure helpers plus a directory scan.
- **Name helpers:** extension sets (:20-55), `libationAsinFrom` (:65), `cleanLibationBookTitle` (:111), `inferTitleFromSelectedFiles` (:123).
- **Model:** `LibationBookCandidate` (:145), with an ASIN taken from the folder, then from the first audio file.
- **History:** `LibationImportHistory` (:205) keeps up to 1,000 imported folder keys (`libation_imported_folders`) and the last-seen time.
- **New exports:**
  - `newLibationExports` (:189) applies a 3-day window on the first run.
  - `countNewExportsInSavedLibationFolder` (:262) feeds the badge on the Settings tile.
- **Scanning:** `scanLibationExportDirectory` (:330), depth 3 and at most 2,000 books.
  - It lists folders with `followLinks: false` and only calls `stat()` on audio and cover files.
  - It never opens a file and skips everything else (json, db, aax and so on).
  - The author is taken from the parent folder name.
- **Matching:** `matchingLibraryBookTitle` (:290) matches by ASIN, then by a normalized title (any script).
- **Launching:** `launchLibationExecutable` (:472) starts a user-picked `.exe` on Windows (any non-forbidden file on Linux) detached, with no arguments.

**Callers:**
- `screens/admin_upload_screen.dart` (upload and history recording), `screens/settings_screen.dart` (the tile and the badge), `widgets/libation_book_picker_sheet.dart`.
- Tests: `admin_upload_screen_test`, `media_upload_api_test`, `integration/upload_test`.

**Flow:**
1. Settings → Advanced tile (badge from `countNew...`), or the admin upload screen.
2. The picker sheet calls `scanLibationExportDirectory(savedFolder)`; results are listed newest first and flagged new or duplicate.
3. The user picks a book.
4. The upload screen fills in title, author and files.
5. The upload is an explicit user action through `ApiService`.
6. On a server-confirmed success, `recordImported`.

### 1.5 Settings, wording and the smaller pieces

- **`player_settings.dart`** (upstream +24/-1, 1,455 lines):
  - Static `PlayerSettings` with about 170 getters and 160 setters.
  - Most go through `_get`/`_set` (:105, :119) on top of `ScopedPrefs` (per account); some are device-wide `SharedPreferences`.
  - One global `settingsChanged` notifier (:81), listened to by `ScreenWake`, `windows_shell` and others.
  - The fork adds the update-check frequency and pre-release defaults.
  - 26 importers.
- **`wording.dart`** (upstream, 107 lines): `classicWordingNotifier` plus `Wording.of(ctx)`. When "Plain wording" is on it returns hard-coded English strings (the fork's "Plain wording" switch).
- **`screen_wake.dart`** (upstream, 74 lines):
  - `ScreenWake.hold(owner, on)` over the channel `com.absorb.screen_wake`, which **only Android implements**.
  - `PlayerScreenWake` combines the settings switch, a session override, on-screen state and whether the reader covers the player.
- **`desktop_shortcuts.dart`** (fork, 139 lines):
  - A table of shortcuts (`desktopShortcutDefinitions` :50).
  - `isTypingInTextField` (:103) and `desktopShellFocusNode`.
  - `DesktopShortcutCallbackAction.isEnabled` (:124): plain keys work only while the shell has focus on desktop.
  - Used by `app_shell` and `settings_screen`, with a test.
- **`startup_task_coordinator.dart`** (fork, 35 lines): `runCritical` runs tasks in order; `startBackground` starts each task in its own microtask with an error handler. Used by `main`, with a test.
- **`whats_new_notes.dart`** (fork, 476 lines):
  - Fetches GitHub release notes for a tag (10 s timeout) and parses the Markdown.
  - Caches the last 5 device-wide.
  - Tested; see ARCHITECTURE.md.
- **`windows_shell.dart`** (fork, **being written now**):
  - Talks to the runner over `absorb/windows_shell`: tray, start with Windows, always on top, keep awake while playing or downloading, taskbar buttons and progress, full screen.
  - Listens to `DownloadService` for a "busy" state.
  - No findings recorded against it.
- **`home_widget_service.dart`** (upstream +2/-1, 1,524 lines):
  - Android home-screen widgets (the iOS branches are dead).
  - `init` is called only on Android and iOS (`main.dart:927`).
  - **But** `refreshStats(force: true)` and `addLocalListeningSeconds` are called from shared code on every platform (`_lp_core.dart:301`, `_lp_core.dart:309`, `_lp_absorbing.dart:692`, `audio_player_service.dart:4308` and others).
  - Timers: progress every 120 s (:1464) and stats every 15 minutes (:1493).
- **`backup_service.dart`** (upstream, 1,063 lines):
  - Export and import of settings, notes, bookmarks, offline listening, RMAB and settings-sync setup.
  - Optional accounts (`includeAccounts`).
  - Setup links for new users.
- **iOS-only, dead in the fork:**
  - `siri_service.dart` and `siri_matcher.dart`. Every public method returns early unless iOS (:48, :589, :598).
  - Hooks in other files: `main.dart:932`, `library_provider.dart:69`, and in `settings_screen.dart` (:1446, :1450 and the Siri tile at :3563, behind `Platform.isIOS`).
  - Also `native_ios_audio_player.dart` (imported by `_audio_player.dart`; report 01), and the iOS branches of `dictionary_service`, `translate_service`, `clip_export_service` and `episode_notification_service`.
- **Other small files:**
  - `notes_service.dart`: per-account notes in prefs, local only, included in backups.
  - `bookmark_service.dart`: local bookmarks plus server sync, with pending create and delete queues.
  - `book_stats_service.dart`, `achievements.dart`, `book_requests.dart`, `book_dock.dart`, `server_notifications.dart`, `server_task_tracker.dart`: BookOrbit and Audiobookshelf models and parsers.
  - `metadata_override_service.dart`: local metadata overrides per item.
  - `book_search_index.dart`: in-memory scored search.
  - `smart_scope_rules.dart`: rule-editor model.
  - `upcoming_releases_service.dart`: Audible/Audnexus series scan.
  - `rmab_service.dart`: ReadMeABook client.
  - `episode_notification_service.dart`: Android WorkManager job that sets `DownloadService.backgroundIsolateMode`.
  - `quick_actions_service.dart`: Android launcher shortcuts.
  - `review_service.dart`: in-app review. `review_service_stub.dart` is for F-Droid; the fork has no F-Droid build.
  - `device_time_zone.dart`: Android channel.

### 1.6 End-to-end flows

**Downloading a book:**
1. The UI or a planner calls `downloadItem`. It checks for a duplicate, the auto-download block (`automatic: true`), Wi-Fi-only and the concurrency limit; it either queues the item in `_queue` or starts it.
2. `_executeDownload` marks the item active, so the UI shows "downloading".
3. A narrated EPUB book takes the separate path `_executeNarrationDownload` (one EPUB task, then `_finishNarration` → `NarrationService.keepFromEpub`).
4. Otherwise `GET item` → `_sessionShapedItem` (or a play session) → `prepareDownload` → `_resolveDurableFiles`. The companion ebook goes to the cache without waiting.
5. Folder name, then cover → `Documents/downloads/<itemId>/cover.jpg` on desktop, then a slim session.
6. `_PendingBook` is persisted, then one `DownloadTask` per track is enqueued under `applicationDocuments/downloads/Author/Title`.
7. `_onTaskUpdate` progress → `_emitBookProgress` (new `DownloadInfo`, `notifyListeners`, at most one every 250 ms; Android notification at most one per second).
8. All tracks complete → `_finalizeSuccess`: files checked → (SAF move) → record `downloaded` + `_save` → `_processQueue`.
9. **Playback from local:** `switchToLocal` swaps a book that is streaming. Afterwards `AudioPlayerService` asks `getLocalPaths` and `getCachedSessionData` → `localAudioSource(path)`.
10. **Relaunch:**
    - `_loadPending` → `_rehydratePending` from the task DB: all complete → finalize; all terminal or nothing tracked → fail; otherwise leave it running.
    - The reconciler then fails anything silent for 3 minutes (no progress) or 10 minutes (some progress).

**Deleting and cleaning:**
- **Delete:** `deleteDownload(byUser)`:
  - Adds the item to the auto-download block.
  - If it's still pending or queued, `cancelDownload` takes over.
  - Otherwise it stops playback when this item is the one playing, deletes the files (skipping shared ones), the folder or legacy folder plus its empty parent, the cover folder (evicting it from the image cache) and the cached ebook (unless the ebook is kept), then saves.
- **Cancel:** `cancelDownload` drops the queued entry, sets `_cancelledIds`, cancels the tasks and runs `_handleCanceled` right away; it doesn't wait for the package. That one cleans up the folder, the record and the DB entries.
- **Start-up check:** `_validateDownloads` drops records whose files are missing.
- **Delete absorbed downloads** (deleting finished downloads) lives in the provider.

**Ebook and narration downloads:**
- `keepEbook` / `registerEbookDownload` create ebook-only records in `_keptEbooks` (the file lives in `ebook_cache`).
- `catchUpEbookCaches` (called on reconnect by `library_provider.dart:428` and `_lp_core.dart:1255`) re-fetches missing companion ebooks and asks the server once per run for books whose record has no ebook.
- `registerNarration` / `updateNarrationTimeline` keep the narration audio taken out of an EPUB as a normal download record.

**Libation import:** see 1.4 (removed 2026-10-30).

**Logging:** see 1.3.

---

## PART 2: Findings

Recent fixes not re-reported: names valid on Windows (ab3d26ad), multi-disc tracks (74b86214), silent-failure logging (e605c274), Libation details leaking between uploads (60788c5f), the web-safe Platform (61554b8c).

### 2.1 Bugs

#### B1. Downloads and logs land in the user's Documents folder on Windows and Linux
- **Severity and confidence:** high, Windows and Linux. Confidence high (the `path_provider_windows` documents directory is FOLDERID_Documents).
- **Where:**
  - `download_service.dart:637-646` (`downloadBasePath`, `_internalBasePath`), `:2342-2344` and `:2542` (task directories, relative to `BaseDirectory.applicationDocuments`).
  - `log_service.dart:36-37`, `:42` and `:279`.
- **Effect:**
  - Audiobooks fill `Documents\downloads\…` and covers fill `Documents\downloads\<uuid>\`.
  - Three log files (`absorb_logs.txt`, `absorb_logs_share.txt`, `log_created_at`) sit at the top of Documents.
  - With OneDrive "Documents backup" (on by default on many Windows 11 PCs), gigabytes of audio get uploaded to the user's cloud.
  - Other app data already uses ApplicationSupport (`ebook_cache.dart:70`, `narration_service.dart:178`).
- **Minimal fix:**
  - On desktop, use `getApplicationSupportDirectory()` (or a folder the user picks) for new downloads and logs.
  - Existing records keep their absolute paths, so they keep working; moving old folders is optional.
  - This changes download storage, so per the release policy it needs the owner's OK.

#### B2. Desktop downloads interrupted by quitting hang for 3–10 minutes after relaunch, then fail and lose their partial files
- **Severity and confidence:** medium-high, Windows and Linux. Confidence medium-high.
- **Where:** `_rehydratePending` `download_service.dart:3702-3708` leaves non-terminal records "in flight". The reconciler at :1376-1382 fails them later. `_failBook` → `_cleanupBookDir` deletes the partial files.
- **Why:**
  - On desktop, `background_downloader` 9.5.5 runs tasks in Dart isolates inside the process.
  - After a quit (tray Quit, an update install, a crash), the DB still says `running` and nothing resumes them.
  - `resumeFromBackground` does nothing on desktop.
- **Trigger:** quit Absorb during a download, then start it again.
- **Minimal fix:** on desktop, in `_rehydratePending`, treat records that aren't terminal as dead. Either re-enqueue `r.task` with fresh headers (`api.downloadHeadersFor`), or fail them at once so Retry is offered straight away.

#### B3. RangeError in the folder-name suffix for short (BookOrbit) ids
- **Severity and confidence:** medium. Confidence high. Upstream bug.
- **Where:** `download_service.dart:1083`, `:2335` and `:2534`: `itemId.substring(itemId.length - 8)`.
- **Trigger:**
  - BookOrbit ids are numbers (see the comment at :470).
  - When an `Author/Title` folder is already used by another download, an id shorter than 8 characters throws a RangeError.
  - The download fails ("Download failed"), or `registerNarration` throws.
- **Minimal fix:** `itemId.length > 8 ? itemId.substring(itemId.length - 8) : itemId`. That's a 3-line upstream change, and a good one to offer upstream (ask the owner first).

#### B4. Credentials reach the log, which is on by default for fork users
- **Severity and confidence:** medium. Confidence high.
- **Where:**
  - `oidc_service.dart:116` logs the raw OIDC session cookie (`name=value`).
  - `oidc_service.dart:288` logs the callback URL, including `code=…`. The sanitizer only matches `https?://` URLs, so a custom-scheme URL isn't masked, and `code` isn't in the list of key=value names it masks (`log_service.dart:195`).
  - `Authorization: Bearer <jwt>` masks only the word "Bearer" and leaves the token.
  - Logging defaults to on because every fork build counts as a beta (`beta_logging_notice.dart:19` + `build_info.dart:9`).
- **Minimal fix:**
  - Log only cookie names.
  - In `_sanitize`, also mask `Bearer\s+\S+`, `code|cookie|sid`, and any `scheme://…?query`.
- **Overlap:** report 02 owns OIDC; this item is the logging side.

#### B5. "Send logs" and "Contact" go to upstream's developer
- **Severity and confidence:** medium (fork-specific). Confidence high.
- **Where:** `log_service.dart:15`, used at :285, :290 and :302.
- **Minimal fix:** a fork address, or point to the fork's GitHub Issues. One line in an upstream file; add it to `tool/fork-overrides.txt`, or route it through a fork constant.

#### B6. Settings-only backups carry secrets
- **Severity and confidence:** medium. Confidence high. Upstream.
- **Where:**
  - The RMAB `apiToken` and `customHeaders` are exported unconditionally (`backup_service.dart:247-252`).
  - So are settings-sync `headers` (:386).
  - The WebDAV password is held back unless accounts are included (:381-391). The file's own rule says "a settings-only backup is a file people hand around".
- **Minimal fix:** put those three values behind `includeAccounts`.

#### B7. Android-only features are offered on Windows and Linux, where they can't work
- **Severity and confidence:** medium. Confidence high.
- **Transcription:**
  - The tile has no platform check (`settings_screen.dart:4865`).
  - The user can download a Whisper model, then every job fails at `extractWav` with `MissingPluginException` (`transcription_service.dart:955-978`; only `AudioWindowExtractor.kt` implements it).
  - Lyrics, Find in ebook and Chapter start finder depend on it too.
- **Clip export:** `com.absorb.clip` throws an uncaught `MissingPluginException` (`clip_export_service.dart`, `catch` only for `PlatformException`).
- **Keep screen on:** the switch (`settings_screen.dart:2818`) does nothing (`screen_wake.dart:28`, no channel on desktop).
- **Minimal fix:**
  - Add `isSupported` getters (Android only) and hide the tiles behind them.
  - For keep screen on, route the desktop case through `windows_shell` keep-awake (display-required) once it lands.

#### B8. A slow disk at start-up silently drops download records and orphans their folders
- **Severity and confidence:** low-medium. Confidence high on the logic.
- **Where:** `_validateDownloads` `download_service.dart:1717-1727` treats a 3 s timeout or any error as missing. Cleanup (:1740-1750) removes only the legacy `downloads/<id>`, not `localDirPath`.
- **Trigger:** Documents on a slow, redirected or network drive, or a still-mounting SD path. The book disappears from the app while its audio stays on disk, unseen.
- **Minimal fix:**
  - Remove a record only on a definite `exists() == false`.
  - When removing, also delete `localDirPath` (guarded by `_dirSharedWithOther`).

#### B9. "Plain wording" turns translated screens English
- **Severity and confidence:** low. Confidence high.
- **Where:** `wording.dart`, all getters. The doc comment (:9-11) says translated locales keep their strings; the code has no locale check.
- **Minimal fix:** `classic && _l.localeName.startsWith('en')` in the constructors.

#### B10. Cancel during finalize
- **Severity and confidence:** low.
- **Where:** `cancelDownload` `download_service.dart:3828-3847`.
- **Effect:** when `p.finalizing` is set, it clears the UI record and deletes the cached ebook. `_finalizeSuccess` then writes `downloaded` anyway, so the book comes back without its offline ebook.
- **Minimal fix:** return early when `p?.finalizing == true`.

#### B11. `retryDownload` guesses whether it's an episode from the id length
- **Severity and confidence:** low.
- **Where:** `download_service.dart:3366` uses `itemId.length > 36`. That only works for UUID ids.
- **Minimal fix:** persist `episodeId` in `DownloadInfo`; `_PendingBook` already has it.

#### B12. Names can break, and Windows paths can get too long
- **Severity and confidence:** low. Confidence low to medium; unverified on the device.
- **Where:** `_sanitizePath` cuts at 100 UTF-16 code units (:420) and can split an emoji surrogate pair.
- **Long paths:** the Windows manifest has no `longPathAware`. `Documents\downloads\` + author (100) + title (100) + track (100+) can pass 260 characters.
- **Next step:** test with a long title before changing anything.

#### B13. Log rotation can lose lines
- **Severity and confidence:** low.
- **Where:** `log_service.dart:128-141`. Rotation reads, then rewrites, while sync appends continue, so lines written in between are lost.
- **Minimal fix:** switch to one `IOSink` (see P2).

### 2.2 Performance

- **P1. Medium. Download progress rebuilds unrelated widgets.**
  - `_emitBookProgress` (`download_service.dart:3041-3063`) notifies **every** listener up to 4 times a second per active book.
  - `AbsorbingCard` calls `setState` on every notification (`absorbing_card.dart:207` and `:283`) for every card kept alive, even when its own book isn't downloading.
  - Same for `book_detail_sheet` (3 listeners), `card_buttons`, `episode_row` and `series_books_sheet`.
  - **Fix:** compare this item's `getInfo(id)` with the previous value before calling `setState` (fork-local in widgets the fork already edits), or add a per-item `ValueListenable`.
- **P2. Medium, Windows. Every log line is a synchronous file open and write.**
  - Logging is on by default (B4), and every `debugPrint` does `writeAsStringSync` (open, append, close) on the UI isolate (`log_service.dart:92`).
  - Startup alone prints one "Loaded:" line per download (`download_service.dart:1253`).
  - **Fix:** keep one buffered `IOSink` with a periodic flush, and drop the per-download start-up line. Measure with `/perf-measure`.
- **P3. Medium on desktop and web. Stats for a home-screen widget that doesn't exist.**
  - `HomeWidgetService.refreshStats(force: true)` runs from the library provider on every platform.
  - It makes two server calls (`getListeningStats`, which is heavy on the server, plus `getAllProgress`) for a widget that only exists on Android, then fails on `HomeWidget.saveWidgetData`.
  - **Fix:** return early unless Android (`home_widget_service.dart:1119`, and the same in `addLocalListeningSeconds` at :1198). That's a 2-line upstream hook.
- **P4. Low-medium. Download sizes are read synchronously, file by file.**
  - The Downloads screen calls `getItemFileSize` for every item (`downloads_screen.dart:69`). That does a `stat` on every file plus `cachedEbookBytesSync`, which lists the whole ebook folder per item (`ebook_cache.dart:83-93`).
  - `cachedEbookBytesSync` is also called inside `build` (`downloads_screen.dart:535`).
  - That's items × cache entries of synchronous IO on the UI thread.
  - **Fix:** one async pass that builds an id → bytes map.
- **P5. Low-medium, unmeasured. A full download save on every launch.**
  - `_save()` runs at every start-up (`download_service.dart:1285`) and after every change.
  - It rewrites `downloads` (every record with its `sessionData`: chapters, tracks, slim item), `kept_ebooks` and `download_origins`.
  - On Windows, `shared_preferences` rewrites the whole prefs JSON file on each set, so three full writes per save.
  - **Fix:** save at start-up only if a migration changed something. Check the size of `shared_preferences.json` first.
- **P6. Low, Windows. The desktop download limits are never set.**
  - The holding queue (6 in all, 4 per host) is configured only on Android (`download_service.dart:1399-1414`).
  - The desktop default is 10 at once with no per-host limit, which is the server-swamping case the comment describes.
  - **Fix:** apply `Config.holdingQueue` on every platform.

### 2.3 Dead code

**iOS-only code** (Apple was removed):
- **`siri_service.dart` and `siri_matcher.dart`** (1,146 lines; upstream):
  - Only `siri_service` imports the matcher. `test/web_safe_platform_test.dart:28` lists `siri_service`.
  - **Recommendation:** follow the CarPlay precedent. Replace `siri_service.dart` with a no-op stub of the same API (list it in `tool/fork-overrides.txt`), and add `siri_matcher.dart` to `tool/fork-removed-paths.txt`.
  - This touches no upstream hook sites, so the merge cost is low. **S, low risk.**
- **The iOS paths in `download_service.dart`** (about 240 lines: :726-776, :1450-1640, plus the `Platform.isIOS` branches). The file churns a lot upstream, so removal **isn't worth it**. Leave them.
- **`native_ios_audio_player.dart`** (431 lines): belongs to report 01, as a stub candidate like Siri.
- **`review_service_stub.dart`** (8 lines): only used by upstream's F-Droid build. Harmless; leave it.

**Unused members** (grepped across `lib`, `test` and `tool`; no references outside their definition):
- **Fork-owned** (remove freely):
  - ~~`libation_import_helper.dart`: `isLibationExportFile` (:87) and `LibationBookCandidate.audioFileCount` (:165).~~ File removed 2026-10-30.
  - `downloads_screen.dart:36`: `_formatDownloadBytes`, the same as `_formatBytes` at :291 in the same file (see 2.4).
- **Upstream** (not worth the merge cost on their own; drop them if the file is touched anyway):
  - `player_settings.dart`: `get/setAutoPlayNextBook`, `get/setAutoPlayNextPodcast` (:732), `clearQueueModePlaylist` (:598), `clearQueueModeCollection`, `getEreaderAutoScrollSleepMinutes` (:1119).
  - `notes_service.countNotes`, `bookmark_service.clearBookmarks`, `metadata_override_service.hasOverride`, `ebook_annotation_service.hasBookmarkAt`, `server_backend.saveActive`, `transcript_line_store.preparedSeconds`, `upcoming_releases_service.isDeepScan`.
  - Test hooks no test uses: `DownloadService.debugPutDownload` (:3164), `debugSetOrigin` (:505), `NarratedBooks.debugSet`, `NarrationService.debugPlacePage`.
- **`download_service._mapError`** (:3580) now only feeds one log message. It duplicates the fork's `_failureReason` (:43). Fold it in when the file is touched next (fork lines).

### 2.4 Duplication

- **Byte formatters (10):**
  - `downloads_screen.dart:36` (fork) and `:291` (identical).
  - `settings_screen.dart:5128`, `admin_stats_screen.dart:63`, `admin_upload_screen.dart:1227`, `transcription_settings_screen.dart:61`, `admin_podcasts_screen.dart:2472` and `:2605`, `book_detail_sheet.dart:2773`, `book_requests.dart:609`.
  - **Recommendation:** remove only the fork's copy. The rest are upstream; a shared util isn't worth the conflicts.
- **Duration and time formatters (12):**
  - `utils/duration_format.dart:4` `formatHm` and `widgets/absorbing_shared.dart:47` `fmtTime`.
  - `stats_screen.dart:2237` and `:2559`, `admin_sessions_screen.dart:298`, `admin_users_screen.dart:1217`, `car_mode_screen.dart:194`, `day_sessions_sheet.dart:139`, `listening_session_card.dart:182`.
  - `sleep_timer_service.dart:66`, `audio_player_service.dart:1864` and `bookmark_service.dart:97`.
  - All upstream; leave them.
- **Download failure text in two places:** `_failureReason` (:43; fork) and `_mapError` (:3580; upstream) both look for the same "no space" and "permission" words.
- **Base folder:** `downloadBasePath` and `_internalBasePath` (:632-647) are identical now that iOS is gone. Harmless.
- **The same `DownloadInfo(...)` rebuilt by hand more than 10 times** (:2019, :2167, :2218, :2289, :3046, :3267, :3333, :3625 and others). A `copyWith` would prevent dropped fields. For example, `catchUpEbookCaches` (:2167) already drops `failureReason`, `bytes*` and `trackCount`. That's harmless for downloaded records, but it's a trap.
- **English strings outside l10n:**
  - Fork: `_downloadEta` and `_downloadRate` in `downloads_screen.dart` ("min left", "hr left").
  - Upstream: `downloadItem` return messages (:1963, :1966, :1991), `downloadLocationLabel` (:665), `wording.dart` (by design).
  - **Recommendation:** move the fork's strings into `app_en.arb`.

### 2.5 Risky patterns

- **Synchronous file IO on the UI isolate** in the download and ebook paths: `deleteDownload` (:3757-3793, a recursive `deleteSync`), `_cleanupBookDir`, `createSync` in `_executeDownload`, and `ebook_cache` (17 sync calls). It's fine for small books; a 100-file delete freezes a frame or two.
- **Errors swallowed without a trace** in cleanup code: `catch (_) {}` at :698, :718, :3538, :3599, :3780 and :3794. A failed folder delete leaves gigabytes behind with no log line.
- **Service-to-UI coupling:**
  - `_toastFailure` and `_l()` reach `rootNavigatorKey` from the service.
  - `AudioPlayerService().switchToLocal` is called from finalize.
  - `UserAccountService.onScopeMoved` is a single static callback slot that the DownloadService constructor takes over (:431).
- **One global notifier for every setting:** `PlayerSettings.settingsChanged` fires for any setting, and `ScreenWake._reload` plus `windows_shell` re-read their prefs on every change.
- **Plain-text secrets in prefs:** tokens in `user_account_service`, the RMAB token, the WebDAV password. These are known; moving them to secure storage needs the owner's OK.
- **`dart:io` `Platform` on code web can reach:** `log_service.dart:62` (only if logging is turned on on web, and caught in `main`) and `libation_import_helper.dart:467` (reached only after `kIsWeb` guards; file removed 2026-10-30). Low risk; note it for report 04's web pass.
- **Libation folders guessed as authors** (moot: removed 2026-10-30): the author comes from the parent folder (`libation_import_helper.dart:406-417`). With Libation's "series" folder template the series name becomes the author, and `Disc 1`/`Disc 2` subfolders become separate books. The user can edit before uploading, so this is low risk; worth a test fixture.

---

## Recommended actions (ranked by value ÷ (effort + merge cost))

| # | Action | Owner | Size | Risk |
|---|---|---|---|---|
| 1 | B5: point "Send logs" and "Contact" at the fork (override the `supportEmail` line, or a fork constant) | upstream line, fork override | S | low |
| 2 | B4 + P2: stop logging the OIDC cookie value and callback code; mask `Bearer …`, `code`, `cookie` and custom-scheme URLs; buffered `IOSink` for the log | upstream (`log_service`, `oidc_service`), small hooks | S | low |
| 3 | B3: guard `substring(itemId.length - 8)` (3 places); offer it upstream with the owner's OK | upstream | S | low |
| 4 | B7: hide Transcription and Clip export off Android (`isSupported`); route keep screen on through `windows_shell` | upstream hooks + fork | S | low |
| 5 | P3: Android-only guard in `HomeWidgetService.refreshStats` / `addLocalListeningSeconds` | upstream (2 lines) | S | low |
| 6 | B6: put the RMAB token, RMAB headers and sync headers behind `includeAccounts` in backups | upstream | S | low |
| 7 | B2: on desktop, re-enqueue (or fail at once) interrupted tasks in `_rehydratePending`; plus P6 (holding queue everywhere) | upstream (fork hunk) | M | medium (downloads: owner tries the Windows build) |
| 8 | P1: `AbsorbingCard` (and the sheets) rebuild only when their own item's download info changes | upstream widgets the fork already edits | S–M | low |
| 9 | B8: `_validateDownloads` deletes only on a definite "missing" and cleans `localDirPath` | upstream | S | low-medium |
| 10 | Siri stub + remove `siri_matcher` (CarPlay precedent) | fork overrides | S | low |
| 11 | B1: desktop download and log folder in ApplicationSupport or a user-picked folder (new downloads only; optional move) | upstream (fork hunk) | M | medium: storage change, **owner OK required** |
| 12 | P4: async size map on the Downloads screen | upstream screen | S | low |
| 13 | Fork clean-ups: remove the duplicate `_formatDownloadBytes`; localize `_downloadEta`/`_downloadRate`; ~~remove `isLibationExportFile` and `audioFileCount`~~ (file removed 2026-10-30) | fork | S | low |
| 14 | B9, B10, B11, B13 (wording locale, cancel-while-finalizing, persisted episode id, log rotation race) | upstream | S each | low |
| 15 | P5: skip the start-up `_save()` unless a migration changed something (measure prefs size first) | upstream | S | low |
| 16 | B12: test long titles on Windows; add `longPathAware` or trim names if it fails | fork (manifest) | S | low (verify first) |

Not recommended: removing the iOS code in `download_service.dart`, consolidating the upstream formatters, removing unused upstream members on their own. All cost merge effort for little gain.
