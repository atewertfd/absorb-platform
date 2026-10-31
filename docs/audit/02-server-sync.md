# Audit 02: server communication, auth and sync

Read-only audit, 2026-10-30, branch `claude/slim` (working tree had uncommitted UI edits by others; none in the files below).
Ownership: "fork" = the file is missing from `origin/main`; "upstream (+N/-M)" = upstream file with the fork's diff against `origin/main`; "upstream (=)" = identical to upstream.
Line numbers are from this checkout and will drift.

**Files covered in depth:** `api_service.dart` (auth, refresh, request helpers, progress/session endpoints), `auth_tokens.dart`, `scoped_prefs.dart`, `user_account_service.dart`, `server_backend.dart`, `session_cache.dart`, `signed_out_playback.dart`, `progress_sync_service.dart`, `sync_logic.dart`, `local_session_service.dart`, `settings_sync_service.dart`, `socket_service.dart`, `highlight_sync.dart`, `server_health_service.dart`, `update_checker_service.dart`, `update_policy.dart`, `update_check_policy.dart`, `wear_auth_service.dart`, `oidc_service.dart`, `lib/providers/auth_provider.dart` (sign-in side of the flow).
**Skimmed (outline and security-relevant parts only):** `bookorbit_api_service.dart`, `bookorbit_media_proxy.dart`, `bookorbit_notification_socket.dart`, `whats_new_notes.dart`, `setup_link_service.dart`, `rmab_service.dart`, `audiobookshelf_update_service.dart`.
**Not server/sync code (excluded):** `read_listen_sync.dart` and `sync_point_store.dart` are ebook/audio position alignment (local); `bookorbit_mapper/match/admin*.dart`, `book_requests.dart`, `server_notifications.dart` are BookOrbit shape and model code; `upcoming_releases_service.dart` talks to Audible/Audnexus, not the user's server.

---

## PART 1: Code map

### 1.1 Per-file map

#### `lib/services/api_service.dart`: upstream (+121/-45), 5,272 lines
- **Purpose:** the Audiobookshelf REST client, and the base class of `BookOrbitApiService`, which is a `part` file of this library.
- **Construction:**
  - `ApiService(...)` at :316.
  - `ApiService.forSession(...)` at :338 picks the BookOrbit subclass when `backend ?? ServerBackend.active` is BookOrbit.
  - Each instance holds its **own copy** of `_accessToken`/`_refreshToken` (:268-269).
  - `AuthProvider.apiService` (auth_provider.dart:279) builds a **new instance on every call**. There are about 296 `.apiService` call sites.
- **Static state shared by every instance:**
  - `_tokenMutationCompleter` (:295), which serializes refreshes across instances.
  - `_preflightCooldownUntil` (:959).
  - `_apiKeyCheckedAt` / `_apiKeyCheckRunning` (:816).
  - Device info: `deviceId` etc. (:298-301; `initDeviceId` :304).
  - `appVersion` (:234).
  - The server-version cache (:1310).
- **Auth core:**
  - `tokenFp` :677: fork, logs only "present/none".
  - `_getWithNetworkRetry` :683: retries a GET once on timeout or `ClientException`.
  - `_adoptPersistedTokens` :713: reloads prefs through `loadPersistedTokens` and takes a newer pair.
  - `_refreshTokenPairOnce` :782: only used by `changeMyPassword` :1621.
  - `_checkRevokedApiKey` :819: an API key 401 triggers one `/api/me` probe, then `onAuthExpired`.
  - `_refreshAccessToken` :843: per-instance completer plus the static lock. It adopts persisted tokens first, makes up to 2 POST `/auth/refresh` attempts (15 s each, 250 ms apart), and returns `refreshed | rejected | transientFailure`. Only a 401/403 counts as `rejected`.
  - `_ensureFreshAccessToken` :986: pre-flight refresh when the JWT `exp` is within 60 s. After a transient failure it backs off for 2 minutes (static).
  - `_authGet/_authPost/_authPatch/_authDelete` :1015-1100: pre-flight, then send, then refresh and retry once on a 401.
    - A `rejected` refresh calls `onAuthExpired`.
    - A legacy token or API key hitting a 401 calls `_checkRevokedApiKey`.
    - Only GET gets the network retry.
- **Sign-in (static):**
  - `login` :1103 (POST `/login` with `x-return-tokens`, 20 s).
  - `loginWithApiKey` :1154.
  - `pingServer` :1182, `pingServerDetailed`, `getServerVersion` :1258.
  - `authorize` :1486, `getMe` :1502.
  - `revokeServerSession` :1602.
  - `changeMyPassword` :1621.
- **Media URLs:**
  - `buildEbookUrl` :387, `getCoverUrl` :1475, author image :1833 and `buildFileUrl` :2387 all carry **`?token=<access token>`**.
  - `buildTrackUrl` :2324 strips the token for `/public/session/` URLs and adds it otherwise.
- **Progress and sessions:**
  - `startPlaybackSession` :2263.
  - `syncPlaybackSessionStatus` :2409, `closePlaybackSession` :2436.
  - `syncLocalSession` :2451 and `syncLocalSessionsAll` :2479 (POST `/api/session/local[-all]`; 404/501 sets `serverTooOld`).
  - `getItemProgress` :2681.
  - `updateProgress` :2838 and `updateEpisodeProgress` :3084 return `statusCode < 500`.
  - `updateEbookProgress` :2882 uses a **raw `http.patch`**.
  - `getAllProgress` uses `/api/me/progress`, falling back to `/api/me`.
- **Callers:** nearly every provider, screen and service.
- **Traps:**
  - The file is huge, so grep and read windows.
  - BookOrbit overrides the `_auth*` helpers (bookorbit_api_service.dart:847-875) and routes `/api/...` paths to handlers. Unmapped routes answer a synthetic 404.
  - Anything that calls `http.*` directly bypasses both refresh and BookOrbit routing.

