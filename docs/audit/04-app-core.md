# Audit 04: app core

Scope: `lib/main.dart`, `lib/build_info.dart`, `lib/screens/app_shell.dart`, `lib/providers/*` (LibraryProvider and its three `part` files, AuthProvider), `lib/models/*`, `lib/utils/*`, `lib/ui_themes/*`, and the l10n setup (`l10n.yaml`, `app_en.arb` structure only).
Method: read-only. Grep plus windowed reads, `git diff origin/main`, `git log`, and a Python scan of `app_en.arb` (duplicate keys, metadata, unused keys). Line numbers are from the working tree on 2026-10-30, branch `claude/slim`. `_lp_absorbing.dart` (2,390 lines, no fork diff) was mapped but not read line by line.

---

## PART 1: Code map

### Ownership and size

| File | Lines | Owner | Fork diff vs `origin/main` |
|---|---|---|---|
| `main.dart` | 968 | upstream | +~120 / -35: web-safe Platform, smooth wheel, scroll diag, image cache policy, motion policy, looks hooks, startup coordinator |
| `build_info.dart` | 22 | upstream | `kBetaNumber` value only |
| `screens/app_shell.dart` | 1,716 | upstream | +~150 / -100: desktop shortcuts, motion policy, `FrostedNavBar`, ticker pausing, update checks on Windows, look picker prompt |
| `providers/library_provider.dart` | 685 | upstream | +22: `dispose()` and logout stops (BookOrbit poll, local probe) |
| `providers/_lp_core.dart` | 4,030 | upstream | +53: downloaded-shelf signature skip, coalesced `refreshLocalProgress` |
| `providers/_lp_absorbing.dart` | 2,390 | upstream | none |
| `providers/_lp_state.dart` | 429 | upstream | none |
| `providers/auth_provider.dart` | 1,721 | upstream | +12: `canUpload` |
| `models/auth_session.dart` | 133 | upstream | none |
| `utils/*` (upstream: 19 files) | 2-280 each | upstream | none |
| `utils/app_motion.dart` | 43 | fork | new |
| `utils/fork_branding.dart` | 8 | fork | new |
| `utils/memory_policy.dart` | 61 | fork | new |
| `utils/performance_policy.dart` | 12 | fork | new |
| `utils/scroll_diagnostics.dart` | 135 | fork | new |
| `utils/smooth_wheel_scroll.dart` | 230 | fork | new |
| `utils/web_safe_platform.dart` | 17 | fork | new |
| `ui_themes/*` (8 files) | 112-799 | fork | new (2,781 lines total) |
| `l10n.yaml` | 3 | upstream | dropped `untranslated-messages-file` |
| `l10n/app_en.arb` | 7,158 | upstream | +91 fork keys, all at the end (key index 3574-3664 of 3665); 1 upstream string changed (`settingsWhatsNewSubtitle`) |

### `main.dart` (upstream, hooked)

- **Global notifiers (lines 60-211):** `themeNotifier`, `flatNotifier`, `colorSourceNotifier`, `manualSeedNotifier`, `gradientIntensityNotifier`, `useColorEverywhereNotifier`, `snappyTransitionsNotifier` (144), `localeNotifier` (147), `coverSchemeNotifier` (152), `einkModeNotifier` (211). Plus `trustAllCerts` (156) read by `_CertOverrides` (163) at certificate check time, and `rootNavigatorKey` (183) used by non-widget code (toasts, LibraryProvider l10n, settings sync).
- **Appliers:** `applyThemeMode` (195), `applyFlatBackground`…`applyUseColorEverywhere` (201-205), `applyEinkModeTheme` (212, also sets `PlayerSettings.einkMode`), `applyAppearanceFromPrefs` (222, used only by `settings_sync_service.dart:517`), `applyOrientationLock` (236).
- `manualColorScheme` (85, 9 users), `buildAppPageTransitionsTheme` (122, fork, tested), `_InstantPageTransitionsBuilder` (98).
- **`main()` (248):** cert override, binding, `installSmoothWheelScroll` + `installScrollDiagnostics` (fork), `configureImageCache` (fork), read-along wiring, `NarratedBooks.load` (2 s cap), splash preserve, orientation lock (2 s cap), reads ~20 appearance prefs **before the account scope exists** (unscoped fallback keys), `UiThemeStore.load()` (302, fork, device-wide), crash hooks (323-332, log to `LogService`), splash remove, `runApp(MultiProvider[AuthProvider, ChangeNotifierProxyProvider<Auth, LibraryProvider>] → UiThemeScope → AbsorbApp)`.
- **`AbsorbApp` (353):** one `ListenableBuilder` over **13 global notifiers** (361-375) that rebuilds the whole `MaterialApp`: builds two `ColorScheme.fromSeed` + two `ThemeData` per rebuild, calls `SystemChrome.setSystemUIOverlayStyle` from `build` (398), resolves `AppMotionMode` (496), attaches `absorbLookFor` extensions (617/685), `builder: absorbLookBuilder` (687), `home: AppMotionScope(AuthGate)` (688).
- **`AuthGate` (698):** listens to setup links (`app_links`), runs `_initServices` (763), `context.watch<AuthProvider>()` (950) and picks `AuthLoadingScreen` / `AppShell(key: ValueKey(activeScopeKey))` / `LoginScreen`.

