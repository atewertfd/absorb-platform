# Audit 08: readers and remaining widgets (`lib/widgets/`)

Read-only audit, 2026-10-30, branch `claude/slim`. Line numbers are from the working tree, which also holds other sessions' uncommitted text-size work: `text_scale_room.dart` is untracked, and the four `library_*_tab.dart` files have edits that aren't committed yet.

Owner codes: **F** = fork-only file. **U=** = upstream file, byte-identical to `origin/main`. **U\*** = upstream file with fork edits; the number after it is changed lines (+/-). Merge cost applies to every U file. "Imp" = number of files in `lib/ test/ tool/` that import it.

## Files covered

The other widgets auditor (07) covers the player, card and book widgets. I cover **every other file in `lib/widgets/`, 102 files**.

**Deep read** (logic, lifecycle, platform behaviour): `ebook_reader_view` (structure, lifecycle, timers, JS bridge, page curl, progress sync, read-along stop path), `ebook_router`, `foliate_reader_view` (+ `services/foliate_book_server.dart`), `pdf_reader_view`, `comic_reader_view` (setup, extraction, pager), `page_curl` (image handling), `update_dialog`, `whats_new_prompt`, `whats_new_sheet` (state, links), `welcome_sheet` diff, `libation_import_card`, `libation_book_picker_sheet`, `accessible_header_action`, `text_scale_room`, `overlay_toast`, `notes_sheet` (delete, export), `edit_metadata_sheet` (all save paths), `adaptive_modal`, `collapsible_section`, `desktop_page_body`, `admin_adaptive_frame`, `offline_status_icon`, `nav_hold_options`, `playlist_picker_sheet` (all fork diffs).

**Grep-level** (controllers and listeners against dispose, timers, `await` then `context`, `dart:io` on web, long-press-only actions, server writes): every remaining file in the table below.

---

# PART 1: Code map

## 1. Readers

How an ebook opens: `openEbookReader()` in `ebook_router.dart` picks the reader by file extension.
- `epub` goes to `_EpubGate`. It downloads the file (`NarrationService.readerFile`), checks whether it is a picture book (`imageEpubPageCount`, cached in a `.imagepages` marker file), then opens either `ComicReaderView(imageEpub:)` or `EbookReaderView`.
- `cbz`, `cbr` and `cb7` go to `ComicReaderView`. CBR and CB7 work only on BookOrbit, whose server unpacks them.
- `pdf` goes to `PdfReaderView`.
- `mobi` and `azw3` go to `FoliateReaderView`.

`canReadEbook()` decides whether the "Read" buttons appear. It is called from `book_detail_sheet`, `absorbing_card`, `expanded_card`, `home_screen`, `downloads_screen`, `app_shell` and `services/find_in_ebook.dart`.

Every reader:
- calls `LibraryProvider.setReaderQuiet(true)` while open;
- attaches `EreaderVolumeNav` (Android volume and page keys, `services/volume_key_service.dart`);
- calls `SystemChrome` immersive mode, which does nothing on desktop;
- stores its position in `ebookLocation`/`ebookProgress` through `ProgressSyncService.pushEbookProgress`, throttled to about one write per 10–15 s, with a flush when the reader is disposed.

