---
name: release
description: Publish an Absorb Plus beta (or prepare a stable release) on the fork atewertfd/absorb-platform — version bump, checks, build, tag, CI release, asset verification. Use when a batch of work is ready to ship or the owner asks to publish.
---

# Release

## Policy (hybrid, set by the owner)

**I publish a beta myself** once all checks pass, **except** when the batch touches:
- the playback engine (`audio_player_service.dart`, `_audio_player.dart`, `desktop_audio*`)
- download storage
- auth or tokens
- the installer or updater
- any data migration

Those betas need the owner's OK, and so does **every stable release** (an even patch number). The pre-shell hook enforces the stable rule and that the tag matches pubspec.

Never touch other releases: no deleting, renaming, or changing which one is Latest without the owner's OK. Inspect first with `gh release list --repo atewertfd/absorb-platform`.

## Steps

1. **Preflight.**
   - The worktree is clean, and the branch is pushed to `fork`.
   - CI is green on that commit: `gh run list --repo atewertfd/absorb-platform --branch <branch> --limit 3`.
   - `.\tool\dev.ps1 check` passes.
0. **Is a release due?** Releases are batched; see CLAUDE.md. Publish only for something broken or unusable, or for a medium batch of changes, roughly at most every 1–2 weeks. Otherwise just push and rebuild the owner's test folder.
2. **Version.** Run `.\tool\dev.ps1 bump` (build number only) and commit it as `chore: bump build identifier to X.Y.Z+N (Beta K)`. `K` is the current `kBetaNumber`, the beta being published. Odd patch means beta; even patch means stable.
   - **After the release is published and verified,** run `.\tool\dev.ps1 bump -NextBeta` so local builds name the next beta.
   - Commit that as `chore: start Beta K+1`.
3. **Local build:** follow the `build-verify` skill. The owner should get the same build locally.
4. **Release notes.** Write them in the scratchpad and start with `## Beta K`, because the in-app update dialog parses that heading. Then:
   - list the user-visible changes since the last release tag (`git log <last-tag>..HEAD --oneline`), in plain words;
   - say what was **not** verified;
   - give the source commit.

   No checksum files, by the owner's preference.
5. **Publish.**
   - The release workflows build from the tagged commit. If the release should also be the fork's default, fast-forward `fork/main` first (`git push fork HEAD:main`). Pushing `main` also redeploys GitHub Pages.
   - Then: `git tag -a vX.Y.Z-N -m "Absorb Plus X.Y.Z+N (Beta K)"` and `git push fork vX.Y.Z-N`.
6. **Watch CI:** `.github/workflows/release.yml`, a single run. It verifies the tag against pubspec, creates the release (Odd patch = pre-release), runs the shared checks, then builds Windows, Linux, web and Android into that one release. Run `gh run watch <id> --exit-status` in the background. If one platform job fails, fix it, then re-run that job, or use workflow_dispatch with the same tag.
7. **Finish the release.**
   - Replace the generated notes: `gh release edit vX.Y.Z-N --notes-file <file>`.
   - Verify with `gh release view vX.Y.Z-N --json name,isPrerelease,assets`. The title should read `Absorb Plus X.Y.Z-N (Beta K)`, it must be a **pre-release** for betas, and it needs the Windows Setup.exe and portable ZIP, Linux tar.gz and .deb, the web ZIP and the Android APKs, and **nothing else**: no SHA256SUMS or other `.txt` files (owner, 2026-10-30: no unnecessary files in the download). Delete any stray asset with `gh release delete-asset` before announcing.
   - Check that Latest didn't change: `gh release view --json tagName`.
8. **Report** the URL, the assets, and anything that failed.
