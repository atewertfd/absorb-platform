# Audit 01: playback

Read-only audit, 2026-10-30, branch `claude/slim`. The working tree had uncommitted UI edits by others; none were in the files below. `lib/services/windows_shell.dart` is untracked work in progress, so it is mentioned only where it uses the player.

**Ownership:**
- "fork" means the file is missing from `origin/main`.
- "upstream (+N/-M)" means an upstream file with the fork's diff against `origin/main` (the merge base equals `origin/main` today).
- "upstream (=)" means identical to upstream.

Line numbers are from this checkout and will drift.

**Files covered in depth:**
- `audio_player_service.dart`, `_audio_player.dart`, `desktop_audio*.dart`
- `sleep_timer_service.dart`, `sleep_timer_tick_policy.dart`, `equalizer_service.dart`
- `chromecast_service.dart` (+ `_stub`), `android_auto_service.dart`, `carplay_service.dart`
- `playback_history_service.dart`, `playback_error_policy.dart`, `cold_start_play_policy.dart`, `now_playing_layout.dart`
- `wear_player_service.dart`, `wear_auth_service.dart`
- The playback-facing parts of `home_widget_service.dart`
- The vendored `packages/audio_service_win`, plus the artwork path in `packages/audio_service`

**Skimmed:**
- `bookmark_preview_player.dart`, `native_ios_audio_player.dart` (iOS-only)
- `session_cache.dart` and `local_session_service.dart` (both covered by audit 02)
- `narration_stream.dart`, `remote_audio_slice.dart`, `audio_locator.dart`, `queue_download_policy.dart`, `external_audio_output_types.dart`, `chapter_lookup.dart`

**Not covered (other areas):** `progress_sync_service.dart` (02), `download_service.dart` (03), and the player widgets (07).

---

## PART 1: Code map

### 1.1 Per-file map

#### `lib/services/audio_player_service.dart`: upstream (+80/-13), 8,383 lines
It holds two classes. Most of the app talks to the second one.

**`AudioPlayerHandler extends BaseAudioHandler` (:50-1375)**
- The OS media-session side: notification, lock screen, Android Auto, Wear, Windows SMTC and Linux MPRIS, all through `audio_service`.
- It owns the only `AudioPlayer` (`_player`, :51; `final`, never recreated).
- **Key members:**
  - `_subscribePlaybackEvents` (:271) forwards `playbackEventStream` → `playbackState`, throttled to state changes or 5 s.
  - `_transformEvent` (:363) builds the `PlaybackState`: controls, speed badge, lock-seek, chapter-relative position.
  - `play`/`pause`/`seek`/`stop` (:504/538/580/597) route to the service.
  - `fastForward`/`rewind` (:642/659) use the per-library skip amounts. `skipToNext`/`skipToPrevious` are just ±skip.
  - `click` (:774) is the Android headset multi-press resolver: 400 ms debounce, plus car / other-audio / sleep-snooze rules and `[AbsorbDiag]` logging.
  - `customAction` (:1047) handles the speed cycle and bookmark.
  - `getChildren`/`search`/`playFromMediaId` (:1155-1375) form the Android Auto browse tree; it delegates to `AndroidAutoService` (field `_autoService`, :1152).
- **Android-only diagnostics:** `_absorbDiagChannel` (`com.absorb.audio_diag`, :95). Upstream says "strip once #243 is closed".

**`AudioPlayerService extends ChangeNotifier` (:1377-8383)**
- An app-wide singleton (`factory` → `_instance`).
- **Static hooks**, set by LibraryProvider and main:
  - `setOnBookFinishedCallback` :1394
  - `setOnPeekNextItemCallback` :1406
  - `setOnAutoQueueAdvancedCallback` :1417
  - `setOnPlayStartedCallback` :1448
  - `setOnEpisodePlayStartedCallback` :1457
  - `setOnPlaybackStateChangedCallback` :1464
  - `onColdStartPlayRequested` :1475
  - `onAppPlay` :1392
  - `drainPendingBookFinished` :1421
- **`init()` (:2956):**
  - Calls `initializeDesktopAudio()` first (fork), then `AudioService.init`.
  - Binds the handler to the service.
  - Wires the EQ appliers (Android skip-silence; iOS tap).
  - Caches the skip / notification settings.
  - Configures the streaming cache.
  - Subscribes `PlayerSettings.settingsChanged` → `_onSettingsChanged` (:1669).
  - Calls `_configureAudioSession` (:3140).
  - main.dart:877 caps the whole thing at 8 s.
- **Starting an item:** `playItem` (:3655) is the single entry point (35 call sites across 59 files). It picks one path:
  - narrated EPUB stream → `_playFromLocal(…, stream)` (:3871)
  - downloaded → `_playFromLocal` (:4329)
  - cached session raced against a fresh one (700 ms, or 2 s from UI) → `_playFromServer` (:4999) or `_playFromSessionCache` (:4718) + `_refreshServerSession` (:4910)
  - plain stream → `_playFromServer`
- **Transport:**
  - `play`/`_playNow` (:7357/7382) handles cold-start restore, the dead-session rebuild, long-pause rebuild (Android), auto-rewind, sleep-rewind undo, the server-position check (UI only) and idle re-init.
  - `pause` (:7947) saves, syncs, does a source swap if one is pending, and arms the 10-min `_pauseStopTimer`, which closes the server session.
  - `stop` (:8274), `stopWithoutSaving` (:8351).
  - `seekTo` (:8061), `skipForward/Backward` (:8116/8136), `skipToNext/PreviousChapter` (:8187/8211), `setSpeed` (:8233), `sleepTimerRewind` (:8091).
