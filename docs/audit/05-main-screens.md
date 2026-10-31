# Audit 05: main screens

Scope: `lib/screens/home_screen.dart`, `library_screen.dart`, `absorbing_screen.dart`, `settings_screen.dart`, `settings_search_index.dart`, `stats_screen.dart`, plus the widgets they own directly (`widgets/settings_search.dart`, `widgets/collapsible_section.dart`, `widgets/library_*_tab.dart`, `widgets/home_section.dart`).
Method: read-only. Grep plus windowed reads, `git log`/`git blame`, and the `background_downloader` source in the Pub cache. Line numbers are from the working tree on 2026-10-30. Other developers were editing these files during the audit (uncommitted `textScaleRoom` / `FittedBox` overflow fixes in home, library and stats), so expect a few lines of drift. Each finding also names its symbol.

---

## PART 1: Code map

### Ownership and size

| File | Lines | Owner | Fork diff vs `origin/main` |
|---|---|---|---|
| `screens/settings_screen.dart` | 5,995 | upstream | +311 / -38 (largest fork footprint of the five) |
| `screens/library_screen.dart` | 4,391 | upstream | +27 / -11 (plus uncommitted `textScaleRoom`) |
| `screens/stats_screen.dart` | 3,026 | upstream | +4 / -3 (plus uncommitted `FittedBox`) |
| `screens/absorbing_screen.dart` | 2,316 | upstream | +33 / -16 |
| `screens/home_screen.dart` | 1,472 | upstream | +7 / -6 (plus uncommitted `textScaleRoom`) |
| `screens/settings_search_index.dart` | 173 | upstream | +11 / -3 |
| `widgets/settings_search.dart` | 212 | upstream | none relevant |
| `widgets/collapsible_section.dart` | 70 | upstream | none |
| `widgets/library_{books,series,authors,narrators,lists}_tab.dart` | 283/139/150/135/180 | upstream | being edited (uncommitted) |
| `widgets/home_section.dart` | 510 | upstream | none relevant |

Every main screen is upstream-owned. The fork's code in them is hooks only. Pages are created lazily by `AppShell._buildPage` (`app_shell.dart:360-375`) and hosted in an **`IndexedStack`** (`app_shell.dart:870`), wrapped in `withActiveSurfaceTickers`. The trap is that every page stays mounted: an inactive page still **rebuilds** whenever a provider it watches notifies. Only its tickers pause.

### Shared fork hooks (all five screens)

- `ui_themes/ui_theme_hooks.dart`: `lookBackdrop`, `lookGlow` for the page gradient (home:545, library:2872/3053, absorbing:665, stats:458, settings:1880); `lookPanelColor`/`lookPanelSide` for Settings panels (1902, 2089, 2137); `lookCardColors` (home:1128); `usesClassicHomeShelves` (home:768).
- `services/wording.dart` (`Wording.of`, `classicWordingNotifier`): absorbing:807/947; settings:2360, 2716, 2830-2880, 4099-4100.
- `utils/web_safe_platform.dart` replaces `dart:io` `Platform` (61554b8c), so `Platform.isX` is web-safe here.
- `widgets/text_scale_room.dart`: **uncommitted**, home:401/…, library header `toolbarHeight`.

### `home_screen.dart` (1,472)

- **Structure.**
  - `HomeScreenState` 51-858: selection/batch 63-176, cache fields 181-194, `initState` 197, `_loadSettings` 219, `didChangeDependencies` 237, `_filterEbookOnly` 245, `_refreshFilteredCache` 262-306, `_onPlayerChanged` 317, `_heroShelf` 344-430 (Continue Listening/Reading big cards), `build` 444-857.
  - Inside `build`: batch FAB 492-538, page header with offline icon, select button, library picker and customize 567-668, shimmer 673, error 683, empty 706, section loop 747-847.
  - Then `_accentCache` 863 (process-wide `Map<String, Color>`, unbounded), `_ContinueListeningCard` 869-1472 (`_deriveScheme` palette extraction 952, `build` 985, `_openEbook` 1312, `_startBook` 1333).
