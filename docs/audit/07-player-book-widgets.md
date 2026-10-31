# Audit 07: player, card and book widgets (`lib/widgets/`)

Read-only audit, 2026-10-30, branch `claude/slim` (working tree has other auditors' uncommitted overflow fixes in `absorbing_card.dart`, `book_detail_sheet.dart` and the library tabs; line numbers below are from that working tree).

Owner: `up` = file exists on `origin/main` (upstream-owned, merge cost applies); `fork` = fork-only. "Fork diff" = lines changed vs `origin/main`.

## Files covered

Deep read (logic, listeners, lifecycle): `absorbing_card.dart`, `expanded_card.dart` (state/lifecycle/item change), `card_progress_bar.dart`, `card_edge_progress_bar.dart`, `card_buttons.dart` (state classes, bookmark/speed), `absorbing_shared.dart`, `absorb_plus_logo.dart`, `absorbing_nav_icon.dart`, `wavy_progress_indicator.dart`, `cover_decode.dart`, `library_item_snapshot.dart`, `stable_cached_network_image.dart`, `book_card.dart` (fork diff + pressable), `book_detail_sheet.dart` (build roots, Absorb button, `_startAbsorb`, chapter rows).

Grep-level (listeners, images, gestures, dispose): `card_button_config.dart`, `card_playback_controls.dart`, `card_scrubber_mode_selector.dart`, `card_chapters_sheet.dart`, `absorb_slider.dart`, `episode_detail_sheet.dart`, `episode_row.dart`, `episode_list_sheet.dart`, `library_grid_tiles.dart`, `home_section.dart`, `cover_badges.dart`, `series_books_sheet.dart`, `series_card.dart`, `collection_detail_sheet.dart`, `playlist_detail_sheet.dart`, `section_detail_sheet.dart`, `sleep_timer_sheet.dart`, `equalizer_sheet.dart`, `bookmark_detail_dialog.dart`, `clip_editor_sheet.dart`, `lyrics_overlay.dart`, `now_playing_text_sheet.dart`, `absorb_wave_icon.dart`, `book_stats_sheet.dart`, `book_files_sheet.dart`, `books_sheet_shared.dart`, `chromecast_button.dart` (+ `_stub`).

Not covered (left to the other widgets auditor): readers (`ebook_*`, `foliate_*`, `pdf_*`, `comic_*`, `page_curl`, `reader_tap_zones`), library tabs, admin/settings/rmab/libation/update/whats-new widgets, `podcast_episode_feed.dart`, `book_activity_card.dart`, `author_card.dart`.

---

# PART 1 — Code map

## Player cards (rebuild with playback)

### `absorbing_card.dart` — up, 1,395 lines, fork diff +10
- **Purpose:** one page of the Absorbing tab's PageView: blurred-cover background, cover with play overlay, stats row (elapsed / % / remaining), chapter scrubber, playback controls, configurable button grid, thin edge progress bar. Swipe up opens `ExpandedCard`.
- **Used by:** `screens/absorbing_screen.dart:867,920` only, keyed by absorbing key and wrapped in a `RepaintBoundary`. `AutomaticKeepAliveClientMixin` keeps every visited card alive.
- **State:** cover provider/identity, raw cover `ColorScheme`, pre-blurred `ui.Image` (`_blurredCover`, disposed on change/dispose), top-strip luminance, fetched chapters/ebook file, `_lastChapterIdx`, saved speed, button order/visible count/icons-only/more-inline, cover shape, `_isStarting`, `_edgeBarExpanded` notifier.
- **Listens to:** `ChromecastService`, `DownloadService` (setState on every notify), `PlayerSettings.settingsChanged` (4 async pref reads), `player.absolutePositionStream` (subscription per card, filtered by `_isActive`), `context.watch<LibraryProvider>()` at :614 (whole card rebuilds on every provider notify), `ListenableBuilder(merge[Chromecast, player])` around the cover area (:861), `LyricsService.instance` around the cover, `StreamBuilder` for the stats row (:787).
- **Rebuild rate while playing:** stats row 1–2 Hz (vendored just_audio position stream is 500–1000 ms, `packages/just_audio/lib/just_audio.dart:641`); whole card on every chapter change, on every LibraryProvider notify (each play/pause/seek via `refreshLocalProgress`), and **every second for chapterless books/podcasts** (:398–404 uses `_lastChapterIdx` as a seconds counter). Scrubber + edge bar repaint at 10 Hz (see below).
- **Platform:** imports `dart:io` (`File`) for local covers; unreachable on web because cover paths starting with `/` only come from downloads. Cast paths are Android-only in practice.
- **Traps:** `_onCoverLoaded` runs from inside `imageBuilder`/`Builder` during build and kicks off `ColorScheme.fromImageProvider` + `_precacheBlur` (guarded by identity checks — don't remove those guards). `debugPrint('[Card] …')` on state-shape change is intentional diagnostics. `_onSpeedMaybeChanged` is removed in dispose but never added (dead). `initialBlurredCover` is passed to `ExpandedCard` but ignored there.

### `expanded_card.dart` — up, 1,305 lines, no fork diff
- **Purpose:** full-screen player (`ExpandedCardRoute`, opaque, `maintainState`). Same layout family as the card, plus history/chapters/etc. Swipe down closes; auto-dismisses when the book finishes; follows auto-advance in place (`_handleItemChange`, :356).
- **Used by:** `absorbing_card.dart:1298` (`expandCard`) and `screens/app_shell.dart:692` (`_maybeAutoExpand`).
- **Listens to:** `player.addListener(_onPlayerChanged)` → full `setState` on every player notify; Chromecast; settings; position stream for chapter tracking (same per-second setState for chapterless items, :450–456); `context.watch<LibraryProvider>()` at :620.
- **Traps:** most logic (chapter tracking, blur generation, cover scheme, button order) is a copy of `absorbing_card.dart`; fixes must be made twice. Item change happens in-place, so child widgets without `didUpdateWidget` keep the old item's state (see F7).

### `card_progress_bar.dart` — up, 762 lines, fork diff +40
- **Purpose:** `CardDualProgressBar` (book + chapter bars, drag/tap seek with vertical fine-scrub, chapter name marquee, time labels), `ChapterPillPainter`, `MarqueeText`.
- **Used by:** `absorbing_card.dart` (scrubber), `expanded_card.dart`.
- **State:** drag values, scrub speeds, scrubber mode, smooth-position anchor (`_lastKnownPos/_lastPosTime/_currentSpeed/_isPlaying`), `_smoothTicker` (100 ms `Timer.periodic` → `_tickNotifier` → `ListenableBuilder`).
- **Listens to:** position stream (or cast stream), Chromecast, settings, app lifecycle, `TickerMode` notifier (fork fix f1a0160f stops the timer on hidden tabs/covered routes and when backgrounded).
- **Rebuild rate:** 10 Hz while playing and visible. `MarqueeText` animates via vsync only while `animate` (fork fix c294af19).
- **Traps:** `_isPlaying` is only refreshed from position events; the bar does not listen to the player. The seek-target filter (`activeSeekTarget` ± 5 s) and near-zero rejection are load-bearing for multi-file books.

### `card_edge_progress_bar.dart` — up, 536 lines, fork diff +39
- **Purpose:** 3.5 px strip at the card top that expands to 50 px on drag/long-press for book scrubbing; `EdgeProgressPainter`.
- **Used by:** `absorbing_card.dart:1184` only.
- **Listens to / rate:** same position/ticker machinery as `card_progress_bar.dart` (copied ~150 lines), plus an `AnimationController` for expand. Its own 100 ms timer — a playing card runs two independent 10 Hz timers. Fork fixed a per-tick `CurvedAnimation` leak (comment at :75).

### `card_buttons.dart` — up, 3,061 lines, no fork diff
- **Purpose:** everything the button grid and "More" menu do: `Pressable`, `CardWideButton`, `MoreMenuItem`, sleep/download/bookmark/speed inline buttons, `CardSpeedSheet`, `SimpleBookmarkSheet`, `MoreMenuSheet` (reorderable), `CardActionDelegate` (~900 lines of action handlers), playback history sheet, keep-screen-on toggle.
- **Used by:** absorbing/expanded cards, `card_playback_controls`, `book_detail_sheet`, `ebook_reader_view`, bookmarks/car-mode/downloads/home screens.
- **State/listeners:** most buttons use `ListenableBuilder` on player/cast/download/sleep (rebuild on notify, not on ticks). `_CardBookmarkButtonInlineState` syncs bookmarks with the server in `initState` (:505) and has no `didUpdateWidget`. `_CardSpeedButtonInlineState` loads saved speed per item on init/settings change only.
- **Traps:** several dialogs create `TextEditingController`s and never dispose them (:1248–1249, :1282–1283, :2897–2898). Speed preset removal is long-press only (:787).

### `card_playback_controls.dart` — up, 220 lines
Skip back/forward + play button row; `ListenableBuilder` on player; settings listener removed in dispose. Has `didUpdateWidget`. No issues found.

### `card_button_config.dart` — up, 97 lines, fork diff 1 line
Button id → icon/label table (`CardButtonDef`), consumed by `player_settings`, `card_buttons`, `ebook_reader_view`. Pure data.

### `card_scrubber_mode_selector.dart` (up, 72) / `card_chapters_sheet.dart` (up, 142)
Settings picker for the scrubber mode (used only by `settings_screen`); chapter list sheet (pull-based position read on open, jumps to current chapter). No issues.

### `absorb_slider.dart` — up, 496 lines
Themed Material `Slider`/`RangeSlider` shapes + `AbsorbProgressPainter` (used by `card_progress_bar`). Built on Material sliders, so keyboard/focus work.

### `wavy_progress_indicator.dart` — up, 173 lines
Repeating 1.4 s `AnimationController` (vsync, so muted when hidden). Only used by `update_dialog.dart:131` — fine while the dialog is up.

### `lyrics_overlay.dart` (up, 622) / `now_playing_text_sheet.dart` (up, 264)
Live transcript overlay on the cover (`_RollingLine` runs a 220 ms forward animation per line change, not repeating). Now-playing text sheet is settings-only. No issues found at grep level.

## Logo and icons

### `absorb_plus_logo.dart` — fork, 324 lines
`AbsorbPlusGeometry` (shared with `tool/make_icons.py`), `AbsorbPlusMark`, `AbsorbPlusLogo`, `AnimatedAbsorbDrop` (Ticker; envelope fade; stops when idle, reduced motion or e-ink; own `RepaintBoundary`). `AbsorbPlusLogo` is referenced only by `test/absorb_plus_logo_test.dart` (no app use).

### `absorbing_nav_icon.dart` — fork, 54 lines
Absorbing tab icon; listens to the player and rebuilds only when `isPlaying` flips; drives `AnimatedAbsorbDrop(animating: playing)`. Used by `app_shell.dart:1697–1698`. **While anything plays and the shell is visible, the ticker requests a frame every vsync** (F3).

### `absorb_wave_icon.dart` — up, 185 lines, fork diff −101/+…
Upstream `AbsorbWaveIcon` delegates to `AbsorbPlusMark`; `AbsorbActionIcon`/`AbsorbReplayIcon`/`AbsorbWatchIcon` remain. Used by login, auth loading, session cards, theme previews, book sheet.

### `absorbing_shared.dart` — up, 403 lines, fork diff −57
Formatting helpers (`fmtTime`, `fmtDur`, `dateLabel`), `EinkCoverTone`, `CoverPlaceholder`, `BlurPaddedCover` (live `ImageFiltered` blur sigma 24 behind contained covers), `DownloadWideButton` (DownloadService listener), `AbsorbingWave` (fork: now `AnimatedAbsorbDrop(animating: true)` — always animating while mounted).

## Book / episode / list widgets

### `book_detail_sheet.dart` — up, 4,129 lines, fork diff +21/−14 (incl. uncommitted overflow fixes)
- **Purpose:** the book sheet: cover (full viewer), metadata, Absorb button with progress fill, quick-actions variant (`showQuickActionsSheet`), chapters, bookmarks preview player, files/stats sheets, mark finished, notes, dock (unfiled upload) view, read-along sync banner.
- **Used by:** ~12 screens/widgets (`showBookDetailSheet`).
- **State:** one 3,750-line `State` (`_BookDetailSheetContentState`): `_item`, cover scheme, `_isAbsorbing`, preview player, cached ebook fallback, etc.
- **Listens to:** `context.watch<LibraryProvider>()` in three build roots (:755, :1841, :2311) → whole sheet rebuilds on every provider notify; Absorb buttons use `ListenableBuilder(merge[AudioPlayerService, DownloadService])` (:984, :2064); `ReadListenSync` notifiers; chapter rows read `player.position` on rebuild (no stream).
- **Traps:** `AbsorbingWave` in the Absorb button animates continuously while `_isAbsorbing || isCurrentPlaying`. `_startAbsorb` (:3539) pops the sheet before playback; context use after awaits was hardened by fork 9003f360.

### `episode_detail_sheet.dart` (up, 840) / `episode_row.dart` (up, 317) / `episode_list_sheet.dart` (up, 1,138)
Episode sheet (+ `showQuick` long-press variant), episode rows (`context.watch<LibraryProvider>()` in `_EpisodeRowState` :37 and `SelectableEpisodeRow` :277; two `ListenableBuilder`s on player/downloads), show episode list. Lists are lazily built, so the full-provider watch is bounded by visible rows.

### `book_card.dart` — up, 618 lines, fork diff +64
Home shelf card. Fork: `context.select` → `LibraryItemSnapshot`, bounded decode via `coverDecodeWidth`/`themedCoverDecodeWidth`. `_PressableCard` (100 ms scale on tap down). Traps: `File(..).existsSync()` in build (upstream), long-press opens quick sheet.

### `library_grid_tiles.dart` — up, 1,099 lines, fork diff +36
`GridBookTile` (fork snapshot select + bounded decode), `GridSeriesTile`/`GridSeriesTileDirect` (stacked covers, bounded decode at :336–364), `GridListTile` (list mode), `showSeriesScanMenu`. `GridSeriesTile` :541, `GridSeriesTileDirect` :649 and `GridListTile` :785 still `context.watch<LibraryProvider>()`.

### `home_section.dart` (up, 510, fork +3) / `series_card.dart` (up, 255) / `section_detail_sheet.dart` (up, 372)
Home shelf rows, `_EpisodeCard` (watches provider, :350), series card, "see all" sheet. Local covers via `Image.file` without `cacheWidth`.

### `series_books_sheet.dart` (up, 1,705) / `collection_detail_sheet.dart` (up, 786) / `playlist_detail_sheet.dart` (up, 832)
Detail sheets with reorderable lists (collection/playlist edit mode), swipe-to-add-to-Absorbing (`SwipeAction`), sub-series expansion. All `context.watch<LibraryProvider>()`. Thumbnails: network covers at server width 400 (fine); local covers decoded full size.

### `sleep_timer_sheet.dart` (up, 901) / `equalizer_sheet.dart` (up, 734)
`ListenableBuilder(SleepTimerService)` (1 Hz while counting); equalizer listener removed in dispose. No issues.

### `bookmark_detail_dialog.dart` (up, 765) / `clip_editor_sheet.dart` (up, 445)
`BookmarkDetailSheet` (title/note edit, preview player, clip editor) opened by tapping a bookmark (`card_buttons.dart:1058`, `bookmarks_screen.dart:539`). Controllers and listeners disposed correctly.

### Covers: `cover_decode.dart` (fork, 21), `library_item_snapshot.dart` (fork, 58), `stable_cached_network_image.dart` (up, 31), `cover_badges.dart` (up, 144, fork +2)
Decode-size clamp 64–1024 px; snapshot value object for `context.select`; `stableCoverCacheKey` strips token/ts so cache survives token refresh; badges overlay. Note: bounded decodes for the **player cards / book sheet / home** were tried and reverted (70fb4fcf → e840dee4 "restore original cover rendering"), so large-cover surfaces intentionally decode full size.

### Misc: `book_stats_sheet.dart` (up, 227), `book_files_sheet.dart` (up, 348), `books_sheet_shared.dart` (up, 230), `chromecast_button.dart` (up, 247 + stub 29)
Stats (ListenableBuilder), file info, shared sort/filter helpers for book sheets, cast picker (`StreamBuilder` of devices; Android). No issues at grep level.

---

# PART 2 — Findings

Severity: H/M/L. Confidence: high = traced in code; medium = traced but impact depends on runtime behaviour not measured; low = plausible, needs a check.

## Bugs

**F1. Absorb button can stick in the "absorbing" state (animated) — M, high.**
`book_detail_sheet.dart:1044` / `:2087` / `:3680` set `_isAbsorbing = true`, then `_startAbsorb` returns at `:3590` `if (api == null) return;` without resetting it (only the narration-download branch resets, :3543). The sheet stays open with the button showing the moving drop and acting as "go to Absorbing" forever. Same if `_activateQueueSource()`/`playItem` throws before the pop. Trigger: tap Absorb while `auth.apiService` is null (signed-out/transitional state). Fix: `if (api == null) { if (mounted) setState(() => _isAbsorbing = false); return; }` and a `try/finally` resetting it when still mounted.

**F2. Leaked full-size decoded cover handle in blur precompute — L/M, medium-high.**
`absorbing_card.dart:545–574` and `expanded_card.dart:562–574` take `info.image` from an `ImageStreamListener` and never call `srcImage.dispose()`. Flutter hands each listener a clone that the listener owns. The cover is resolved with `ImageConfiguration.empty` from the width-1200 URL, so each leaked handle pins a ~1200×1200 RGBA bitmap (~5.8 MB) until GC finalization; expanded card regenerates on every open and on each auto-advance. Also `completer.complete` is unguarded (`:548`) — an animated/multi-frame image would throw on the second frame. Fix: `srcImage.dispose()` after `picture.toImage`, and `if (!completer.isCompleted)` on the success path.

**F7. Expanded player shows the previous book's bookmark count after auto-advance — L, high.**
`ExpandedCard._handleItemChange` (`expanded_card.dart:394`) swaps `_item` in place; `_CardBookmarkButtonInlineState` (`card_buttons.dart:501–524`) loads its count only in `initState` and has no `didUpdateWidget` (`CardSpeedButtonInline` :615 likewise for the saved speed, though the active path reads `player.speed`). Fix: add `didUpdateWidget` that reloads when `itemId/episodeId` change (or key the button grid by item id in `expanded_card.dart`).

**F8. `_isPlaying` in both progress bars only updates from position events — L, low.**
`card_progress_bar.dart:177–214`, `card_edge_progress_bar.dart:186–213`. The vendored position stream stops while paused; the bars rely on the pause producing one final `playbackEvent` (just_audio's `playbackEventStream` → `controller.add(position)` then `.distinct()`). If the backend (just_audio_media_kit on Windows/Linux) emits nothing new, the 100 ms timer keeps running while paused (display stays correct because `_smoothPos` falls back to `player.position` after 1 s). Check with `ABSORB_SCROLL_DIAG=1` while paused; if it ticks, add `widget.player.addListener` → update `_isPlaying` + `_syncTicker()`.

## Performance

**F3. Animated Absorbing tab icon renders at display refresh rate during all playback — M, medium (fork).**
`absorbing_nav_icon.dart:48` → `AnimatedAbsorbDrop` (`absorb_plus_logo.dart:200–245`) uses a `Ticker`, so while anything plays and the shell is visible the engine produces a frame every vsync (60–144 Hz on Windows) for a 24 px icon. The `RepaintBoundary` limits repaint, not frame production/compositing/present. This undoes the idle-frame work (`AbsorbingScreen._loadQueueMode` fix) for the most common state — "playing in the background with the window open". Same for `AbsorbingWave` in the book sheet's Absorb button. Fix (fork-only, S): drive `_DropMotion` from a ~15 fps `Timer.periodic` instead of a Ticker (still honoring TickerMode via `TickerMode.of`), or animate only when the tab is not selected / pause after N seconds. Measure first with `/perf-measure` (playing, Home tab, window visible).

**F4. Scrubber and edge bar repaint the whole card layer 10×/s — M, medium (upstream).**
`CardDualProgressBar` (`card_progress_bar.dart:138`) and `CardEdgeProgressBar` (`card_edge_progress_bar.dart:151`) each run a 100 ms timer and neither is behind a `RepaintBoundary` (`absorbing_card.dart:1064–1067`, `:1184`; same in `expanded_card.dart`). The nearest boundary is the per-card one in `absorbing_screen.dart`, so each tick repaints the scrim gradient, stats text, controls and button grid (cover and blur have their own boundaries). Two timers per playing card. Fix: wrap the two bar widgets in `RepaintBoundary` (2 lines per card file) and optionally share one ticker or tick at 250 ms when the bar is narrower than ~600 px (a 10 h book on a 300 px bar moves 1 px per 2 minutes).

**F5. Player cards rebuild wholesale on unrelated notifications — M, high (upstream).**
- `absorbing_card.dart:614` and `expanded_card.dart:620` `context.watch<LibraryProvider>()`: every keep-alive card rebuilds fully (cover subtree, button grid, LayoutBuilders) on each provider notify; `refreshLocalProgress` notifies on play/pause/seek/chapter.
- Chapterless items: `absorbing_card.dart:398–404`, `expanded_card.dart:450–456` setState the **whole card every second** (the seconds counter reuses `_lastChapterIdx`); the visible values that change per second already update via the stats `StreamBuilder` and the bars' own ticker.
- `absorbing_card.dart:861` `Listenable.merge([...])` and `:792` `widget.player.absolutePositionStream` (a new mapped stream per call, `audio_player_service.dart:2741`) are created in build, so every rebuild re-subscribes.
Fix: replace the watch with a `context.select` snapshot (progress, progress data, cover URL, item updatedAt, media headers, absorbing cache entry) as done for `BookCard`; drop the per-second setState branch (or limit it to what actually needs it); cache the merged listenable/stream in state. M effort because of the many lib reads in build.

**F6. Full-resolution decodes of downloaded covers in list thumbnails — M, high (upstream).**
Downloaded covers are fetched hi-res (`download_service.dart:1813` `_hiResCoverUrl`), and when offline `getCoverUrl` returns the local path. These `Image.file` calls have no `cacheWidth`: `collection_detail_sheet.dart:589`, `playlist_detail_sheet.dart:577/668/772`, `series_books_sheet.dart:1044/1611`, `section_detail_sheet.dart:331`, `series_card.dart:238`, `home_section.dart:413/415`, `book_detail_sheet.dart:2050`. A 2–3k px cover is 16–36 MB decoded for a 56–112 px row. `BookCard` and grid tiles already use `coverDecodeWidth` + `themedCoverDecodeWidth` (respects the full-quality-covers look detail). Fix: same helper on list thumbnails only (not the big player/sheet covers — that change was reverted by the owner, e840dee4).

**F9. Full-provider watches on grid series/list tiles — L/M, high (upstream).**
`library_grid_tiles.dart:541` (`GridSeriesTile`), `:649` (`GridSeriesTileDirect`), `:785` (`GridListTile`) rebuild every visible tile on each LibraryProvider notify; `GridBookTile` already uses the snapshot. Same for `home_section.dart:350` `_EpisodeCard`, `episode_row.dart:37/277`. Fix: extend `LibraryItemSnapshot` (or a small series snapshot) to these tiles.

**F10. Bookmark server sync per button init — L, medium (upstream).**
`card_buttons.dart:505–518`: every `CardBookmarkButtonInline` built (each absorbing card page built by the PageView, the expanded card, the book sheet) calls `BookmarkService().syncBookmarks` on init. Opening the Absorbing tab with several cards issues one sync per built card. Fix: rely on a service-level freshness window (sync at most once per item per N minutes).

Other perf notes (no action needed): `MarqueeText` vsync-based and paused when not playing; `WavyProgressIndicator` repeat only inside the update dialog; `LyricsOverlay` line animation is one-shot; the expanded route is opaque so cards/timers underneath are ticker-muted; `book_card.dart` `existsSync()` in build is sync I/O per card (upstream, tiny files, leave).

## Touch-only interactions (desktop gaps)

Flutter recognizes long-press and drag with a mouse, so these work but are undiscoverable/awkward on Windows; none has a right-click, button or keyboard equivalent unless noted.

| Interaction | Where | Desktop equivalent |
|---|---|---|
| **Open full player: swipe up on the card** | `absorbing_card.dart:666` | Only auto-expand on play (`app_shell.dart _maybeAutoExpand`). No button, no shortcut. |
| **Close full player: swipe down (velocity > 300)** | `expanded_card.dart:657` | None found: no close button, no Escape handling in `desktop_shortcuts.dart`/`app_shell.dart`. Highest-value gap. |
| Remove a speed preset: long-press chip | `card_buttons.dart:787` | None. |
| Quick-add bookmark: long-press Bookmark button | `card_buttons.dart:540` | Add from the bookmarks sheet (tap) works. |
| Quick actions sheet: long-press cover | `book_card.dart:234,360`, `library_grid_tiles.dart:128` | Tap opens the full book sheet with the same actions. |
| Episode quick sheet: long-press | `episode_row.dart:95`, `home_section.dart:385` | Tap opens episode detail. |
| Series scan menu: long-press series tile | `library_grid_tiles.dart:591` (`showSeriesScanMenu`, only caller) | None. |
| Open sub-series sheet: long-press | `series_books_sheet.dart:689` | Tap only expands inline. |
| Add to Absorbing: swipe right on row | `playlist_detail_sheet.dart:636`, `collection_detail_sheet.dart:656` | Via the item's own sheet. |
| Edge bar scrub: long-press + move | `card_edge_progress_bar.dart:337` | Horizontal drag also works. |

Suggested pattern (fork hook, small): map `onSecondaryTap` to the same callback as `onLongPress` in `Pressable`, `_PressableCard` and the tiles; add a collapse chevron/Escape to the expanded player.

## Dead code

| Item | Owner | Evidence | Merge cost |
|---|---|---|---|
| `widget.player.removeListener(_onSpeedMaybeChanged)` + `_onSpeedMaybeChanged` | up | `absorbing_card.dart:212,463`; never added | Leave or 2-line delete; harmless |
| `ExpandedCard.initialBlurredCover` param | up | `expanded_card.dart:61,71` never read; passed at `absorbing_card.dart:1306`. Either use it (clone) to skip a re-blur on open, or drop | Low |
| `AbsorbPlusLogo` widget | fork | Only `test/absorb_plus_logo_test.dart` uses it (ARCHITECTURE.md lists it as in use) | None; keep if planned, else delete with its test |
| `BookDetailInfoChip`, `ChapterPillPainter`, `EdgeProgressPainter`, `showSeriesScanMenu`, `eqBandLabel`, `toggleKeepScreenOn`, `SeriesBooksSheet`, `SleepTimerSheet` | up | Public but used only in their own file | Not dead; leave (upstream) |

Analyzer is clean for these files (`build/dev-logs/flutter-analyze.log`: 2 issues, both in the new `test/ui_overflow_sweep_test.dart`).

## Duplication

- **Position/ticker engine** duplicated between `card_progress_bar.dart:35–270` and `card_edge_progress_bar.dart:40–280` (subscribe, seek-target filter, near-zero rejection, `_smoothPos`, TickerMode/lifecycle sync). Each fix (e.g. f1a0160f) has to land twice. A shared fork-owned `CardPositionClock` (one per player, one timer) would cut both the duplication and F4's double timer, but touches two upstream files heavily — only worth it if upstream stops changing them.
- **Card vs expanded card**: chapter tracking, `_precacheBlur`/`_generateBlur`, cover scheme derivation, button-order loading are near-identical in `absorbing_card.dart` and `expanded_card.dart` (F2 and F5 exist in both). Upstream-owned; don't refactor, but fix in both.
- **Two public `MarqueeText` classes**: `card_progress_bar.dart:658` and `library_sort_filter_sheet.dart:1093` (the latter without `animate`). Name clash if both are ever imported. Upstream; leave.
- `Image.file`/`CachedNetworkImage` cover-with-placeholder blocks repeated across collection/playlist/series/section sheets (F6 fix would touch each).

## Risky patterns

- Side effects from build: `_onCoverLoaded` (`absorbing_card.dart:511,709,723,961`, `expanded_card.dart` Builder) starts async work from `imageBuilder`. Guarded by identity checks; keep them.
- Undisposed dialog `TextEditingController`s (`card_buttons.dart:1248,1249,1282,1283,2897,2898`) — GC'd, no native resources; L.
- `dart:io` imported in 12 of these widgets for local covers; safe on web only because local paths never occur there. Any new local-path source must keep `kIsWeb` guards (`test/web_safe_platform_test.dart` lists files to check).
- `book_detail_sheet.dart` is a single 3,750-line State; `context.watch` in three build roots means any provider notify rebuilds the full sheet including chapter lists.

---

# Recommended actions (ranked by value ÷ (effort + merge cost))

| # | Action | Owner | Size | Risk | Why |
|---|---|---|---|---|---|
| 1 | F1: reset `_isAbsorbing` on every early return/exception in `_startAbsorb` | up (3–5 lines) | S | Low | Real stuck-UI bug, trivial fix |
| 2 | F3: throttle `AnimatedAbsorbDrop` (Timer at ~15 fps or pause when tab selected); measure with `/perf-measure` before/after | fork | S | Low | Continuous vsync frames during all playback on Windows; zero merge cost |
| 3 | F4: `RepaintBoundary` around `CardDualProgressBar` and `CardEdgeProgressBar` in `absorbing_card.dart`/`expanded_card.dart` | up (2 lines each) | S | Low | Cuts 10 Hz full-card repaints to the bar layer |
| 4 | F2: dispose `srcImage` and guard `completer` in both blur precomputes | up (2 lines each) | S | Low | Frees ~6 MB per blur; prevents multi-frame throw |
| 5 | Expanded player: add a collapse button + Escape (fork hook via `desktop_shortcuts.dart`) | fork + 1 upstream hook | S | Low | Only way to close on desktop is a fast mouse drag |
| 6 | F6: `cacheWidth` via `themedCoverDecodeWidth` on local-cover list thumbnails only | up (1 line per site, ~10 sites) | S/M | Low | Large RAM savings offline/Android; respects owner's revert on big covers |
| 7 | F7: `didUpdateWidget` in bookmark/speed inline buttons | up | S | Low | Stale count after auto-advance |
| 8 | Right-click = long-press in `Pressable`, `_PressableCard`, grid tiles | up (small hooks) | S | Low | Desktop parity for quick sheets, series scan menu, preset removal |
| 9 | F5: drop the per-second whole-card setState for chapterless items; cache merged listenable/stream | up | S | Med (verify chapterless podcast UI) | 1 Hz full rebuilds of every playing chapterless card |
| 10 | F5/F9: `context.select` snapshots for `AbsorbingCard`, `ExpandedCard`, `GridSeriesTile*`, `GridListTile` | up | M | Med | Fewer rebuilds on provider notifies; many lib reads to enumerate |
| 11 | F8: verify paused ticker on Windows with `ABSORB_SCROLL_DIAG=1`; add a player listener only if it ticks | up | S | Low | Possible 10 Hz timer while paused |
| 12 | F10: freshness window for bookmark sync in `BookmarkService` | service (other auditor's area) | S | Low | N server calls on Absorbing tab open |
| 13 | Dead code: remove `_onSpeedMaybeChanged` pair; use or drop `initialBlurredCover`; decide on `AbsorbPlusLogo` | up / fork | S | Low | Hygiene; low value |
| 14 | Shared position clock for both bars | up (heavy) | L | Med | Only if upstream churn on these files stays low (`footprint -Churn`) |
