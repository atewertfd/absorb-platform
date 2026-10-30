"""Claude Code hooks for Absorb Plus.

Guards the rules in CLAUDE.md so they hold even when a step is rushed:
never push to upstream, never hand-edit generated files, never delete a
Flutter tree through its plugin links, never reformat upstream files, and
ask before anything that publishes or destroys release history.

Usage (wired in .claude/settings.json):
  python tool/claude_hooks.py pre-shell | pre-edit | post-edit | stop | session-start

Each subcommand reads the hook's JSON from stdin. Decision logic lives in
pure functions that take a Context, so tool/tests/test_claude_hooks.py can
exercise it without git or a filesystem.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

ALLOW, ASK, DENY = "allow", "ask", "deny"

GENERATED_PLUGIN_FILES = (
    "linux/flutter/generated_plugin_registrant.cc",
    "linux/flutter/generated_plugin_registrant.h",
    "linux/flutter/generated_plugins.cmake",
    "windows/flutter/generated_plugin_registrant.cc",
    "windows/flutter/generated_plugin_registrant.h",
    "windows/flutter/generated_plugins.cmake",
)
DEFAULT_FLUTTER = r"C:\Users\pc\develop\flutter\bin\flutter.bat"


@dataclass
class Decision:
    verdict: str
    reason: str = ""


# --------------------------------------------------------------------------
# Context: everything the rules need to know about the repo. Tests swap in
# a fake.
# --------------------------------------------------------------------------

class Context:
    def __init__(self, cwd: str):
        self.cwd = Path(cwd or os.getcwd())
        self.root = self._find_root(self.cwd)

    @staticmethod
    def _find_root(start: Path) -> Path:
        for p in [start, *start.parents]:
            if (p / ".git").exists():
                return p
        return start

    def git(self, *args: str, timeout: float = 10) -> str:
        try:
            out = subprocess.run(["git", "-C", str(self.root), *args],
                                 capture_output=True, text=True, timeout=timeout)
            return out.stdout.strip() if out.returncode == 0 else ""
        except Exception:
            return ""

    def dirty_paths(self) -> list[str]:
        lines = self.git("status", "--porcelain").splitlines()
        return [l[3:].strip().strip('"') for l in lines if l.strip()]

    def upstream_of_current_branch(self) -> str:
        return self.git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")

    def exists_upstream(self, rel: str) -> bool:
        if not self.git("rev-parse", "--verify", "--quiet", "origin/main"):
            return False
        try:
            r = subprocess.run(["git", "-C", str(self.root), "cat-file", "-e",
                                f"origin/main:{rel}"], capture_output=True, timeout=10)
            return r.returncode == 0
        except Exception:
            return False

    def pubspec_version(self) -> str:
        try:
            text = (self.root / "pubspec.yaml").read_text(encoding="utf-8")
        except OSError:
            return ""
        m = re.search(r"^version:\s*(\S+)", text, re.M)
        return m.group(1) if m else ""

    def resolve(self, raw: str) -> Path | None:
        if not raw or any(ch in raw for ch in "$%`*?") or raw.startswith("~"):
            return None
        p = Path(raw.strip("'\""))
        if re.match(r"^/[a-zA-Z]/", raw):  # Git Bash style /c/Users/...
            p = Path(f"{raw[1]}:/{raw[3:]}")
        return (p if p.is_absolute() else self.cwd / p).resolve()

    def rel(self, path: Path) -> str | None:
        try:
            return path.resolve().relative_to(self.root.resolve()).as_posix()
        except (ValueError, OSError):
            return None

    def removed_paths(self) -> list[str]:
        f = self.root / "tool" / "fork-removed-paths.txt"
        try:
            lines = f.read_text(encoding="utf-8").splitlines()
        except OSError:
            return []
        return [l.split("#")[0].strip() for l in lines if l.split("#")[0].strip()]

    def link_inside(self, path: Path, budget_s: float = 4.0) -> str:
        """Return the first junction/symlink/.plugin_symlinks found inside
        `path` (not following links), 'TIMEOUT' if the scan ran long, or ''."""
        deadline = time.monotonic() + budget_s
        stack = [path]
        while stack:
            if time.monotonic() > deadline:
                return "TIMEOUT"
            current = stack.pop()
            try:
                entries = list(os.scandir(current))
            except OSError:
                continue
            for e in entries:
                if e.name == ".plugin_symlinks" or _is_link(e.path):
                    return e.path
                try:
                    if e.is_dir(follow_symlinks=False):
                        stack.append(Path(e.path))
                except OSError:
                    continue
        return ""


def _is_link(p: str) -> bool:
    try:
        st = os.lstat(p)
    except OSError:
        return False
    if stat.S_ISLNK(st.st_mode):
        return True
    attrs = getattr(st, "st_file_attributes", 0)
    return bool(attrs & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))


# --------------------------------------------------------------------------
# pre-shell
# --------------------------------------------------------------------------

def split_segments(command: str) -> list[str]:
    parts = re.split(r"\r?\n|&&|\|\||;|\|", command)
    return [p.strip() for p in parts if p.strip()]


def tokens(segment: str) -> list[str]:
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def _after(toks: list[str], word: str) -> list[str] | None:
    lowered = [t.lower() for t in toks]
    if word not in lowered:
        return None
    return toks[lowered.index(word) + 1:]


def _git_args(toks: list[str], sub: str) -> list[str] | None:
    """Arguments after `git [opts] <sub>`, or None if this isn't that command."""
    if not toks or os.path.basename(toks[0]).lower() not in ("git", "git.exe"):
        return None
    i = 1
    while i < len(toks) and toks[i].startswith("-"):
        i += 2 if toks[i] in ("-C", "-c") else 1
    if i < len(toks) and toks[i] == sub:
        return toks[i + 1:]
    return None


