---
name: build-verify
description: Check, build and verify the Windows release of Absorb Plus into build\windows\x64\runner\Release (the folder the owner runs). Use after any code change that should reach the owner's build, or when asked to rebuild.
---

# Build and verify

The owner runs `C:\Users\pc\Desktop\claude\Absorb\build\windows\x64\runner\Release\absorb.exe`. Every user-facing change ends with a fresh build there.

1. **Version.** If this build should be distinguishable from the last one the owner has, bump first, as its own commit:
   ```powershell
   .\tool\dev.ps1 bump          # pubspec build +1 and kBetaNumber +1
   git commit -am "chore: bump build identifier to <version> (Beta <n>)"
   ```
2. **Check:** `.\tool\dev.ps1 check` (pub get, analyze, every test). Don't build on red.
3. **Is the owner using the build?** `dev.ps1 build` refuses while that exact `absorb.exe` is running. Then either:
   - ask the owner, and pass `-CloseRunning` only once they say it's fine (it closes the app gracefully); or
   - verify the build somewhere else: `git worktree add ..\absorb-verify HEAD`, build there, and later remove that worktree with `git worktree remove`. **Never** recursively delete a Flutter tree (see the CLAUDE.md warning about `.plugin_symlinks`).
4. **Build:** `.\tool\dev.ps1 build`. It needs NuGet, restores the generated plugin files after building, and fails if the exe's ProductVersion doesn't match `pubspec.yaml`.
5. **Report:** the version, the exe timestamp, and anything not verified, such as UI flows that weren't clicked through.

If CMake complains about NuGet, or a `NUGET-NOTFOUND` result is cached from an earlier run, delete `build\windows\x64\CMakeCache.txt` and rebuild.