### Startup sequence (end to end)

1. `main()`: binding, desktop input hooks, image cache limits, device-wide prefs (theme etc. from **unscoped** keys), `UiThemeStore.load()` (look, glass, look details; migrates a saved `classic` once), cert flag, crash hooks, native splash removed, `runApp`.
2. First frame: `AuthGate` shows `AuthLoadingScreen` (`AuthProvider._isLoading` starts `true`, `auth_provider.dart:71`).
3. `_initServices` (main.dart:763), all sequential and **unguarded until line 849**: `ApiService.initVersion`, device info (Android), beta logging default + `LogService.init`, `UserAccountService().init()` (scope), `ScopedPrefs.migrateToScope()`, re-reads all appearance prefs from the **scoped** keys (803-822), orientation lock again (2 s cap), episode notification registration, cover seed restore.
4. `AuthProvider.tryRestoreSession()` (850) starts (not awaited): prefs → `/me` or authorize → `notifyListeners` → `AuthGate` swaps to `AppShell`; `ProxyProvider` calls `LibraryProvider.updateAuth` → fresh-login branch loads cached libraries, socket, `loadLibraries()`.
5. In parallel `_initServices` continues: queue-mode migrations, device id, `DownloadService.init` (8 s cap), `AudioPlayerService.init` (8 s cap), cold-start play adoption, notification permission.
6. `StartupTaskCoordinator.startBackground` (902, fork): Chromecast (Android) and one sequential block (progress sync, local sessions, EQ, auto sleep, settings sync, Android Auto, home widget, quick actions). `_servicesReady = true` and pending setup links run **before** that block finishes (upstream waited for it).
7. `AppShell.initState` (app_shell.dart:397): start page from prefs, lazy page build, player/cast/library listeners, `_showLaunchPrompts` (What's new → Welcome → beta logging notice → look picker, sequential), `_checkForUpdate` (GitHub builds and every Windows build).

### `screens/app_shell.dart` (upstream, hooked)

- **Navigation:** stack pages 0 Home, 1 Library, 2 Absorbing (default), 3 Stats, 4 Settings in an `IndexedStack` (870) wrapped in `withActiveSurfaceTickers` (pauses tickers of hidden pages; pages stay mounted and still rebuild). Pages are built lazily (`_ensurePageBuilt`, 358). Optional 6th **Podcasts destination** shares stack page 1; mapping in `_pageForDest` (475) / `_selectedDest` (482) / `_syncTabLibrary` (494) + `app_shell_navigation_policy.dart` (`shouldRestoreBookLibrary`).
- **Static entry points** via `_AppShellState._instance` (182): `goToAbsorbingGlobal`, `setExpandedOpen`, `openSearchGlobal`, `openLibraryWith{Tag,Genre}FilterGlobal` (retry up to 180 frames), `notifyScreenReady`. `_instance` is cleared in `dispose` only if it is still `this` (540), so the account-switch remount is safe.
- **Tab switch:** `_navigateTo` (258) fades 200 ms (fork: `AppMotion` decides, `_navigationRequest` drops stale fades); re-tapping Absorbing scrolls to the first card. `_refreshDataForTab` (786): local progress always, progress-only on Library/Absorbing/Stats, full `lib.refresh()` on Home at most once a minute.
- **Bottom nav:** `_buildBottomNav` (889) mirrors Home/Library `barsRevealNotifier` onto `_navBarAnimController` (scroll-to-hide) with post-frame re-attach logic; long-press anywhere maps x to a slot → nav hold menu (`_runNavHold` 1027, editable launcher list in prefs). Wrapped in `FrostedNavBar` (fork).
- **Desktop:** `Shortcuts`/`Actions`/`Focus(desktopShellFocusNode)` around the `Scaffold` (846-866, fork) → `_handleDesktopShortcut` (1331). There is **no desktop sidebar** (ARCHITECTURE.md says there is; `utils/desktop_workspace.dart` is an upstream leftover whose `DesktopWorkspaceScope` is never inserted).
- **Lifecycle:** `didChangeAppLifecycleState` (707) treats `hidden` and `paused` as background (guarded by `_lifecycleBackgrounded`), trims the decoded image cache (fork), forwards to LibraryProvider/sleep timer/player/home widget/settings sync; resume re-applies the orientation lock, adopts companion tokens, refreshes the current tab, re-checks updates.
- **Cover color:** `_deriveCoverScheme` (554) runs `PaletteGenerator` on the playing (or first Absorbing) cover and sets `coverSchemeNotifier` + saved seed. Called from the player listener and on **every** LibraryProvider notification (cheap early return on same item).
- **Auto-expand:** `_maybeAutoExpand` (639) pushes `ExpandedCardRoute` when playback starts on the Absorbing tab (not over the reader).
- **Back button:** `PopScope` (812): clear Library search → double-back exit on Absorbing → otherwise go to Absorbing.

### Providers

**`LibraryProvider`** (`library_provider.dart:41`, `ChangeNotifier with _StateMixin, _CoreMixin, _AbsorbingMixin`). One object for nearly all app data; lives for the whole process.

- `_lp_state.dart`: fields and cheap getters. `isOffline` = manual ‖ network ‖ signed-out (150). `_api` (7) = `auth.apiService`, which **constructs a new `ApiService` on every access** (`auth_provider.dart:279`, each one starts a prefs read in its constructor). Caches: `_sectionsByLibrary`/`_sectionsFetchedAt` (39-40), series caches (79-81), `_absorbingItemCache`, `_progressMap`, `_localProgressOverrides`, `_locallyFinishedItems`, `_knownEpisodeIds`. Timers: ping (20 s), health check (60 s), BookOrbit poll (30 s), local probe (30 s with backoff to 5 min), connectivity debounce (2 s), progress refresh debounce. `getCoverUrl` (390) returns a server URL online and a **local file path** offline.
- `_lp_core.dart` sections: rolling downloads (4), podcast subscriptions (240), year-hidden (288), **offline mode** (312: `setManualOffline`, `tryReconnect`, `setNetworkOffline` 408, `_buildOfflineSections` 450), downloaded shelf (596), progress (705, `refreshLocalProgress` 972), connectivity (1199), local probe (1335), health check (1462), BookOrbit poll (1500), **battery lifecycle** (1542: `onAppBackgrounded`, `onAppForegrounded`, `setReaderQuiet`, `applyEinkMode`, `_resumeLiveWork`), socket handlers (1737), personalized home (2008, 5 s per-library cooldown), playlists (2311), collections (2434), section customization (2577), genre sections (2627), podcast subscriptions (2801), rolling auto-download (3129).
- `_lp_absorbing.dart`: the Absorbing list (add/queue/reorder/remove/finish), playlist and collection queue modes (1357, 1537), up-next preview (2008).
- Constructor (68) registers static callbacks on `AudioPlayerService`, `ChromecastService` and `SiriService`; `dispose` (128, fork) releases timers and listeners (tests/hot restart only).
- **Notify patterns:** 73 `notifyListeners()` sites (43 core, 12 absorbing, 18 in `library_provider.dart`). The fork made two hot ones conditional: `_onDownloadsChanged` (611, signature skip) and `_runLocalProgressRefresh` (982, only when an override changed, coalesced). Socket progress events, shelf loads and offline flips each notify once. Consumers: 33 `context.watch<LibraryProvider>()` vs 2 `context.select` in `lib/` (ARCHITECTURE.md's "widgets usually select a slice" is not true today).

**`AuthProvider`** (`auth_provider.dart:26`): server URL, tokens, user JSON, permissions (`isAdmin`, `canUpload` fork 156, `canDelete`…), backend (ABS/BookOrbit), local-server override (`checkLocalServer` 1308, `clearLocalOverride` 1337), e-reader devices. Session restore `tryRestoreSession` (536), logins (764, 977, 1079), `_onAccountActivated` (1217), `logout` (1390), `switchToAccount` (1492), `editServerConnection` (1667), token rotation `_onTokensRefreshed` (327), auth expiry → `_signOutKeepingAccount` (489, signed-out mode). No credentials are logged (checked every `debugPrint`).

### Account switching, logout, signed-out, offline

- **Switch** (`switchToAccount`): stops playback, clears car caches, `UserAccountService().switchTo` (scope key changes), `PlayerSettings.notifySettingsChanged()`, reloads five synchronous PlayerSettings caches and EQ, swaps credentials, pings, authorizes, `notifyListeners`. Then `AuthGate` remounts `AppShell` (new `ValueKey(activeScopeKey)`) and `updateAuth` takes the `isNewUser` branch (`library_provider.dart:190`): clears most caches, `restoreOfflineMode`, cached libraries, socket connect + `loadLibraries` (or offline sections when the server didn't answer). **Not reloaded on switch:** the appearance notifiers (theme, flat, e-ink, color source/seed, gradient, snappy, wording), `_sectionsByLibrary`, `_locallyFinishedItems`, the socket and BookOrbit feed when the new server is unreachable. See F2, F5, F6.
- **Logout**: `AuthProvider.logout` clears tokens/prefs → `updateAuth` else-branch (342) clears data, stops all timers incl. BookOrbit poll and local probe (fork), disconnects the socket → `LoginScreen`.
- **Signed-out** (auth expired, account kept): `isSignedOut` → `AppShell` stays; `updateAuth` signed-out branch (307) stops live work and shows offline sections from downloads; `_api` is null and `isOffline` is true.
- **Offline**: manual (`manual_offline_mode`, device-wide raw pref) or network (`_networkOffline`, flipped by connectivity events, health-check failure, socket reconnect failure; recovered by the 20 s ping timer, connectivity debounce or `tryReconnect`). Going offline rebuilds Home from downloads and refreshes Android Auto; coming back flushes pending progress/sessions, clears the image cache and reloads libraries.

### How settings and looks rebuild the app

- **Whole-app rebuild** (`AbsorbApp`'s `ListenableBuilder`, main.dart:360): any change to theme, flat, locale, cover scheme (every new book in "From cover" mode), Plain wording, color source, manual seed, gradient, use-color-everywhere, e-ink, snappy, `uiThemeNotifier` (also fires on glass strength and look-detail changes via `_LookNotifier`, ui_theme.dart:600) or `uiThemePreviewNotifier` ("Try it", also fires on preview glass). A new `ThemeData` triggers `AnimatedTheme`'s 200 ms lerp, so every `Theme.of` dependent rebuilds for ~12 frames.
- **Scoped rebuilds:** `UiThemeScope` (InheritedNotifier, ui_theme.dart:704) is the fallback for widgets built outside the app theme; `AbsorbLook.of` (384) reads the theme extension first. `memory_policy.dart` listens to `uiThemeNotifier` to switch image cache limits.
- **Not rebuilt by anything:** OS reduce-motion and platform brightness are read inside `build` without a subscription (F9).

### `lib/ui_themes/` (fork, all new)

| File | Lines | What |
|---|---|---|
| `ui_theme.dart` | 735 | `AppUiTheme` enum (plus/frosted/midnight; ids stable, `plus` = Standard), `GlassStrength`, `AbsorbLook` ThemeExtension (behavior flags + visual tokens, 9 presets, `withDetails`, `withNeutralSurfaces` for e-ink, `lerp`, `==`), `absorbLookFor` (562), global notifiers (574-597), `UiThemeStore` (630: `load`, `choose`, `chooseGlass`, `markChosen`, `needsChoice`; prefs `fork_ui_theme`, `fork_ui_glass`), `UiThemeScope` |
| `look_details.dart` | 125 | `LookDetails` (4 bools), `lookDetailsNotifier`, `LookDetailsStore` (prefs `fork_look_*`) |
| `frosted.dart` | 266 | `frostedThemeData` (theme-level surfaces), `absorbLookBuilder` (MaterialApp.builder: themed `Theme` + `_AppBaseTheme` + `UiThemeTryOutLayer`), `appBaseTheme`, `themeForLook`, `FrostedNavBar`, `FrostedSurface` (blur, never on web), `lookSheetColor` |
| `ui_theme_hooks.dart` | 131 | one-line checks for upstream files (`themedCoverDecodeWidth`, `lookGlow`, `lookBackdrop`, `lookPanel*`, `lookRadius`, `headerActionConstraints`, `classicShelfCardHeight`…) |
| `ui_theme_picker.dart` | 799 | `UiThemePicker.show` loop (dialog → optional Try it → reopen on Go back), `showIfUnchosen` (first launch), `changeFromSettings`, dialog, `GlassStrengthControl`, `UiThemeSettingsTile` (look row, glass, 4 detail switches, Plain wording) |
| `ui_theme_preview.dart` | 408 | mock app screens per look, covers from `LibraryProvider.personalizedSections` |
| `ui_theme_try.dart` | 205 | `UiThemeTryOut` (static session: `start`/`keep`/`goBack`/`end`, Completer-based), floating bar above the nav bar |
| `ui_theme_appearance.dart` | 112 | `UiThemeAppearance` interface + real impl over main.dart's color notifiers (testable picker) |

State: 5 global `ValueNotifier`s (`uiThemeNotifier`, `uiThemePreviewNotifier`, `glassStrengthNotifier`, `glassStrengthPreviewNotifier`, `lookDetailsNotifier`); previews are memory-only. Tests: `ui_theme_test`, `ui_theme_glass_test`, `ui_theme_rendering_test`, `ui_theme_try_test`, plus picker tests. Traps: `AbsorbLook.copyWith` cannot reset a nullable token back to null; `AppUiTheme.spec` is used only by tests; `UiThemeTryOutBar` assumes an 80 px nav bar.

### `lib/utils/`

Fork:
- `app_motion.dart`: `AppMotion.resolveMode` (e-ink/snappy → instant, OS reduce motion → reduced), `AppMotionScope`. Scope sits in `home:` only (F10).
- `memory_policy.dart`: decoded image cache 64 MB / 500 entries, or Flutter defaults with "Full-quality covers"; `trimDecodedImageCacheForBackground` clears non-live images on background. Global listener on `uiThemeNotifier` (intentional, never removed).
- `performance_policy.dart`: `withActiveSurfaceTickers` (`TickerMode`).
- `smooth_wheel_scroll.dart`: intercepts `PlatformDispatcher.onPointerDataPacket` on Windows/Linux and re-emits each wheel notch as a critically damped spring over frames; skips over native textures (WebView2), e-ink, snappy and OS reduce motion. Raw `Ticker`, runs only while motion is pending.
- `scroll_diagnostics.dart`: opt-in with `ABSORB_SCROLL_DIAG=1` (desktop), no cost otherwise.
- `web_safe_platform.dart`: shadow `Platform` (isAndroid/IOS/Windows/Linux/MacOS) imported with `dart:io hide Platform` in 25 files. Duplicates upstream `app_platform.dart` (`AppPlatform`, 2 users) on purpose: the shadow class keeps upstream diffs to the import line.
- `fork_branding.dart`: one flag hiding the upstream donation card.

Upstream: pure helpers (`duration_format`, `episode_key`, `fuzzy_search`, `chapter_title_match`, `series_number_match`, `passage_match` (isolate EPUB matching), `transcript_align`, `cover_accent` (palette → accent), `server_url`, `percent_escapes`, `read_status`, `share_origin`, `whisper_language`, `absorbing_inclusion`, `text_file_download{,_stub,_web}` conditional export, `desktop_workspace` (web-only workspace checks, no live scope)). All have importers.

### `build_info.dart`, models, l10n

- `kBetaNumber` (5) is rewritten by `tool/dev.ps1 bump` (regex on `const int kBetaNumber = N;`); `betaNumberFor` hides it for even (stable) patch numbers.
- `models/auth_session.dart`: server auth-session list DTOs, used by `auth_sessions_screen.dart` and `api_service.dart`.
- l10n: `pubspec.yaml` `generate: true`; `l10n.yaml` = arb-dir `lib/l10n`, template `app_en.arb`, output `app_localizations.dart` (nullable getter, hence `AppLocalizations.of(context)!` everywhere). 12 `.arb` files, 13 generated `.dart`. `app_en.arb`: 3,665 keys, 514 `@` metadata entries, every placeholder key has metadata, no orphan metadata.

---

## PART 2: Findings

Severity: High / Medium / Low. Confidence: how sure the trace is without running the app. Recent fixes in `git log -30` (dispose leaks, logout leftovers, post-await context use, web Platform) were checked and are not repeated.

### Bugs

**F1. Offline and signed-out covers on Windows are treated as URLs.** Medium, confidence medium-high (needs one manual check). Owner: upstream sites, Windows is fork-only.
`getCoverUrl` (`_lp_state.dart:408-413`) returns `DownloadInfo.localCoverPath`, which is `File.path` from the download folder (`download_service.dart:829`): `C:\...` on Windows. Every consumer decides "local file" with `coverUrl.startsWith('/')` (app_shell.dart:580 plus about 30 sites in book_card, absorbing_card, expanded_card, home_screen, library_grid_tiles, book_detail_sheet, ui_theme_preview…). On Windows the path goes to `CachedNetworkImageProvider` and fails, so offline Home, Absorbing and the cover-derived app color show placeholders. Trigger: download a book on Windows, go offline (or let the session expire). Minimal fix: a fork helper `isLocalCoverPath(String s) => !s.contains('://')` (or `path.isAbsolute`) in a new util, and replace the `startsWith('/')` checks, starting with the screens the owner uses offline. Coordinate with the area 7 report, which owns most of those widgets.

**F2. Switching accounts keeps the previous account's appearance.** Medium, confidence high. Owner: upstream.
Theme mode, flat background, e-ink, color source, manual seed, gradient, use-color-everywhere, snappy and wording are per-account (`PlayerSettings._get` → `ScopedPrefs`, player_settings.dart:104). They are pushed into the notifiers only at startup (main.dart:803-817) and after a settings-sync import (`applyAppearanceFromPrefs`). `switchToAccount` (auth_provider.dart:1492) and the login paths (`_onAccountActivated` 1217) never call it, so the app keeps account A's look while Settings shows account B's saved values. E-ink also keeps `PlayerSettings.einkMode` and LibraryProvider's quiet state from A. Fix: after `UserAccountService().switchTo` and in `_onAccountActivated`, `await applyAppearanceFromPrefs()`; extend `applyAppearanceFromPrefs` (main.dart:222) with `snappyTransitionsNotifier` and `classicWordingNotifier`. Doing it in `AuthGate` when `activeScopeKey` changes keeps the change inside main.dart (already hooked by the fork).

**F3. A thrown error early in `_initServices` leaves the app on the loading screen forever.** Medium-low (rare), confidence medium. Owner: upstream.
`_initServices` (main.dart:763-850) awaits `UserAccountService().init()`, `ScopedPrefs.migrateToScope()`, about 15 prefs reads and the OLED migration with no try/catch. `tryRestoreSession` is only called at 850, and `AuthProvider._isLoading` starts `true` (auth_provider.dart:71), so any throw there (for example a corrupt `shared_preferences.json` on Windows, or a bad saved-accounts entry outside its inner try) keeps `AuthLoadingScreen` up with only a log line. Fix: wrap lines 796-845 in `try { … } catch (e) { debugPrint(…); }` so line 850 always runs; `tryRestoreSession` has its own handling.

**F4. A settings change can throw the user out of the Podcasts tab.** Low-medium, confidence medium (traced, not reproduced). Owner: upstream.
`PlayerSettings.settingsChanged` → `_loadPodcastTabPrefs` (app_shell.dart:441) always calls `_restoreBookLibraryForCurrentTab(restoreLibraryPage: true)`. On stack page 1 with the podcast library selected (the user is in the Podcasts destination), `shouldRestoreBookLibrary` returns true and `_syncTabLibrary(1, …)` switches back to the book library. 41 setters notify (`notify: true`), including `podcastQueueMode`, speed presets, skip lengths, cover size, which can be changed from the player while the shell is on page 1. Fix: pass `restoreLibraryPage: true` only from `initState`/`_loadStartScreen`, and only re-sync from the listener when `enabled`/`libId` actually changed.

**F5. On account switch to an unreachable server, the old account's live feeds keep running.** Low-medium, confidence high. Owner: upstream (fork already fixed the logout branch).
The `isNewUser`/fresh-login branch of `updateAuth` (library_provider.dart:190-223) stops connectivity, ping and health timers, but not `_stopBookOrbitPoll()`, `_stopLocalProbeTimer()` or `SocketService().disconnect()`. When the new server doesn't answer, the branch returns at line 265 before `socket.connect` (which would replace the old socket). Result: account A's Audiobookshelf socket stays connected with A's token and its callbacks still point into the provider, and A's BookOrbit notification feed keeps raising toasts in `AppShell`. Fix: in that branch add `_stopBookOrbitPoll(); _stopLocalProbeTimer(); SocketService().disconnect();` next to the other stops (3 lines, same pattern as the fork's logout fix).

**F6. Per-library shelf cache survives an account switch.** Low, confidence medium. Owner: upstream.
`_sectionsByLibrary` / `_sectionsFetchedAt` (_lp_state.dart:39-40) and `_locallyFinishedItems` are not cleared in the new-user or logout branches. Two accounts on the same server share library ids, so `selectLibraryLight` (library_provider.dart:530, Podcasts tab flip) briefly shows the previous user's Continue Listening shelves, or keeps them for up to 5 s inside the cooldown (_lp_core.dart:2020). `_locallyFinishedItems` from A suppresses B's local progress for the same item ids. Fix: clear these three in both branches.

**F7. `refreshLocalProgress` reads one pref per known item on every player change.** Low-medium (perf), confidence high. Owner: upstream (the fork already coalesced it).
`_runLocalProgressRefresh` (_lp_core.dart:982) awaits `ProgressSyncService().getLocal(itemId)` (a scoped prefs read plus `jsonDecode`) for every key of `_progressMap` (all server progress, often hundreds to thousands) plus downloads. Home calls it from its player listener (`home_screen.dart:319`) and `AppShell` on every tab tap. Fix (upstream-friendly): limit the scan to items that can have local progress (downloads, Absorbing list, current item), or keep an in-memory index of `progress_*` keys in `ProgressSyncService`.

**F8. Duplicate ARB key `statsTopGenres`.** Low, confidence high. Owner: upstream.
`app_en.arb:5427` and `:6535`, same value, also in `origin/main`. JSON last-wins, so harmless today; a future upstream edit to one copy would silently lose. Leave it to upstream (or report it there).

**F9. OS-level changes that never reach the theme.** Low, confidence high.
`AbsorbApp` reads `accessibilityFeatures.disableAnimations` (main.dart:491, fork) and `platformBrightness` (396, upstream) inside `build` with no subscription. Toggling OS reduce motion leaves the motion mode stale until another notifier fires; with theme "System", an OS dark/light switch updates `MaterialApp` but not the Android nav-bar colors set at 398. Fix: a small `WidgetsBindingObserver` in `AbsorbApp` (make it stateful) that calls `setState` on `didChangeAccessibilityFeatures` / `didChangePlatformBrightness`.

**F10. `AppMotionScope` only covers the first route.** Low (latent), confidence high. Owner: fork.
It is placed at `home:` (main.dart:688), so dialogs, sheets and pushed pages see `AppMotionScope.maybeOf == null`. Current users cope (`absorb_plus_logo.dart:214` falls back to `MediaQuery` + e-ink; `app_shell.dart:953` is inside home), but any future user in a pushed route silently gets "normal". Fix: move it into `absorbLookBuilder` or wrap `builder:` so it sits above the navigator.

### Rebuild storms

- **R1. `AppShell` rebuilds on every LibraryProvider notification.** `context.watch<LibraryProvider>()` in `_buildBottomNav` (940) and `_buildDestinations` (1662); it only needs `isPodcastLibrary`, `selectedLibraryId` and whether the podcast library exists. Each rebuild recreates the shortcuts map, `Scaffold`, `IndexedStack` wrappers and `NavigationBar`, and can schedule post-frame re-attach callbacks. Also `MediaQuery.of(context)` (936) rebuilds on every inset/keyboard change; `sizeOf` + `orientationOf` suffice. Fix: one `context.select` record. Upstream file, ~5 lines. Medium value on Windows (socket progress events notify often).
- **R2. Whole-`MaterialApp` rebuild on each new book's cover color** (`coverSchemeNotifier` in the merge list, main.dart:365), even when color source is "manual" and the result is identical (then only the two `ThemeData` builds are wasted; equal themes don't animate). Expected design; skip unless profiling points here.
- **R3. `AuthGate` watches all of `AuthProvider`** (950) and rebuilds `AppShell`'s build on every auth notify (token rotation, server toasts, version fetch). Cheap; note only.
- Checked and fine: `_runLocalProgressRefresh` and `_onDownloadsChanged` notify only on change; `Provider.of(context)` without `listen: false` does not occur in this area; `UiThemeScope` merges are cached in an `Expando` so rebuilding the scope is not a change.

### Memory and leaks

- No new leaks found. Global listeners are intentional and process-long (`_LookNotifier` on glass/details, `configureImageCache` on `uiThemeNotifier`, smooth wheel `Ticker`, scroll diag timer when opted in). `UiThemeTryOut` removes its listener in `_finish`. `AppShell` removes all its listeners in `dispose`; `LibraryProvider.dispose` (fork) covers its timers.
- `auth.apiService` builds a new `ApiService` per `_api` access (R-pattern P2 below); short-lived objects, no leak, but each fires an async prefs read in the constructor.

### Dead code (whole repo incl. `test/` and `tool/`)

| Item | Owner | Evidence | Action |
|---|---|---|---|
| `playAction` / `pauseAction` ARB keys (`app_en.arb:6992-6993`) | fork (d60da4f9) | no Dart reference outside generated files | remove from `app_en.arb`, regenerate |
| `StartupTaskCoordinator.runCritical` | fork | only `test/startup_tasks_test.dart` | remove with its test, or keep as test-only API |
| `AppUiTheme.spec` | fork | tests only | keep or inline into tests |
| `if (currentTime > 0 && _resetItems.remove(itemId))` (_lp_core.dart:1007) | upstream | unreachable: line 993 already `continue`s for reset items | leave (merge cost) |
| 126 more unused ARB keys (e.g. `whatsNewTitle`, `themeOled`, `colorSourceWallpaper`, `adminRmab*`) | upstream | no reference in `lib/`, `test/`, `tool/` | leave; they cost nothing and removal conflicts every merge |
| `DesktopWorkspaceScope`, `DesktopWorkspaceNavigator.register` | upstream | never instantiated/called, also upstream | leave |

### Duplication

- **D1. Appearance prefs are read three times** (main.dart:279-301, 803-822, `applyAppearanceFromPrefs` 222-231) with slightly different sets (the third lacks snappy, wording, locale, the sync caches). This drift is the root of F2. Upstream code; the fork-friendly fix is to make the startup re-read call one complete function.
- **D2. `web_safe_platform.Platform` vs upstream `AppPlatform`**: intentional (keeps upstream diffs to import lines). Keep.
- **D3. Cover-key parsing** `itemId.length > 36 ? substring(0, 36)` repeated in app_shell (564), `_lp_state` (393), `_lp_core` (637, 659) although `utils/episode_key.dart` exists. Upstream; leave.

### Risky patterns

- **P1. Formatting in fork-touched blocks** of upstream files: main.dart 491-692 (extra indent level) and 902-942 (`StartupTaskCoordinator` list), app_shell.dart 846-886. Not a bug, but it will make future conflicts in these blocks harder to read. Don't `dart format` (upstream file); fix by hand only when touching them.
- **P2. `AuthProvider.apiService` is a factory, not a cached client** (auth_provider.dart:279). Token state lives per instance; refreshed tokens reach other instances only through `loadPersistedTokens`. Upstream design; know it before caching an `ApiService` anywhere.
- **P3. Side effects in `build`**: `SystemChrome.setSystemUIOverlayStyle` (main.dart:398) and post-frame scheduling in `_buildBottomNav` (909-932). Upstream; leave.
- **P4. Docs drift**: ARCHITECTURE.md claims a desktop sidebar in app_shell and that widgets usually `context.select`; neither is true. Fix the doc.

---

## Recommended actions

Ranked by value ÷ (effort + merge cost).

| # | Action | Finding | Owner | Size | Risk |
|---|---|---|---|---|---|
| 1 | Stop BookOrbit poll, local probe and socket in `updateAuth`'s new-user branch (3 lines) | F5 | upstream file, fork-style hook | S | Low |
| 2 | Re-apply scoped appearance on account switch/login; make `applyAppearanceFromPrefs` complete and call it from `AuthGate` when the scope key changes | F2, D1 | main.dart (already fork-hooked) | S | Low |
| 3 | Guard `_initServices` 796-845 with try/catch so `tryRestoreSession` always runs | F3 | upstream file | S | Low |
| 4 | Verify on Windows, then add `isLocalCoverPath` and replace `startsWith('/')` in the screens used offline (app_shell first) | F1 | fork util + upstream call sites | M | Medium (many sites; merge cost) |
| 5 | Clear `_sectionsByLibrary`, `_sectionsFetchedAt`, `_locallyFinishedItems` on new user and logout | F6 | upstream file | S | Low |
| 6 | `context.select` in `_buildBottomNav`/`_buildDestinations`; `MediaQuery.sizeOf`/`orientationOf` | R1 | upstream file | S | Low |
| 7 | Only re-sync the Podcasts tab when its prefs changed | F4 | upstream file | S | Low (verify first) |
| 8 | Remove `playAction`/`pauseAction` ARB keys and `runCritical` | dead code | fork | S | None |
| 9 | Move `AppMotionScope` above the navigator; observe accessibility/brightness changes in `AbsorbApp` | F10, F9 | main.dart / fork | S | Low |
| 10 | Narrow the `refreshLocalProgress` scan | F7 | upstream file | M | Medium (progress display) |
| 11 | Correct ARCHITECTURE.md (no sidebar; watch vs select) | P4 | fork doc | S | None |
| 12 | Report duplicate `statsTopGenres` upstream (owner OK needed for upstream PRs) | F8 | upstream | S | None |