def check_push(args: list[str], ctx: Context) -> Decision:
    opts = [a for a in args if a.startswith("-")]
    pos = [a for a in args if not a.startswith("-")]
    remote = pos[0] if pos else ""
    refspecs = pos[1:]
    if not remote:
        upstream = ctx.upstream_of_current_branch()
        if upstream.startswith("origin/"):
            return Decision(DENY, "This branch tracks origin (upstream pounat/absorb). "
                                  "Push to the fork instead: git push fork <branch>.")
        return Decision(ALLOW)
    if remote == "origin" or "pounat/absorb" in remote:
        return Decision(DENY, "Never push to upstream (origin = pounat/absorb). "
                              "Push to the fork remote instead.")
    if "--delete" in opts or "-d" in opts or any(r.startswith(":") for r in refspecs):
        return Decision(ASK, "Deleting a remote branch or tag on the fork.")
    if "--tags" in opts or "--mirror" in opts or "--all" in opts:
        return Decision(ASK, "This pushes many refs at once (tags trigger releases).")
    force = any(o in ("-f", "--force", "--force-with-lease") or o.startswith("--force")
                for o in opts) or any(r.startswith("+") for r in refspecs)
    for ref in refspecs:
        target = ref.lstrip("+").split(":")[-1]
        if force and target in ("main", "refs/heads/main"):
            return Decision(ASK, "Force-pushing the fork's main branch.")
        tag = target.removeprefix("refs/tags/")
        if re.match(r"^v\d", tag):
            return check_release_tag(tag, ctx)
    return Decision(ALLOW)