- **State:** selection set, filtered-section cache keyed on list identity, cover shape and subtitles per library, `_hideEbookOnly`, `_cardsOpenDetails`, last player item and playing flag.
- **Reads:**
  - `context.watch<LibraryProvider>()` (450) and `context.watch<AuthProvider>()` (473) at the top of `build`.
  - `AudioPlayerService` listener calls `refreshLocalProgress` and `refreshProgressShelves` only on item change or stop.
  - Listens to `PlayerSettings.settingsChanged`.
- **Platform:** `DesktopBatchActionBar` (upstream widget) is used on every platform; `RefreshIndicator` pull-to-refresh (559).
- **Traps:** `_cachedSections` holds *unfiltered* ordered sections, and `_filterEbookOnly` re-runs on every build for each shelf (782). `build` mutates state (`_resetSelectionState`, `_selectedItemIds.retainAll`) without `setState`. That's intentional.

### `library_screen.dart` (4,391)

- **Top level, 1-331:** grid helpers, `LibrarySort`, `LibraryFilter`, `MissingMetadataField`, `SeriesFilter` enums and server-support predicates. These are public and used by `library_sort_filter_sheet.dart` and the tabs.
- **`LibraryScreenState` 339-4391:**

  | Lines | Part |
  |---|---|
  | 339-551 | fields: search controller, `FocusNode`, 5 scroll controllers, `TabController` |
  | 552-572 | `initState` |
  | 576-623 | socket listeners `_onItemRemoved` and `_onAuthorsChanged` (2 s debounce) |
  | 629-680 | book requests, RMAB flag, tabs |
  | 682-765 | `_onLibraryProviderChanged`: library switch resets every tab |
  | 767-1125 | `_tryInitialLoad`, `_restoreSortFilter`, `_onSettingsChanged`, `_loadFilterData` |
  | 1127-1149 | `dispose` |
  | 1158-1504 | `_loadPage`, `_loadOfflinePage` |
  | 1505-1717 | series paging |
  | 1718-1851 | authors and narrators |
  | 1852-2160 | sort/filter changes, tag/genre chips |
  | 2162-2217 | lists |
  | 2250-2519 | search (400 ms debounce, serialized with `_searchInFlight` and `_searchGen`; well guarded) |
  | 2520-2732 | sort/filter sheet |
  | 2733-2995 | `build`: batch FAB 2789-2856, gradient 2859, per-tab `CustomScrollView`s 2893-2931, floating tab bar and podcast pill 2933-2988 |
  | 3004-3247 | `_buildHeaderSliver` (watches the provider again) |
  | 3248-3465 | pills and manage button |
  | 3466-3593 | info row |
  | 3594-3690 | tabbed `IndexedStack` |
  | 3691 | grid |
  | 3719-3941 | selection, batch, author quick-match |
  | 3942-4003 | tab grids, delegating to `widgets/library_*_tab.dart` |
  | 4004-end | search results |
- **Reads:** `context.watch<LibraryProvider>` (2742, 3013, 3692), `watch<AuthProvider>` (2760), manual `lib.addListener(_onLibraryProviderChanged / _onLibraryChanged)`, `SocketService` listeners, `PlayerSettings.settingsChanged`.
- **Traps:** `dispose` uses `context.read` inside `try/catch` (1143-1147). See finding P3-4.

### `absorbing_screen.dart` (2,316)

- **`_AbsorbingScreenState` 62-1023:**
  - State fields: `PageController` swapped on orientation change, `_cardKeys` `GlobalKey` map, queue-mode fields.
  - `_loadQueueMode` 128, `_refreshUpNext` 175 (stamp-guarded), `_rebuild` 220 (player and cast listener with change detection), `_scrollToActiveCard` 323, `_stopAndRefresh` 377, `_pullRefresh` 399.
  - `build` 587-932: header and mode chips, page dots, card `PageView` 852-930 with a per-page `AnimatedBuilder` squeeze transform.
  - `_emptyState` 934, `_showReorderSheet` 959.
