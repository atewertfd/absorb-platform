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

# Multi-character operators are single tokens, so a splice can never split
# one (e.g. "=>" into "= >") without the identity check noticing.
OPERATORS = (
    r"\.\.\.\?|\.\.\.|\?\?=|>>>=|>>>|<<=|>>=|\?\.|\?\?|=>|==|!=|<=|>=|&&"
    r"|\|\||\+\+|--|<<|>>|[-+*/%&|^~]=|\.\.|~/"
)
# Identifiers, numbers, single-line string literals, line comments,
# operators and any other non-space character except commas (commas move
# when code is reformatted, so alignment ignores them).
TOKEN = re.compile(
    r"[A-Za-z_$][\w$]*|\d[\w.]*|'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\""
    r"|//[^\n]*|" + OPERATORS + r"|[^\s\w,]"
)
STRICT = re.compile(
    r"[A-Za-z_$][\w$]*|\d[\w.]*|'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\""
    r"|//[^\n]*|" + OPERATORS + r"|[^\s\w]"
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
    def gap_mine(j):
        """The fork's whitespace/comma gap in front of its token j."""
        start = mine[j - 1][2] if j > 0 else 0
        end = mine[j][1] if j < len(mine) else len(ours)
        return ours[start:end]

    text = ""            # output built so far
    seams = []           # output offsets where fork text meets upstream text
    pending = None       # fork gap the next upstream segment should start with

    def bridge(segment, want, fork_text):
        """Append `segment` so the gap in front of it matches the fork's gap
        `want`: same commas, and the fork's own spacing in front of fork text.
        Upstream text keeps upstream's spacing unless that would join lines
        the fork keeps apart."""
        nonlocal text
        ws = " \t\r\n"
        body = text.rstrip(ws)
        have_ws = text[len(body):]
        rest = segment.lstrip(ws)
        have_ws += segment[:len(segment) - len(rest)]
        # Commas: exactly as many as the fork has here (zero or one).
        want_comma = "," in want
        while body.endswith(",") and (not want_comma or rest.startswith(",")):
            body = body[:-1].rstrip(ws)
        if rest.startswith(","):
            if want_comma and not body.endswith(","):
                body += ","
            rest = rest[1:]
            have_ws = rest[:len(rest) - len(rest.lstrip(ws))] or have_ws
            rest = rest.lstrip(ws)
        if want_comma and not body.endswith(","):
            body += ","
        want_ws = want.split(",")[-1]
        if fork_text and want_ws:
            gap = want_ws
        elif not have_ws.strip(" \t") and "\n" in want_ws:
            gap = want_ws                 # keep separate lines separate
        elif not have_ws and want_ws:
            gap = want_ws
        else:
            gap = have_ws if have_ws or want_ws else ""
        text = body + gap + rest

    pos = 0
    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "equal":
            continue
        # Upstream text up to the change keeps upstream's formatting.
        anchor = up[i1][1] if i1 < len(up) else len(upstream)
        segment = upstream[pos:anchor]
        if pending is not None:
            bridge(segment, pending, fork_text=False)
            pending = None
        else:
            text += segment
        seams.append(len(text))
        if j1 < j2:
            chunk = ours[mine[j1][1]:mine[j2 - 1][2]]
            bridge(chunk, gap_mine(j1), fork_text=True)
        # Whatever upstream text comes next must meet the fork's gap after
        # this change (for a pure insertion that is the gap before up[i1]).
        pending = gap_mine(j2)
        seams.append(len(text))
        pos = up[i2 - 1][2] if i2 > i1 else anchor
    tail = upstream[pos:]
    if pending is not None:
        bridge(tail, pending, fork_text=False)
    else:
        text += tail
    return tidy_seams(text, seams)


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
    # Only touch code: hide string literals and a trailing comment first.
    hidden = []

    def hide(match):
        hidden.append(match.group())
        return f"\x00{len(hidden) - 1}\x00"

    body = re.sub(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"|//.*$", hide, body)
    body = tidy_code(body).rstrip()
    return indent + re.sub(r"\x00(\d+)\x00", lambda m: hidden[int(m.group(1))], body)


def tidy_code(body):
    body = re.sub(r"(?<=\S)  +", " ", body)           # doubled spaces
    body = re.sub(r"(?<=\S) +([;,)\].])", r"\1", body)  # space before ; , ) ] .
    body = re.sub(r"\( +", "(", body)                  # space after (
    body = re.sub(r" *(\|\||&&|\?\?|=>) *", r" \1 ", body)  # binary operators
    body = re.sub(r"(=>) $", r"\1", body)
    body = re.sub(
        r"\b([A-Za-z_]\w*) +\(",
        lambda m: m.group(0) if m.group(1) in KEEP_SPACE_BEFORE_PAREN
        else m.group(1) + "(", body)
    return body


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
    parser.add_argument("--explain", action="store_true",
                        help="show where a refused file would differ")
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
            if args.explain:
                a, b = strict_tokens(ours), strict_tokens(result)
                sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
                for op, i1, i2, j1, j2 in sm.get_opcodes()[:200]:
                    if op != "equal":
                        print(f"      fork:   {' '.join(a[max(0, i1 - 6):i2 + 3])}")
                        print(f"      result: {' '.join(b[max(0, j1 - 6):j2 + 3])}")
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