def check_release_tag(tag: str, ctx: Context) -> Decision:
    version = ctx.pubspec_version()
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)\+(\d+)$", version)
    if not m:
        return Decision(ASK, f"Pushing release tag {tag}; couldn't read pubspec version.")
    expected = f"v{m.group(1)}.{m.group(2)}.{m.group(3)}-{m.group(4)}"
    if tag != expected:
        return Decision(DENY, f"Release tag {tag} doesn't match pubspec.yaml "
                              f"({version} -> {expected}). Bump with tool/dev.ps1 bump first.")
    if int(m.group(3)) % 2 == 0:
        return Decision(ASK, f"{tag} has an even patch number, which marks a STABLE release. "
                             "Stable releases need the owner's OK.")
    return Decision(ALLOW)


def check_discard(args: list[str], sub: str, ctx: Context) -> Decision:
    if sub == "reset":
        if "--hard" in args:
            return Decision(DENY, "git reset --hard discards work. Commit or stash first, "
                                  "or restore specific files.")
        return Decision(ALLOW)
    if sub == "clean":
        if any(a.startswith("-") and "f" in a.lstrip("-") for a in args if not a.startswith("--")) \
                or "--force" in args:
            return Decision(ASK, "git clean -f permanently deletes untracked files.")
        return Decision(ALLOW)
    # checkout / restore of paths
    if sub == "restore" and "--staged" in args and "--worktree" not in args:
        return Decision(ALLOW)
    if sub == "checkout" and "--" not in args and "." not in args:
        return Decision(ALLOW)  # branch switch; git refuses to clobber changes
    paths = args[args.index("--") + 1:] if "--" in args else \
        [a for a in args if not a.startswith("-") and not a.startswith("--source")]
    if paths and all(p.replace("\\", "/") in GENERATED_PLUGIN_FILES
                     or p.replace("\\", "/").rstrip("/") in ("linux/flutter", "windows/flutter")
                     for p in paths):
        return Decision(ALLOW)
    dirty = ctx.dirty_paths()
    if not dirty:
        return Decision(ALLOW)
    return Decision(ASK, f"This overwrites uncommitted changes ({len(dirty)} file(s) modified). "
                         "Make sure none of them are someone else's work.")


RM_NAMES = ("rm", "rm.exe")
REMOVE_ITEM_NAMES = ("remove-item", "ri", "del", "erase", "rd", "rmdir")


def recursive_delete_targets(toks: list[str]) -> list[str] | None:
    """Targets of a recursive delete, or None if this segment isn't one."""
    if not toks:
        return None
    name = os.path.basename(toks[0]).lower()
    args = toks[1:]
    if name in RM_NAMES:
        flags = "".join(a.lstrip("-") for a in args if a.startswith("-") and not a.startswith("--"))
        if "r" in flags.lower() or "--recursive" in args:
            return [a for a in args if not a.startswith("-")]
        return None
    if name in REMOVE_ITEM_NAMES:
        lowered = [a.lower() for a in args]
        recursive = any(a in ("-recurse", "-r", "-rec", "/s") for a in lowered)
        if not recursive and name not in ("rd", "rmdir"):
            return None
        if name in ("rd", "rmdir") and "/s" not in lowered and "-recurse" not in lowered:
            return None
        targets, skip = [], False
        for a, low in zip(args, lowered):
            if skip:
                targets.append(a)
                skip = False
            elif low in ("-path", "-literalpath"):
                skip = True
            elif not a.startswith("-") and not a.startswith("/"):
                targets.append(a)
        return targets
    if name in ("robocopy", "robocopy.exe"):
        lowered = [a.lower() for a in args]
        if "/mir" in lowered or "/purge" in lowered:
            pos = [a for a in args if not a.startswith("/")]
            return pos[1:2]
        return None
    return None


