# Code map

How Absorb Plus is put together and where to look. The layout under `lib/` is upstream's ([pounat/absorb](https://github.com/pounat/absorb)). It stays as is so upstream merges stay clean; see "Fork rules" at the end.

## Start-up and navigation

| Where | What |
|---|---|
| `lib/main.dart` | `main()` sets up certificates, image cache limits and read-along, then `MultiProvider` (`AuthProvider`, `LibraryProvider`). `_initServices` starts audio first, then optional services in the background through `StartupTaskCoordinator` (fork). |
| `lib/screens/app_shell.dart` | The main window after sign-in. Its tabs are 0 Home, 1 Library, 2 Absorbing (now playing and queue), 3 Stats and 4 Settings. Pages are built lazily and kept alive. It also hosts the expanded player, the desktop sidebar and keyboard shortcuts, the nav hold menu and update checks. |
| `lib/screens/login_screen.dart`, `lib/models/auth_session.dart` | Sign-in, including OIDC and multiple accounts. |

## State (providers)

- **`AuthProvider`** (`lib/providers/auth_provider.dart`) holds the server URL, tokens, the user JSON and permissions (`isAdmin`, `canUpload` from the fork), multiple accounts and the signed-out state. It owns the `ApiService`.
- **`LibraryProvider`** (`lib/providers/library_provider.dart`) is one class assembled from three `part` mixins:
  - `_lp_state.dart`: the fields.
  - `_lp_core.dart`: loading libraries and shelves, progress, offline mode, downloaded shelves.
  - `_lp_absorbing.dart`: the Absorbing queue.

  Widgets usually `context.select` a small slice. For example, cards use `LibraryItemSnapshot` (fork) to avoid rebuilding on every notification.

## Services (`lib/services/`, about 120 files)

| Area | Main files |
|---|---|
| Server API | `api_service.dart` (Audiobookshelf REST: items, progress, uploads, search, admin), `bookorbit_api_service.dart` and `bookorbit_*` (BookOrbit backend), `server_backend.dart` (which backend is active), `socket_service.dart` (live server events) |
| Playback | `audio_player_service.dart` (the player and media session; very large), `_audio_player.dart` (just_audio wrapper), `desktop_audio*.dart` (fork: libmpv on desktop), `chromecast_service.dart`, `carplay_service.dart`, `android_auto_service.dart`, `sleep_timer_service.dart`, `equalizer_service.dart` |
| Progress and sync | `progress_sync_service.dart`, `local_session_service.dart`, `sync_logic.dart`, `settings_sync_service.dart` |
| Downloads and offline | `download_service.dart` (queue, files, recovery), `queue_download_policy.dart`, `library_cache.dart`, `session_cache.dart` |
| Reader and read-along | `narration_*`, `read_along_script.dart`, `read_listen_sync.dart`, `ebook_*`, `foliate_book_server.dart`, `transcription_service.dart` |
| Settings | `player_settings.dart` (most user preferences), `scoped_prefs.dart` (per-account preferences) |
| Fork features | `libation_import_helper.dart`, `update_checker_service.dart`, `update_policy.dart`, `update_check_policy.dart`, `server_health_service.dart`, `desktop_shortcuts.dart`, `startup_task_coordinator.dart` |

## Screens and widgets

- `lib/screens/` holds full pages. `settings_screen.dart` (about 6,000 lines) contains every settings section, including Settings → Advanced, which hosts ReadMeABook, Libation import and transcription. The `admin_*` files are server admin pages.
- `lib/widgets/` holds sheets, cards and controls. Cards that rebuild with playback are `absorbing_card.dart`, `card_progress_bar.dart`, `card_edge_progress_bar.dart` and `card_buttons.dart`.

## Fork-only code (keep it in these files)

| Feature | Files |
|---|---|
| Libation import | `services/libation_import_helper.dart` (scan, ASIN, history, library matching), `widgets/libation_import_card.dart`, `widgets/libation_book_picker_sheet.dart`. The hooks live in `screens/admin_upload_screen.dart` and the Settings → Advanced tile. |
| Updates from the fork | `services/update_checker_service.dart`, `update_policy.dart`, `update_check_policy.dart`, `widgets/update_dialog.dart` |
| Performance policies | `utils/memory_policy.dart`, `utils/performance_policy.dart`, `utils/app_motion.dart`, `widgets/library_item_snapshot.dart`, `widgets/cover_decode.dart` |
| Desktop | `services/desktop_shortcuts.dart`, `services/desktop_audio*.dart`, `widgets/accessible_header_action.dart`, `windows/cmake/webview_shutdown.cmake` |
| Server health | `services/server_health_service.dart`, `screens/server_health_screen.dart` |
| Download file names | `services/download_track_names.dart` (`uniqueTrackFileNames`: tracks that share a name, e.g. multi-disc `CD1/01.mp3` + `CD2/01.mp3`, get their track number in front; called from `download_service.dart` `_resolveDurableFiles`) |
| UI themes (Absorb Plus / Classic / Frosted) | `ui_themes/ui_theme.dart` (enum, `AbsorbLook` ThemeExtension presets with behavior flags + surface tokens, device-wide pref `fork_ui_theme`, `UiThemeScope` fallback), `ui_themes/frosted.dart` (`frostedThemeData`, `absorbLookBuilder`, `FrostedNavBar`, `FrostedSurface`; blur off on web), `ui_themes/ui_theme_hooks.dart` (one-line checks upstream files call, incl. `lookGlow`/`lookPanel*`), `ui_themes/ui_theme_picker.dart` + `ui_theme_preview.dart` (two-step picker: look with live mock previews, then color via `ui_theme_appearance.dart` = the Settings color source), Settings tile. Hooks: `main.dart` (load, scope, `uiThemeNotifier` listen, `extensions:` x2, `builder: absorbLookBuilder`), `app_shell.dart` (launch prompt, `FrostedNavBar`), glow in `home/library/absorbing/stats/settings_screen.dart`, `adaptive_modal.dart` (desktop dialog glass), `collapsible_section.dart`, `settings_screen.dart` + `settings_search_index.dart`, `book_card.dart`, `cover_badges.dart`, `home_section.dart`; `memory_policy.dart` reads `currentAbsorbLook`. New look = enum value + preset + two strings. Glass strength (Frosted: Light / Medium / Strong, Medium = the original values): `GlassStrength` + `AbsorbLook.frosted(brightness, glass)` in `ui_theme.dart`, device-wide pref `fork_ui_glass`, `glassStrengthNotifier` / `glassStrengthPreviewNotifier` (the look notifiers re-notify on glass changes, so `main.dart` needs no extra hook). "Try it" (`ui_theme_try.dart`) previews look + glass app-wide in memory only, with Keep / Go back. |
| Tooling | see "Developer tooling" below |