| Reader | Engine | Windows | Android | Linux | Web |
|---|---|---|---|---|---|
| EPUB (`EbookReaderView`) | vendored `packages/flutter_epub_viewer` (epub.js in `flutter_inappwebview`); book served by `LocalBookServer` on loopback with a random token | WebView2 | WebView | **no `flutter_inappwebview` plugin on Linux** (not in `linux/flutter/generated_plugins.cmake`) | **fails**: `dart:io` file cache and HttpServer |
| MOBI/AZW3 (`FoliateReaderView`) | foliate-js in `InAppWebView`, served by `FoliateBookServer` (loopback, **no token**) | WebView2 | WebView | **no plugin** | **fails** |
| PDF (`PdfReaderView`) | `pdfrx` (pdfium) | ok | ok | ok | fails (`fetchEbookToCache` uses `File`/`path_provider`) |
| Comic (`ComicReaderView`) | `archive` unzip in an isolate into numbered files; `PageView` + `InteractiveViewer`; BookOrbit pages come from the network | ok (mouse can't drag a `PageView`; see F4) | ok | ok | fails (`path_provider`) |

### `ebook_reader_view.dart`: U\* (+7/−1), 7,865 lines, imported only by `ebook_router` (plus `test/web_safe_platform_test.dart`)

- **Fork diff:** the web-safe `Platform` import, and two `mounted` guards in `_showFontSheet` (:3032, :3084).
- **Section index** (line ranges are approximate):

| Lines | Part |
|---|---|
| 1–134 | Imports (about 50 services); `_ReaderAction`, `_ReaderPalette`; widget params (`openAtCfi`, `findText`, `findChapterHint`, `findPositionSeconds`, `openAtAudioSeconds`, `startReadAlong`) |
| 135–435 | State fields; prefs keys at about :394 |
| 436–616 | `initState` (reading clock, settings, then `_downloadAndOpen`), `EreaderVolumeNav`, `didChangeAppLifecycleState` (snapshots the CFI on paused/hidden, stops read-along, re-displays on resume if the page drifted), audio metadata, route-animation fullscreen |
| 617–1049 | Settings: theme, font (`_setupFontInjector` :680 injects `@font-face` into each section iframe), spread and scroll (bump `_viewerKey`, which **remounts the WebView**), turn styles, controls auto-hide, bar buttons, margins, keep-awake |
| 1050–1105 | `dispose` (cancels timers, flushes read-along via `_stopReadAlong`, sends reading time, restores the system UI) |
| 1106–1156 | Tap zones (`_readerTapAt`, 3x3 grid from `reader_tap_zones.dart`) |
| 1157–1420 | Page turns and page curl: `_turnPage`, curl or ripple over **WebView screenshots** (`takeScreenshot`, JPEG q92 → `ui.Image`), drag-to-curl |
| 1421–1488 | JS tap handler `absorbReaderTap` |
| 1489–1734 | Opening the book: initial location, `_pullServerPosition`, `_downloadAndOpen` (1603), other-account spot, `_syncProgress` (1680; throttled to 15 s during read-along, flushed by `_flushEbookPush`) |
| 1735–2114 | Highlights: sync with the server, paint, restore (`absorbCfiText` handler), `pageInfo` handler (1881), add, share, remove, recolour, menu |
| 2115–2348 | Bookmarks; selection actions (copy, search, define → `dictionary_sheet`, translate); notes on highlights; TOC |
| 2349–2881 | Settings sheet (about 530 lines of UI) |
| 2882–3002 | Auto-scroll: six JS handlers (`absorbAutoScroll*`) and the toggle |
| 3003–3221 | Theme swatches, font sheet, translator sheet |
| 3222–3429 | Book search (`_searchBook` runs in JS over a second `ePub()` instance, `window.__absorbSearchBook`, kept for the WebView's lifetime) |
| 3430–3800 | Find in ebook (transcript → fuzzy passage search; the hint sections come from `sync_point_store`) |
| 3801–3976 | Catch-up between audio and page (estimate, offer, catch up on open) |
| 3977–4304 | Find in audiobook from a selection (section info, a transcribed probe window, locate) |
| 4305–4425 | `_startAudioAt`, `_ensureThisBookPlaying` |
| 4426–4782 | EPUB3 media-overlay narration: load, clip on page, play from, carry the reading spot, tick |
| 4783–5239 | Read-along control: toggle, resume, start, bootstrap JS (`__absorbRA`), jump to audio, prep card, sync pill |
| 5240–5906 | Read-along engine: `_stopReadAlong`, `_readAlongTick` (5294–5525, `Timer.periodic`), page turns, `_paintReadAlongLine` (5660), flash highlight |
| 5907–6083 | Search screen, spot history (`ebook_history`), reading-time clock (15 s periodic; counts reading as listening time only when enabled, always on BookOrbit) |
| 6084–6250 | Annotations sheet |
| 6251–6515 | Chrome: `_wrap`, top bar, pinned top bar, viewer area |
| 6516–6634 | Auto-scroll sleep timer |
| 6635–7168 | Reader controls sheet, bar shortcut, audio chapters, cast, download, media bar |
| 7169–7596 | `build()`: `EpubViewer(key: ValueKey(_viewerKey), epubSource: EpubSource.fromFile(...))`. `onEpubLoaded` (about :7309) re-registers every JS handler after each remount. Also `onRelocated`, `onSelection`, touch callbacks. |
| 7597–7865 | `_EbookSearchScreen`, `_SearchExcerpt`, `_HighlightColorButton`, `_ReaderBookText` (the `BookTextSource` adapter for `find_in_ebook`) |

- **JS bridge:**
  - Ten `addJavaScriptHandler` names, plus the viewer's own callbacks.
  - About 36 `evaluateJavascript`/`callAsyncJavaScript` sites.
  - Heavy text work (section text, char counts, fuzzy search) **stays in JS**; only counts, offsets and excerpts come back. That's the right design; don't move text over the channel.
  - The book reaches the page over loopback, not base64.
- **Traps:**
  - `_viewerKey++` remounts the WebView, so every handler must be registered in `onEpubLoaded`, never once in `initState`.
  - `_stopReadAlong()` runs from `dispose`, so its JS calls are wrapped in try/catch on purpose.
  - On Windows, `inactive` (focus loss) also sets `_readerActive=false`.
  - The file is upstream-owned and 7.9k lines: grep and read windows. Don't split it (huge merge cost).

### Other readers
- **`foliate_reader_view.dart`: U=, 485 lines.**
  - JS handlers: `onReady`, `onBookLoaded`, `onRelocate`, `onTap`, `onError`.
  - Taps arrive from a Flutter `Listener` plus a JS click fallback, debounced to 350 ms.
  - Its doc comment claims FB2, FBZ and CBZ support, but `foliateEbookFormats = {'mobi','azw3'}` (`services/ebook_cache.dart:27`). The comment is stale.
- **`pdf_reader_view.dart`: U=, 320 lines.** `PdfViewer.file`. The page number is the `ebookLocation`. Outline sheet.
- **`comic_reader_view.dart`: U=, 922 lines.**
  - `extractComicPages` runs in an isolate and writes numbered files. Entry names are never used as paths, so a zip-slip attack is impossible.
  - `_precacheAround` keeps ±2 full-resolution pages decoded.
  - Right-to-left reading is stored per book. Bookmarks are kept locally (and on BookOrbit for picture EPUBs).
- **`ebook_router.dart`: U=, 188 lines.** Described above. Imports `dart:io` (`File`).
- **`page_curl.dart`: U=, 410.** `PageCurlController`/`PageCurlLayer` paint curl and ripple turns over `ui.Image` pictures. `kDrawnTurnStyles = ['curl','ripple']`.
- **`reader_tap_zones.dart`: U=, 362.** A 3x3 tap-zone grid with movable lines, plus its editor.
- **`dictionary_sheet.dart` (U=, 190), `quote_share_sheet.dart` (U=, 541; renders a PNG and shares it via a temp file), `narration_download_dialog.dart` (U=, 65), `transcription_download_prompt.dart` (U=, 61), `progress_dialog.dart` (U=, 49):** the readers' helper sheets.
- **Read-along** has no widget of its own. It lives in `ebook_reader_view` (4783–5906), `lyrics_overlay.dart` (U=, 622: the live transcript on the player cover, with a 6 s pill timer that is cancelled correctly) and the services (`read_along_script`, `read_listen_sync`, `lyrics_service`, `transcription_service`).

## 2. Fork-owned widgets (F)

| File | Lines | Imp | Purpose / state |
|---|---|---|---|
| `accessible_header_action.dart` | 88 | 4 | `FocusableActionDetector` + `Semantics(excludeSemantics)` + 44 px tap target around custom header icons (Enter/Space activate, focus ring). Clean; good pattern to copy. Used by `offline_status_icon` and page headers. |
| `libation_import_card.dart` | 187 | 1 | Pure-UI `ExpansionTile` for Settings → Advanced / `admin_upload_screen`. All actions are callbacks; test keys exposed. Clean. |
| `libation_book_picker_sheet.dart` | 186 | 1 | Bottom sheet listing scanned exports (search field when there are more than 8; New/Imported tags). Clean. Uses raw `showModalBottomSheet` (M3 caps it at 640 px on desktop). |
| `whats_new_sheet.dart` | 717 | 4 | In-app release notes: a bottom sheet below 720 px width, otherwise a 640 px dialog. Links limited to http(s) by the parser (`services/whats_new_notes.dart:256`); `TapGestureRecognizer`s disposed. Tested. |
| `text_scale_room.dart` | 48 | 7 | **Untracked WIP.** `textScaleRoom()` + `LabelRoomGridDelegate` (adds label height to grid cells at large text). Used by home/library screens and tabs plus `absorbing_card`. |

Fork-only files covered by audit 07: `absorb_plus_logo`, `absorbing_nav_icon`, `cover_decode`, `library_item_snapshot`.

## 3. Upstream files with fork edits (U\*)

| File | Lines | Imp | Fork change | Notes |
|---|---|---|---|---|
| `update_dialog.dart` | 224 | 3 | +99: Windows installer path, cancel, a progress route that closes only itself, injectable hooks | Fork-heavy; ok. See F10. |
| `whats_new_prompt.dart` | 52 | 5 | Rewritten to open `WhatsNewSheet`; off on web and `DEV_BUILD` | ok |
| `adaptive_modal.dart` | 355 | 13 | Dropped `DesktopWheelScrollRegion`; Frosted look hooks | Indentation left as is on purpose (smaller diff). `showAdaptiveSheetDialog`/`showAdaptiveActionMenu`: a sheet on mobile, a dialog on the desktop workspace. |
| `collapsible_section.dart` | 70 | 6 | Look hooks (`lookPanel*`) | ok |
| `desktop_page_body.dart`, `admin_adaptive_frame.dart` | 23 / 149 | 2 / 1 | Removed `DesktopWheelScrollRegion` (native scrolling restored) | Stray `)\n;` formatting, harmless |
| `offline_status_icon.dart` | 84 | 3 | Wrapped in `AccessibleHeaderAction` | ok |
| `nav_hold_options.dart` | 231 | 4 | `rmab*` ids always unavailable (ReadMeABook lives in Advanced settings) | The `rmabWeb`/`rmabConfigured` params are now unused; intentional, to keep the diff small |
| `playlist_picker_sheet.dart` | 212 | 2 | Tooltip + `Semantics` + `InkWell` on the action rows | F9 (double semantics) |
| `notes_sheet.dart`, `episode_list_sheet.dart` | 574 / 1,138 | 1 / 12 | Post-`await` `mounted` guards | F8 (notes) |
| `welcome_sheet.dart`, `auth_loading_screen.dart` | 160 / 43 | 5 / 1 | Logo and "A B S O R B   P L U S" | ok |
| `audible_series_sheet.dart`, `cover_badges.dart` | 736 / 144 | 4 / 12 | Web-safe Platform / small | ok |
| `library_{authors,books,lists,series}_tab.dart` | 150/283/180/139 | 1 each | Uncommitted: `LabelRoomGridDelegate` | WIP by another session |

## 4. Upstream-identical files (U=)

All are clean at grep level (controllers and listeners disposed, no leaked timers) unless a finding says otherwise.

| File | Lines | Imp | Purpose |
|---|---|---|---|
| absorb_page_header | 119 | 31 | Shared page header |
| absorb_placement | 94 | 8 | "Add to Absorbing" with a position picker |
| action_pill | 85 | 4 | Icon-over-label pill grid (optional long-press for rearranging) |
| add_books_search_sheet | 371 | 3 | Stay-open bulk-add search picker (collections and playlists) |
| admin_task_indicator | 317 | 1 | Server task badge + `AdminTasksSheet` |
| author_books_sheet | 687 | 4 | Author detail sheet (`showAuthorDetailSheet`); swipe rows |
| author_card | 95 | 1 | Author grid tile |
| beta_logging_notice | 55 | 2 | One-time "logs are on in betas" notice |
| book_activity_card | 307 | 2 | Reading/listening activity card (BookOrbit style) |
| book_files_sheet | 348 | 1 | Per-file format/codec list; long-press copies the path |
| book_stats_sheet | 227 | 1 | Per-book listening stats |
| bookorbit_match_view | 652 | 1 | BookOrbit Match tab in the metadata editor |
| books_sheet_shared | 230 | 12 | Helpers for author, narrator and series sheets |
| card_playback_controls / card_scrubber_mode_selector | 220 / 72 | 2 / 1 | Card controls (borderline: audit 07's area) |
| chromecast_button (+ `_stub`) | 247 / 29 | 2 / 0 | Cast picker. The stub is swapped in only by `fdroid/com.barnabas.absorb.yml` (upstream's F-Droid recipe; the fork's package id differs, so it is dead for the fork but cheap to keep) |
| clip_editor_sheet | 445 | 1 | Clip export (play and mark, then `saveFile`) |
| collection_picker_sheet | 199 | 1 | Add to collection |
| color_wheel_picker | 109 | 1 | HSV wheel |
| day_sessions_sheet | 314 | 1 | Sessions of one day (stats) |
| delete_confirm_dialog | 92 | 4 | Soft/hard delete choice |
| desktop_batch_actions | 418 | 2 | Desktop multi-select actions, quick match |
| edit_author_sheet | 530 | 1 | Author editor (root admin); writes `updateAuthor`, image |
| edit_metadata_sheet | 2,183 | 1 | `MetadataEditView`: Details / Cover / Match / Encode / Embed tabs; all server writes are behind Save or Apply buttons. F5 |
| editable_sheet_item | 89 | 2 | Reorderable row |
| feature_hint | 115 | 3 | Dismissible tips (listens to `resetTick`, removes the listener correctly) |
| filesystem_picker_screen | 145 | 1 | Server filesystem browser (`/api/filesystem`) |
| finished_books_this_year_sheet | 428 | 1 | Year's finished books; **remove/restore only by long press** |
| home_customize_sheet | 371 | 1 | Home sections order and visibility |
| html_description | 283 | 5 | Light HTML → RichText |
| library_narrators_tab | 135 | 1 | Narrators tab |
| library_picker_sheet | 104 | 3 | Library switcher |
| library_search_results | 665 | 3 | Library search result tiles and sections |
| library_sort_filter_sheet | 1,141 | 1 | Sort and filter sheet |
| listening_session_card | 198 | 3 | Session row |
| metadata_lookup_sheet | 686 | 1 | Metadata search through the ABS server |
| narrator_books_sheet | 183 | 3 | Narrator sheet |
| new_list_flow | 156 | 1 | New collection or playlist |
| now_playing_text_sheet | 264 | 1 | Media-notification text builder |
| podcast_episode_feed | 740 | 1 | Recent-episodes feed, paged |
| rmab_book_detail_sheet / rmab_config_sheet / rmab_request_status_chip / rmab_search_results_sheet | 480 / 1,279 / 101 / 468 | 3 / 7 / 3 / 3 | ReadMeABook integration (reached only from Advanced settings) |
| scroll_reveal | 169 | 2 | Header reveal driven by scroll position |
| section_detail_sheet | 372 | 1 | Router to the detail sheet for a home-section entity |
| section_labels | 32 | 2 | Localized shelf labels |
| series_card | 255 | 1 | Stacked series covers |
| server_admin_status_badges / server_connection_editor | 85 / 255 | 1 / 1 | Admin badges; custom headers and connection settings |
| settings_search | 212 | 2 | Settings search ranking (tested) |
| setup_link_login / setup_link_share_sheet | 126 / 170 | 2 / 2 | Setup-link sign-in and sharing |
| shimmer | 98 | 1 | Pulsing placeholders (one `AnimationController` per box; ignores reduced motion; home first load only) |
| sign_in_again | 12 | 2 | Re-sign-in helper |
| stable_cached_network_image | 31 | 2 | Cover image wrapper |
| stackable_sheet | 150 | 17 | Stacked bottom sheets (depth cap) |
| stats_charts | 460 | 1 | Stats charts |
| swipe_action | 214 | 7 | `Dismissible`-based swipe-to-act rows (no semantics actions) |
| theme_presets | 26 | 5 | Colour presets |
| tips_sheet | 214 | 1 | Tips |
| overlay_toast | 258 | 86 | `showOverlayToast` (a single current toast, removal made idempotent through an `Expando`) + `LiveOverlayToast`. F11 |

**Dead code:** no fully unused widget or top-level symbol in my scope. I grepped every public class and function across `lib/ test/ tool/`; every one is referenced at least once. The only file with no importer is `chromecast_button_stub.dart`, which is used by upstream's F-Droid recipe; keep it. One unused bit: `navHoldIdAvailable`'s `rmabWeb`/`rmabConfigured` params, left on purpose.

**Tests:** only `collapsible_section`, `whats_new_*`, `welcome_sheet`, `update_dialog`, `settings_search`, `accessible_header_action`, `nav_hold_options` and the Libation card (through `admin_upload_screen_test`) are tested. No reader, `overlay_toast`, `notes_sheet` or `edit_metadata_sheet` tests.

---

# PART 2: Findings

Severity: H/M/L. Confidence: **high** = traced in code; **med** = traced, but runtime behaviour not reproduced. Before listing, I checked each one against `git log` (the recent "web-safe Platform" and "closed screen after await" fixes) to skip anything already fixed.

### F1. "Read ebook" is offered on platforms where the reader can't work (M, high)
- **Where:** `ebook_router.dart:26-32` (`canReadEbook`) has no platform check.
- **Web:** every reader fails.
  - EPUB and MOBI need `dart:io` files and an `HttpServer`.
  - PDF and comic use `path_provider`/`File` in `fetchEbookToCache`/`readerFile` (`services/ebook_cache.dart:70` → `getApplicationSupportDirectory`).
  - The user sees "Error loading ebook: Unsupported operation…" or a raw exception string (`ebook_reader_view.dart:1652`, `pdf_reader_view` `_error = '$e'`).
- **Linux:** `flutter_inappwebview` has no Linux implementation (absent from `linux/flutter/generated_plugins.cmake`), so EPUB and MOBI/AZW3 build an `InAppWebView` that can't render: an error or blank page. PDF and CBZ should work.
- **Fix:** add a fork helper `ebookReadableOnThisPlatform(ext)` and call it from `canReadEbook`, a one-line hook in the upstream file:
  - `kIsWeb` → false;
  - Linux → only `pdf` and the comic formats.
- **Effort:** S. Low risk.

### F2. No keyboard (or reliable mouse-wheel) page turning in any reader on Windows (M, high for "no Flutter-side handler")
- **Where:** none of `ebook_reader_view`, `foliate_reader_view`, `pdf_reader_view`, `comic_reader_view` or `reader_tap_zones` has a `Focus`/`onKeyEvent`/`Shortcuts` or `onPointerSignal`.
- The EPUB page's JS (`packages/flutter_epub_viewer/lib/assets/webpage/html/epubView.js`) and `assets/foliate/reader-app.js` register no `keydown` either.
- On Windows (the owner's main platform), pages turn only by clicking tap zones. Arrow keys, PageUp/PageDown and Space do nothing.
- **Fix, with one hook point for all four readers:** `EreaderVolumeNav` (`services/volume_key_service.dart`) already gets `onPrev`/`onNext` from each reader. On desktop, have its `attach()` also register a `HardwareKeyboard.instance.addHandler` mapping ←/→, PageUp/PageDown, Space and Shift+Space, removed in `detach()`.
  - A fork-only `ReaderKeyNav` class called from there keeps the upstream diff to about 2 lines.
- **Caveat (med):** when WebView2 has native keyboard focus (after clicking text), keys may not reach Flutter. A JS `keydown` that posts to the existing `absorbReaderTap` channel is the fallback for EPUB.
- **Effort:** M. Low-medium risk; test with the Windows build.

### F3. PDF, comic and MOBI readers flush progress only on `paused`, which Windows doesn't send (L-M, med)
- **Where:** `pdf_reader_view.dart:69`, `comic_reader_view.dart:181`, `foliate_reader_view.dart:101`: `if (state == AppLifecycleState.paused) _flushProgress();`.
- On desktop the app goes `inactive` → `hidden` when minimized or hidden to the tray.
- Page changes are throttled to 10 s (`_pendingPage` stays unsent until the next turn or dispose). So "turn a page, hide to tray, quit from the tray" can lose the last position.
- `ebook_reader_view` already handles `hidden` (:517).
- **Fix:** `paused || hidden` in all three (one line each, upstream). S, low risk.

### F4. Comic pages can't be dragged with a mouse on desktop (L, med)
- `ComicPager` is a `PageView` with the default `ScrollBehavior`. Desktop `dragDevices` exclude the mouse, and there's no app-wide `scrollBehavior` (grep finds no `dragDevices`).
- Mouse users get only tap edges and the scrubber (plus F2).
- **Fix:** comes with F2's keys, or give the pager a `ScrollConfiguration` that adds `PointerDeviceKind.mouse`. S, upstream.

### F5. The metadata match "success" toast ignores the cover result; the cover preview may not refresh (L, high / med)
- **Where:** `edit_metadata_sheet.dart:600-603`. `await api.updateItemCoverUrl(...)` is not assigned to `ok`, so "Updated from match" shows even when the cover change failed.
- This breaks the CLAUDE.md rule: don't claim success unless the server response proves it.
- **Also:**
  - `:612` and `:799` bump `_coverVersion++` **after** `setState(() => _saving = false)`, outside any `setState`. The preview URL's `?v=` cache-buster only updates on the next unrelated rebuild (med).
  - On BookOrbit the preview URL has no version parameter at all (:1701).
- **Fix:** `ok = await ...`, and move `_coverVersion++` into the `setState`. S, upstream (3 lines).

### F6. The MOBI/AZW3 loopback server has no token and sends `Access-Control-Allow-Origin: *` (L, high)
- **Where:** `services/foliate_book_server.dart:20-30` (the reader's backend; cross-reference for the services auditor).
- While a MOBI is open, any web page in the user's browser can probe the localhost ephemeral ports. It can fetch `/book/...` and read the response, because CORS `*` allows it.
- The EPUB server (`packages/flutter_epub_viewer/lib/src/local_book_server.dart:15-40`) already uses a `Random.secure()` path token.
- **Fix:** same token scheme; drop the CORS header (same-origin page). S, upstream.

### F7. Page-curl screenshots (`ui.Image`) are never disposed (L perf, high)
- **Where:** `ebook_reader_view.dart:1247-1286` (`_pictureOfPage`, `_queueCurlShot`, `_refreshCurlShot`) and `_turnPage`/`_turnUnderCurl`.
- Each turn decodes a full-window JPEG (about 8–10 MB of RGBA at phone resolution, more on a large Windows window). The replaced and discarded images rely on GC finalizers to free their memory.
- Only when the curl or ripple turn style is on (opt-in).
- **Fix:** `dispose()` the old `_curlShot` when replacing or clearing it, and the stale shot in the `_currentCfi != cfi` branch. Let `PageCurlLayer` own and dispose `_top`/`_under` on `hide()`. M (ownership needs care), upstream.

### F8. Notes: the dismissed `Dismissible` isn't removed synchronously (L, high)
- **Where:** `notes_sheet.dart:282-285`. `onDismissed: (_) async { await NotesService().deleteNote(...); _loadNotes(); }`.
- Flutter requires the item to leave the list synchronously. Any rebuild during the await triggers "A dismissed Dismissible widget is still part of the tree" (debug assert).
- The key `'${createdAt}_$index'` also changes for every later note after a delete.
- Deleting is also possible by **long press only** on the card (:340), with no visible button (the swipe works with a mouse drag).
- **Fix:** `setState(() => _notes.removeAt(index))` before the await; key by `createdAt` only. S, upstream.

### F9. Playlist picker rows announce twice to screen readers (L, high; fork-introduced)
- **Where:** `playlist_picker_sheet.dart:184-210`. An outer `Semantics(button, label, onTap)` wraps an `InkWell(onTap)` whose child holds the same text, giving two tappable nodes.
- **Fix:** add `excludeSemantics: true` to the outer `Semantics` (the `AccessibleHeaderAction` pattern). S, fork edit in an upstream file.

### F10. Update dialog edge cases (L, med; fork code)
- **Where:** `update_dialog.dart:169,193`.
- `progress.dispose()` runs right after `closeProgress()`. If the download finishes before the dialog's first frame, `closeProgress` defers the pop to a post-frame callback while the dialog builds a `ValueListenableBuilder` on the already disposed notifier (debug assert only).
- If `launchWindowsInstaller`/`installApk` **throws** instead of returning a status, the progress dialog stays up until Cancel.
- **Fix:** dispose in `whenComplete` of the dialog future; wrap the install in try/catch → browser fallback. S.

### F11. `LiveOverlayToast.show` doesn't become `_currentToast` (L, high)
- **Where:** `overlay_toast.dart:78-90`. It removes the previous toast but never registers itself, so a later `showOverlayToast` (or a second live toast) stacks on top of it until `dismiss()`.
- **Also:** toasts aren't announced to screen readers (no `SemanticsService.announce`/live region).
- **Fix:** set `_currentToast = entry` and clear it in `dismiss`. S, upstream (86 importers, but a tiny diff).

### F12. Foliate external links (L, med)
- **Where:** foliate-js (`assets/foliate/foliate-js/view.js:356-362`) handles a book's external links with `window.open(href, '_blank')`. `foliate_reader_view.dart:384-397` sets neither `shouldOverrideUrlLoading` nor `onCreateWindow`.
- Depending on the platform WebView, the link is ignored or replaces the reader page.
- **Fix:** handle the `external-link` event in `reader-app.js` (return false and post to a Flutter handler that calls `launchUrl`). M, upstream assets.

### F13. Exports on web (L, high; web untested)
- **Where:** `notes_sheet.dart:161` (`getTemporaryDirectory` + `Share.shareXFiles`) and `quote_share_sheet.dart:176`.
- Both throw on web inside a button callback, so the tap does nothing.
- The fork already has `utils/text_file_download.dart` (a conditional web download) that notes export could use, or the button could be hidden on web. S.

### F14. Small items (L)
- **Raw English error strings in readers**, shown to users: `'Not connected to server'` and `'Error loading ebook: $e'` in `ebook_reader_view.dart:1608,1652`, plus `foliate`/`pdf` `_error = '$e'`, which shows raw exception text. Localize them, and log the raw error instead. Upstream.
- **Stale doc comment:** `foliate_reader_view.dart:33` lists FB2, FBZ and CBZ.
- **Swipe-only and long-press-only actions** with no visible or semantic alternative:
  - `finished_books_this_year_sheet.dart:247,331` (remove/restore);
  - `swipe_action.dart` (no `customSemanticsActions`);
  - `book_files_sheet.dart:313` (copy path).
  - Mouse long-press and drag do work on Windows, but nothing hints at them.
- **`shimmer.dart`:** one ticker per box, a new `Tween`/`CurvedAnimation` every build, and no reduced-motion check. Only during home's first load. Leave it (upstream, transient).
- **`ebook_reader_view` keeps a second parsed `ePub()`** (`window.__absorbSearchBook`) alive for the WebView's lifetime after the first search, find or char count. That's memory on huge books. Leave it (upstream design).

### Checked and fine
- Controllers, `FocusNode`s and listeners in all 102 files are balanced with `dispose`/`removeListener`. The heuristic scan found only false positives.
- The `ebook_reader_view` timers (`_readingTimer`, `_readAlongTimer`, `_controlsHideTimer`, `_curlShotTimer`, `_autoScrollSleepTimer`, `_pendingTapAction`, `_narrationSpotTimer`) are all cancelled in `dispose`. `_ebookPushTimer` is flushed through `_stopReadAlong()`.
- The auto-scroll sleep sheet's ticker cancels itself when the sheet's context unmounts.
- The `await`-then-`context` scan (the lint is disabled in `analysis_options.yaml`) found only safe cases after the recent mounted-guard commits.
- What's-new links are http(s) only. Libation widgets are pure UI and never touch Libation config files.
- All metadata and author writes happen only behind explicit Save/Apply buttons.

---

# Recommended actions

Ranked by value ÷ (effort + merge cost).

| # | Action | Tag | Size | Risk |
|---|---|---|---|---|
| 1 | F1: gate `canReadEbook` by platform (web: none; Linux: PDF and comics only) through a fork helper | fork helper + 1-line upstream hook | S | Low |
| 2 | F5: assign the match cover result; bump `_coverVersion` inside `setState` | upstream (3 lines) | S | Low |
| 3 | F3: flush reader progress on `hidden` too (pdf, comic, foliate) | upstream (3 × 1 line) | S | Low |
| 4 | F2: keyboard page turns in `EreaderVolumeNav` on desktop (fork `ReaderKeyNav`), plus a JS `keydown` fallback for the EPUB WebView | fork file + about 2-line upstream hook | M | Low-med (verify on Windows) |
| 5 | F9: `excludeSemantics` on the playlist picker rows | fork edit | S | Low |
| 6 | F6: token + no CORS for `FoliateBookServer` | upstream service | S | Low |
| 7 | F11: register the live toast as current; clear it on dismiss | upstream | S | Low |
| 8 | F8: remove the dismissed note synchronously; stable key | upstream | S | Low |
| 9 | F10: harden the update dialog (dispose timing, try/catch → browser fallback) | fork code | S | Low (touches the updater → owner OK before release per policy) |
| 10 | F13: hide notes/quote export on web or use `text_file_download` | upstream + fork helper | S | Low |
| 11 | F7: dispose curl screenshots | upstream | M | Med (image ownership between reader and layer) |
| 12 | F4/F12/F14: mouse-drag comics, foliate external links, localized reader errors | upstream | S-M | Low |

**Don't:**
- split `ebook_reader_view.dart` or `edit_metadata_sheet.dart`;
- merge the four readers' duplicated fullscreen and progress-throttle code;
- convert raw `showModalBottomSheet` calls to `adaptive_modal` across upstream widgets.

All of these are large merge cost for little user value. The one cheap exception is the fork-owned `libation_book_picker_sheet`, which could use `showAdaptiveSheetDialog` on desktop if the owner wants Libation import to feel native on Windows.
