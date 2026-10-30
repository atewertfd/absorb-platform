"""Tests for tool/upstream_merge.py and tool/check_fork_removed.py."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_fork_removed as cfr  # noqa: E402
import upstream_merge as um  # noqa: E402


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True,
                          check=True).stdout


def write(root, rel, text):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="")


class ArbMergeTests(unittest.TestCase):
    def test_appends_fork_keys_to_upstream_text(self):
        base = '{\n  "a": "A"\n}\n'
        theirs = '{\n  "a": "A",\n  "up": "Up"\n}\n'
        ours = '{\n  "a": "A",\n  "fork": "Fork",\n  "@fork": {}\n}\n'
        merged, review = um.merge_arb(theirs, ours, base)
        data = json.loads(merged)
        self.assertEqual(list(data), ["a", "up", "fork", "@fork"])
        self.assertTrue(merged.startswith('{\n  "a": "A",\n  "up": "Up",'))
        self.assertEqual(review, [])

    def test_reports_fork_changed_value(self):
        base = '{\n  "a": "A"\n}\n'
        merged, review = um.merge_arb('{\n  "a": "A"\n}\n', '{\n  "a": "Changed"\n}\n', base)
        self.assertEqual(review, ["a"])
        self.assertEqual(json.loads(merged)["a"], "A")

    def test_key_deleted_upstream_stays_deleted(self):
        base = '{\n  "a": "A",\n  "gone": "x"\n}\n'
        merged, _ = um.merge_arb('{\n  "a": "A"\n}\n', base, base)
        self.assertNotIn("gone", json.loads(merged))


class CheckRemovedTests(unittest.TestCase):
    def test_violations(self):
        tracked = ["ios/Runner/x.swift", "lib/main.dart", "iosish/keep.txt"]
        found = cfr.violations(tracked, ["ios/", "codemagic.yaml"], "name: x\n")
        self.assertEqual(len(found), 1)
        self.assertIn("ios/", found[0])
        found = cfr.violations([], ["ios/"], "dependencies:\n  flutter_carplay:\n    path: x\n")
        self.assertIn("flutter_carplay", found[0])


class MergeIntegrationTests(unittest.TestCase):
    """Simulated upstream that edits removed Apple code and adds strings."""

    def test_merge_drops_removed_paths_and_unions_arb(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            git(root, "init", "-q", "-b", "main")
            git(root, "config", "user.email", "t@example.com")
            git(root, "config", "user.name", "t")
            write(root, "ios/Runner/AppDelegate.swift", "base\n")
            write(root, "lib/main.dart", "void main() {}\n")
            write(root, "lib/services/carplay_service.dart", "class CarPlay { real() {} }\n")
            write(root, "lib/l10n/app_en.arb", '{\n  "hello": "Hello"\n}\n')
            write(root, "pubspec.yaml", "name: x\n")
            git(root, "add", "-A")
            git(root, "commit", "-q", "-m", "base")
            git(root, "branch", "upstream")

            # Fork: remove Apple, stub CarPlay, add a string.
            write(root, "tool/fork-removed-paths.txt", "ios/   # apple\n")
            write(root, "tool/fork-overrides.txt", "lib/services/carplay_service.dart\n")
            git(root, "rm", "-r", "-q", "ios")
            write(root, "lib/services/carplay_service.dart", "class CarPlay { stub() {} }\n")
            write(root, "lib/l10n/app_en.arb", '{\n  "hello": "Hello",\n  "forkKey": "Fork"\n}\n')
            git(root, "add", "-A")
            git(root, "commit", "-q", "-m", "fork")

            # Upstream: edits Apple code and CarPlay, adds its own string.
            git(root, "checkout", "-q", "upstream")
            write(root, "ios/Runner/AppDelegate.swift", "upstream change\n")
            write(root, "ios/Runner/New.swift", "new apple file\n")
            write(root, "lib/services/carplay_service.dart", "class CarPlay { real2() {} }\n")
            write(root, "lib/l10n/app_en.arb", '{\n  "hello": "Hello",\n  "upKey": "Up"\n}\n')
            write(root, "lib/main.dart", "void main() { print(1); }\n")
            git(root, "add", "-A")
            git(root, "commit", "-q", "-m", "upstream")
            git(root, "checkout", "-q", "main")

            code = um.run("upstream", fetch=False, gen=False, cwd=root)

            self.assertEqual(code, 0)
            self.assertEqual(um.unmerged(root), [])
            tracked = git(root, "ls-files").split()
            self.assertFalse([p for p in tracked if p.startswith("ios/")])
            self.assertIn("stub", (root / "lib/services/carplay_service.dart").read_text())
            arb = json.loads((root / "lib/l10n/app_en.arb").read_text())
            self.assertEqual(set(arb), {"hello", "upKey", "forkKey"})
            self.assertIn("print(1)", (root / "lib/main.dart").read_text())
            git(root, "merge", "--abort")


if __name__ == "__main__":
    unittest.main()
