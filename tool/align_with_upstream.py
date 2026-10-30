"""Shrink the fork's diff against upstream by undoing formatting-only churn.

For each file, the fork's version is compared with upstream's token by token
(whitespace and comma placement ignored). The fork's real changes are then
re-applied on top of upstream's text, so upstream's line breaks and
indentation come back and only the fork's actual edits remain in the diff.

A file is rewritten only when the result is token-for-token identical to the
fork's current code (commas included, trailing commas before a closing
bracket ignored). Otherwise it is left untouched and reported.

Usage (from the repo root):
  python tool/align_with_upstream.py [--ref origin/main] [--apply] FILE...

Without --apply it only reports what would change.
"""

import argparse
import difflib
import re
import subprocess
import sys

# Identifiers, numbers, single-line string literals, line comments and any
# other non-space character except commas (commas move when code is
# reformatted, so alignment ignores them).
TOKEN = re.compile(
    r"[A-Za-z_$][\w$]*|\d[\w.]*|'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\""
    r"|//[^\n]*|[^\s\w,]"
)
STRICT = re.compile(
    r"[A-Za-z_$][\w$]*|\d[\w.]*|'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\""
    r"|//[^\n]*|[^\s\w]"
)


def spans(text):
    return [(m.group(), m.start(), m.end()) for m in TOKEN.finditer(text)]


def strict_tokens(text):
    out = [m.group() for m in STRICT.finditer(text)]
    # Trailing commas before a closing bracket are formatting.
    return [t for i, t in enumerate(out)
            if not (t == "," and i + 1 < len(out) and out[i + 1] in ")]}")]


def realign(upstream, ours):
    up = spans(upstream)
    mine = spans(ours)
    matcher = difflib.SequenceMatcher(
        None, [t for t, _, _ in up], [t for t, _, _ in mine], autojunk=False)
    out = []
    seams = []  # output offsets where fork text meets upstream text
    pos = 0
    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "equal":
            continue
        # Upstream text before the change keeps upstream's formatting.
        anchor = up[i1][1] if i1 < len(up) else len(upstream)
        out.append(upstream[pos:anchor])
        seams.append(sum(len(s) for s in out))
        if j1 < j2:
            # Carry the fork's own separator in front of the change when it
            # holds a comma upstream lacks (e.g. a new trailing argument).
            lead_mine = ours[mine[j1 - 1][2]:mine[j1][1]] if j1 > 0 else ""
            lead_up = upstream[up[i1 - 1][2]:anchor] if i1 > 0 else ""
            if "," in lead_mine and "," not in lead_up:
                out.append(", ")
            chunk_end = mine[j2 - 1][2]
            out.append(ours[mine[j1][1]:chunk_end])
            if i1 == i2:
                # Pure insertion: keep the fork's separator after it.
                tail = ours[chunk_end:mine[j2][1]] if j2 < len(mine) else ""
                out.append(tail if tail else " ")
        seams.append(sum(len(s) for s in out))
        pos = up[i2 - 1][2] if i2 > i1 else anchor
        if i2 > i1 and j1 == j2:
            # Pure deletion: drop a comma that only separated deleted code.
            nxt = upstream[pos:pos + 2]
            if nxt.startswith(","):
                pos += 1
    out.append(upstream[pos:])
    return tidy_seams("".join(out), seams)


# Words that keep a space before "(" (Dart keywords and common forms).
KEEP_SPACE_BEFORE_PAREN = {
    "if", "for", "while", "switch", "catch", "return", "await", "in", "is",
    "as", "else", "case", "yield", "throw", "async", "sync", "on", "when",
    "final", "var", "const", "new", "and", "or", "not", "with",
}


def tidy_line(line):
    """Fix spacing artefacts on a line that contains a splice seam."""
    stripped = line.rstrip()
    body = stripped.lstrip()
    indent = stripped[:len(stripped) - len(body)]
    if not body or body.startswith("//"):
        return stripped
    body = re.sub(r"(?<=\S)  +", " ", body)           # doubled spaces
    body = re.sub(r"(?<=\S) +([;,)\].])", r"\1", body)  # space before ; , ) ] .
    body = re.sub(r"\( +", "(", body)                  # space after (
    body = re.sub(r" *(\|\||&&|\?\?|=>) *", r" \1 ", body)  # binary operators
    body = re.sub(r"(=>) $", r"\1", body)
    body = re.sub(
        r"\b([A-Za-z_]\w*) +\(",
        lambda m: m.group(0) if m.group(1) in KEEP_SPACE_BEFORE_PAREN
        else m.group(1) + "(", body)
    return indent + body


def tidy_seams(text, seams):
    lines = text.split("\n")
    starts = []
    offset = 0
    for line in lines:
        starts.append(offset)
        offset += len(line) + 1
    touched = set()
    import bisect
    for seam in seams:
        touched.add(max(0, bisect.bisect_right(starts, seam) - 1))
    out = []
    for index, line in enumerate(lines):
        if index in touched:
            fixed = tidy_line(line)
            # A seam that left only indentation behind (deleted wrapper).
            if not fixed.strip() and line.strip() == "" and line != "":
                continue
            out.append(fixed)
        else:
            out.append(line)
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", default="origin/main")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    failed = 0
    for path in args.files:
        shown = subprocess.run(["git", "show", f"{args.ref}:{path}"],
                               capture_output=True, text=True, encoding="utf-8")
        if shown.returncode != 0:
            print(f"skip  {path}: not in {args.ref}")
            continue
        raw = open(path, encoding="utf-8", newline="").read()
        newline = "\r\n" if "\r\n" in raw else "\n"
        ours = raw.replace("\r\n", "\n")
        upstream = shown.stdout.replace("\r\n", "\n")
        if "'''" in ours or '"""' in ours:
            print(f"skip  {path}: triple-quoted strings are not tokenized safely")
            continue
        result = realign(upstream, ours)
        if strict_tokens(result) != strict_tokens(ours):
            failed += 1
            print(f"FAIL  {path}: realigned code would differ; left unchanged")
            continue
        before = sum(1 for _ in difflib.unified_diff(
            upstream.splitlines(), ours.splitlines(), lineterm="", n=0))
        after = sum(1 for _ in difflib.unified_diff(
            upstream.splitlines(), result.splitlines(), lineterm="", n=0))
        print(f"{'wrote' if args.apply else 'ok   '} {path}: diff lines {before} -> {after}")
        if args.apply and result != ours:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(result.replace("\n", newline))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
