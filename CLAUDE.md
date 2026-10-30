# Absorb Plus — working notes

Absorb Plus is a fork of [pounat/absorb](https://github.com/pounat/absorb) (Flutter Audiobookshelf client), published at [atewertfd/absorb-platform](https://github.com/atewertfd/absorb-platform). Windows desktop is the primary target, then Android, then Linux and web. Apple and ARM builds are low priority.

## Remotes and publishing

- `origin` = upstream `pounat/absorb`. **Never push to it.** Fetch and merge from it to keep up with upstream fixes.
- `fork` / `windows` = `atewertfd/absorb-platform`. Push branches here.
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

- Output must go to `build\windows\x64\runner\Release` (the owner runs `absorb.exe` from there). If that exact exe is running, close only that copy, gracefully.
- Verify the exe's ProductVersion matches `pubspec.yaml`.
- Flutter commands rewrite `linux/flutter/generated_plugin*` and `windows/flutter/generated_plugin*`. Restore them with `git restore --source=HEAD --` unless a plugin change is intended.
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

## Tests

- Focused: `test/admin_upload_screen_test.dart`, `test/media_upload_api_test.dart`, `test/update_policy_test.dart`, `test/update_check_policy_test.dart`, `test/memory_policy_test.dart`, `test/transition_policy_test.dart`, `test/nav_hold_options_test.dart`.
- Add tests with every behavior change. Widget tests inject pickers, scanners, uploaders and clocks through `AdminUploadScreen` parameters.
