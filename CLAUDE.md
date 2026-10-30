# Absorb Plus — working notes

Absorb Plus is a fork of [pounat/absorb](https://github.com/pounat/absorb) (Flutter Audiobookshelf client), published at [atewertfd/absorb-platform](https://github.com/atewertfd/absorb-platform). Windows desktop is the primary target, then Android, then Linux and web. Apple and ARM builds are low priority.

## Location

- The main checkout is **`C:\Users\pc\Desktop\claude\Absorb`** (since 2026-10-29). The owner runs builds from `C:\Users\pc\Desktop\claude\Absorb\build\windows\x64\runner\Release\absorb.exe`.
- Older Codex checkouts under `C:\Users\pc\Documents\Codex\2026-09-29\` still exist: the original `absorb-windows-port`, its `absorb-memory-optimization` worktree, and the paused NAS `local-server-discovery` worktree. Don't build or commit there. Their branches are reachable read-only through the `codex-local` remote, whose push URL is disabled on purpose.

## Remotes and publishing

- `origin` = upstream `pounat/absorb`. **Never push to it.** Fetch and merge from it to keep up with upstream fixes.
- `fork` = `atewertfd/absorb-platform`. Push branches here.
- `codex-local` = the old Codex checkout, read-only.
- Pushing a `v*` tag to the fork runs `windows-release.yml` (installer and portable ZIP) and `desktop-web-release.yml` (Linux, web, Android) and publishes a **pre-release**. Pushing `main` redeploys the web build to GitHub Pages.
- Publishing a release, changing which release is Latest, or deleting releases, tags or assets needs the owner's explicit OK. Inspect existing releases first.

## Build identity

- Bump the version on every user-facing build, in its own commit: `pubspec.yaml` `version: X.Y.Z+N` and `kBetaNumber` in `lib/build_info.dart`. The app shows `X.Y.Z+N (Beta K)` in Settings. The release workflow titles releases with `kBetaNumber`.
- Tags use `vX.Y.Z-N`. Release notes start with `## Beta K`, which the update dialog parses.

## Local Windows build (always)

```powershell
flutter analyze --no-fatal-infos
flutter test --no-pub
flutter build windows --release --no-pub --dart-define=GITHUB_BUILD=true
```

- Requires the NuGet CLI on PATH (`winget install Microsoft.NuGet`, installed per user to `%LOCALAPPDATA%\Microsoft\WinGet\Links`). The upstream `flutter_inappwebview_windows` plugin downloads WebView2 headers through it. If a build once ran without NuGet, delete `build\windows` so CMake re-detects it.
- Output must go to `build\windows\x64\runner\Release` (the owner runs `absorb.exe` from there). If that exact exe is running, close only that copy, gracefully.
- Verify the exe's ProductVersion matches `pubspec.yaml`.
- Flutter commands rewrite `linux/flutter/generated_plugin*` and `windows/flutter/generated_plugin*` (locally they drop `jni`). Restore them with `git restore --source=HEAD --` **after** building, unless a plugin change is intended. Restoring before a `--no-pub` build breaks CMake, because the committed list names `jni`. Run `flutter pub get` first if they were restored.
- **Never recursively delete a Flutter checkout or worktree with `robocopy /MIR`, `Remove-Item -Recurse` or similar.** `windows|linux|macos/flutter/ephemeral/.plugin_symlinks` holds directory links into the shared Pub cache, and those tools follow them and empty the cached packages. (This happened once and emptied 23 cached packages.) Remove the `.plugin_symlinks` links themselves first (`cmd /c rmdir <link>` removes a junction, not its target), or use `git worktree remove`. If the cache was damaged, find empty folders under `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev`, `rmdir` them, and run `flutter pub get`.
- If the owner is running the Release build (for example, testing a beta), don't close it or overwrite the folder. Verify the build in a separate `git worktree` and rebuild the Release folder once they're done.
- Don't run `dart format` on large existing files: it rewraps hundreds of unrelated lines. Format only new files or new code.

## Product rules

- **Keep the normal Absorb look.** No redesigns, color changes or new animations unless the owner asks. Earlier scroll and animation experiments regressed and were rolled back.
- **Performance work is stability-first.** Prefer rebuild scope, timer/lifecycle handling, bounded caches and lazy work. No engine rewrites or Windows-wide tweaks. Measure where possible.
- Never break playback, downloads, sync, scrolling, Android, or the web build to improve Windows.

## Safety rules

- Absorb is a client of the user's own Audiobookshelf server. Credentials are entered by the user and never logged.
- Never search the machine for passwords, tokens or account files. Never read Libation's account or configuration files.
- Never upload, modify or delete server data without an explicit user action. Don't claim an import worked unless the server response proves it.
- Libation integration imports Libation's *exported* files only. Absorb does not sign in to Audible or Libation and does not bypass DRM. Say so honestly in the UI and docs.
- Don't test against the owner's real server or NAS. Use fixtures or a throwaway server.

## Code map (fork-specific areas)

- Libation import: `lib/services/libation_import_helper.dart`, `lib/screens/admin_upload_screen.dart` (Settings → Advanced → Import Libation exports).
- ReadMeABook: `lib/services/rmab_service.dart`, `lib/widgets/rmab_*.dart` (Settings → Advanced only, not the admin dashboard).
- Updates: `lib/services/update_checker_service.dart`, `update_policy.dart`, `update_check_policy.dart`, `lib/widgets/update_dialog.dart`. The checker reads the fork's releases.
- Windows installer: `installer/Absorb.iss` (Inno Setup). It updates in place and keeps user data.

Keep fork-only features in their own files where possible, so upstream merges stay easy.

## Standing owner preferences

- **Installer:** a normal EXE installer plus a separate portable ZIP. Updates install in place and keep settings and data, and uninstalling must not unexpectedly delete user data.
- **Release assets:** the owner previously asked for SHA256SUMS assets to be removed. CI still attaches them for Android, Linux and web. Inspect a release before changing assets, and don't add new checksum files.
- **Git:** never `git reset --hard` or check out over uncommitted work. Inspect `git status` before editing, make small logical commits, and run `git diff --check`.
- **NAS / Docker:** the Audiobookshelf/ReadMeABook server-discovery work for the owner's NAS (remembered address, no rescans on every start) is paused and separate from the Windows app. Don't touch the NAS unless asked.
- **Libation references:** [getting started](https://github.com/rmcrackan/Libation/blob/master/docs/getting-started.md), [CLI](https://github.com/rmcrackan/Libation/blob/master/docs/advanced/command-line-interface.md). Absorb never bundles or reimplements Audible downloading. Authentication stays in Libation.
- **Updates:** never force them. Show "update available" and let the user choose.

## Tests

- Focused: `test/admin_upload_screen_test.dart`, `test/media_upload_api_test.dart`, `test/update_policy_test.dart`, `test/update_check_policy_test.dart`, `test/memory_policy_test.dart`, `test/transition_policy_test.dart`, `test/nav_hold_options_test.dart`.
- Add tests with every behavior change. Widget tests inject pickers, scanners, uploaders and clocks through `AdminUploadScreen` parameters.