def check_recursive_delete(targets: list[str], ctx: Context) -> Decision:
    if not targets:
        return Decision(ASK, "Recursive delete with a target I couldn't read.")
    for raw in targets:
        path = ctx.resolve(raw)
        if path is None:
            return Decision(ASK, f"Recursive delete of '{raw}', which I can't resolve to a path.")
        if not path.exists():
            continue
        if (path / ".git").exists() or path == path.anchor or path == Path.home():
            return Decision(DENY, f"Refusing to recursively delete {path}: it is a repo, "
                                  "drive or home root.")
        if _is_link(str(path)):
            continue  # deleting the link itself is what we want
        found = ctx.link_inside(path)
        if found == "TIMEOUT":
            return Decision(ASK, f"{path} is large; I couldn't confirm it holds no links.")
        if found:
            return Decision(DENY, f"{path} contains a link ({found}). Recursive deletes follow "
                                  "links on Windows and would empty the target (this once wiped "
                                  "23 packages in the shared Pub cache). Remove the links first "
                                  "(cmd /c rmdir <link>) or use git worktree remove.")
    return Decision(ALLOW)


def check_dart_format(toks: list[str], ctx: Context) -> Decision | None:
    joined = [os.path.basename(t).lower() for t in toks]
    if not joined or joined[0] not in ("dart", "dart.bat", "dart.exe", "flutter", "flutter.bat"):
        return None
    if len(toks) < 2 or toks[1] != "format":
        return None
    targets = [t for t in toks[2:] if not t.startswith("-")]
    if not targets:
        return Decision(DENY, "dart format without a file list reformats everything. "
                              "Format only new files.")
    for raw in targets:
        path = ctx.resolve(raw)
        if path is None or path.is_dir():
            return Decision(DENY, f"dart format on '{raw}' would reformat a whole directory. "
                                  "Format only new files.")
        rel = ctx.rel(path)
        if rel and ctx.exists_upstream(rel):
            return Decision(DENY, f"{rel} is an upstream file. Reformatting it creates merge "
                                  "conflicts; format only code you wrote, by hand.")
    return Decision(ALLOW)


def check_gh(toks: list[str]) -> Decision | None:
    if not toks or os.path.basename(toks[0]).lower() not in ("gh", "gh.exe"):
        return None
    words = [t.lower() for t in toks[1:]]
    if words[:2] in (["release", "delete"], ["release", "delete-asset"]):
        return Decision(ASK, "Deleting a GitHub release or asset can't be undone.")
    if words[:2] == ["release", "edit"] and any(
            w in ("--latest", "--prerelease=false", "--draft=false") for w in words):
        return Decision(ASK, "This changes which release is Latest or makes one stable.")
    if words[:1] == ["repo"] and "delete" in words:
        return Decision(DENY, "Never delete the repository.")
    return None


WRAPPERS = {
    "cmd": ("/c", "/k"), "cmd.exe": ("/c", "/k"),
    "powershell": ("-command", "-c"), "powershell.exe": ("-command", "-c"),
    "pwsh": ("-command", "-c"), "pwsh.exe": ("-command", "-c"),
    "bash": ("-c",), "bash.exe": ("-c",), "sh": ("-c",),
}


def _unwrap(toks: list[str]) -> str | None:
    """The inner command of `cmd /c ...`, `powershell -Command ...`, `bash -c ...`."""
    if not toks:
        return None
    flags = WRAPPERS.get(os.path.basename(toks[0]).lower())
    if not flags:
        return None
    lowered = [t.lower() for t in toks]
    for flag in flags:
        if flag in lowered:
            inner = toks[lowered.index(flag) + 1:]
            return " ".join(inner) if len(inner) > 1 else (inner[0] if inner else None)
    return None