- **Position:**
  - The `position` getter (:2721) adds `_trackStartOffsets[_currentTrackIndex]` and returns the pending seek target while a new item loads.
  - `absolutePositionStream` (:2741) returns a **new mapped stream per call**.
  - `positionStream` (:2713) is the raw track-relative stream.
- **Recovery:**
  - `_attemptStreamRetry` (:6119): ≤3 retries with backoff, and it clears `SessionCache`.
  - `_retryWithTranscode` (:5428), `_recoverLocalPlayback` (:5399).
  - `_applyPendingSessionUpgrade` (:5988) swaps the source to tokenless session URLs at a pause or seek.
  - `_applyPendingLocalSwap` (:4134) swaps a stream to a finished download.
  - `_rebuildSourceOnDeadSession` (:7834), `_recoverSession` (:7267), `_resumeServerSync` (:7905).
- **Queue pre-buffer:**
  - About 15 s before the end, `_maybePreloadNextBook` (:1968) asks LibraryProvider for the next single-file item.
  - It appends the item to the live `ConcatenatingAudioSource` (Android and desktop) or calls `setNextSource` (iOS).
  - `_onAutoQueueAdvanced` (:2185) promotes the metadata.
  - `_finalizeAndroidAutoAdvance` (:2276) drops the old tracks and seeks.
- **Media item text:**
  - `_pushMediaItem` (:5627) → `_updateNotificationMediaItem` (:5861), with `NowPlayingLayout`.
  - Cover art is a `content://<pkg>.covers/cover/<id>` URI on **every non-iOS platform** (:5670). See finding B5.
- **iOS-only (unreachable in this fork, kept to avoid merge conflicts):** about 500 lines in total:
  - `_primeNativeQueueAdvancer` :2122, `_iosAutoAdvanceKick` :2309, `_iosForegroundResyncIfNeeded` :2340, `reassertIosClaimWhilePaused` :2406, `adoptBackgroundEngineIfRunning` :2442, `_iosReconcileEngineOnForeground` :2504, `_primeNowPlaying` :2578
  - `_pushIosSkipIntervals` :1734, the memory helpers :3433-3522, stuck detection / play verify :6682-6790, iOS last-track guard :6822
- **Important state and its lifecycle:**
  - **`_playbackGeneration` (:7088)** is bumped only by `playItem` (:3712) and `_retryWithTranscode` (:5448). Every start path checks `_startSuperseded(gen)` after each await and backs out through `_abandonStart` (:7100), which closes the session it opened. Fork addition: `_dropStaleSession` (:7113) does the same for background session re-creates.
  - **Subscriptions:**
    - `_syncSub` (position tick: local save every 5 s, accrual, server sync every 20 s, chapter change, completion fallback)
    - `_completionSub` (processingState)
    - `_indexSub` (track index)
    - `_nativeAutoAdvanceSub`
    - All are created in `_setupSync` (:6237) and `_subscribeTrackIndex` (:2803), and cancelled in `_clearState` (:5912) and at the top of `playItem`.
  - **Timers:**
    - `_bgSaveTimer` (300 s periodic, only while playing; created in two places, :6261 and :7693)
    - `_pauseStopTimer` (10 min)
    - `_coverRepushTimer` (3 s one-shot)
    - `_advanceBufferingBackstop` (30 s, Android)
    - `_duckWatchdogTimer` (4 s, static)
    - `_stuckCheckTimer` / `_playVerifyTimer` (iOS)
  - **Audio-session subscriptions** (static `_interruptSub`, `_noisySub`, `_devicesSub`) are re-created on every `_configureAudioSession()` call, which is once per item start.
  - **`notifyListeners`** fires 28 times in the file: on start, state changes and seeks. It **never fires on position ticks.** UIs that show position must use `absolutePositionStream`. That's a trap for the new `windows_shell.dart` `_AppPlayback.progress`, which only refreshes on notify.
- **Platform differences:**
  - **Android:**
    - `click` resolver; becomingNoisy / devices-changed pause.
    - Duck handling, Dolby → transcode (non-Samsung, :5074).
    - `stop()` on completion (:6910); `pause()` elsewhere.
    - Long-pause rebuild (:7489).
    - EQ session attach (:6203).
  - **Windows/Linux:**
    - The `_audio_player.dart` desktop shims: load then seek; reload on a cross-file seek.
    - SMTC via `packages/audio_service_win` (fork): play, pause, next and previous only; no stop, no timeline. MPRIS via `audio_service_mpris`.
  - **Web:** just_audio_web plus audio_service_web. `Platform` comes from `utils/web_safe_platform.dart` (fork).
