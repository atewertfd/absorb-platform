"""Extra lints that only fork-added files must pass.

`use_build_context_synchronously` stays off in analysis_options.yaml, because
upstream code has many hits we don't want as noise (or as merge-conflict
fodder). This script turns it on for one analyzer run and fails only for hits
in files the fork added, i.e. paths that don't exist in upstream's tree.

How it works, in one extra analyzer run:
  1. Mirror lib/ and test/ into build/fork_lints/ (plain file copies, no
     links), with a copy of analysis_options.yaml that enables the lint and a
     package_config.json whose relative paths point back at the real checkout.
  2. Run `dart analyze --format=machine` on the mirror.
  3. Compare each hit's path with upstream's file list (`git ls-tree` of
     origin/main locally; in CI, where origin is the fork, a tree-only shallow
     fetch of pounat/absorb).

Run from anywhere:  python tool/fork_lints.py   (dev.ps1 check and CI run it)
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIRROR = ROOT / "build" / "fork_lints"
UPSTREAM_URL = "https://github.com/pounat/absorb.git"
UPSTREAM_FETCH_REF = "refs/fork-lints/upstream"
LINTS = ("use_build_context_synchronously",)
MIRRORED_DIRS = ("lib", "test")


# ---------------------------------------------------------------- upstream


def git(*args, cwd=ROOT, check=True):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True,
                          check=check)


def upstream_remote(remotes_v: str) -> str | None:
    """Name of the remote that points at pounat/absorb, from `git remote -v`."""
    for line in remotes_v.splitlines():
        parts = line.split()
        if len(parts) >= 2 and re.search(r"[/:]pounat/absorb(\.git)?/?$", parts[1]):
            return parts[0]
    return None


def resolve_upstream_ref(explicit: str | None = None, cwd=ROOT) -> str:
    if explicit:
        return explicit
    remote = upstream_remote(git("remote", "-v", cwd=cwd).stdout)
    if remote and git("rev-parse", "--verify", "--quiet", f"{remote}/main",
                      cwd=cwd, check=False).returncode == 0:
        return f"{remote}/main"
    # CI: origin is the fork. Trees only, one commit deep: fast and small.
    git("fetch", "--quiet", "--depth=1", "--filter=blob:none", "--no-tags", UPSTREAM_URL,
        f"+main:{UPSTREAM_FETCH_REF}", cwd=cwd)
    return UPSTREAM_FETCH_REF


def upstream_files(ref: str, cwd=ROOT) -> set[str]:
    out = git("ls-tree", "-r", "--name-only", ref, cwd=cwd).stdout
    return {line for line in out.splitlines() if line}


# ------------------------------------------------------------------ mirror


def enable_lints(options_text: str, lints=LINTS) -> str:
    """Flip `lint: false` to true. A lint that isn't listed is already on
    (flutter_lints enables it)."""
    for lint in lints:
        options_text = re.sub(rf"(^\s*{lint}\s*:\s*)false\b", r"\1true", options_text,
                              flags=re.M)
    return options_text


def mirror_package_config(config: dict, real_dart_tool: Path, package_name: str) -> dict:
    """Point every relative rootUri at the real checkout, except the app itself
    (which must resolve to the mirror's lib/)."""
    out = dict(config)
    packages = []
    for pkg in config["packages"]:
        pkg = dict(pkg)
        uri = pkg["rootUri"]
        if pkg["name"] != package_name and not re.match(r"^[a-zA-Z][\w+.-]*:", uri):
            pkg["rootUri"] = (real_dart_tool / uri).resolve().as_uri() + "/"
        packages.append(pkg)
    out["packages"] = packages
    return out


def package_name(pubspec_text: str) -> str:
    m = re.search(r"^name:\s*([\w]+)", pubspec_text, re.M)
    if not m:
        raise SystemExit("fork_lints: no package name in pubspec.yaml")
    return m.group(1)


def _has_links(path: Path) -> bool:
    for dirpath, dirnames, filenames in os.walk(path):
        for name in dirnames + filenames:
            p = Path(dirpath) / name
            if p.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(p)):
                return True
    return False