def decide_shell(command: str, ctx: Context, depth: int = 0) -> Decision:
    worst = Decision(ALLOW)
    rank = {ALLOW: 0, ASK: 1, DENY: 2}
    for seg in split_segments(command):
        toks = tokens(seg)
        d: Decision | None = None
        inner = _unwrap(toks)
        if inner and depth < 3:
            d = decide_shell(inner, ctx, depth + 1)
            if rank[d.verdict] > rank[worst.verdict]:
                worst = d
            continue
        if (args := _git_args(toks, "push")) is not None:
            d = check_push(args, ctx)
        else:
            for sub in ("reset", "checkout", "restore", "clean"):
                if (args := _git_args(toks, sub)) is not None:
                    d = check_discard(args, sub, ctx)
                    break
            if d is None and (args := _git_args(toks, "tag")) is not None:
                if "-d" in args or "--delete" in args:
                    d = Decision(ASK, "Deleting a tag.")
        if d is None and (targets := recursive_delete_targets(toks)) is not None:
            d = check_recursive_delete(targets, ctx)
        if d is None:
            d = check_dart_format(toks, ctx)
        if d is None:
            d = check_gh(toks)
        if d and rank[d.verdict] > rank[worst.verdict]:
            worst = d
    return worst


# --------------------------------------------------------------------------
# pre-edit / post-edit
# --------------------------------------------------------------------------

def decide_edit(file_path: str, ctx: Context) -> Decision:
    path = ctx.resolve(file_path) or Path(file_path)
    rel = ctx.rel(path) or file_path.replace("\\", "/")
    if re.match(r"^lib/l10n/app_localizations.*\.dart$", rel):
        return Decision(DENY, "Generated by flutter gen-l10n. Edit lib/l10n/app_en.arb instead; "
                              "the post-edit hook regenerates these files.")
    if rel in GENERATED_PLUGIN_FILES:
        return Decision(DENY, "Generated by Flutter tooling; never edit by hand.")
    for removed in ctx.removed_paths():
        if rel == removed.rstrip("/") or rel.startswith(removed.rstrip("/") + "/"):
            return Decision(DENY, f"{rel} is in tool/fork-removed-paths.txt (removed from the "
                                  "fork on purpose). Remove it from that list first if this "
                                  "is really wanted.")
    return Decision(ALLOW)


def post_edit_messages(file_path: str, ctx: Context, session_id: str,
                       run_gen_l10n=None) -> list[str]:
    path = ctx.resolve(file_path) or Path(file_path)
    rel = ctx.rel(path) or ""
    notes = []
    if re.match(r"^lib/l10n/app_[a-z_]+\.arb$", rel):
        ok, out = (run_gen_l10n or _run_gen_l10n)(ctx)
        notes.append("Regenerated localizations (flutter gen-l10n)." if ok else
                     f"flutter gen-l10n FAILED after editing {rel}:\n{out[-1500:]}")
    elif rel.startswith("lib/") and ctx.exists_upstream(rel) and _first_time(session_id, rel):
        notes.append(f"{rel} is an upstream file: keep the change minimal (no reformatting, "
                     "no moved code); put new logic in a fork-owned file and call it from here.")
    return notes


def _run_gen_l10n(ctx: Context) -> tuple[bool, str]:
    flutter = os.environ.get("FLUTTER") or DEFAULT_FLUTTER
    try:
        r = subprocess.run([flutter, "gen-l10n"], cwd=str(ctx.root), capture_output=True,
                           text=True, timeout=120, shell=flutter.lower().endswith(".bat"))
        return r.returncode == 0, (r.stdout + r.stderr)
    except Exception as e:  # noqa: BLE001 - report, never crash the hook
        return False, str(e)


def _first_time(session_id: str, rel: str) -> bool:
    marker = Path(tempfile.gettempdir()) / f"absorb-hooks-{session_id or 'nosession'}.txt"
    try:
        seen = set(marker.read_text(encoding="utf-8").splitlines()) if marker.exists() else set()
        if rel in seen:
            return False
        with marker.open("a", encoding="utf-8") as f:
            f.write(rel + "\n")
    except OSError:
        pass
    return True


# --------------------------------------------------------------------------
# stop / session-start
# --------------------------------------------------------------------------