#### `lib/services/bookorbit_api_service.dart`: upstream (=), 5,774 lines (`part of api_service.dart`)
- **Purpose:** an `ApiService` subclass that answers Audiobookshelf routes from BookOrbit `/api/v1`.
- **Key members:**
  - `clearCaches` :148: about 20 static maps, cleared on account change.
  - `currentAccessToken` / `tokenAfterRejection` :192/198, used by the media proxy.
  - `_sendRefresh` :274: `/api/v1/auth/refresh`, with cookie-based web refresh tokens.
  - `probe` :305, `signIn` :331.
  - `_route` :886 and `_dispatch` :920: a `_BoHttpError` becomes that HTTP status, and any other exception becomes a 500.
  - The session family: `_startSession` :4902, `_checkpoint` :4955, `_localSession` :5067.
- **Static caches:**
  - `_manifests`, `_details`, `_recent` and others.
  - `_recent` (TTL futures) is never pruned, only cleared on account change.
- **Constructor side effect:** it attaches and starts `BookOrbitMediaProxy` on every construction.

#### `lib/services/bookorbit_media_proxy.dart`: upstream (=), 273 lines
- **Purpose:** a loopback HTTP proxy (127.0.0.1, random or saved port) that adds a fresh Bearer token for covers, audio and ebooks.
  - Every URL carries a 24-byte random path secret, persisted in prefs (`bookorbit_proxy_secret`).
  - It is native only; `_stub` serves the web.

#### `lib/services/auth_tokens.dart`: upstream (=), 30 lines
- **Purpose:** `AuthTokens.fromResponse` reads `user.accessToken/refreshToken/token` or the top-level fields. `isLegacy` is true when there is no access token.

#### `lib/services/user_account_service.dart`: upstream (=), 479 lines
- **Purpose:** the singleton holding saved accounts and the active scope.
  - `SavedAccount.scopeKey` :33 is `<url without scheme or trailing slash>_<username>`. It contains `:` when the URL has a port.
- **Persistence:** `saved_accounts` (JSON, **tokens in plaintext**) and `active_account_scope`.
- **Key functions:**
  - `init` :108, with `_alignScopeWithSession` :146, which trusts `server_url`/`username` over the stored scope.
  - `saveAccount` :166 (runs the `beforeAccountChange` hook).
  - `switchTo` :185: synchronous; `_persistActiveKey()` is not awaited.
  - `updateTokens` :212.
  - `persistRefreshedTokens` :254: writes the refresh token first, refuses half a pair, then reads back to verify.
  - `loadPersistedTokens` :312: `prefs.reload()`, then returns the pair only when it belongs to the same session.
  - `clearTokens` :333.
  - `updateAccountConnection` :370 with `_migrateScopedData` :412: copies `old:*` to `new:*`, then calls `onScopeMoved`.
- **Hooks:**
  - `beforeAccountChange` is set by `SignedOutPlayback`.
  - `onScopeMoved` is set by `DownloadService`.
- **Dead:** `scopedKey()` :454 has 0 references (lib, test, tool).

#### `lib/services/scoped_prefs.dart`: upstream (=), 195 lines
- **Purpose:** static wrappers over SharedPreferences that prefix keys with `<activeScopeKey>:`.
- **Fallback rule:** reads fall back to the unscoped key **only while no scope exists** (`_shouldFallback` :23).
- **`migrateToScope` :44:** a one-time copy of unscoped keys into the scope, skipping `_globalKeys` :27 and any key containing `:`. Called from main.dart:800.
- **Rule of thumb:**
  - Per-account data goes through ScopedPrefs: progress, pending queues, absorbing lists, settings sync config, RMAB, local sessions.
  - Device data uses plain prefs: `downloads`, `absorb_device_id`, `server_url`/`token`/`refresh_token` (the *active session*), `server_backend`, `update_*`, `bookorbit_proxy_*`.
- **Trap:** every call awaits `getInstance()`, so two read-modify-write sequences on one key can interleave (see F7).

#### `lib/services/session_cache.dart`: upstream (=), 109 lines
- **Purpose:** per-scope cache of track lists, chapters and duration (`<scope>:session_cache_<item>[_<ep>]`) for an instant cold start.
- It re-implements the scope prefix by hand.
- Entries are never pruned except by `clearAll()` at logout.

#### `lib/services/server_backend.dart`: upstream (=), 48 lines
- **Purpose:** the `ServerBackend` enum (`abs`, `bookorbit`).
- **`static active`:** a process-global for the current session, persisted as `server_backend`.
  - `ApiService.forSession`, `SocketService.connect` and `pingServer` read it as their default.

#### `lib/services/signed_out_playback.dart`: upstream (=), 68 lines
- **Purpose:** after an auth expiry the account stays active with an empty token.
  - `api()` returns an `ApiService` aimed at `http://signed-out.invalid`, so every call fails like an offline one and queues.
  - `end()` stops playback when signing into a different account.

#### `lib/services/progress_sync_service.dart`: upstream (+23/-5), 793 lines
- **Purpose:** a singleton that saves progress locally first and keeps the offline queues.
- **ScopedPrefs keys:**
  - `progress_<id>` holds `{currentTime, duration, speed, isFinished, timestamp}`.
  - `pending_syncs` (list), `pending_ebook_progress` (map JSON).
  - `offline_listening_<id>` with its `pending_offline_listening` list.
  - `streaming_pending_<id>` with its `pending_streaming_listening` list.
  - `stats_time_saved*`.
- **State:**
  - `_isOnline` comes from `connectivity_plus`, subscribed in `init` :28.
  - `_isFlushing`, `_flushAgain`, `_flushCompleter`, `_isFlushingOfflineListening`.
  - `_consecutiveFailures` is capped at 10 (:25); past that, nothing is rescheduled.
  - `_serverDurationCache` :157 is unbounded and never cleared.
