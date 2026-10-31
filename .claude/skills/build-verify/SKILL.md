---
name: build-verify
description: Check, build and verify the Windows release of Absorb Plus into build\windows\x64\runner\Release and refresh the owner's test copy in Desktop\Absorb Plus Beta\Windows. Use after any code change that should reach the owner's build, or when asked to rebuild.
---

# Build and verify

The owner tests from `C:\Users\pc\Desktop\Absorb Plus Beta\Windows\absorb.exe` (desktop shortcut "Absorb Plus (test build)"). `dev.ps1 build` builds into `build\windows\x64\runner\Release` and copies that into the beta folder. Every user-facing change ends with a fresh build there.

1. **Version.** Every build the owner gets is distinguishable from the last one: bump first, as its own commit.
   ```powershell
   .\tool\dev.ps1 bump          # pubspec build number +1 only; kBetaNumber stays
   git commit -am "chore: bump build identifier to <version> (Beta <n>)"
   ```
   `<n>` is the current `kBetaNumber` (the next beta to publish). Only after publishing a beta: `dev.ps1 bump -NextBeta`.
2. **Check:** `.\tool\dev.ps1 check` (pub get, analyze, every test, tool tests, removed paths, fork lints). Don't build on red.
3. **Build:** `.\tool\dev.ps1 build -CloseRunning` (standing owner OK, 2026-10-30). `-CloseRunning` asks a running Release or beta copy to quit through the runner's `AbsorbPlus.QuitRequest` message: it saves progress first and works even when Close to tray hid the window. The build needs NuGet and fails if the exe's ProductVersion doesn't match `pubspec.yaml`.
   - If the beta copy didn't close in time, the build still succeeds, "What's new" is refreshed, and a yellow line says to run `.\tool\dev.ps1 beta-sync -CloseRunning` later.
   - To verify a build without touching either folder: `git worktree add ..\absorb-verify HEAD`, build there, and later remove it with `git worktree remove`. **Never** recursively delete a Flutter tree (see the CLAUDE.md warning about `.plugin_symlinks`).
4. **Push** to `fork`. For phone-relevant changes, batch a `.\tool\dev.ps1 apk` in the background (see CLAUDE.md).
5. **Report:** the version, the exe timestamp, and anything not verified, such as UI flows that weren't clicked through.

If CMake complains about NuGet, or a `NUGET-NOTFOUND` result is cached from an earlier run, delete `build\windows\x64\CMakeCache.txt` and rebuild.
