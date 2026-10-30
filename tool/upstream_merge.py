"""Merge upstream (pounat/absorb) into the current Absorb Plus branch.

Handles everything with a known answer and leaves only real conflicts:
  1. requires a clean tree; records the fork's footprint before the merge;
  2. fetches origin and runs `git merge --no-ff --no-commit <ref>`;
  3. deletes every path in tool/fork-removed-paths.txt again (this also
     resolves modify/delete conflicts on them);
  4. keeps the fork's version of each path in tool/fork-overrides.txt;
  5. takes upstream's pubspec.lock and generated app_localizations*.dart
     (regenerated afterwards);
  6. merges conflicted lib/l10n/app_*.arb files key by key (upstream's text
     plus the fork's extra keys);
  7. regenerates localizations, runs tool/check_fork_removed.py and lists
     what's left for a human (or the upstream-merger agent).

It never commits, pushes, aborts or resets. Usage, from the repo root:
  python tool/upstream_merge.py [--ref origin/main] [--no-fetch] [--no-gen]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))
import check_fork_removed  # noqa: E402

DEFAULT_FLUTTER = r"C:\Users\pc\develop\flutter\bin\flutter.bat"


def git(*args: str, check: bool = False, cwd: Path = ROOT) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True,
                          encoding="utf-8", check=check)


def read_list(name: str, root: Path = ROOT) -> list[str]:
    f = root / "tool" / name
    if not f.exists():
        return []
    return [l.split("#", 1)[0].strip() for l in f.read_text(encoding="utf-8").splitlines()
            if l.split("#", 1)[0].strip()]


def merge_arb(theirs_text: str, ours_text: str, base_text: str | None) -> tuple[str, list[str]]:
    """Upstream's .arb text with the fork's extra keys appended.

    Returns (merged_text, keys_needing_review). A key whose value the fork
    changed while upstream kept the base value is reported, not merged."""
    theirs = json.loads(theirs_text)
    ours = json.loads(ours_text)
    base = json.loads(base_text) if base_text else {}
    review = [k for k in ours if k in theirs and ours[k] != theirs[k]
              and theirs[k] == base.get(k) and ours[k] != base.get(k)]
    extra = {k: v for k, v in ours.items() if k not in theirs and k not in base}
    if not extra:
        return theirs_text, review
    newline = "\r\n" if "\r\n" in theirs_text else "\n"
    body = json.dumps(extra, indent=2, ensure_ascii=False).split("\n")[1:-1]
    head = theirs_text.rstrip()
    assert head.endswith("}")
    head = head[:-1].rstrip()
    merged = head + "," + newline + newline.join(body) + newline + "}" + newline
    json.loads(merged)  # must stay valid JSON
    return merged, review


def show(ref: str, path: str, cwd: Path = ROOT) -> str | None:
    r = git("show", f"{ref}:{path}", cwd=cwd)
    return r.stdout if r.returncode == 0 else None


def unmerged(cwd: Path = ROOT) -> list[str]:
    return [p for p in git("diff", "--name-only", "--diff-filter=U", cwd=cwd).stdout.splitlines() if p]


def run(ref: str, fetch: bool, gen: bool, cwd: Path = ROOT) -> int:
    if git("status", "--porcelain", cwd=cwd).stdout.strip():
        print("Working tree isn't clean. Commit or stash first.")
        return 2
    footprint = git("diff", "--shortstat", f"{ref}...HEAD", "--", "lib", ":!lib/l10n", cwd=cwd).stdout.strip()
    print(f"Fork footprint before: {footprint or 'n/a'}")
    if fetch:
        remote = ref.split("/", 1)[0]
        print(f"Fetching {remote}...")
        git("fetch", remote, "--quiet", cwd=cwd)
    behind = git("rev-list", "--count", f"HEAD..{ref}", cwd=cwd).stdout.strip()
    if behind == "0":
        print(f"Nothing to merge: HEAD already contains {ref}.")
        return 0
    print(f"Merging {behind} upstream commit(s) from {ref}...")
    git("-c", "rerere.enabled=true", "merge", "--no-ff", "--no-commit", ref, cwd=cwd)

    for entry in read_list("fork-removed-paths.txt", cwd):
        git("rm", "-r", "-q", "-f", "--ignore-unmatch", "--", entry, cwd=cwd)
    for path in read_list("fork-overrides.txt", cwd):
        if show("HEAD", path, cwd) is not None:
            git("checkout", "--ours", "--", path, cwd=cwd)
            git("add", "--", path, cwd=cwd)

    review_notes = []
    for path in unmerged(cwd):
        if path == "pubspec.lock" or re.match(r"^lib/l10n/app_localizations.*\.dart$", path):
            git("checkout", "--theirs", "--", path, cwd=cwd)
            git("add", "--", path, cwd=cwd)
        elif re.match(r"^lib/l10n/app_[a-z_]+\.arb$", path):
            theirs, ours = show("MERGE_HEAD", path, cwd), show("HEAD", path, cwd)
            base_rev = git("merge-base", "HEAD", "MERGE_HEAD", cwd=cwd).stdout.strip()
            if theirs is None or ours is None:
                continue
            merged, review = merge_arb(theirs, ours, show(base_rev, path, cwd))
            (cwd / path).write_text(merged, encoding="utf-8", newline="")
            git("add", "--", path, cwd=cwd)
            if review:
                review_notes.append(f"{path}: fork-changed keys kept upstream's value: "
                                    + ", ".join(review))

    # A clean text merge of two .arb edits can still drop a comma; make sure
    # every merged .arb is valid JSON, rebuilding it key by key if not.
    changed = git("diff", "--name-only", "--cached", "HEAD", cwd=cwd).stdout.splitlines()
    for path in changed:
        if not re.match(r"^lib/l10n/app_[a-z_]+\.arb$", path) or not (cwd / path).exists():
            continue
        try:
            json.loads((cwd / path).read_text(encoding="utf-8"))
        except ValueError:
            theirs, ours = show("MERGE_HEAD", path, cwd), show("HEAD", path, cwd)
            if theirs and ours:
                base_rev = git("merge-base", "HEAD", "MERGE_HEAD", cwd=cwd).stdout.strip()
                merged, _ = merge_arb(theirs, ours, show(base_rev, path, cwd))
                (cwd / path).write_text(merged, encoding="utf-8", newline="")
                git("add", "--", path, cwd=cwd)
                review_notes.append(f"{path}: text merge produced invalid JSON; rebuilt key by key")

    if gen:
        flutter = os.environ.get("FLUTTER") or DEFAULT_FLUTTER
        print("Regenerating localizations...")
        r = subprocess.run([flutter, "gen-l10n"], cwd=str(cwd), capture_output=True, text=True,
                           shell=flutter.lower().endswith(".bat"))
        if r.returncode != 0:
            print("flutter gen-l10n failed:\n" + (r.stdout + r.stderr)[-1500:])
        git("add", "--", "lib/l10n", cwd=cwd)

    tracked = git("ls-files", cwd=cwd).stdout.splitlines()
    pubspec = (cwd / "pubspec.yaml").read_text(encoding="utf-8") if (cwd / "pubspec.yaml").exists() else ""
    problems = check_fork_removed.violations(
        tracked, read_list("fork-removed-paths.txt", cwd), pubspec)
    remaining = unmerged(cwd)
    print()
    for note in review_notes:
        print("REVIEW  " + note)
    for p in problems:
        print("REMOVED PATH BACK  " + p)
    if remaining:
        print(f"{len(remaining)} file(s) still conflicted (resolve, or hand to the "
              "upstream-merger agent):")
        for p in remaining:
            markers = 0
            try:
                markers = (cwd / p).read_text(encoding="utf-8", errors="replace").count("\n<<<<<<< ")
            except OSError:
                pass
            print(f"  {p}  ({markers} hunk(s))" if markers else f"  {p}")
    else:
        print("No conflicts left.")
    print("\nNext: flutter pub get, tool/dev.ps1 check, python tool/align_with_upstream.py on "
          "fork-touched files, tool/dev.ps1 build, then commit with the footprint before/after.")
    return 1 if (remaining or problems) else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", default="origin/main")
    parser.add_argument("--no-fetch", action="store_true")
    parser.add_argument("--no-gen", action="store_true", help="skip flutter gen-l10n")
    args = parser.parse_args()
    return run(args.ref, fetch=not args.no_fetch, gen=not args.no_gen)


if __name__ == "__main__":
    sys.exit(main())