def sync_tree(src: Path, dest: Path) -> None:
    """Make dest a plain-file copy of src's .dart files. Only touches files
    that changed, and only removes plain files it finds under dest."""
    wanted = {}
    for p in src.rglob("*.dart"):
        wanted[p.relative_to(src).as_posix()] = p
    if dest.exists():
        if _has_links(dest):
            raise SystemExit(f"fork_lints: {dest} contains a link; remove it by hand")
        for p in sorted(dest.rglob("*"), reverse=True):
            rel = p.relative_to(dest).as_posix()
            if p.is_file() and rel not in wanted:
                p.unlink()
            elif p.is_dir() and not any(p.iterdir()):
                p.rmdir()
    for rel, srcfile in wanted.items():
        target = dest / rel
        data = srcfile.read_bytes()
        if target.is_file() and target.read_bytes() == data:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def build_mirror(root: Path = ROOT, dest: Path = MIRROR) -> Path:
    real_config = root / ".dart_tool" / "package_config.json"
    if not real_config.is_file():
        raise SystemExit("fork_lints: run `flutter pub get` first")
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "pubspec.yaml").write_text(pubspec, encoding="utf-8")
    options = (root / "analysis_options.yaml").read_text(encoding="utf-8")
    (dest / "analysis_options.yaml").write_text(enable_lints(options), encoding="utf-8")
    config = mirror_package_config(json.loads(real_config.read_text(encoding="utf-8")),
                                   real_config.parent, package_name(pubspec))
    (dest / ".dart_tool").mkdir(exist_ok=True)
    (dest / ".dart_tool" / "package_config.json").write_text(
        json.dumps(config, indent=2), encoding="utf-8")
    for name in MIRRORED_DIRS:
        if (root / name).is_dir():
            sync_tree(root / name, dest / name)
    return dest


# ---------------------------------------------------------------- analysis


def split_machine_line(line: str) -> list[str]:
    """Split on unescaped | and undo the analyzer's backslash escapes
    (a path's \\ is written as \\\\, a | in a message as \\|)."""
    fields, cur, i = [], [], 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and i + 1 < len(line):
            cur.append(line[i + 1])
            i += 2
            continue
        if ch == "|":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    fields.append("".join(cur))
    return fields


def parse_machine(output: str, mirror: Path) -> list[dict]:
    """Parse `dart analyze --format=machine` lines:
    SEVERITY|TYPE|CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE"""
    base = str(mirror.resolve()).replace("\\", "/").rstrip("/") + "/"
    diags = []
    for line in output.splitlines():
        fields = split_machine_line(line.strip())
        if len(fields) < 8 or fields[0] not in ("INFO", "WARNING", "ERROR"):
            continue
        path = fields[3].replace("\\", "/")
        if path.lower().startswith(base.lower()):
            path = path[len(base):]
        diags.append({"severity": fields[0], "code": fields[2].lower(), "path": path,
                      "line": int(fields[4]), "col": int(fields[5]),
                      "message": "|".join(fields[7:])})
    return diags


def classify(diags: list[dict], upstream: set[str], lints=LINTS):
    fork, up = [], []
    for d in diags:
        if d["code"] in lints:
            (up if d["path"] in upstream else fork).append(d)
    return fork, up


def find_dart(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    flutter = os.environ.get("FLUTTER")
    if flutter:
        name = "dart.bat" if os.name == "nt" else "dart"
        sibling = Path(flutter).parent / name
        if sibling.is_file():
            return str(sibling)
    found = shutil.which("dart")
    if not found:
        raise SystemExit("fork_lints: dart not found (set FLUTTER or put dart on PATH)")
    return found


def run_analyzer(dart: str, mirror: Path) -> str:
    proc = subprocess.run([dart, "analyze", "--format=machine", "."], cwd=mirror,
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    output = proc.stdout + "\n" + proc.stderr
    # 0-3 mean "ran" (3 = errors, 2 = warnings, 1 = fatal infos); anything
    # else (usage error, crash) means no trustworthy result.
    if proc.returncode not in (0, 1, 2, 3):
        print(output[-2000:])
        raise SystemExit(f"FAIL: dart analyze exited {proc.returncode}")
    return output


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dart", help="dart executable (default: next to $FLUTTER, else PATH)")
    ap.add_argument("--upstream-ref", help="git ref with upstream's tree (default: auto)")
    ap.add_argument("--all", action="store_true", help="also list hits in upstream files")
    args = ap.parse_args(argv)

    start = time.monotonic()
    upstream = upstream_files(resolve_upstream_ref(args.upstream_ref))
    mirror = build_mirror()
    diags = parse_machine(run_analyzer(find_dart(args.dart), mirror), mirror)

    errors = [d for d in diags if d["severity"] == "ERROR"]
    if errors:
        # A broken mirror would hide hits; never pass silently.
        for d in errors[:20]:
            print(f"  {d['path']}:{d['line']}:{d['col']} {d['code']}: {d['message']}")
        print(f"FAIL: {len(errors)} analyzer errors in the lint mirror "
              f"(run `flutter analyze` first)")
        return 1
    fork, up = classify(diags, upstream)
    shown = [(d, "") for d in fork] + ([(d, " (upstream)") for d in up] if args.all else [])
    for d, tag in shown:
        print(f"  {d['path']}:{d['line']}:{d['col']} {d['code']}{tag}: {d['message']}")
    took = f"{time.monotonic() - start:.0f}s"
    if fork:
        print(f"FAIL: {len(fork)} hit(s) in fork files ({len(up)} in upstream files, "
              f"not enforced; {took})")
        return 1
    print(f"OK: 0 hits in fork files ({len(up)} in upstream files, not enforced; {took})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