- **Other classes:** `_PageDots` 1025, `_ReorderAbsorbingSheet` 1088-2248 (the queue sheet: mode content loaders 1324-1476, lists 1797-2248), `_DragHandle` 2249.
- **Reads:** `watch<LibraryProvider>` (596), `AudioPlayerService` and `ChromecastService` listeners, `PlayerSettings.settingsChanged`.
- **Traps:** `build` calls `_loadMergeLibraries()`, `_loadQueueMode()` and `_refreshUpNext()` on **every build** (588-590), about 6 async prefs reads per frame of rebuilds. The idle loop was fixed in 00e4eaab with diff-guarded `setState`, but the reads remain.

### `stats_screen.dart` (3,026)

- **`_StatsScreenState` 32-2256:**

  | Lines | Part |
  |---|---|
  | 32-105 | state and `initState` (1.2 s `AnimationController`) |
  | 150-176 | infinite sessions paging |
  | 180 | `_loadGoalSettings` (about 12 sequential prefs reads, unconditional `setState`) |
  | 213 | year in review |
  | 345-442 | `_loadStats`: cache-first, then network stats, then sessions; account-scope guarded |
  | 445-489 | `build`: `AnimatedBuilder(_animValue)` wraps **all** of `_buildContent` |
  | 510-753 | `_buildContent`: computes every aggregate, then a section map ordered by user settings into a non-lazy `ListView(children:)` |
  | 762-1240 | charts |
  | 1250-1463 | year review |
  | 1464-1606 | goals |
  | 1607-1804 | hero, accent and period cards |
  | 1805 | bar chart |
  | 1945 | top items |
  | 2005-2256 | day sessions |
- **Other classes:** `SessionDetailsSheet` 2277-3025 (edit, delete, jump to start/end), `_JumpTarget` 3026.
- **Reads:** `context.read` only (no watch), plus `PlayerSettings.settingsChanged`.
- **Traps:** hard-coded English `_monthNames` (78; upstream).

### `settings_screen.dart` (5,995): section index

`_SettingsScreenState` 84-5995. Persistence is almost entirely `PlayerSettings` (`lib/services/player_settings.dart`, SharedPreferences through `ScopedPrefs`). Each setter calls `PlayerSettings._notify()`, which fires the global `settingsChanged`.

**State and helpers (84-1839)**

| Lines | Content |
|---|---|
| 85-143 | build flavor, `_versionLine`, update-frequency labels, desktop shortcut labels (fork, hard-coded English) |
| 145-183 | `_showDesktopShortcutsDialog` (fork) |
| 184-426 | about 120 state fields mirroring prefs |
| 323-407 | BookOrbit inbox (notifications and achievements), book requests |
| 428-449 | `_keyFor` / `_onSectionExpanded`: one `GlobalKey` per section; auto-scroll 350 ms after expand |
| 453-467 | `initState`: `_loadSettings`, What's new flag, book requests, admin issue count, sync status, socket and `settingsChanged` listeners, Libation new-export count (removed 2026-10-30) |
| 471-528 | Libation count (fork, removed 2026-10-30), admin issue badge (3 s debounce), ABS server update check, `dispose` |
| 530-546 | `_openSearchResult`: clear query, expand section, highlight after 700 ms |
| 548-626 | external queue-mode refresh, queue mode setters |
| 626-1185 | color swatches and custom color dialog, nav-hold dialog, stats goal editors, episode-notification interval, podcast tab library |
| **1186-1444** | **`_loadSettings`**: one 54-entry positional `Future.wait` (1187-1241), then about 25 sequential awaits. **The trailing index comments are stale** (they say 29-55 where the real indices are 28-53); the casts at 1243-1317 are correct. `results[47]` (`getClassicWording`) is fetched and never read. |
| 1454-1637 | per-library overrides (cover shape, subtitles, skip) |
| 1638-1810 | language picker, auto-download sources |
| 1811-1839 | rewind save, local server URL save |

**`build` (1840-5059)**

The whole page is one `SliverToBoxAdapter(Column)`. The search bar sits at 1896-1935. When the query is non-empty, the column is replaced by `SettingsSearchResults` (5045-5051).