## Developer tooling (all fork-owned)

| What | Where | Use |
|---|---|---|
| Everyday commands | `tool/dev.ps1` | `check`, `build`, `bump`, `footprint`, `server`, `itest` |
| Throwaway test server | `tool/test-server/` (`docker-compose.yml`, `seed.py`; `data/` and `.env` git-ignored) | Audiobookshelf 2.37.2 on `127.0.0.1:13378` only, never a real server. `dev.ps1 server up`, `server seed` (root + second account with generated test credentials in `.env`, a 3-file MP3 book and a 2-chapter M4B made by the container's ffmpeg, library scan; idempotent), `server down`, `server reset` (deletes only `tool/test-server/data`) |
| Integration tests | `test/integration/*_test.dart`, tag `abs-server`; `dart_test.yaml` skips the tag so `check` never loads them | `dev.ps1 itest` (`--tags abs-server --run-skipped`): the real `ApiService` for login, token refresh, libraries/items, progress, two accounts, a playback session, admin and Libation uploads. Plain `test()` only (the widget binding blocks real HTTP); suites skip with a reason when `.env` or the server is missing |
| Undo formatting churn | `tool/align_with_upstream.py` | `python tool/align_with_upstream.py [--apply] FILE...` |
| RAM/CPU sampling | `tool/measure-windows-usage.ps1` | Read-only process counters for a running build |
| Frame/rebuild diagnostics | `lib/utils/scroll_diagnostics.dart` | Start the app with `ABSORB_SCROLL_DIAG=1`; logs wheel input, frame timings, redraws per frame and rebuild sources to `%TEMP%\absorb-scroll-diag.txt`. Debug builds also log which widget starts each frame's rebuild and, at 15–17 s, the stacks that marked widgets dirty. Found the idle redraw loop in `AbsorbingScreen._loadQueueMode`. |
| Desktop audio smoke test | `tool/verify-desktop-audio.ps1`, `tool/desktop_audio_smoke.dart` | Checks the libmpv backend without a server |
| Claude Code guards | `tool/claude_hooks.py` (tests in `tool/tests/`), wired in `.claude/settings.json` | Blocks upstream pushes, junction-following deletes, upstream reformatting and generated-file edits; asks before release/tag deletion |
| Claude Code procedures | `.claude/skills/*/SKILL.md` | `/status`, `/build-verify`, `/release`, `/perf-measure`, `/fork-feature` |
| Claude Code subagents | `.claude/agents/*.md` | `reviewer`, `upstream-merger`, `test-writer` |
| CI | `.github/workflows/_checks.yml` (analyze, tests, tool tests, removed-paths check; reused), `ci.yml` (every push; web + Linux builds and Pages deploy on `main`), `release.yml` (`v*` tags: one release with Windows, Linux, web, Android) | |
| Upstream merges | `tool/upstream_merge.py` (`dev.ps1 merge`), `tool/fork-removed-paths.txt`, `tool/fork-overrides.txt`, `tool/check_fork_removed.py` | `/upstream-merge` skill |

## Strings

`lib/l10n/app_en.arb` is the source. Other languages have their own `.arb` files. The `app_localizations*.dart` files are generated by `flutter gen-l10n`; untranslated keys fall back to English. The fork dropped `untranslated-messages-file` from `l10n.yaml`: writing that report made every `pub get` about 18 s slower locally (about 50 s in CI). To see the untranslated keys, add the line back temporarily and run `flutter gen-l10n`.

## Fork rules (why the layout isn't reorganized)

The fork keeps merging upstream, which ships changes almost daily. Moving or reformatting upstream files would turn each merge into hundreds of conflicts. So:

1. **New fork features go in new files.** Upstream files get only small hooks: an import, a callback, a tile.
2. **Never reformat upstream files.** Run `python tool/align_with_upstream.py FILE...` to see, and `--apply` to undo, formatting churn. It only rewrites a file when the result is token-identical.
3. **To find the fork's footprint:** `git diff --stat origin/main -- lib ':!lib/l10n'`.
