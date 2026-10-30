"""Tests for tool/claude_hooks.py. Run: python -m unittest discover tool/tests"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import claude_hooks as h  # noqa: E402


class FakeContext(h.Context):
    def __init__(self, root, *, dirty=(), upstream_branch="fork/claude/x",
                 upstream_files=(), version="1.12.1+305", removed=(), links=None):
        self.cwd = Path(root)
        self.root = Path(root)
        self._dirty = list(dirty)
        self._upstream_branch = upstream_branch
        self._upstream_files = set(upstream_files)
        self._version = version
        self._removed = list(removed)
        self._links = links or {}

    def dirty_paths(self):
        return self._dirty

    def upstream_of_current_branch(self):
        return self._upstream_branch

    def exists_upstream(self, rel):
        return rel in self._upstream_files

    def pubspec_version(self):
        return self._version

    def removed_paths(self):
        return self._removed

    def link_inside(self, path, budget_s=4.0):
        return self._links.get(Path(path).name, "")


class ShellTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / ".git").mkdir()
        (self.root / "lib").mkdir()
        (self.root / "lib" / "main.dart").write_text("void main() {}")
        (self.root / "lib" / "new_file.dart").write_text("")
        (self.root / "build").mkdir()
        (self.root / "scratch").mkdir()
        self.ctx = FakeContext(self.root, upstream_files={"lib/main.dart"},
                               links={"scratch": str(self.root / "scratch" / ".plugin_symlinks")})

    def tearDown(self):
        self.tmp.cleanup()

    def v(self, cmd, ctx=None):
        return h.decide_shell(cmd, ctx or self.ctx).verdict

    def test_push_to_origin_denied(self):
        self.assertEqual(self.v("git push origin main"), h.DENY)
        self.assertEqual(self.v("cd x && git push origin --dry-run"), h.DENY)
        self.assertEqual(self.v("git push https://github.com/pounat/absorb.git x"), h.DENY)

    def test_bare_push_tracking_origin_denied(self):
        ctx = FakeContext(self.root, upstream_branch="origin/main")
        self.assertEqual(self.v("git push", ctx), h.DENY)
        self.assertEqual(self.v("git push"), h.ALLOW)

    def test_push_to_fork_allowed(self):
        self.assertEqual(self.v("git push fork claude/upstream-sync"), h.ALLOW)

    def test_force_push_fork_main_asks(self):
        self.assertEqual(self.v("git push --force fork HEAD:main"), h.ASK)
        self.assertEqual(self.v("git push fork +main"), h.ASK)

    def test_release_tags(self):
        self.assertEqual(self.v("git push fork v1.12.1-305"), h.ALLOW)          # odd patch beta
        self.assertEqual(self.v("git push fork v1.12.1-304"), h.DENY)           # mismatch
        stable = FakeContext(self.root, version="1.12.2+400")
        self.assertEqual(self.v("git push fork v1.12.2-400", stable), h.ASK)  # stable
        self.assertEqual(self.v("git push fork --tags"), h.ASK)
        self.assertEqual(self.v("git push fork :refs/tags/v1.0.0-1"), h.ASK)

    def test_reset_hard_denied(self):
        self.assertEqual(self.v("git reset --hard HEAD~1"), h.DENY)
        self.assertEqual(self.v("git reset --soft HEAD~1"), h.ALLOW)

    def test_discarding_changes(self):
        dirty = FakeContext(self.root, dirty=["lib/main.dart"])
        self.assertEqual(self.v("git checkout -- lib/", dirty), h.ASK)
        self.assertEqual(self.v("git restore lib/main.dart", dirty), h.ASK)
        self.assertEqual(self.v("git checkout -- lib/", self.ctx), h.ALLOW)  # clean tree
        self.assertEqual(self.v("git switch main", dirty), h.ALLOW)
        self.assertEqual(self.v("git checkout feature-branch", dirty), h.ALLOW)
        self.assertEqual(self.v("git restore --staged lib/main.dart", dirty), h.ALLOW)
        generated = ("git restore --source=HEAD -- linux/flutter/generated_plugins.cmake "
                     "windows/flutter/generated_plugins.cmake")
        self.assertEqual(self.v(generated, dirty), h.ALLOW)
        self.assertEqual(self.v("git clean -fd", dirty), h.ASK)

    def test_recursive_delete_through_links_denied(self):
        self.assertEqual(self.v("rm -rf scratch"), h.DENY)
        self.assertEqual(self.v("Remove-Item -LiteralPath scratch -Recurse -Force"), h.DENY)
        self.assertEqual(self.v("robocopy empty scratch /MIR"), h.DENY)
        self.assertEqual(self.v('cmd /c "rd /s /q scratch"'), h.DENY)
        self.assertEqual(self.v("cmd /c rd /s /q scratch"), h.DENY)
        self.assertEqual(self.v('powershell -NoProfile -Command "Remove-Item scratch -Recurse"'),
                         h.DENY)
        self.assertEqual(self.v('bash -c "git push origin main"'), h.DENY)

    def test_recursive_delete_plain_dir_allowed(self):
        self.assertEqual(self.v("rm -rf build"), h.ALLOW)
        self.assertEqual(self.v("rm -rf does-not-exist"), h.ALLOW)
        self.assertEqual(self.v("rm file.txt"), h.ALLOW)

    def test_recursive_delete_repo_root_denied(self):
        self.assertEqual(self.v(f'rm -rf "{self.root}"'), h.DENY)

    def test_recursive_delete_unresolvable_asks(self):
        self.assertEqual(self.v('Remove-Item -Recurse -Force $dir'), h.ASK)
        self.assertEqual(self.v('rm -rf "$TARGET"'), h.ASK)

    def test_dart_format(self):
        self.assertEqual(self.v("dart format lib/main.dart"), h.DENY)       # upstream file
        self.assertEqual(self.v("dart format lib/new_file.dart"), h.ALLOW)  # fork file
        self.assertEqual(self.v("dart format lib"), h.DENY)                 # directory
        self.assertEqual(self.v("dart format ."), h.DENY)
        self.assertEqual(self.v("C:/flutter/bin/dart.bat format --output=none lib/main.dart"),
                         h.DENY)

    def test_gh_release_guards(self):
        self.assertEqual(self.v("gh release delete v1.0.0 --yes"), h.ASK)
        self.assertEqual(self.v("gh release edit v1 --latest"), h.ASK)
        self.assertEqual(self.v("gh release view v1"), h.ALLOW)
        self.assertEqual(self.v("gh repo delete atewertfd/absorb-platform"), h.DENY)
        self.assertEqual(self.v("git tag -d v1.0.0"), h.ASK)

    def test_harmless_commands(self):
        for cmd in ("git status", "git log --oneline -5", "flutter test", "ls -la",
                    "python tool/align_with_upstream.py lib/main.dart"):
            self.assertEqual(self.v(cmd), h.ALLOW, cmd)


@unittest.skipUnless(os.name == "nt", "directory junctions are Windows-only")
class RealJunctionTests(unittest.TestCase):
    """The real link scan must spot a junction like Flutter's .plugin_symlinks."""

    def test_junction_detected_and_target_untouched(self):
        import subprocess
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "pub-cache-package"
            target.mkdir()
            (target / "pubspec.yaml").write_text("name: x")
            tree = Path(tmp) / "worktree" / "windows" / "flutter" / "ephemeral"
            tree.mkdir(parents=True)
            subprocess.run(["cmd", "/c", "mklink", "/J", str(tree / "pkg"), str(target)],
                           check=True, capture_output=True)
            ctx = h.Context(tmp)
            self.assertTrue(ctx.link_inside(Path(tmp) / "worktree"))
            d = h.decide_shell(f'rm -rf "{Path(tmp) / "worktree"}"', ctx)
            self.assertEqual(d.verdict, h.DENY)
            self.assertTrue((target / "pubspec.yaml").exists())
            subprocess.run(["cmd", "/c", "rmdir", str(tree / "pkg")], check=True)


class EditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.ctx = FakeContext(self.root, removed=["ios/", "lib/services/carplay_image_url.dart"],
                               upstream_files={"lib/main.dart"})

    def tearDown(self):
        self.tmp.cleanup()

    def v(self, rel):
        return h.decide_edit(str(self.root / rel), self.ctx).verdict

    def test_generated_files_denied(self):
        self.assertEqual(self.v("lib/l10n/app_localizations_en.dart"), h.DENY)
        self.assertEqual(self.v("lib/l10n/app_localizations.dart"), h.DENY)
        self.assertEqual(self.v("windows/flutter/generated_plugins.cmake"), h.DENY)
        self.assertEqual(self.v("lib/l10n/app_en.arb"), h.ALLOW)

    def test_removed_paths_denied(self):
        self.assertEqual(self.v("ios/Runner/AppDelegate.swift"), h.DENY)
        self.assertEqual(self.v("lib/services/carplay_image_url.dart"), h.DENY)
        self.assertEqual(self.v("lib/services/iosish.dart"), h.ALLOW)

    def test_post_edit_runs_gen_l10n_for_arb(self):
        calls = []
        notes = h.post_edit_messages(str(self.root / "lib/l10n/app_en.arb"), self.ctx, "s1",
                                     run_gen_l10n=lambda ctx: (calls.append(1) or (True, "")))
        self.assertEqual(calls, [1])
        self.assertIn("Regenerated", notes[0])

    def test_post_edit_upstream_note_once_per_session(self):
        sid = f"test-{os.getpid()}-{id(self)}"
        first = h.post_edit_messages(str(self.root / "lib/main.dart"), self.ctx, sid)
        second = h.post_edit_messages(str(self.root / "lib/main.dart"), self.ctx, sid)
        self.assertEqual(len(first), 1)
        self.assertEqual(second, [])


if __name__ == "__main__":
    unittest.main()