| Lines | Section (`_keyFor` id) | Persistence |
|---|---|---|
| 1843-1871 | build-time side effects: admin issue retry, ABS update check, per-library override load, BookOrbit inbox reload (all post-frame) | none |
| 1942-1976 | Tips card | none |
| 1978-2083 | Profile card, BookOrbit inbox tiles | `UserAccountService` (account sheet 5472-5718) |
| 2084-2169 | Server Admin / BookOrbit admin tiles | none |
| 2170-2539 | **Appearance**: language 2185, `UiThemeSettingsTile` 2197 (fork), theme 2204, flat 2229, e-ink 2240, color source 2295, use color everywhere 2327, start screen 2346, progress text 2383, page fade 2410, subtitles 2423, rectangle covers 2435, cover size 2451, button fill 2487, lock rotation 2522 (iPad excluded) | `PlayerSettings.set*` plus `main.dart` `apply*` notifiers |
| 2540-2711 | **Customize Stats**: goals, book challenge, chart, section order/visibility | `setStatsGoalMinutesFor`, `setStatsBookGoal`, `setStatsWeekStart`, `setStatsChart*`, section order |
| 2712-3009 | **Absorbing Cards**: full-screen player, cover play, scrubber, speed-adjusted time, keep screen on, queue mode 2830-2960 (Wording), auto-download queue 2961, button grid reset 2987 | `setCard*`, `setFullScreenPlayer`, queue modes |
| 3010-3389 | **Playback**: speed presets 3099, skips, chapter barrier 3165/3319, long skip 3188, auto-rewind 3240-3389 | `PlayerSettings`, `AutoRewindSettings.save` |
| 3390-3473 | **Media Controls**: notification chapter progress, now-playing text, lock seek bar, Android only: duck interruptions and speed bookmark | `PlayerSettings` |
| 3474-3559 | **Car** (Android Auto / CarPlay sort and autoplay); **not platform-gated** | `setCar*`, `setAutoplayOnCarConnect`, `setKeepScreenOnInCarMode` |
| 3560-3612 | **Siri** (iOS only; dead on this fork) | none |
| 3613-3964 | **Sleep Timer**: shake, rewind, fade, chime, button mode; auto sleep 3857-3964 | `PlayerSettings`, `SleepTimerService().updateAutoSleepSettings` |
| 3965-4204 | **Downloads & Storage**: Wi-Fi only, concurrency, rolling downloads, auto-series 4017, auto-download sources 4065, download location 4114 (`!isIOS`), storage 4131, manage 4144 | `PlayerSettings`, `DownloadService` |
| 4205-4443 | **Library** (in `Consumer<LibraryProvider>`): podcast tab, hide e-book-only, home cards open details, Goodreads, explicit/e-book badges, per-library cover, subtitles and skip overrides | `PlayerSettings` (`setSkipOverride` and friends) |
| 4444-4509 | **Permissions**: notifications tile on **every platform**; episode notifications on Android/iOS; battery on Android | `permission_handler` |
| 4510-4678 | **Issues & Support**: Server health 4522 (fork, hard-coded English), tips, What's new 4549/4558 (fork), upstream issues/Discord/contact 4570-4600, logging 4606-4660 | `WhatsNewPrompt`, `PlayerSettings.setLoggingEnabled`, `LogService` |
| 4679-4877 | **Advanced**: nav hold, local server, trust certs, MP3 index (Android), pre-releases (`_updatesEnabled`), RMAB, book requests, Libation import (fork, removed 2026-10-30), transcription | `PlayerSettings`, `ScopedPrefs` (RMAB keys), `applyTrustAllCerts` |
| 4878-4910 | Support the Dev (hidden by `ForkBranding.showUpstreamSupportCard = false`) | none |
| 4911-4940 | Backup and sync | `SettingsSyncService` |
| 4941-4960 | All bookmarks | none |
| 4961-5043 | Version and Check for update (`UpdateCheckerService`, `UpdateDialog`) | none |