- **Key functions:**
  - `saveLocal` :45, `cacheServerProgress`, `serverTrustedDuration` :159.
  - `syncToServer` :200.
  - `flushPendingSync` :256 takes 5 items per batch. For each item it calls `getItemProgress`, then `SyncLogic.shouldPullServer`, then either pulls (`cacheServerProgress(overridePending)`) or pushes (`updateProgress`/`updateEpisodeProgress`). Network errors are detected by **string matching** (:410).
    - The tail flushes offline listening and ebook positions.
    - A retry is scheduled with `Future.delayed(SyncLogic.backoffDelay)` (:465). It captures the `api` it was given.
  - `pushEbookProgress` :479 and `_flushPendingEbookProgress`.
  - Offline listening:
    - `addOfflineListeningTime` and the streaming buffer `add/reduceStreamingPendingTime`.
    - `migrateOrphanStreamingTime` runs at startup (main.dart:914).
    - `_flushOfflineListeningTimeInternal` :659 opens a `/play` session, syncs `timeListened`, then closes it.
- **Callers:** `audio_player_service` (save, streaming buffer, offline time), `library_provider.dart:268/583/615` and `_lp_core.dart:334/436` (flush on load, refresh, back online, manual-offline off), the reader (ebook positions), and main.dart:910 (`init`).

#### `lib/services/sync_logic.dart`: upstream (=), 89 lines
- **Purpose:** pure decisions, which must stay in step with the inline code:
  - `backoffDelay`: 250 ms, then 5 s doubling to a 300 s cap.
  - `shouldPullServer`: local wins on a newer-or-equal timestamp, when it is more than 30 s ahead, or when it holds offline listening time.
  - `shouldAdoptServerAtCachedStart`, used by audio_player_service:4979.

#### `lib/services/local_session_service.dart`: upstream (+42/-19), 435 lines
- **Purpose:** client-built ABS *local* sessions (`playMethod 3`) for downloaded plays. There is one session per item per calendar day, and timestamps are captured when time accrues.
- **ScopedPrefs keys:** `local_session_active` and `local_session_pending` (a list of JSON strings).
- **In-memory state:** `_active`, `_loaded`, `_flushing`, and `_localUnsupported` (:44), a **process-wide** flag. None of it is reset on an account switch; only `debugReset` resets it, and that is test-only.
- **Key functions:**
  - `init` :148 moves an orphaned active session to pending.
  - `beginSession`, and `accrue` with day rollover.
  - `pushActive` :294 upserts the cumulative total.
  - `finalizeActive`.
  - `flushPending` :341 sends local-all and drops only what was sent.
  - `_legacyFlush` :403 opens a `/play` session and syncs `timeListened` = the session's **cumulative** total.
- **Callers:** audio_player_service (6615, 6979, 7163, 7994, 8323), library providers (flush), and ebook_reader_view (`newSessionId`, `queue`).

#### `lib/services/settings_sync_service.dart`: upstream (+38/-4), 967 lines
- **Purpose:** syncs settings through a user-owned **WebDAV file** (Nextcloud or similar), not through ABS. Each account gets one file, `absorb-settings-<sha256(scope)[:16]>.json`.
- **What travels:** an allowlist `_syncedKeys` :105 plus `_deviceLocalSettings`, which stays home. Accounts, tokens and pending ledgers never travel (filtered both on push and on pull).
- **Config (ScopedPrefs):**
  - `settingsSyncEnabled`, `Url`, `User`, `Pass` (**plaintext**), `Headers`, `IncludeRmab`.
  - Sync state: `LastSeen` and `LastHash`.
- **Lifecycle:**
  - `start()` :387 sets a listener on `PlayerSettings.settingsChanged`, debounced 20 s, plus `Timer.periodic(45 s, pushIfChanged)`.
  - `onAppForegrounded` :432 restarts the timer, then push-if-unsent, then pull, then push.
  - `onAppBackgrounded` stops the timers and pushes.
  - Network failures back off from 1 to 30 minutes (`_noteNetworkFailure` :191).
  - `pushIfChanged` builds the full backup export (`BackupService.exportSettings`) and hashes it on every tick.
  - Pull is last-writer-wins on `syncedAt`, and pushes are suppressed for 10 s after an import.
- **Callers:** main.dart:919-920, app_shell.dart:756/771, the backup/sync screens, and login_screen (`resolveSourceAfterRestore`).

#### `lib/services/socket_service.dart`: upstream (=), 691 lines
- **Purpose:** a singleton socket.io connection to ABS, `websocket` transport only.
  - Reconnects 5 times, with delays from 1 s up to 30 s.
  - It is skipped for BookOrbit and in e-ink mode.
- **Connecting:**
  - `connect` :347 first calls `disconnect()`, which **clears every callback**.
  - Authentication emits `auth` with `_token`.
- **Events:**
  - `init` calls `onAuthenticated` (the provider catches up on progress).
  - `auth_failed` :382 does a full `disconnect()`.
  - `user_item_progress_updated` calls `onProgressUpdated`.
  - item, series, collection, playlist, author, task, log and e-reader events.
- **Tokens:** `updateToken` :339 re-emits `auth` after a refresh, but only while connected.
- **Battery:** `softDisconnect`/`softReconnect` :575 are used by `_lp_core.dart:1553-1709` for lifecycle and battery. `softReconnect` duplicates all of `connect`'s handler registration (about 150 lines).
- **Who wires it:** `library_provider.dart:281-294` sets the callbacks and then calls `connect`. `auth_provider.dart:1707` (`editServerConnection`) and `switchServer` (local/remote flip) also connect.

#### `lib/services/bookorbit_notification_socket.dart`: upstream (=), 148 lines
- **Purpose:** BookOrbit's `/notifications` socket.
  - It asks for `api.freshAccessToken()` on **every handshake**, the pattern the ABS socket lacks.
  - An `unauthorized` event is retried 3 times with backoff.

#### `lib/services/highlight_sync.dart`: upstream (=), 198 lines
- **Purpose:** two-way ebook highlight sync, BookOrbit only (`api.keepsEbookHighlights`).
- Jobs are chained per item (`_chains`). Pending deletes and edits come from `EbookAnnotationService`.

#### `lib/services/server_health_service.dart`: fork, 106 lines
- **Purpose:** a read-only probe: ping, version, then `getMe`, then `getLibraries`.
- **Used by:** `screens/server_health_screen.dart`.