def stop_warnings(ctx: Context) -> list[str]:
    warnings = []
    check = ctx.git("diff", "--check", "HEAD")
    if check:
        warnings.append("git diff --check found whitespace problems:\n" + check[:800])
    changed = ctx.git("diff", "--name-only", "HEAD").splitlines()
    if any(re.match(r"^lib/l10n/app_[a-z_]+\.arb$", c) for c in changed) and \
            not any(c.startswith("lib/l10n/app_localizations") for c in changed):
        warnings.append("An .arb file changed but the generated app_localizations files "
                        "didn't. Run flutter gen-l10n.")
    return warnings


def session_summary(ctx: Context) -> str:
    branch = ctx.git("rev-parse", "--abbrev-ref", "HEAD") or "?"
    dirty = len(ctx.dirty_paths())
    lines = [f"Absorb Plus repo: branch {branch}, {dirty} uncommitted file(s)."]
    fork_ref = f"fork/{branch}"
    if ctx.git("rev-parse", "--verify", "--quiet", fork_ref):
        counts = ctx.git("rev-list", "--left-right", "--count", f"HEAD...{fork_ref}").split()
        if len(counts) == 2:
            lines.append(f"vs {fork_ref}: {counts[0]} ahead, {counts[1]} behind (unpushed = ahead).")
    if ctx.git("rev-parse", "--verify", "--quiet", "origin/main"):
        lag = ctx.git("rev-list", "--count", "HEAD..origin/main")
        lines.append(f"Upstream origin/main has {lag or '?'} commit(s) not merged here "
                     "(as of the last fetch).")
    lines.append(f"Version {ctx.pubspec_version()}. Rules: CLAUDE.md; tooling: tool/dev.ps1, "
                 ".claude/skills.")
    if _release_build_running(ctx):
        lines.append("The owner's Release absorb.exe is RUNNING: don't overwrite "
                     "build\\windows\\x64\\runner\\Release; verify builds in a separate worktree.")
    return "\n".join(lines)


def _release_build_running(ctx: Context) -> bool:
    exe = ctx.root / "build" / "windows" / "x64" / "runner" / "Release" / "absorb.exe"
    if os.name != "nt" or not exe.exists():
        return False
    try:
        r = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "(Get-Process absorb -ErrorAction SilentlyContinue).Path"],
            capture_output=True, text=True, timeout=8)
        return any(Path(l.strip()) == exe for l in r.stdout.splitlines() if l.strip())
    except Exception:
        return False


# --------------------------------------------------------------------------
# I/O
# --------------------------------------------------------------------------

def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj))


def _permission(event: str, d: Decision) -> None:
    if d.verdict == ALLOW:
        return  # say nothing: normal permission rules apply
    _emit({"hookSpecificOutput": {"hookEventName": event,
                                  "permissionDecision": d.verdict,
                                  "permissionDecisionReason": d.reason}})


def main(argv: list[str]) -> int:
    sub = argv[1] if len(argv) > 1 else ""
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        data = {}
    ctx = Context(data.get("cwd") or os.getcwd())
    tool_input = data.get("tool_input") or {}
    try:
        if sub == "pre-shell":
            _permission("PreToolUse", decide_shell(tool_input.get("command", ""), ctx))
        elif sub == "pre-edit":
            fp = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
            _permission("PreToolUse", decide_edit(fp, ctx))
        elif sub == "post-edit":
            fp = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
            notes = post_edit_messages(fp, ctx, data.get("session_id", ""))
            if notes:
                _emit({"hookSpecificOutput": {"hookEventName": "PostToolUse",
                                              "additionalContext": "\n".join(notes)}})
        elif sub == "stop":
            warnings = stop_warnings(ctx)
            if warnings:
                _emit({"systemMessage": "\n".join(warnings)})
        elif sub == "session-start":
            _emit({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                          "additionalContext": session_summary(ctx)}})
        else:
            print(f"unknown subcommand {sub!r}", file=sys.stderr)
    except Exception as e:  # noqa: BLE001 - a hook bug must never block work
        print(f"claude_hooks.py {sub} error: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