**After `build`:** rewind previews 5061, `_formatBytes` 5128, **`_pickDownloadLocation` 5135-5405 (which contains the misplaced "Windows Settings" section, 5246-5304; see B1)**, sync 5407-5471, account sheet 5472-5718, RMAB/Libation openers 5727-5778 (Libation removed 2026-10-30), logout, add, edit, remove and switch account 5779-5995 (context-after-await fixed in 9003f360).

**`settings_search_index.dart`:** 140 hand-written `SettingSearchEntry(sectionId, …)` rows. Each `sectionId` must equal a `_keyFor` id. It isn't generated, so new tiles silently drop out of search. **Missing:** book requests, RMAB import, Backup and sync, All bookmarks, Keyboard shortcuts, Server health, What's new. The `'Windows Settings'` row points at a section that isn't in the page (B1).

---

## PART 2: Findings

Severity: S1 (broken feature), S2 (wrong behaviour or notable cost), S3 (minor). Confidence: H, M or L.

### Bugs

**B1. The Windows Settings section can't be reached. S1, H, fork.**
- **Where:** `settings_screen.dart:5246-5304`. `CollapsibleSection(key: _keyFor('Windows Settings'))`, which holds the *Keyboard shortcuts* dialog and the *Update check frequency* dropdown, sits **inside `_pickDownloadLocation`'s bottom sheet, nested in `if (legacyCount > 0)`**, not in `build`.
- **History:** it has been there since it was introduced in 61146dfe ("feat: add Windows settings and update frequency control"); `git show 61146dfe:` puts it inside `_pickDownloadLocation` too.
- **Effect on Windows:**
  1. The section never shows.
  2. The update frequency is stuck at the default of every 12 hours.
  3. The settings-search row (`settings_search_index.dart:168-169`) opens nothing, because `_keyFor('Windows Settings').currentContext == null`.
  4. If it ever does render (Windows, legacy external downloads, sheet open), its `setState` calls don't rebuild the sheet.
  5. The overflow sweep ("Settings, every section open") can't cover it.
- **Fix:** move lines 5246-5304 into `build`, after the Advanced section (around line 4877), and drop it from the sheet. About 60 lines moved, fork-only code.

**B2. "Choose folder" for downloads always fails on Windows and Linux. S2, H, upstream.**
- **Where:** `settings_screen.dart:4114`. The tile is gated only by `!Platform.isIOS && _canPickDownloadLocation`, and `_canPickDownloadLocation` is set `true` unconditionally (1426).
- **Cause:** "Choose folder" (5345) calls `FileDownloader().uri.pickDirectory`. In `background_downloader` 9.5.5, `_DesktopUriUtils.pickDirectory` throws `UnimplementedError` (`uri_utils.dart:292-302`).
- **Effect:** the catch shows "can't write to that folder", so desktop users see a dead setting.
- **Fix, either:**
  - gate the tile with `Platform.isAndroid` (one-line upstream touch); or
  - make it fork-side: a desktop folder picker via `FilePicker.platform.getDirectoryPath()` (already used in `admin_upload_screen.dart:670`), but only if `DownloadService.setCustomDownloadUri` accepts `file://` URIs on Windows. That needs checking by the downloads auditor.

**B3. Support links send fork users to the upstream developer. S2, H, fork policy.**
- **Where:** `settings_screen.dart:4570-4600`.
  - "Bugs & feature requests" opens `github.com/pounat/absorb/issues`.
  - "Join Discord" opens upstream's Discord.
  - "Contact" emails `LogService.supportEmail` (`absorb@barnabashq.com`, `log_service.dart:15`).
  - "Send logs" likely goes to the same place; not traced.
- **Why it matters:** `ForkBranding` already hides upstream's Support card. These rows route Absorb Plus bug reports, with device info and logs, to someone who doesn't ship this build.
- **Fix:** owner decision. Add `ForkBranding.issuesUrl` / `supportEmail` and hide Discord. That's a small fork-owned change plus a 3-line hook.

