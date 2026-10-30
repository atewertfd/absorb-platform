"""Fail if anything listed in tool/fork-removed-paths.txt is tracked again.

Also checks pubspec.yaml for Apple-only config that must stay removed.
Run from the repo root:  python tool/check_fork_removed.py   (CI runs it too)
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIST = ROOT / "tool" / "fork-removed-paths.txt"

PUBSPEC_FORBIDDEN = [
    (re.compile(r"^\s*flutter_carplay\s*:", re.M), "flutter_carplay dependency"),
    (re.compile(r"^\s*ios:\s*true", re.M), "ios: true (launcher icons / splash)"),
    (re.compile(r"^\s*remove_alpha_ios\s*:", re.M), "remove_alpha_ios"),
]


def removed_paths(list_file: Path = LIST) -> list[str]:
    paths = []
    for line in list_file.read_text(encoding="utf-8").splitlines():
        entry = line.split("#", 1)[0].strip()
        if entry:
            paths.append(entry)
    return paths


def matches(path: str, entry: str) -> bool:
    entry = entry.rstrip("/")
    return path == entry or path.startswith(entry + "/")


def violations(tracked: list[str], entries: list[str], pubspec: str) -> list[str]:
    found = []
    for entry in entries:
        hits = [p for p in tracked if matches(p, entry)]
        if hits:
            found.append(f"{entry}: {len(hits)} tracked file(s), e.g. {hits[0]}")
    for pattern, what in PUBSPEC_FORBIDDEN:
        if pattern.search(pubspec):
            found.append(f"pubspec.yaml contains {what}")
    return found


def main() -> int:
    tracked = subprocess.run(["git", "-C", str(ROOT), "ls-files"], capture_output=True,
                             text=True, check=True).stdout.splitlines()
    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    problems = violations(tracked, removed_paths(), pubspec)
    if problems:
        print("Paths removed from Absorb Plus are back (see tool/fork-removed-paths.txt):")
        for p in problems:
            print("  - " + p)
        return 1
    print(f"OK: none of the {len(removed_paths())} removed paths are tracked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
