---
name: fork-feature
description: Conventions for adding or changing an Absorb Plus feature without making upstream merges harder — where code goes, strings, tests, docs. Use whenever starting new feature work in lib/.
---

# Adding a fork feature

Absorb Plus keeps merging upstream (pounat/absorb). Every line changed in an upstream file is a possible conflict later. Design for that.

1. **Where the code goes.**
   - New logic goes in **new files**, following upstream's layout: `lib/services/<feature>_*.dart`, `lib/widgets/<feature>_*.dart`, `lib/screens/...`.
   - Upstream files only get thin hooks: an import, a constructor parameter or callback, one tile or button.
   - Example to copy: Libation. Its logic is in `lib/services/libation_import_helper.dart`, its UI in `lib/widgets/libation_import_card.dart` and `libation_book_picker_sheet.dart`, and the only hooks are in `admin_upload_screen.dart` and `settings_screen.dart`.
   - To see if a file is upstream's: `git cat-file -e origin/main:<path>`. If that succeeds, it's upstream-owned.
2. **No reformatting** of existing upstream files. The pre-shell hook blocks `dart format` on them. If churn slips in, run `python tool/align_with_upstream.py --apply <files>`.
3. **Reuse before adding.** Use `lib/utils/duration_format.dart` for durations. There is no shared byte formatter yet: if a fork feature needs one, add a fork file (`lib/utils/format_bytes.dart`) instead of another private `_formatBytes`. Use `debugPrint` for logs; `LogService` captures them.
4. **Strings.**
   - Add new keys only to `lib/l10n/app_en.arb`, with `@key` placeholder metadata for parameters. The post-edit hook runs `flutter gen-l10n`.
   - Never edit `app_localizations*.dart`.
5. **Settings keys** for fork features belong together in a fork-owned file (`lib/services/fork_pref_keys.dart` once it exists). Don't put raw string keys in the middle of code.
6. **Tests come with every behavior change.**
   - Make UI testable by injecting pickers, scanners, uploaders, searchers and clocks through constructor parameters. `AdminUploadScreen` is the model.
   - Use `SharedPreferences.setMockInitialValues`, hand-written fakes, or `MockClient` from `package:http/testing.dart` (there is no mocking package). Never use a real server; integration tests use the throwaway test server.
7. **Safety rules from CLAUDE.md apply:**
   - no credentials in logs;
   - uploads and server changes only on an explicit user action;
   - Libation means imported exports only, never Audible login.
8. **Before committing:**
   - `.\tool\dev.ps1 check` passes;
   - ask the `reviewer` subagent to review the diff;
   - add the feature's files to the fork-only table in `docs/ARCHITECTURE.md`;
   - record `.\tool\dev.ps1 footprint` in the commit message if upstream files changed.