**B4. Stats never refreshes on Windows with a mouse. S2, M, upstream.**
- **Where:** `stats_screen.dart:99, 474-478`. `_loadStats` runs once in `initState` (the page is kept alive for the session) and otherwise only through `RefreshIndicator`.
- **Cause:** there is no custom `ScrollBehavior` (grep finds none). Flutter's default desktop `dragDevices` exclude the mouse, so pull-to-refresh can't start with a mouse.
- **Effect:** with the app living in the tray, Stats (today, week, streak, sessions) can be days old. Home, Library and Absorbing get data pushes; Stats doesn't.
- **Fix, fork-side, either:**
  - reload when the Stats tab becomes active (`AppShell` already knows `_currentIndex`); or
  - a refresh action in the header on desktop.

  Confidence is M because touch and trackpad users can still pull.

**B5. The Permissions → Notifications tile is shown on every platform. S3, M, upstream.**
- **Where:** `settings_screen.dart:4453-4471`.
- **Linux:** no `permission_handler` plugin is registered (`linux/flutter/generated_plugins.cmake` has none), so `Permission.notification.status` throws `MissingPluginException` as an unhandled async error and the tap does nothing.
- **Windows:** `permission_handler_windows` is registered, but the result is meaningless.
- **Related:** the Car (3474-3559) and Siri sections need the same platform review. Car (Android Auto/CarPlay) shows on desktop and web.
- **Fix:** wrap these in `Platform.isAndroid || Platform.isIOS`. Small upstream touches.

**B6. Build-time post-frame loaders can fire twice. S3, H, upstream.**
- **Where:** `settings_screen.dart:1854-1865`.
  - `_serverUpdateCheckRunning` and `_serverUpdateCheckedFor` are only set inside `_loadServerUpdate`, which runs post-frame. Two builds before that frame (two watched providers notifying) schedule two uncached GitHub requests (`AudiobookshelfUpdateService.check` has no cache).
  - Likewise `_loadCurrentLibraryOverrides` is rescheduled on every build until `_curLibId` updates.
- **Fix:** set `_serverUpdateCheckedFor = serverVersion` (and a pending library id) synchronously in `build`, before scheduling.

**B7. `jumpToPage(0)` is called during build. S3, M, upstream.**
- **Where:** `absorbing_screen.dart:617-620`. On a library switch, `build` calls `_pageController.jumpToPage(0)`. That dispatches scroll notifications mid-build, which risks "setState during build" in listeners.
- **Fix:** move it into `addPostFrameCallback`.

**B8. Podcast detection by id length. S3, L, upstream.**
- **Where:** `absorbing_screen.dart:1225`. `_currentPodcastShowId` decides "podcast" by `id.length > 36`, which assumes UUID item ids. Legacy `li_…` ids, or another server's id format, would misclassify.
- **Fix:** flag only; prefer `_player.currentEpisodeId != null`.

### Rebuild and performance

**P1. Settings rebuilds its entire ~3,200-line tree on every `LibraryProvider` and `AuthProvider` notification, even while hidden. S2, H, upstream.**
- **Where:** `settings_screen.dart:1843-1844`, top-of-build `context.watch` for both providers. Because of the `IndexedStack`, the Settings page stays mounted, so every library notification rebuilds it from any tab.
- **What one rebuild costs:**
  - It constructs every section's children list. `ExpansionTile` skips elements for collapsed sections, but every widget constructor still runs.
  - It also re-runs the four build-time side-effect checks.
- **What it actually uses:** `lib.libraries` and `lib.selectedLibraryId` outside the scoped `Consumer` (4214); auth fields that rarely change.
- **Fix:** replace the two watches with `context.select`. For example, `select<LibraryProvider, (List, String?)>((l) => (l.libraries, l.selectedLibraryId))`, and the same for the auth fields. A few upstream lines; measure with `/perf-measure`.

