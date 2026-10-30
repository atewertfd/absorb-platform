# Repository Guidelines

Absorb Plus is a Flutter Audiobookshelf client, maintained as a fork of [pounat/absorb](https://github.com/pounat/absorb). **`CLAUDE.md` is the authoritative guide**: build, release, version and safety rules plus owner preferences. `docs/ARCHITECTURE.md` maps the code. This file is the short version for any coding agent.

## Structure

- `lib/screens/`, `lib/widgets/`, `lib/services/`, `lib/providers/`, `lib/utils/` hold app code. The layout is upstream's: keep files where upstream has them so upstream merges stay clean.
- `lib/l10n/app_*.arb` holds strings. The generated `app_localizations*.dart` files come from `flutter gen-l10n` and are never edited by hand.
- `test/` holds Flutter tests, and `tool/` holds maintenance scripts. `packages/` holds vendored plugins with their own lint baselines.

## Build and test (Windows, PowerShell)

```powershell
.\tool\dev.ps1 check      # pub get, analyze, tests
.\tool\dev.ps1 build      # Windows release into build\windows\x64\runner\Release
.\tool\dev.ps1 bump       # next build number + beta number, in pubspec.yaml and lib/build_info.dart
```

## Style

- Follow `analysis_options.yaml` and Dart conventions.
- **Don't reformat existing upstream files.** Formatting churn becomes merge conflicts. Format only new files or code you wrote. `tool/align_with_upstream.py` undoes accidental churn.
- Keep fork-only features in their own files and touch upstream files only where they must hook in.
- Put user-facing text in `lib/l10n/app_en.arb`, then run `flutter gen-l10n`.

## Testing

Add or update tests with every behavior change. Inject fakes for network, uploads, file pickers and time; never use a real Audiobookshelf server.

## Commits

Use scoped, imperative messages (`fix: …`, `perf: …`, `refactor: …`, `docs: …`). Push only to `atewertfd/absorb-platform`, never upstream.

## Product and safety

- Keep Absorb's normal look.
- Performance work must be stability-first.
- Never search for credentials or read Libation account/configuration files.
- Libation support imports the user's exported files only. It is not an Audible login and does not download protected content.
- Uploads to Audiobookshelf happen only on an explicit user action.
