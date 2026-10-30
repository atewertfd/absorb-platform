---
name: upstream-merge
description: Merge new upstream Absorb (pounat/absorb, origin/main) changes into Absorb Plus — automated rules for removed/overridden paths and strings, conflict resolution, verification. Use when upstream has new commits (see /status or the weekly report).
---

# Merge upstream

1. **Start clean.**
   - Commit or finish current work, then run `git status` and `/status` to see how many upstream commits are waiting.
   - Work on a merge branch: `git switch -c claude/upstream-<yyyy-mm-dd>`.
2. **Run the automated part:**
   ```powershell
   .\tool\dev.ps1 merge        # = python tool/upstream_merge.py
   ```
   It fetches `origin`, runs `merge --no-commit`, deletes everything in `tool/fork-removed-paths.txt` again, keeps the fork's version of `tool/fork-overrides.txt` entries, takes upstream's `pubspec.lock` and generated l10n, merges `.arb` files key by key (and repairs invalid JSON), regenerates localizations, and checks that removed paths stay gone. It prints any **REVIEW** notes and the files still conflicted.
3. **Resolve what's left.**
   - **Small conflicts:** resolve them yourself.
   - **Larger or numerous conflicts:** hand them to the `upstream-merger` subagent, a few files per agent; parallel agents are fine for unrelated files.
   - **Policy:**
     - keep every upstream change and every fork behavior;
     - formatting-only differences go to upstream's side;
     - in playback, sync, download or auth logic, never guess: compare both sides' intent with `git log MERGE_HEAD -- <file>` and `git log HEAD -- <file>`.
   - Check for leftovers: `git diff --check` and `git grep -n '^<<<<<<< '`.
4. **New upstream Apple or other removed-area code** that the tool reports, such as new calls into removed services: make it compile with the smallest fork-side change, ideally in the stub or override file rather than upstream's call site.
5. **Verify:**
   - `.\tool\dev.ps1 check`, which runs analyze, the tests, the tool tests and the removed-paths check;
   - `python tool/align_with_upstream.py <fork-touched upstream files>`, adding `--apply` when it shrinks the diff;
   - `/build-verify`.
6. **Commit** as `merge: bring in upstream Absorb (<N> commits, <upstream version>)`. In the body, list the notable upstream features or fixes, each conflict choice made, and the footprint before and after (from the tool's first line and `.\tool\dev.ps1 footprint`).
7. **Push** the branch to `fork`. CI runs. Then fold it into the working branch.

   If the upstream changes are user-visible, consider a beta with `/release`. A merge that touched playback, downloads or auth falls under the risky list, so the owner's OK is needed before publishing it.