**P2. Stats rebuilds and recomputes everything every animation frame. S2, H, upstream.**
- **Where:** `stats_screen.dart:481-484`. `AnimatedBuilder(animation: _animValue, builder: (_, __) => _buildContent(...))` reruns all of `_buildContent` (510-753) on every tick of the 1.2 s animation: streaks, longest streak, heatmap over a year of days, top items, habits, every session row.
- **When it runs:** on first load, after cached-then-network loads (`reset/forward` at 386 and 421), on every media switch (114) and on refresh. That's about 70-170 full rebuilds each time, on the Windows CPU.
- **Fix:** compute the aggregates once per data change (memoize on `_stats`, `_media`, `_chartRange`, `_weekStart`) and pass `_animValue` only to the widgets that animate (hero count-up, bars). Medium upstream diff, so do it only if `/perf-measure` shows a cost.

**P3. Smaller costs. S3.**
1. **Absorbing:** 6 async prefs reads on every build (588-590); move them to `settingsChanged` and library-change hooks. H.
2. **Home:** `_filterEbookOnly` allocates a new list per shelf on every build when "hide e-book-only" is on (782, 773), so `HomeSection` always gets fresh lists. Fold the filter into `_refreshFilteredCache`. M.
3. **The global `PlayerSettings.settingsChanged` fan-out:** any setting toggle triggers:
   - Stats `_loadGoalSettings`: about 12 sequential reads plus an unconditional `setState`, which means P2-sized rebuild work minus the animation;
   - Home `_loadSettings`;
   - Library `_onSettingsChanged`;
   - Absorbing `_loadQueueMode`;
   - Settings' own `_onExternalSettingsChange`, a second full Settings rebuild.

   Diff-guard the Stats `setState`. H.
4. **Library `dispose`:** `context.read<LibraryProvider>()` sits inside `try/catch` (1143-1147). In debug the deactivated-ancestor assert throws, the catch swallows it, and the listeners leak (they're harmless because they check `mounted`). Cache the provider in `initState`. Low value; the page is rarely disposed. M.
5. **Home:** `didChangeDependencies` reads a pref on every dependency change (237). On desktop that's every window-resize frame, via the `MediaQuery` dependency from `textScaleRoom`. L.
6. **Unbounded caches:** `_accentCache` (home:863, a Color per cover URL) and Absorbing `_cardKeys` (68, a `GlobalKey` per absorbing key ever shown) are never pruned. They're small, but clear them on account switch. L.

### Layout risks at desktop sizes

These are not covered by `test/ui_overflow_sweep_test.dart`, which checks overflow at 6 sizes, not width or stretching.

- **Settings and Stats have no max content width.** At 1920 px, tiles stretch edge to edge: switches about 1.5k px from their labels, the three period cards very wide, the heatmap stretched. Only the shortcuts dialog is constrained (151). This is an owner decision because of the "keep the normal look" rule. If wanted, one fork-side `Center(ConstrainedBox(maxWidth: ~900))` wrapper in `AppShell` around pages 3 and 4 costs no upstream lines.
- **The Absorbing card `PageView`** uses `viewportFraction: 0.92` at any width (66, 608), so on a wide window a single card is about 1,700 px wide. It depends on `AbsorbingCard`'s internal wide layout (another auditor's area). Mouse drag can't page the `PageView` (same `dragDevices` reason as B4); dots and keys remain.
- **Fixed heights with text:** the home hero row (401) and library `toolbarHeight` (192/…) are being patched right now with `textScaleRoom` (uncommitted). Re-check after that lands; not duplicated here.
- **Home hero shelf header:** `Row` (368-383) has an unflexed `Text(title)` beside an `Expanded` divider. A long localized title at narrow width overflows. The sweep may catch it in English only.

### Dead code, duplication, hygiene