#### `lib/services/update_checker_service.dart`: upstream (+358/-59), 587 lines (mostly fork code)
- **Purpose:** GitHub release check on `atewertfd/absorb-platform`.
  - `releases/latest`, or `releases?per_page=10` when betas are included.
  - In-flight dedupe for automatic and forced checks separately.
  - The cooldown only starts after GitHub answers.
  - The prefs `update_last_check` and `update_dismissed_version` are global.
- **Installers:**
  - `ApkUpdater` downloads the APK in-app, then `OpenFilex`.
  - `WindowsUpdater` downloads to temp, then `Process.start(detached)`, then `exit(0)`.
  - `UpdateDownload` is cancellable and deletes partial files.
- **Callers:** app_shell, settings_screen, update_dialog.
- **Platform:** imports `dart:io`. Every `Platform.*` use sits behind `kIsWeb` or a native-only entry point.

#### `lib/services/update_policy.dart`: upstream (+156/-1); `update_check_policy.dart`: fork, 104 lines
- **Purpose:** pure helpers:
  - asset selection (ABI-aware APK, Windows `setup` installer);
  - `compareUpdateVersions` and `pickUpdateRelease` (highest version that already has this platform's asset);
  - `isInnoSetupInstall` (checks for `unins000.exe`);
  - the frequency enum, `isUpdateCheckDue`, `InFlightUpdateCheck`.
- **Tests:** `update_policy_test`, `update_check_policy_test`, `update_checker_service_test`.

#### `lib/services/wear_auth_service.dart`: upstream (=), 66 lines
- **Purpose:** a MethodChannel bridge that publishes the full session, **including the refresh token and custom headers**, to the paired Wear OS app.
  - It is a no-op off Android.
  - The tokens it sends back are picked up by `AuthProvider.adoptCompanionTokens`.

#### `lib/services/oidc_service.dart`: upstream (=), 500 lines
- **Purpose:** the ABS OIDC flow:
  1. a pre-flight GET `/auth/openid?...PKCE S256, state` with `dart:io HttpClient` captures the cookies and the 302;
  2. `flutter_web_auth_2` handles the browser;
  3. the callback checks `state`, then GETs `/auth/openid/callback` with the code and verifier plus the cookies.
- There is a BookOrbit variant.
- Native only (`dart:io`).

#### `lib/providers/auth_provider.dart`: upstream (+12), 1,721 lines
- **Purpose:** the owner of the live session: `_accessToken`, `_refreshToken`, `_serverUrl`, `_username`, `_backend`, local or remote URL, and the signed-out state.
- **Key functions:**
  - `apiService` :279 and `_createSessionApi` :295 wire `loadPersistedTokens`, `onTokensRefreshed` and `onAuthExpired`, bound to the session's server and user.
  - `_onTokensRefreshed` :327, `adoptCompanionTokens` :408.
  - `_onAuthExpired` :446 leads to `_signOutKeepingAccount` :489.
  - `tryRestoreSession` :536.
  - `login` :764, `loginWithApiKey` :977, `loginWithOidc` :1079.
  - `logout` :1390, `switchToAccount` :1492, `editServerConnection` :1667.
  - `_accountGen` guards answers that arrive late.

### 1.2 End-to-end flows

**Sign-in**
- **Password.** `AuthProvider.login`:
  1. normalizes the URL (`utils/server_url.dart`);
  2. calls `ApiService.login`, a POST `/login` with `x-return-tokens: true`; BookOrbit uses `BookOrbitApiService.signIn`;
  3. reads the tokens with `AuthTokens.fromResponse`;
  4. writes the active session to plain prefs (`server_url`, `refresh_token` first, then `token`, `username`, `user_id`, `server_backend`, `custom_headers`);
  5. calls `UserAccountService.saveAccount`, which runs `beforeAccountChange` (signed-out playback stops) and sets the active scope to `scopeKey`;
  6. calls `_onAccountActivated` (EQ and local-server settings reload), clears widget stats, pushes the session to Wear and notifies.
- **API key.** Validates with `/api/me` and is stored as a legacy token (no refresh).
- **OIDC.** Goes through `OidcService`; the callback answer is the same shape as `/login`.
- **Restore at launch.** main.dart:796 runs `UserAccountService.init`, :800 `migrateToScope`, and :850 `tryRestoreSession`. `tryRestoreSession`:
  1. reads the plain prefs and restores the credentials *always* (so offline works);
  2. pings (local and remote);
  3. if the server is reachable, calls `authorize()` (falling back to `getMe()`) for the user, permissions and e-reader devices.

**Token refresh (ABS JWT with rotating, single-use refresh tokens)**
1. **Before a request.** `_ensureFreshAccessToken` refreshes when `exp` is less than 60 s away.
2. **On a 401.** Each `_auth*` call runs `_refreshAccessToken` once and replays the request.
3. **One refresh at a time.** The per-instance completer joins concurrent calls on one instance. The static `_tokenMutationCompleter` serializes refreshes across all instances.
4. **Adopt before refreshing.** Each refresh first tries `_adoptPersistedTokens` (`prefs.reload()`, same session only). An instance with a stale pair, or one that a background isolate, Android Auto or Wear rotated, picks up the stored pair instead of spending a refresh token that is already spent.
5. **Success.** `onTokensRefreshed` leads to `AuthProvider._onTokensRefreshed`, then `persistRefreshedTokens` (refresh first, read-back verified), then `token_saved_at`, `SocketService.updateToken`, Wear publish and notify.
6. **Rejected (401/403).** `onAuthExpired` leads to `_signOutKeepingAccount`, which drops the tokens and keeps the account and scope. The player switches to `SignedOutPlayback.api()`, a toast appears, and queues keep filling until sign-in.
7. **Transient failure.** The original response is returned, and the pre-flight is off for 2 minutes.
8. **Companions.** `adoptCompanionTokens` runs before an account switch and before an explicit logout, so a pair rotated by Wear or Android Auto is not lost.

**Progress sync**
- **Streaming play.** audio_player_service syncs `/api/session/<id>/sync` on its timer.
  - Listening also goes into `streaming_pending_<id>` and is reduced after a confirmed sync.
  - Anything left at launch is moved to `offline_listening`.
- **Downloaded play.** Uses `LocalSessionService`:
  - `accrue` per tick;
  - `pushActive` (POST `/api/session/local`) on the sync interval when online;
  - `finalizeActive` queues the session if it wasn't pushed;
  - `flushPending` (POST `/api/session/local-all`) on reconnect.
- **Position.** `ProgressSyncService.saveLocal` writes `progress_<id>` and adds the item to `pending_syncs`.
  - `flushPendingSync` (load, refresh, back online, manual offline off) compares against `/api/me/progress/<id>` and pushes with PATCH or pulls.
  - Retries use exponential backoff. After 10 consecutive failures they stop until the next caller (in practice LibraryProvider's back-online or refresh paths, since the service's own connectivity handler passes no `api`).
- **Ebook position.** `pushEbookProgress` sends a PATCH. On failure it queues `pending_ebook_progress`, which is flushed at the tail of `flushPendingSync`.
- **Offline listening time.** `offline_listening_<id>` is flushed by opening a `/play` session, syncing `timeListened` at max(local, server position), then closing it.
- **Realtime in.** The socket's `user_item_progress_updated` leads to `LibraryProvider._onRemoteProgressUpdated`, and `init` leads to `_catchUpRemoteProgress`. BookOrbit has no progress events, so `_lp_core` polls every 30 s (`_startBookOrbitPoll` :1500).

**Settings sync**
- Settings go to a WebDAV file the user configures, not to ABS.
- **Push:** debounced on change (20 s), every 45 s by hash comparison, and on background.
- **Pull:** on foreground, last writer wins by `syncedAt`, and the payload is filtered in both directions.
- See the 1.1 entry.

**Realtime socket**
- **Connect.** LibraryProvider sets the callbacks, then calls `SocketService.connect(serverUrl, token, headers)`.
- **Authenticate.** The socket emits `auth` on every connect and reconnect; the server's `init` leads to `onAuthenticated`.
- **Lifecycle.** Background, reader-quiet and e-ink do `softDisconnect`, and resume does `softReconnect` with the saved token.
- **Failures.**
  - Exhausted reconnects lead to `onReconnectFailed`, then `LibraryProvider._goOffline`.
  - `auth_failed` leads to a hard `disconnect()` (see F5).
- **BookOrbit** has a separate notification socket, and that one renews its token on each handshake.

**Multi-account and server switching**
- **Accounts.** Accounts live in `saved_accounts`. The active session is the plain `server_url/token/refresh_token/username` keys, and per-account data lives under `<scopeKey>:`.
- **`switchToAccount`:**
  1. bumps `_accountGen` and calls `adoptCompanionTokens`;
  2. stops the player;
  3. clears the Android Auto, CarPlay and BookOrbit caches;
  4. calls `UserAccountService.switchTo`, a synchronous scope flip;
  5. reloads scoped PlayerSettings caches and the EQ;
  6. writes the active-session prefs, pings, then authorizes.
  - LibraryProvider sees a new `userId@serverUrl` key and reloads everything, socket included.
- **Logout.** `logout` stops playback, clears the Android Auto/CarPlay caches, the search index, the widget, `SessionCache` and the BookOrbit caches. Only with `revokeServerSession` does it POST `/logout`. It then removes the account or clears its tokens.
- **Local/remote flip.** `useLocalServer` changes only `activeServerUrl`. The socket moves with `switchServer`, and LibraryProvider refreshes on the flip.
- **Server address edit.** Editing an account's server address (dynamic DNS) migrates every scoped key to the new scope and calls `onScopeMoved`, which re-points download origins.
- **Singletons that are not reset on a switch:** `ProgressSyncService` (backoff counters, a scheduled retry holding the old `ApiService`, the duration cache), `LocalSessionService` (`_localUnsupported`, `_loaded`), `SettingsSyncService` (timers, retry state). See F1 and F3.

---

## PART 2: Findings

Confidence: **H** = traced in code end to end; **M** = traced, but the trigger depends on runtime conditions not proven here; **L** = plausible, needs a repro.
Owner tags: [U] upstream file, [F] fork file.

### Bugs

**F1. A scheduled progress retry can push one account's queue through another account's session.** Severity: High (data mix-up). Confidence: M. [U] `progress_sync_service.dart:465`
- **Mechanism:**
  - `flushPendingSync` schedules `Future.delayed(backoff, () => flushPendingSync(api: api))` with the `ApiService` captured at schedule time.
  - It reads `pending_syncs` through `ScopedPrefs`, which resolves to the *current* scope when it runs.
  - Nothing resets or cancels it on an account switch (`switchToAccount` never touches ProgressSyncService).
- **Trigger:**
  1. Account A has a pending push failing with backoff (offline server, 5xx), so a retry is scheduled for up to 5 minutes later.
  2. The user switches to account B, which has its own pending items.
  3. The retry fires and sends B's positions with A's token.
- **Consequence:**
  - Same server: B's positions are written to A's progress and removed from B's queue, so B never syncs.
  - Different servers: they 404 or fail and keep backing off.
  - An in-flight flush that spans the switch has the same problem.
- **Fix (S):**
  - Capture `UserAccountService().activeScopeKey` at schedule time and in `flushPendingSync`. Abort when the scope changed, or hold a generation counter bumped from `switchToAccount`/`logout`.
  - Better still, take an `ApiService Function()` supplier that the provider resolves to the current session.

**F2. `updateProgress`/`updateEpisodeProgress` count 4xx answers as success, so queued progress is dropped.** Severity: Medium-High. Confidence: H. [U] `api_service.dart:2854, 2868, 3098, 3111`
- **Mechanism:** both return `statusCode < 500`. `flushPendingSync` (:372-397) and `syncToServer` treat `true` as "landed" and remove the item from `pending_syncs`.
- **Trigger:**
  - A 401 after a *transient* refresh failure (the refresh times out while the API answers, a token rotated elsewhere while this instance retries);
  - a reverse proxy's 403 (expired Cloudflare Access cookie or header);
  - 408 or 429.
- **Consequence:** the local position is never sent. Commit 0e21af5a fixed this for listening *time*, not for positions.
- **Fix (S, one line ×4):** success means `2xx`. Also treat 404 as "drop" (the item is gone). Everything else stays pending.

**F3. Legacy local-session mode re-sends the cumulative listening time on every push, multiplying listening stats; the switch to it is process-wide and sticky.** Severity: Medium. Confidence: H (mechanism) / M (trigger). [U] `local_session_service.dart:44, 297-307, 366-372`
- **Mechanism:**
  - After one 404/501 from `/api/session/local`, `_localUnsupported = true` for the whole process and every account.
  - From then on, `pushActive` (called on every sync interval, audio_player_service:6615/7994) runs `_legacyFlush(api, _active!)`. That opens a **new** `/play` session and syncs `timeListened = _active['timeListening']`, the *cumulative* total.
  - `legacyAll()` also re-sends the active session on every flush without marking it.
  - Over 10 one-minute intervals that credits 1+2+…+10 = 55 minutes.
- **Trigger:** genuinely old servers, but also **BookOrbit**. Its `_route` turns a `_BoHttpError(404)` from `_localSession` (`_putPosition` on a deleted book, bookorbit_api_service.dart:5079) into an HTTP 404, which `syncLocalSession` reads as `serverTooOld`.
- **Fix (S/M):**
  - Track how much was already sent through the legacy path (`legacySent`) and send only the difference.
  - Key `_localUnsupported` by server origin and reset it on account change.
  - Only set it when the route itself is missing. On BookOrbit, the single-session handler should map 404 to a dropped session the way local-all does.

**F4. Settings sync retries a WebDAV password the server rejects every 45 s, forever.** Severity: Medium. Confidence: H. [U] `settings_sync_service.dart:803-805, 392`
- **Mechanism:**
  - A PUT answered 401/403, or any non-2xx such as 404, 409 or 507, returns without `_noteNetworkFailure()`.
  - `_lastHash` is unchanged, so `pushIfChanged` pushes again on the next 45 s tick, plus each foreground.
- **Trigger:** the user changes their Nextcloud password, or an app password is revoked.
- **Consequence:**
  - Nextcloud brute-force throttling or fail2ban can lock out the user or their IP.
  - Constant traffic and log noise.
- **Fix (S):**
  - Back off on every non-2xx.
  - After an `authFailed`, stop automatic pushes until the credentials change or the user taps Sync.

**F5. An ABS socket `auth_failed` turns live sync off for the rest of the session.** Severity: Medium. Confidence: M. [U] `socket_service.dart:382-385, 599-602`
- **Mechanism:** the handler calls `disconnect()`, which disposes the socket, nulls `_token` and clears **every callback**. After that, `softReconnect` returns early (token null) and nothing re-wires the callbacks until LibraryProvider reloads the account.
- **Trigger:** a reconnect (a network blip, a laptop waking) that authenticates with an access token which expired while no HTTP call refreshed it. ABS `validateAccessToken` rejects an expired JWT.
- **Consequence:** cross-device progress and item updates stop silently. Unlike `reconnect_failed`, the UI doesn't go offline either.
- **Fix (S):**
  - On `auth_failed`, get `freshAccessToken()` from the current API and re-emit `auth` (once).
  - Or give `auth`'s payload a fresh token on every connect, as `BookOrbitNotificationSocket` does.
  - Fall back to `onReconnectFailed`, not a callback-wiping `disconnect`.

**F6. `SocketService.connect()` erases the callbacks it was meant to keep.** Severity: Low. Confidence: H. [U] `socket_service.dart:347-348`; caller `auth_provider.dart:1707`
- **Mechanism:**
  - `connect` starts with `disconnect()`, which nulls `onProgressUpdated` and every other callback.
  - LibraryProvider sets the callbacks *before* calling `connect`, so its own call is safe, because `_socket` is null at that point.
  - `editServerConnection` on the active account, with a **headers-only** change, calls `connect` again. The auth key is unchanged, so LibraryProvider doesn't reload, and the callbacks are gone.
- **Fix (S):** make `connect` dispose only the socket, and keep `disconnect()` for logout.

**F7. Race on the pending lists: a position saved during a flush can lose its "pending" mark.** Severity: Low-Medium. Confidence: M. [U] `progress_sync_service.dart:74-78, 242-244, 288-290, 351-353, 390-392`
- **Mechanism:**
  - `saveLocal` (read `pending_syncs`, add, write) and the flush's per-item removal (read, remove, write) are separate async read-modify-write sequences on one key.
  - Each `ScopedPrefs.getStringList` awaits, so a removal that read the list before a concurrent add writes back a list without the new id.
- **Consequence:** `progress_<id>` is saved but not queued. It heals on the next `saveLocal` of that item, but not if that was the last save (pause, then app killed).
- **The same pattern** exists in `addOfflineListeningTime` and `LocalSessionService._enqueue/_dropPending`, though the latter already merges.
- **Fix (S):** serialize mutations of these lists through one `Future` chain or lock inside the service.

**F8. ABS ebook-position PATCH bypasses the auth helpers.** Severity: Low-Medium. Confidence: H. [U] `api_service.dart:2902`
- **Mechanism:** `updateEbookProgress` uses raw `http.patch(..., headers: _headers)`, so it gets no pre-flight refresh, no 401 refresh-and-retry, ignores the injected `_httpClient` (tests), and leaves `lastEbookProgressStatus` as shared mutable instance state.
- **Consequence:** with an expired token every page turn 401s and is queued. The queued flush retries with the same instance; a 401 there counts as a failure and increments the backoff (:551-554).
- **Fix (S):** use `_authPatch`. BookOrbit already overrides this method, so there is no routing impact.

**F9. The connectivity handler's flush never runs.** Severity: Low. Confidence: H. [U] `progress_sync_service.dart:37`
- **Mechanism:** `flushPendingSync()` is called with no `api`, so it returns at :257.
- **Consequence:**
  - Recovery after "Too many consecutive failures… waiting for next connectivity change" (:457) relies on LibraryProvider's own back-online and refresh paths, not on this handler.
  - The behavior is acceptable, but the log message is misleading.
- **Fix (S):** have the provider register an `ApiService Function()` the service can call.

### Security

**S1. Tokens in plaintext storage.** Known pending owner decision; listed for completeness. [U]
- `saved_accounts` (every account's access and refresh token, user_account_service.dart:41-50).
- `token`/`refresh_token` in plain SharedPreferences.
- `settingsSyncPass` (WebDAV password), `rmab_api_token`, `bookorbit_proxy_secret`.
- Wear receives the refresh token over the Data Layer (wear_auth_service.dart:39-49).
- Not a new finding.

**S2. Access tokens in URL query strings** (`?token=`). Medium, by design. [U]
- **Where:** `api_service.dart:388, 1476, 1833, 2377, 2388` (ebook, cover, author image, track, download URLs).
- **Where they leak:**
  - server and reverse-proxy access logs;
  - `cached_network_image`'s on-disk cache database (the URL column);
  - persisted download records.
- **Why it matters:** access tokens rotate, but an **API key or legacy token never expires**, so for those accounts the secret stays at rest in those stores.
- **Note:** `stableCoverCacheKey` strips the token only for item covers. Author images get a new cache key on every rotation (a performance side effect).
- **Fix:** M; upstream-shaped, so leave it unless the owner makes token handling a priority.

**S3. Session cookie value logged during OIDC.** Low. Confidence: H. [U] `oidc_service.dart:116`
- `debugPrint('[OIDC] Captured raw cookie: $nameValue')` writes the express session cookie's value.
- `LogService._sanitize` only masks `token|secret|password|authorization|bearer|*key` followed by `=`/`:`, so `connect.sid=…` survives into the exportable log file.
- **Fix (S):** log the name only, as the parsed-cookie branch at :108 already does.

**S4. First 20 characters of the stored token logged at every launch.** Low. Confidence: H. [U] `auth_provider.dart:587`
- For JWTs this is the non-secret header.
- For opaque tokens (BookOrbit, other servers) it is part of the secret, and it goes to the console and logcat unmasked.
- The file log masks it through the `token:` regex.
- It contradicts the fork's own `tokenFp` rule (api_service.dart:675-680).
- **Fix (S):** use `ApiService.tokenFp(savedToken)`. It is a 1-line hook in an upstream file.

**S5. The log sanitizer has gaps.** Low. [F/U boundary; `log_service.dart:190-200`, which is mostly another auditor's area]
- It doesn't catch JSON pairs (`"accessToken":"eyJ…"`, because the `"` sits before the `:`) or bare JWTs.
- Today only `api_service.dart:914` (`Token refresh error: $e`) could carry a token: a `FormatException` quoting a malformed refresh reply. Every other auth path deliberately logs `runtimeType` only.
- **Fix (S):** log `e.runtimeType` at :914, and add a `eyJ[\w-]+\.[\w-]+\.[\w-]+` mask to the sanitizer.

**S6. Windows updater runs the downloaded installer without checking it.** Low-Medium. Confidence: H. [U+fork code] `update_checker_service.dart:448-505`
- **Gaps:**
  - No signature, hash or size check; it relies only on TLS to GitHub and the fork account's integrity.
  - A truncated stream that ends cleanly would still be launched, because `received` is never compared with `contentLength`.
- The owner chose no SHA256SUMS assets.
- **Cheap hardening (S):**
  - Require `received == total` when the length is known.
  - Verify the asset's `size` from the GitHub API.
  - Optionally require Authenticode via `Get-AuthenticodeSignature` once the installer is signed.

**S7. BookOrbit proxy path secret ends up in logs.** Low. [U]
- The proxy URL `http://127.0.0.1:<port>/<secret>/…` keeps its path through `_sanitizeUrls`. Any logged media URL therefore writes the persistent secret, which lets local apps reuse the session through the port.
- **Fix (S):** have the sanitizer redact the first path segment for `127.0.0.1`.

**Checked and OK:**
- `tokenFp` (fork) never prints token characters.
- Login, API-key and refresh errors log `runtimeType` only.
- OIDC uses PKCE S256 and checks `state`.
- The media proxy binds to loopback with a 24-byte secret.
- Settings sync filters accounts, tokens and pending ledgers in both directions, and the WebDAV password leaves only with `includeAccounts`.
- `persistRefreshedTokens` write ordering and read-back are sound.

### Dead code

Each was grepped across lib, test and tool.

| Item | Where | Refs | Recommendation |
|---|---|---|---|
| `UserAccountService.scopedKey()` | user_account_service.dart:454 | 0 | Upstream: leave it (merge cost beats 4 lines) |
| `ProgressSyncService.dispose()` | progress_sync_service.dart:790 | 0 | Upstream: leave it |
| The connectivity listener's `flushPendingSync()` | progress_sync_service.dart:37 | n/a | Functionally a no-op; fix rather than delete (F9) |
| `SyncLogic.maxRetryDelay` | sync_logic.dart:9 | Internal only | Fine |

Not dead, despite looking like it:
- `_refreshTokenPairOnce` (used by `changeMyPassword`);
- `shouldAdoptServerAtCachedStart` (audio_player_service:4979);
- `LocalSessionService.newSessionId`/`queue` (ebook reader);
- `ServerHealthService` (server_health_screen).

### Duplication

- **Socket handler registration** is copied between `connect` (:347-533) and `softReconnect` (:575-691), about 150 lines; the event lists are identical today. [U] Extracting `_wire(io.Socket)` is S but touches a whole upstream file, so do it only if upstream doesn't ship socket changes often.
- **Network-error detection by string match** appears twice in progress_sync_service (:410-420, :767-772), with different string sets. [U]
- **Compound `itemId.length > 36` parsing:** 74 occurrences in 21 files, while `lib/utils/episode_key.dart` exists. [U] Not worth a sweep against upstream.
- **`SessionCache._key`** rebuilds the ScopedPrefs prefix by hand. [U] Harmless.
- **The "write refresh token first" persistence** is spelled out in `switchToAccount`, `login*` and `persistRefreshedTokens`. A single `persistSession()` helper would prevent ordering regressions. [U]

### Performance

- **Settings sync tick** (only when enabled): every 45 s it builds the *entire* backup export (`BackupService.exportSettings`), JSON-encodes and SHA-256 hashes it.
  - On Windows the app rarely goes to the background, so this runs all day.
  - The export includes ebook annotations and metadata overrides (up to 2 MB).
  - Suggest 2–5 minutes, or a cheap dirty flag. [U]
- **Request worst case:** pre-flight refresh (2×15 s), then GET (15 s + retry 15 s), then a 401 refresh (2×15 s) is more than 75 s for one call against a black-holed server. The 2-minute cooldown limits repeats. Acceptable, but worth knowing. [U]
- **Offline listening for a deleted item** is retried on every flush and costs a GET progress plus a POST `/play` each time. It is never dropped; `notAccepted` only stops the batch. [U]
- **`updateProgress` logs the full response body on every push** (:2867). Each `debugPrint` is a synchronous file append in LogService. [U]
- **LibraryProvider timers** (out of scope; listed so the providers audit can cross-check): health ping every 60 s while online, offline ping every 20 s, BookOrbit poll every 30 s, local-server probe.
  - A single failed 60 s ping goes offline (`_lp_core.dart:1478-1480`), with no second sample.
- **Unbounded in-memory caches:** `_serverDurationCache` and `BookOrbitApiService._recent` grow per item or key until restart or account change. Small in practice. [U]

### Risky patterns

- **A fresh ApiService per `auth.apiService` read**, each with its own token copy (auth_provider.dart:279).
  - It is correct today only because of the static mutation lock plus `_adoptPersistedTokens` (`prefs.reload()` disk I/O inside every refresh).
  - Any new direct `http.*` call (as in F8) or any new per-instance cache breaks that.
  - Long-lived holders (`LibraryProvider._api`, `AudioPlayerService` via `useApi`, delayed closures as in F1) keep stale pairs until they 401.
- **Process-global singletons that hold per-account state** without an account-change hook:
  - `ProgressSyncService` (F1);
  - `LocalSessionService._localUnsupported` (F3);
  - `ServerBackend.active` (a static mutated by `saveActive`, read by every default-backend call).
  - Suggest one `AccountChange` notifier that these services subscribe to. M; fork file plus small hooks.
- **Unawaited futures:**
  - `UserAccountService.switchTo` → `_persistActiveKey()` (:192). A crash right after a switch reverts the scope, but `_alignScopeWithSession` repairs it on the next launch.
  - Flush calls in library_provider:268-270 and `_lp_core:334-337` are fire-and-forget. That is fine, because the services guard re-entry.
- **Swallowed errors:**
  - `catch (_) {}` around active-session prefs writes in `switchToAccount` (:1581) and `logout` (:1481). A failed write leaves the plain session keys pointing at the old account while the scope moved. `_alignScopeWithSession` fixes it on the next launch, but within the session progress could be scoped wrongly.
  - Log, at least.
- **Fragile network-error classification** by `e.toString()` (progress_sync_service).
  - On the web a `ClientException('XMLHttpRequest error')` matches none of the strings, so the batch keeps going item by item.
  - It is then counted only through the "no progress" rule.

### Test coverage notes

- **Existing:**
  - `api_service_test`, `api_failure_logging_test`;
  - `progress_sync_transport_test` (2xx and 5xx only);
  - `local_session_flush_test` (legacy flush bookkeeping, not `pushActive` in legacy mode);
  - `settings_sync_transport_test`/`_helpers_test`;
  - the update tests;
  - integration tests (`test/integration/*`, real ABS in Docker).
- **Missing, and each would have caught a finding above:**
  - 401/403 on progress push (F2);
  - scope change during a scheduled retry (F1);
  - legacy `pushActive` repeated twice (F3);
  - PUT 401 backoff (F4);
  - socket `auth_failed` (F5).

---

## Recommended actions (ranked by value ÷ (effort + merge cost))

| # | Action | Tag | Size | Risk |
|---|---|---|---|---|
| 1 | F2: progress PATCH success means 2xx (404 means drop); 4 one-line changes plus a test with 401/403 | upstream | S | Low (could keep stale items pending longer; backoff covers it) |
| 2 | F4: back off on every non-2xx settings-sync PUT, and pause automatic pushes after `authFailed` until the credentials change | upstream | S | Low |
| 3 | F1: scope/generation guard in `flushPendingSync` and its scheduled retry (abort when `activeScopeKey` changed) | upstream | S | Low |
| 4 | S3 + S4 + S5(:914): stop logging the cookie value, the token prefix and the refresh exception text (1 line each) | upstream | S | None |
| 5 | F3: send only the difference in legacy `pushActive`/`legacyAll`; key `_localUnsupported` per origin and reset it on account change; BookOrbit single-session 404 means drop | upstream | S–M | Medium (listening stats path; test with `local_session_flush_test`) |
| 6 | F5 + F6: on `auth_failed`, refresh and re-auth once (or fall back to `onReconnectFailed`); make `connect` keep the callbacks | upstream | S | Low-Medium (realtime path; test with the Docker server) |
| 7 | F8: `updateEbookProgress` uses `_authPatch` | upstream | S | Low |
| 8 | F7: serialize pending-list read-modify-write sequences in ProgressSyncService | upstream | S | Low |
| 9 | S6: Windows/APK updater checks the size (`received == total`, the GitHub asset `size`) before launching | fork code | S | Low |
| 10 | Settings sync tick at 2–5 minutes, or a dirty flag instead of a full export every 45 s | upstream | S | Low |
| 11 | Account-change hook for the sync singletons (ProgressSync, LocalSession, SettingsSync) | fork file + hooks | M | Medium |
| 12 | S7: sanitizer redacts the loopback proxy secret; mask bare JWTs | upstream (log_service) | S | None |
| 13 | Extract `_wireSocket` (removes about 150 duplicate lines) | upstream | S | Merge churn: do it only when upstream is quiet in socket_service |
| 14 | S1/S2: secure token storage and token-free media URLs | upstream | L | Owner decision pending |
