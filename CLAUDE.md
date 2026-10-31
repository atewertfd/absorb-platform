@AGENTS.md

# Claude Code: rules for Absorb Plus

Claude is the main and only developer of Absorb Plus, a fork of [pounat/absorb](https://github.com/pounat/absorb) published at [atewertfd/absorb-platform](https://github.com/atewertfd/absorb-platform). The shared conventions are in AGENTS.md (imported above), the code map is `docs/ARCHITECTURE.md`, and procedures are skills (below).

**Platforms:** Windows, Android and web are the main focus, with Linux slightly behind. Apple support is removed.

| Platform | Who tests it | So Claude must |
|---|---|---|
| Windows | The owner, the most | Build after every change; `dev.ps1 build` refreshes `Desktop\Absorb Plus Beta\Windows` |
| Android | The owner's phone, often but less | After meaningful changes, `dev.ps1 apk` (background) puts a signed APK in `Desktop\Absorb Plus Beta\Android` |
| Web | Nobody by hand | Check it through CI builds and the Pages deploy |
| Linux | Never by hand | Cover it through CI builds and checks |

## Owner decisions (2026-10-29)

- **Upstream: hybrid.** Keep merging `origin/main`. Restructure freely in fork-owned code and tooling. Change upstream-owned files only when the gain beats the merge cost; split giant upstream files only on the criteria in the plan (`footprint -Churn`).
- **Upstream merges are never automatic.** Nothing merges, pushes or publishes on a schedule; reports only *report*. Claude decides when a merge is worth it and does it on its own branch (`claude/upstream-<date>`) with the `/upstream-merge` skill. Claude reviews every real conflict itself, then runs all checks and builds Windows. A merge that touches playback, downloads, sign-in or the installer reaches the owner's `main` and releases only after the owner has tried that Windows build and said OK.
- **Apple: removed.** Paths in `tool/fork-removed-paths.txt` stay deleted. Merges drop them automatically, and the hooks block edits to them.
- **Releases: hybrid.** Claude publishes routine **betas** once every check passes. **Stable releases**, and betas touching the playback engine, download storage, auth or tokens, the installer or updater, or data migrations, need the owner's OK first. See the `release` skill.
- **Releases are batched (2026-10-30).** Don't publish for every small change.
  - Publish a beta when something is broken or unusable, such as a crash, playback, downloads, sync or sign-in failing. Release those fixes quickly.
  - Otherwise publish when a medium batch of features or fixes has built up: roughly at most every 1–2 weeks, never for one tiny tweak.
  - Work still lands on GitHub, the owner's Windows test folder is still rebuilt after every change, and web still redeploys from `main`.
  - Each release gets one set of notes covering everything since the last one.
- Always ask before:
  - system-level installs or Windows features;
  - anything touching the owner's real Audiobookshelf server or NAS;
  - moving tokens to secure storage;
  - opening upstream PRs;
  - pruning branches on the fork.

## Location and remotes

- The main checkout is `C:\Users\pc\Desktop\claude\Absorb`.
- **The owner tests from `C:\Users\pc\Desktop\Absorb Plus Beta`** (owner request, 2026-10-30): one folder that's always current.
  - `Windows\` is refreshed by every `dev.ps1 build`, or `beta-sync` if it was open during the build.
  - `Android\Absorb Plus beta.apk` comes from `dev.ps1 apk`.
  - `What's new.txt` lists the changes since the last published release.
  - The desktop shortcut "Absorb Plus (test build)" opens the Windows copy.
  - Every change is also pushed to `fork`. Releases stay batched.
- **After every app change (standing owner OK, 2026-10-30):**
  - run `dev.ps1 bump` and `dev.ps1 build -CloseRunning`;
  - that closes the beta copy even when it's hidden in the tray, refreshes `Windows\` and "What's new", then push;
  - for changes that affect the phone, also run `dev.ps1 apk` in the background, **batched** (one APK per few changes) and **untracked**: don't wait on it or report it; update the phone download page when it lands. Build it right away only when the owner asks for the phone update (owner, 2026-10-30).
- `origin` is upstream; **never push to it** (hook- and permission-enforced). `fork` is where everything is pushed. `codex-local` is the old Codex checkout under `C:\Users\pc\Documents\Codex\2026-09-29\`, kept read-only as a backup; don't build or commit there.
- A `v*` tag on the fork publishes a pre-release through CI. Pushing `main` redeploys the web build to GitHub Pages.

## Tooling (use it)

- **Skills** (`.claude/skills`, also slash commands):
  - `/status`: where things stand;
  - `/build-verify`: check, build and verify the Release folder;
  - `/release`: publish a beta following the policy;
  - `/perf-measure`: RAM and CPU numbers before any performance claim;
  - `/fork-feature`: where new code goes.
- **Subagents** (`.claude/agents`):
  - `reviewer`: read-only diff review before commits;
  - `upstream-merger`: conflict resolution during upstream merges;
  - `test-writer`: tests using the project's fakes.
- **Hooks** (`tool/claude_hooks.py`, wired in `.claude/settings.json`). They block pushes to upstream, `git reset --hard`, recursive deletes through junctions, `dart format` on upstream files, edits to generated or removed files, and they ask before deleting releases or tags and before stable tags. They regenerate localizations after `.arb` edits and print the repo state at session start. Their tests: `python -m unittest discover -s tool/tests`.
- **Where things are built:**
  - Windows: locally, into the owner's Release folder.
  - Android, Linux and web: GitHub Actions. It's free (public repo) and runs in the background, and Android gets the permanent signing key there.
  - A signed phone-test APK: run `gh workflow run ci.yml --ref <branch>` and download the `absorb-android-apk` artifact.
  - **Local APKs (owner OK, 2026-10-30):** the Android SDK is installed at `%LOCALAPPDATA%\Android\Sdk` (JDK 21 from `JAVA_HOME`). `dev.ps1 apk -Local` builds the signed arm64 test APK here, checks its signature and copies it to the beta folder. It needs `android\key.properties` (git-ignored), which **the owner** creates once with `tool\android-signing-setup.ps1`. Never read, print or copy `key.properties` or the key folder's `password.txt`. Without it, `dev.ps1 apk` builds on CI as before.
- **Scripts:**
  - `tool/dev.ps1` (check, build, bump, footprint, merge);
  - `tool/align_with_upstream.py` (undo formatting churn);
  - `tool/measure-windows-usage.ps1`.

## Keeping context small

- **`dev.ps1` prints one line per step.** Full logs are in `build\dev-logs\<step>.log`; read them only when a step fails (the failing tail is printed anyway). Use `-Full` to stream everything.
- **Never dump raw tool output.**
  - Filter with `tail`, `grep`, `Select-String` or `--json ... --jq`.
  - Run builds, CI watches (`gh run watch`) and long tests in the background, and read only the summary.
- **Don't read giant files whole.** `audio_player_service.dart`, `ebook_reader_view.dart`, `settings_screen.dart`, `api_service.dart` and `_lp_core.dart` run 4,000–8,000 lines. Grep for the symbol, then read a window around it.
- **Delegate broad searches and audits** to `Explore` or `general-purpose` subagents, and big reviews to `reviewer`. Keep only their conclusions.
- **One session per task.** `CLAUDE.md`, memory and the SessionStart hook bring a new session up to speed. Before a long session ends, update `docs/ARCHITECTURE.md` and memory so nothing lives only in the conversation.

## Hazards learned the hard way

- **Never recursively delete a Flutter tree** with `robocopy /MIR`, `Remove-Item -Recurse` or `rm -rf`. `*/flutter/ephemeral/.plugin_symlinks` are junctions into the shared Pub cache, and a delete through them once emptied 23 cached packages. Remove the links first (`cmd /c rmdir <link>`), or use `git worktree remove`.
  - **Repair:** find empty folders under `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev`, `rmdir` them, then run `flutter pub get`.
- **Generated plugin files** (`*/flutter/generated_plugin*`): restore them only **after** building. The committed list names `jni`, which this machine's Flutter drops, so restoring before a `--no-pub` build breaks CMake. `dev.ps1` handles this.
- **NuGet is required for Windows builds** (WebView2 plugin). If CMake cached `NUGET-NOTFOUND`, delete `build\windows\x64\CMakeCache.txt`.
- **Closing Absorb's window only hides it to the tray.** For refreshing the beta folder, the owner allows `-CloseRunning`, which quits it gracefully. Without that flag, `build` and `beta-sync` leave an open copy alone and only refresh "What's new".
- **Bash heredocs on this machine collapse `\\`.** Write scripts containing backslashes or regexes to a file with the Write tool.
- **Never `dart format` existing upstream files**: it rewraps hundreds of lines into future conflicts.

## Product and safety rules

- **Keep Absorb's normal look.** No redesigns, color changes or new animations unless the owner asks; earlier animation and scroll experiments regressed and were rolled back.
- **Performance work is stability-first:** rebuild scope, lifecycle, bounded caches. Measure with `/perf-measure`. Never break playback, downloads, sync, scrolling, Android or web to improve Windows.
- Absorb is a client of the user's own Audiobookshelf server.
  - Credentials are entered by the user and never logged.
  - Never search the machine for passwords, tokens or account files. Never read Libation's account or config files (permission-denied).
  - Never upload, modify or delete server data without an explicit user action, and never claim success unless the server response proves it.
  - Libation support imports **exported files** only. It is not an Audible login and doesn't bypass DRM; say so honestly.
  - Never test against the owner's server or NAS. Use fixtures or the throwaway Docker test server.

## Owner preferences

- **Installer:** a normal EXE installer plus a portable ZIP. Updates install in place and keep data; uninstalling never deletes user data unexpectedly.
- **Builds:** every user-facing build gets a build-number bump (`dev.ps1 bump`), so the app shows which build is running.
  - The **Beta number** (`kBetaNumber`) names the next beta to be published and stays put between releases.
  - Raise it only after publishing: `dev.ps1 bump -NextBeta`.
- **Updates:** never forced. Show "update available" and let the user choose.
- **Release assets:** no SHA256SUMS files.
- **NAS / local-server discovery work** (`codex-local/feature/local-server-discovery`): paused until the owner says go.
- **Libation docs:** [getting started](https://github.com/rmcrackan/Libation/blob/master/docs/getting-started.md), [CLI](https://github.com/rmcrackan/Libation/blob/master/docs/advanced/command-line-interface.md).
- **Git:** small logical commits. Never `reset --hard` or overwrite uncommitted work.