- **Dead:** the Siri section (settings:3559-3612), the search entries (index:97+), `_refreshSiriStatus` (1446) and the `Platform.isIOS` branches all compile but never run on this fork (Apple removed). Leave them: they're upstream lines and removal costs merge conflicts.
- **Dead fetch:** `results[47]` `getClassicWording()` (1235) in `_loadSettings` is fetched and discarded. Trivial; upstream.
- **Stale comments:** the 54-entry positional `Future.wait` index comments (1214-1241). This is a trap for the next person adding a setting. If touched, convert the fork additions to named locals after the `wait`, as the code already does for later settings.
- **Hard-coded English (fork-added):** the keyboard shortcut labels and dialog (122-183), "Server health" (4522-4523), "Keyboard shortcuts" (5259-5261). They belong in `app_en.arb` per AGENTS.md. Upstream also hard-codes "Lock rotation", "Duck brief interruptions", "Auto-download series" and Stats `_monthNames`; leave those.
- **Duplication:**
  - Home and Library carry near-identical selection and batch code (`_toggleSelection`, `_toggleSelectAll`, `_runBatchAction`, `DesktopBatchActionBar` wiring: home:63-176/492-538, library:3719-3825/2811-2855).
  - The page gradient block is copied five times (now with `look*` hooks).
  - The queue-mode "more restrictive" merge is copied in settings:236-244 and absorbing:140-146 (the comment admits it).

  All upstream; not worth extracting at the current merge cost.
- **Search index drift:** see Part 1. Eight fork and upstream tiles aren't searchable. A test that walks the Settings tree (the sweep already pumps "every section open") and asserts each `ListTile` title appears in `settingsSearchEntries` would stop the drift.

### Risky patterns checked, no new issue

- Context after `await` in account flows: fixed in 9003f360.
- `_startBook` and `_openEbook`: `mounted` / `context.mounted` guards present.
- Library search: serialized and generation-guarded.
- `_loadStats`: account-scope guarded.
- Controllers: all disposed. Library has 5 `ScrollController`s, `FocusNode`, `TabController`. Stats' session editor disposes its 5 `TextEditingController`s on both paths.
- `_DragHandle` `AnimationController`: disposed.
- `_deriveScheme` `setState` from build: a no-op on the dirty element, so harmless.

---

## Recommended actions (ranked by value ÷ (effort + merge cost))

| # | Action | Tag | Size | Risk |
|---|---|---|---|---|
| 1 | **B1:** move the Windows Settings section from `_pickDownloadLocation` into `build`, after Advanced. Verify search opens it. | fork | S | low |
| 2 | **B3:** route the issues, contact and log links through `ForkBranding` (fork repo issues, owner's address or none); hide upstream Discord. Owner OK needed for the destination. | fork | S | low |
| 3 | **P1:** replace Settings' top-level `watch<LibraryProvider/AuthProvider>` with `select`. Measure before and after with `/perf-measure` (idle CPU while playing on another tab). | upstream (about 4 lines) | S | low |
| 4 | **B2:** hide "Download location" off Android, or a desktop picker after the downloads audit confirms `file://` support. | upstream (1 line) or fork | S | low |
| 5 | **B4:** refresh Stats when its tab becomes active (throttled, e.g. at most once per 60 s) from `AppShell`'s tab switch. | fork hook | S | low |
| 6 | **B6:** set the guard fields synchronously before the post-frame loaders in Settings `build`. | upstream (2-3 lines) | S | low |
| 7 | **B5:** platform-gate Permissions → Notifications and the Car section to Android/iOS. | upstream (2 wraps) | S | low |
| 8 | Move the fork's hard-coded English (shortcuts, Server health, Windows Settings) into `app_en.arb`. | fork | S | low |
| 9 | Add a settings search-coverage test (every tile title in a section has an index entry); add the 8 missing entries. | fork test + upstream index lines | M | low |
| 10 | **P3-3:** diff-guard `setState` in Stats `_loadGoalSettings`. **P3-1:** stop the per-build prefs reads in Absorbing. | upstream | S | low-med (queue mode logic) |
| 11 | **B7:** move Absorbing `jumpToPage(0)` to post-frame. | upstream | S | low |
| 12 | **P2:** memoize Stats aggregates and narrow the `AnimatedBuilder` scope, only if a measurement shows a hit. | upstream | M | med (merge churn in a large build) |
| 13 | Max content width for Settings and Stats on desktop. **Owner decision** (look rule). | fork (`AppShell` wrapper) | S | low |
| 14 | Leave the Siri and iOS dead code, the duplicated selection/gradient code and the `_loadSettings` positional list alone unless upstream restructures them. | upstream | none | none |