- **Traps:**
  - Never `await` a `seek` on Android without `_seekCap` (:2873): end-of-file seeks never answer (GH #428).
  - Every new await inside a start path needs a `_startSuperseded(gen)` check after it (GH #391).
  - `_pushMediaItem` must run *after* `setSpeed`: the pushed duration is speed-adjusted.
  - Don't read `_currentEpisodeId` after an await in a start path. Snapshot it first (see :5021).
  - `_clearState` does **not** reset `_chapters`. Callers do that, because a retry needs the chapters.

#### `lib/services/_audio_player.dart`: upstream (+33/-4), 194 lines
- **Purpose:** a platform-switching `AudioPlayer` wrapper: `NativeIosAudioPlayer` on iOS (dead in this fork), `just_audio` everywhere else. It re-exports the just_audio types.
- **Fork shims for libmpv (`_isDesktop`, :44):**
  - `setAudioSource` (:93) pauses, loads, *then* seeks to `initialPosition`, then resumes. Reason: media_kit drops a seek sent before the file is ready.
  - `seek(index:)` (:153) reloads the whole source at the new index when the index changes. Reason: `media_kit.jump` resolves before the file loads.
- **Trap:** a cross-file seek on desktop re-opens the whole playlist. On books with hundreds of files that can exceed the service's 6 s `_seekCap`. The seek then "times out" but still completes later.

#### `lib/services/desktop_audio.dart` / `_native.dart` / `_stub.dart`: fork, 2 / 14 / 1 lines
- A conditional export. `initializeDesktopAudio()` calls `JustAudioMediaKit.ensureInitialized(windows: true, linux: true)` once and sets the title to "Absorb Plus".
- It must run before any `ja.AudioPlayer` is constructed. `AudioPlayerService.init` does that (:2966).
- The sleep-timer chime (`ja.AudioPlayer()`, sleep_timer_service.dart:694) and `BookmarkPreviewPlayer` rely on init having run first.
- Smoke test: `tool/desktop_audio_smoke.dart` / `tool/verify-desktop-audio.ps1`.

#### `lib/services/sleep_timer_service.dart`: upstream (+19), 948 lines
- **Purpose:** an app-wide singleton for time, chapter and episode sleep, auto-sleep windows, shake-to-extend, fade, chime, the media-button snooze, and the sleep rewind with a 5-min undo.
- **Key members:**
  - `setTimeSleep` (:186; an `async void`)
  - `_onTimerTick` (:247): 1 s ticks in the foreground or near the fade, 5 s in the background
  - `_onPlayerChanged` (:216): resume reset, a player listener
  - `setChapterSleep` (:362) / `_startChapterMonitor` (:412): position-based trigger, cancelled when another item plays (fork, :419)
  - `setEpisodeSleep` (:465)
  - `_triggerSleep` (:574): pauses, restores the volume, rewinds
  - `takeSleepRewindUndo` (:616), called by `_playNow`
  - `cancel` (:651), `checkAutoSleep` (:806), `_scheduleWindowBoundary` (:849)
  - `_startShakeDetection` (:721): `sensors_plus` at 100 ms
  - `onAppBackgrounded/Foregrounded` (:915/929), called from app_shell
- **Callers:**
  - `AudioPlayerService`: `resetDismiss`, `checkAutoSleep`, `cancel`
  - Handler `click`: `snoozeFromMediaButton`
  - `sleep_timer_sheet.dart`, `WearCommands`, `ChromecastService` (via the `isCastEngaged` checks)
- **Platform:** the shake stream has no Windows or Linux implementation. The error is caught in `onError` and logged, and the stream is opened anyway whenever a timer starts.

#### `lib/services/sleep_timer_tick_policy.dart`: upstream (=), 15 lines
A pure tick decision (wait / countDown / trigger). It has no test.

#### `lib/services/equalizer_service.dart`: upstream (=), 492 lines
- **Purpose:** EQ bands, bass boost, virtualizer, loudness, mono and skip-silence, stored globally or per item, through `MethodChannel('com.absorb.equalizer')` (:13).
- **Platform:** the channel exists **only on Android** (MainActivity.kt). On Windows, Linux and web, `init` (:76) falls back to `_setupSoftwareFallback` (:112), which sets `_available = true` and 5 fake bands. **No software processing exists**, so the sheet is a placebo there (finding B6).
- **Key members:** `attachToSession` (:256, Android audio session id), `switchItem` (:319, called by every start path), `reloadForActiveAccount` (:452, auth_provider).
- **Duplicates:** the same channel name is also declared twice in audio_player_service (`_eqChannel` :3115, `_eqChannelForDiag` :1950).

#### `lib/services/chromecast_service.dart`: upstream (+1/-1), 1,228 lines (+ `chromecast_service_stub.dart`, 88, swapped in by `fdroid/com.barnabas.absorb.yml`)
- **Purpose:** an app-wide singleton for Google Cast.
- **Key members:**
  - `init` (:141; main.dart calls it **only on Android**, :905)
  - session listener (:178), with a 5 s disconnect grace and a backstop reconnect (`_beginReconnectOrWipe` :245)
  - `castItem` (:589; stops the local player with `keepSleepTimer: true`)
  - `_listenToPosition` (:497): queue/fallback offset translation, plus a 15 s `_syncTimer`
  - `_saveProgressLocal` (:1137), `_syncProgressToServer` (:1144), `stopCasting` (:1046)
- **Callers:** `AudioPlayerService.playItem` (skips while casting) and `seekTo`, `SleepTimerService`, the card buttons, `absorbing_card`.
- **Platform:**
  - `castSupported` is `true` on every platform. Only F-Droid swaps in the stub.
  - The vendored `packages/flutter_chrome_cast` picks its implementation with `dart:io Platform.isAndroid ? Android : iOS` (`_discovery_manager/discovery_manager.dart`). So on Windows and Linux it uses the iOS channel, and on web `Platform` throws (finding B7).

#### `lib/services/android_auto_service.dart`: upstream (+2/-1), 2,097 lines
- **Purpose:** the Android Auto browse tree. It holds:
  - `AutoMediaIds` (:44, the id grammar)
  - `refresh` (:391): downloads first, then the server in the background
  - `_refreshFromServer` (:632): `getLibraries` + a personalized view per library + recent episodes per podcast library, through its **own** `ApiService` from prefs (`getApi` :326)
  - `getChildrenOf` (:1012) with `_childrenCache` and in-flight dedupe
  - sorted / bucketed library listing (:1464+)
- **Lifecycle:**
  - It is constructed on **every platform** at handler creation (`_autoService` field, audio_player_service.dart:1152). The constructor adds a `DownloadService` listener (:231).
  - `refresh(force: true)` is called **unguarded** from `library_provider.dart:516/540` (library switch), `_lp_core.dart:419/445` (offline ↔ online) and `app_shell.dart:805` (resume). Only main.dart:921 is Android-guarded (finding P1).

#### `lib/services/carplay_service.dart`: fork override, 20 lines
A no-op stub kept so upstream call sites compile. It's listed in `tool/fork-overrides.txt`. Keep it.

#### `lib/services/playback_history_service.dart`: upstream (=), 193 lines
- **Purpose:** a per-book event log (play, pause, seek, sync, …) stored as a JSON string list in `ScopedPrefs` under `playback_history_<itemId>`, capped at 1000 entries per book.
- It is written by `AudioPlayerService._logEvent` (:1850, which doesn't await it) and read by the history sheet (card_buttons.dart).
- It is never pruned across books. Only `clearHistory` (card_buttons.dart:2662) removes it (finding P2).

#### Small policy / helper files (all upstream (=), no tests)
| File | Lines | Purpose |
|---|---|---|
| `playback_error_policy.dart` | 29 | `isSourceError`, `shouldRetryWithTranscode`: string matching on the error text |
| `cold_start_play_policy.dart` | 52 | Decides what `play()` does with no item loaded (restore last played / nothing) |
| `now_playing_layout.dart` | 137 | `NowPlayingPiece` and the two-line media-controls text builder |
| `external_audio_output_types.dart` | 16 | Which removed outputs pause playback (Android devices-changed) |
| `session_cache.dart` | 109 | Per-item cached session (tracks, chapters) for instant start (see audit 02) |
| `chapter_lookup.dart` | 81 | Pure chapter index / next-skip-target lookup |

#### `lib/services/wear_player_service.dart` (200) / `wear_auth_service.dart` (66): upstream (=)
- Wear OS bridges, no-ops unless Android (`!kIsWeb && Platform.isAndroid`, short-circuit, so web-safe).
- Player state is published from `HomeWidgetService` (:900); watch commands come back through `WearCommands.handle` (:145).

#### `lib/services/home_widget_service.dart`: upstream, 1,524 lines (playback parts only)
- Android/iOS home widget and Wear publishing. `init()` only runs on Android/iOS (main.dart:927).
- `AudioPlayerService` still calls `addLocalListeningSeconds` (:1198; every 20 s while streaming) and `getStashedNowPlayingPosition` (:256; guarded) on all platforms.

#### `packages/audio_service_win`: fork (vendored and patched, see `PATCHES.md`), 118 Dart + about 450 C++ lines
- The Windows SMTC backend for `audio_service`.
- Supports: play, pause, next, previous; title, artist, album; artwork from `http(s)` or a file path.
- Not supported: stop (not enabled), timeline and scrubbing, queue.
- `setState` sends only playing / paused.

### 1.2 End-to-end flow (streamed book; downloaded differences in brackets)
1. **UI → `playItem`.** A card / Home / Android Auto (`_playFromAutoMediaId` :1238) / widget / cold-start restore calls `AudioPlayerService().playItem(api:, itemId:, …)`.
2. **`playItem` (:3655):**
   1. Bumps `_playbackGeneration`, pauses the old audio, normalizes the episode title.
   2. Finalizes the old local session if the item changed (fork, :3734).
   3. Sets the `_current*` state and runs `_onPlayStartedCallback` (rolling downloads).
   4. Picks the start position: max(caller, local progress, widget stash; iOS engine).
   5. Cancels the old subscriptions.
3. **Session.** `api.startPlaybackSession` (raced against `SessionCache`, :3938-4018) returns the session id and audio tracks. Then:
   - Dolby check → transcode (:5074)
   - `_buildTrackOffsets` (:2757)
   - one `AudioSource.uri` per track (URL from `api.buildTrackUrl`, tokenless `/public/session/<id>/track/<i>` when possible)
   - `ConcatenatingAudioSource`
   - [Downloaded: `localAudioSource(path)` per file; `LocalSessionService().beginSession` (:4639) instead of a server session.]
4. **Load.** `_configureAudioSession` → `setActive(true)` → `setAudioSource` (desktop: load-then-seek shim) → `_seekForStart` (:2848, which re-seeks if stalled) → `_subscribeTrackIndex` → `setSpeed` → `_pushMediaItem` → `EqualizerService().switchItem` → 200 ms wait → `play()` → `_setupSync()` → `SessionCache.save`.
5. **Position stream (`_syncSub`, :6318), on every tick (about 5 Hz on long books):**
   - end → 0 jump guard
   - pre-buffer check
   - chapter change (once a second) → `_pushMediaItem` + `refreshPlaybackState`
   - ticker repush
   - completion fallback
   - every 5 s: `_saveProgressLocal` (prefs) and `_accrueListening` (:7134; streaming-pending, offline ledger or local session)
   - every 20 s: `_syncToServer` (:7176) → `api.syncPlaybackSession` (+ `_logEvent(syncServer)`), or session re-create (:6555), or a no-session `progressSync.syncToServer`
6. **Media session.** `playbackEventStream` → handler `playbackState` (≤ every 5 s or on change) → audio_service → Android notification / AA / SMTC / MPRIS.
7. **Pause (:7947).** Save locally → accrue → `_syncToServer` (or the local-session push) → a pending source swap if any → arm the 10-min `_pauseStopTimer`, which closes the session.
8. **Completion.** `processingState == completed` (:6292), the position fallback (:6505) or the end → 0 guard leads to `_onPlaybackComplete` (:6802):
   - a spurious-completion guard
   - `markFinished` / `updateEpisodeProgress` (fire and forget)
   - local `saveLocal(isFinished)`
   - close the session [finalize the local session]
   - `_onBookFinishedCallback` → LibraryProvider auto-advance → the next `playItem`
   - [With a pre-buffered next item, `_onAutoQueueAdvanced` promotes it in place instead.]
9. **Stop (:8274).** Save, accrue, sync, close the session [push and finalize the local session], `player.stop()`, `_clearState`, cancel sleep, `setActive(false)`.

---

## PART 2: Findings

Confidence: **H** means verified in the code path end to end; **M** means verified in code but it depends on plugin or runtime behavior I didn't execute; **L** means plausible, needs a repro.
Recent fixes not re-reported: stale state leaking into the next book (a14d231c), the web-safe Platform change (61554b8c), the media-state throttle (6a883661).

### Bugs

**B1. Stop or sign-out during a load lets the old start play anyway.** Wrong behavior; medium-high confidence (H on logic). File: `audio_player_service.dart:8274` (`stop`), :8351 (`stopWithoutSaving`).
- **Cause:** `stop()` clears state but never bumps `_playbackGeneration`, so `_startSuperseded(gen)` stays false for an in-flight `playItem`.
- **Trigger:** press stop, or sign out / switch account (`auth_provider.dart:1405/1502` call `pause()` + `stop()` when `hasBook`, which is already true during load), while the start is still waiting on the session POST, prefs, or the 700 ms–2 s race.
- **What happens next:** the start then:
  - assigns `_playbackSessionId`
  - loads the source
  - calls `_pushMediaItem` and `_player.play()`
  - runs `_setupSync()` with `_currentItemId == null`
- **Result:** audio plays with no item in the UI (`hasBook` false); progress is never saved; the server session stays open. After a sign-out it's the previous account's book.
- **Other timing:** if the stop lands inside `setAudioSource`, the load is interrupted instead and the user gets "Playback failed: …".
- **Fix:** `_playbackGeneration++` at the top of `stop()` and `stopWithoutSaving()`. The existing `_abandonStart` paths then back out and close the session. Upstream file, about 2 lines.

**B2. Casting a podcast episode saves and reads progress under the show id.** Wrong behavior; high confidence. File: `chromecast_service.dart:622` and :1141.
- `castItem` reads `getSavedPosition(itemId)`, and `_saveProgressLocal` saves under `_castingItemId`.
- Everywhere else, including the completion path at :1103 and the server fallback at :1164, uses `'$itemId-$episodeId'`.
- **Effect:**
  - Casting an episode starts at the show-level key's position, which is whatever was last cast.
  - The episode's own local progress isn't updated while casting, and the show-level key gets polluted.
- **Fix:** build the compound key in both places. Upstream file, 2 lines. Worth reporting upstream (ask the owner first).

**B3. Queue pre-buffer auto-advance leaks the previous item's mode.** Wrong behavior; medium confidence. File: `audio_player_service.dart:2185-2269`.
- **Missing resets:** `_onAutoQueueAdvanced` promotes the next item's metadata but leaves `_localSessionMode`, `_isOfflineMode` and `_shortLocalDurationSec` alone. It starts no `LocalSessionService` session and applies no per-book speed or EQ.
- **When it applies:** Android, Windows and Linux (non-iOS path :2090) in manual queue mode with a single-file next item. `peekNextQueueItemForPreBuffer` (`_lp_absorbing.dart:2038`) returns downloaded *or* streamed items regardless of the current mode.
- **Downloaded → next item:** `accrue` sees a key mismatch, finalizes the old session, then skips every later tick (`_active == null`). **The next book's listening time is lost.** Progress still syncs through the no-session path.
- **Streamed → downloaded next item:**
  - The 20 s tick re-creates a `/play` session.
  - `_stashSessionUpgrade` then makes the next seek or pause **swap the playing local file to stream URLs** (`_applyPendingSessionUpgrade` only refuses in local or offline mode).
- **Truncated download → next item:** the old `_shortLocalDurationSec` still clamps seeks in the new book.
- **Fix (M):** in `_onAutoQueueAdvanced`:
  - reset `_shortLocalDurationSec = null`
  - set `_localSessionMode = next['localPaths'] != null`
  - finalize and begin local sessions the way `playItem` does (:3734, :4639)
  - apply `getBookSpeed` and `EqualizerService().switchItem`

**B4. `_subscribePlaybackEvents` leaks a listener on every non-source error.** Minor; medium-high confidence. File: `audio_player_service.dart:271-345`.
- The `listen()` result is never stored or cancelled. On error (`cancelOnError` is false, so the old subscription survives) it calls `_subscribePlaybackEvents` again after 1 s.
- Each error adds up to 3 listeners, and `_resubscribeCount` is shared and reset by every good event.
- **Effect:** duplicate `onError` handling: `_attemptStreamRetry` and `_retryWithTranscode` are called N times. Their in-flight flags mask most of it.
- **Fix:** keep a `StreamSubscription? _eventSub`, cancel it before resubscribing. Upstream, S.

**B5. Windows SMTC and Linux MPRIS never get cover art.** Minor (UX); medium-high confidence. File: `audio_player_service.dart:5658-5677`.
- The non-iOS branch always sends `content://<pkg>.covers/cover/<id>`. That's an Android ContentProvider.
- `audio_service` passes `content:` URIs through untouched (`packages/audio_service/lib/audio_service.dart:1038`).
- `audio_service_win_plugin.cpp:321-332` only handles http(s) or a file path, so `GetFileFromPathAsync("content://…")` fails and is caught. MPRIS clients can't resolve it either.
- The 3 s cache-bust repush (:5837) repeats the same URI.
- **Fix:**
  - Use `content://` only when `Platform.isAndroid`.
  - Desktop: `Uri.file(localCover)` when downloaded, else `coverUrl` (http, which audio_service caches to a file).
- Verify visually in the Windows media flyout.

**B6. The Equalizer button and sheet do nothing on Windows, Linux and web.** Wrong behavior (UX); high confidence.
- There is no `com.absorb.equalizer` implementation outside Android, and `_setupSoftwareFallback` (equalizer_service.dart:112) exposes 5 bands that nothing applies.
- `'equalizer'` is in `PlayerSettings.defaultButtonOrder` (player_settings.dart:1281) and is not filtered in `card_button_config.dart:60` `_hiddenButtons`.
- **Fix:** add `if (kIsWeb || !Platform.isAndroid) 'equalizer'` to `_hiddenButtons`. Upstream file, 1 line, low merge risk. Alternatively, a fork hook.

**B7. The Cast button is shown on Windows, Linux and web, where cast can't work.** Wrong behavior; medium confidence.
- `ChromecastService.castSupported` is a `const true`, and `init()` only runs on Android.
- On Windows and Linux, `devicesStream` uses the vendored package's iOS method channel (`discovery_manager.dart`: `Platform.isAndroid ? Android : iOS`), so the list stays empty or throws `MissingPluginException`.
- On web, `dart:io Platform.isAndroid` throws `UnsupportedError` when the sheet builds.
- **Fix:** hide `'cast'` in `_hiddenButtons` unless Android (the same line as B6).

**B8. `_playerBroken` survives into the next book.** Minor; high confidence. File: `audio_player_service.dart:5392`.
- It is set when a local decoder fails while paused (:5409, :7747) and cleared only inside `_playNow`'s rebuild (:7603). Neither `playItem` nor `_clearState` resets it.
- If the user then starts another book, its first resume after a pause triggers an unneeded rebuild, which restarts the item through `playItem` and opens a new session.
- **Fix:** `_playerBroken = false;` in `playItem` next to `_pauseRequested = false` (:3680).

**B9. `_retryWithTranscode` early returns leave half-cleared state.** Minor; medium confidence. File: :5476 and :5492.
- After `_clearState()` plus restoring the ids, a `null` session or empty tracks just `return`. The player keeps the failed source, there's no sync or completion subscription, and nothing tells the user.
- It also skips the following, unlike `_playFromServer`:
  - `_resetPreBufferState()`, so `_activeConcatSource` still points at the failed source and a later pre-buffer appends to the wrong concat
  - `updateChaptersQueue`
  - `_captureStreamUrls`
- **Fix:** route through `_playFromServer(forceTranscode: true, generation: gen)` instead of the hand-rolled copy.

**B10. Sleep chime can leave the book at 15% volume.** Minor; medium confidence. File: `sleep_timer_service.dart:690-716`.
- The main volume is ducked and restored only when `playerStateStream.where(completed).first` completes. If the chime errors or never completes, the restore never runs and the error is unhandled.
- `cancel()` and `_triggerSleep()` restore `_fadeStartVolume` only when a fade was running.
- **Fix:** add `.timeout()` / `catchError` that restores `prevVol`.

**B11. `setTimeSleep` race leaves a 1 Hz periodic timer running.** Minor; medium confidence. File: `sleep_timer_service.dart:186`.
- `async void`: after `cancel()` it awaits prefs. If chapter or episode sleep is set meanwhile, `_startTimeCountdown()` still starts the periodic `_timer`. It no-ops on every tick (`_mode != time`) until the next `cancel()`.
- **Fix:** re-check `_mode == SleepTimerMode.time` after the await.

**B12. Minor robustness gaps (low severity, H on code):**
- **`_attemptStreamRetry` (:6119)** has no try/finally around `playItem`. If it throws, `_retryInProgress` stays true until the next `_clearState`.
- **`_onPlaybackComplete` (:6802)** has no try/finally. A throw in `saveLocal` or `stop` leaves `_isCompletingBook = true` until the next `playItem` (:3867), so completions are ignored.
- **`AudioPlayerHandler.stop()` (:597)** calls `_player.stop()` directly: no save, no session close, and the service still thinks the item is loaded. Stop isn't advertised in `PlaybackState` or SMTC, so this only bites if some client sends it anyway.
- **The idle re-init `playItem(...)` (:7654)** isn't awaited and its error string is dropped, so the user sees no message if the re-init fails.
- **The `stopWithoutSaving` (:8351)** path doesn't cancel `_pauseStopTimer`. Harmless today: it only cancels an active sleep timer 10 min later, while nothing is playing locally.

### Dead code

| Item | Where | Owner | Remove? |
|---|---|---|---|
| `_eqSessionSub` field (never assigned non-null) | audio_player_service.dart:6201, cancelled at :6204, :5946 | upstream | Only if touching nearby; trivial |
| `AudioPlayerService.durationStream` getter (no callers) | :2715 | upstream | Not worth the merge cost |
| `AudioPlayerService.isOfflineMode` getter (no callers) | :1946 | upstream | Not worth it |
| `AudioPlayer.jaPlayer`, `.bufferedPositionStream`, `.setAsset` (no callers; the chime uses `ja.AudioPlayer.setAsset` directly) | _audio_player.dart:48, :74, :177 | upstream (fork-modified file) | Could go with the next fork edit of this file |
| `AudioPlayerService.dispose()` / `SleepTimerService.dispose()`: singletons never disposed; the service `dispose` also skips `_completionSub`/`_coverRepushTimer` | :8372, sleep:942 | upstream | Leave |
| iOS-only engine paths (about 500 lines, listed in 1.1) + `native_ios_audio_player.dart` (431) + `siri_service.dart` (749) / `siri_matcher.dart` (397) | various | upstream | **No.** About 2,000 lines, but every upstream iOS fix would conflict. If ever wanted: add `native_ios_audio_player.dart` to `tool/fork-removed-paths.txt` with a stub, like CarPlay. Medium effort; only worthwhile if upstream stops touching iOS. |
| `[AbsorbDiag]` channel + `[PlayItemEntry]` stack dump (:3697, "strip before next beta") + `[Handler] stop() trace` (:612) + `[PodDur]` per push (:5641) | audio_player_service | upstream | Upstream's call; keep for merge parity |
| `chromecast_service_stub.dart` | services | upstream | **Not dead.** F-Droid build swaps it in. |

### Duplication worth knowing (consolidate only in fork code or when upstream does)
- **Four copies of the "build source → load → seek → push → EQ → play → `_setupSync`" sequence:** `_playFromLocal` :4500-4658, `_playFromSessionCache` :4775-4880, `_playFromServer` :5228-5345, `_retryWithTranscode` :5486-5566. They have already drifted (B9). Upstream-owned and about 300 lines, so don't refactor here. Just fix B9 by reusing `_playFromServer`.
- **Four copies of "start (episode) session → `_dropStaleSession` → adopt → stash upgrade":** sync tick :6555-6602, `_recoverSession` :7267, `_rebuildSourceOnDeadSession` :7834, `_resumeServerSync` :7905. There are 18 `start*PlaybackSession` call sites in the file.
- **The progress key** `'$_currentItemId-$_currentEpisodeId'` is rebuilt inline 12 times, although `_mediaItemKey` (:3648) and `playbackDownloadKey` (:45) exist. The same pattern caused B2 in cast.
- **The `manual_offline_mode` pref** is read in 11 places.
- **The `_bgSaveTimer` body** is duplicated (:6261, :7693).
- **Two seek-target trackers:** `_lastSeekTargetSeconds/_lastSeekTime` (UI snap, :1823) vs `_lastSeekTargetSec/_lastSeekAt` (retry and guards, :1600).
- **Linear chapter scans** in the sync tick (:6396), `currentChapter` (:8263), `_initChapterInfo`, `skipBackward` (:8149), `skipToPreviousChapter`, `SleepTimerService._getCurrentChapterIndex` (:517) and `ChromecastService.currentChapter`, although `ChapterLookup` exists.
- **`MethodChannel('com.absorb.equalizer')`** is declared 3 times.

### Performance
- **P1. Android Auto browse refresh runs on Windows, Linux and web.** Medium impact (network and server).
  - `AndroidAutoService().refresh(force: true)` is unguarded at library switch, offline ↔ online transitions and app resume (cooldown-gated).
  - Each call means `getLibraries` + 1 personalized view per library + 1 recent-episodes call per podcast library, through a second `ApiService`, for a browse tree nothing on desktop reads.
  - The singleton is also constructed on every platform (handler field), with a `DownloadService` listener that rebuilds a signature string of all downloads on each notify.
  - **Fix:** `if (kIsWeb || !Platform.isAndroid) return;` at the top of `refresh()` (android_auto_service.dart:391). Upstream, 1 line. Check `siri_service` isn't needed (it's iOS-only).
- **P2. Prefs writes during playback.** Impact unknown; measure with `/perf-measure` before acting.
  - `_saveProgressLocal` writes `progress_<key>` every 5 s.
  - `_logEvent(syncServer)` rewrites the up-to-1000-entry history list every 20 s, plus one write per seek or skip.
  - On Windows and Linux, `shared_preferences` rewrites the **whole** prefs JSON file per set, and the history keys are never pruned across books, so that file only grows.
  - `_logEvent` isn't awaited, so two events close together can race read-modify-write and drop one (minor).
  - **Options:** don't log `syncServer` (it's an "advanced" event anyway); prune old `playback_history_*`. Upstream files.
- **P3. Debug logging volume.** 341 `debugPrint`s in the file, including a full `StackTrace.current` on every `playItem` and `Handler.stop`. When file logging is on, each one is a synchronous file append on the UI isolate (log_service.dart:92). Low impact, unless the user leaves logging on.
- **P4. Fixed 200 ms sleep before `play()`** in every start path (:4628, :5319, …). It adds start latency on desktop where it isn't needed (the reason given is iOS/Android session activation). Low.
- **P5. `absolutePositionStream` returns a new mapped stream per call.** `absorbing_card.dart:792` creates it inside `build`, so every rebuild unsubscribes and resubscribes the `StreamBuilder`. Low. A cached `late final` broadcast stream in the service would fix all callers.
- **P6. Desktop cross-file seek reloads the whole playlist** (`_audio_player.dart:153`). That's by design for media_kit, but on many-file books it can be multi-second and hits the 6 s `_seekCap`. Measure on a large multi-file book.
- **Not a problem:**
  - Steady playback triggers no `notifyListeners`.
  - The tick handler is cheap (one string per tick).
  - `_bgSaveTimer` and `_stuckCheckTimer` stop on pause.
  - `_attachEqualizer` schedules 2 harmless delayed lookups on non-Android.
  - `addLocalListeningSeconds` (home_widget_service.dart:1198) hits a missing `home_widget` channel every 20 s on desktop and web: one caught exception and a log line each time. Trivial, but guard it if touching that file.

### Risky patterns
- **Fire-and-forget futures with partial handling:** `_attemptStreamRetry(e)` from the stream `onError` callbacks (:298, :6315, :6673); `playItem` at :7654. Errors inside are mostly caught, but results are dropped.
- **Recursive resubscribe on error with no backoff:** `_configureAudioSession` from the audio-session `onError` callbacks (:3316, :3344, :3410). A stream that errors on subscribe would loop. L.
- **`ChromecastService._listenToPosition` / `_listenToMediaStatus`** also resubscribe immediately on error.
- **Shared singletons mutate across awaits.** The fork's generation checks cover the start paths. The background paths (`_resolveMissingLibraryId`, sync tick) re-check `_currentItemId` after the await, so they're fine.
- **Almost no tests for playback.** Only `test/local_session_flush_test.dart` covers anything here; upstream ships no tests. The pure policies are trivial to test with no fakes: `PlaybackErrorPolicy`, `ColdStartPlayPolicy`, `sleepTimerTickAction`, `ChapterLookup`, `NowPlayingLayout`, `AutoMediaIds.parse*`, `AudioPlayerService.calculateAutoRewind`.

### Recommended actions (ranked by value ÷ (effort + merge cost))
| # | Action | Owner | Size | Risk |
|---|---|---|---|---|
| 1 | B1: `_playbackGeneration++` in `stop()` / `stopWithoutSaving()` | upstream (2 lines) | S | Low; needs a test that stop during a fake slow session doesn't play |
| 2 | B6 + B7: hide `equalizer` and `cast` buttons unless Android (`card_button_config.dart` `_hiddenButtons`) | upstream (2 lines) | S | Low |
| 3 | P1: early return in `AndroidAutoService.refresh()` off Android | upstream (1 line) | S | Low |
| 4 | B2: compound episode key in cast save/read | upstream (2 lines) | S | Low; offer upstream PR (ask owner) |
| 5 | B8: reset `_playerBroken` in `playItem` | upstream (1 line) | S | Low |
| 6 | B5: desktop cover art (file / http instead of `content://`) | upstream (~6 lines) | S | Low-medium; verify the SMTC flyout by hand |
| 7 | B4: keep and cancel the playback-event subscription | upstream (~5 lines) | S | Low |
| 8 | Tests for the pure playback policies listed above | fork (new test files) | S | None |
| 9 | B10 / B11: chime volume restore timeout; `setTimeSleep` mode re-check | upstream (~6 lines) | S | Low |
| 10 | B3: correct mode, session, speed and EQ on pre-buffer auto-advance | upstream (~25 lines) | M | Medium (touches playback and stats; owner OK per release rules) |
| 11 | B9: make `_retryWithTranscode` reuse `_playFromServer(forceTranscode)` | upstream (−80 lines) | M | Medium (playback engine) |
| 12 | P2: measure the prefs write cost on Windows; then drop the `syncServer` history log and prune old histories | upstream | M | Low after measuring |
| 13 | Cache `absolutePositionStream` once (P5) | upstream (~5 lines) | S | Low; only matters together with audit 07's repaint work |
| — | Not recommended: deleting iOS engine code / Siri / native iOS player; unifying the 4 start paths | upstream | L | High merge cost |

Items 1, 10 and 11 touch the playback engine. Per CLAUDE.md, a beta containing them needs the owner's OK after a Windows test build.
