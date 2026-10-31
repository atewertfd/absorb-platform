"""Tests for tool/fork_lints.py (no analyzer run; that's dev.ps1 check / CI)."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fork_lints as fl  # noqa: E402

LINT = "use_build_context_synchronously"


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True,
                          check=True).stdout


def write(root, rel, text):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="")
    return p


class MachineOutputTests(unittest.TestCase):
    def test_split_undoes_escapes(self):
        line = r"INFO|LINT|x|C:\\a\\b.dart|3|4|5|uses a \| pipe"
        self.assertEqual(fl.split_machine_line(line),
                         ["INFO", "LINT", "x", r"C:\a\b.dart", "3", "4", "5", "uses a | pipe"])

    def test_parse_maps_mirror_paths_and_skips_noise(self):
        mirror = Path(tempfile.gettempdir()) / "fl_mirror"
        esc = str(mirror.resolve()).replace("\\", "\\\\")
        sep = "\\\\" if "\\" in str(mirror.resolve()) else "/"
        out = "\n".join([
            "Analyzing fl_mirror...",
            f"INFO|LINT|USE_BUILD_CONTEXT_SYNCHRONOUSLY|{esc}{sep}lib{sep}a.dart|12|5|7|Don't.",
            f"WARNING|STATIC_WARNING|PATH_DOES_NOT_EXIST|{esc}{sep}pubspec.yaml|1|1|1|x",
            "",
        ])
        diags = fl.parse_machine(out, mirror)
        self.assertEqual(len(diags), 2)
        self.assertEqual(diags[0], {"severity": "INFO", "code": LINT, "path": "lib/a.dart",
                                    "line": 12, "col": 5, "message": "Don't."})
        self.assertEqual(diags[1]["path"], "pubspec.yaml")

    def test_classify_splits_fork_and_upstream_and_ignores_other_codes(self):
        diags = [
            {"code": LINT, "path": "lib/fork_only.dart"},
            {"code": LINT, "path": "lib/upstream.dart"},
            {"code": "unused_import", "path": "lib/fork_only.dart"},
        ]
        fork, up = fl.classify(diags, {"lib/upstream.dart"})
        self.assertEqual([d["path"] for d in fork], ["lib/fork_only.dart"])
        self.assertEqual([d["path"] for d in up], ["lib/upstream.dart"])


class MirrorTests(unittest.TestCase):
    def test_enable_lints_flips_only_the_listed_rule(self):
        text = ("linter:\n  rules:\n    use_build_context_synchronously: false\n"
                "    prefer_const_constructors: false\n")
        out = fl.enable_lints(text)
        self.assertIn("use_build_context_synchronously: true", out)
        self.assertIn("prefer_const_constructors: false", out)
        self.assertEqual(fl.enable_lints("include: x\n"), "include: x\n")

    def test_package_config_points_back_at_the_checkout(self):
        real = Path(tempfile.gettempdir()) / "proj" / ".dart_tool"
        cfg = {"configVersion": 2, "packages": [
            {"name": "app", "rootUri": "../", "packageUri": "lib/"},
            {"name": "vendored", "rootUri": "../packages/vendored", "packageUri": "lib/"},
            {"name": "pubbed", "rootUri": "file:///C:/cache/pubbed-1.0", "packageUri": "lib/"},
        ]}
        out = fl.mirror_package_config(cfg, real, "app")
        uris = {p["name"]: p["rootUri"] for p in out["packages"]}
        self.assertEqual(uris["app"], "../")
        self.assertEqual(uris["vendored"],
                         (real.parent / "packages" / "vendored").resolve().as_uri() + "/")
        self.assertEqual(uris["pubbed"], "file:///C:/cache/pubbed-1.0")
        self.assertEqual(cfg["packages"][1]["rootUri"], "../packages/vendored")  # not mutated

    def test_build_mirror_copies_dart_files_and_drops_stale_ones(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, dest = Path(tmp) / "repo", Path(tmp) / "repo" / "build" / "fork_lints"
            write(root, "pubspec.yaml", "name: app\n")
            write(root, "analysis_options.yaml",
                  "linter:\n  rules:\n    use_build_context_synchronously: false\n")
            write(root, ".dart_tool/package_config.json", json.dumps({"configVersion": 2,
                  "packages": [{"name": "app", "rootUri": "../", "packageUri": "lib/"}]}))
            write(root, "lib/a.dart", "void a() {}\n")
            write(root, "lib/assets/readme.txt", "not dart\n")
            write(root, "test/a_test.dart", "void main() {}\n")
            write(dest, "lib/gone.dart", "stale\n")

            fl.build_mirror(root, dest)

            self.assertEqual((dest / "lib/a.dart").read_text(encoding="utf-8"), "void a() {}\n")
            self.assertTrue((dest / "test/a_test.dart").is_file())
            self.assertFalse((dest / "lib/gone.dart").exists())
            self.assertFalse((dest / "lib/assets").exists())
            self.assertIn("use_build_context_synchronously: true",
                          (dest / "analysis_options.yaml").read_text(encoding="utf-8"))
            cfg = json.loads((dest / ".dart_tool/package_config.json").read_text(encoding="utf-8"))
            self.assertEqual(cfg["packages"][0]["rootUri"], "../")

    def test_build_mirror_needs_pub_get(self):
        with tempfile.TemporaryDirectory() as tmp:
            write(tmp, "pubspec.yaml", "name: app\n")
            with self.assertRaises(SystemExit):
                fl.build_mirror(Path(tmp), Path(tmp) / "m")


class UpstreamTests(unittest.TestCase):
    def test_upstream_remote_is_found_by_url(self):
        remotes = ("fork\thttps://github.com/atewertfd/absorb-plus.git (fetch)\n"
                   "origin\thttps://github.com/pounat/absorb.git (fetch)\n")
        self.assertEqual(fl.upstream_remote(remotes), "origin")
        self.assertIsNone(fl.upstream_remote(
            "origin\thttps://github.com/atewertfd/absorb-plus.git (fetch)\n"))
        self.assertIsNone(fl.upstream_remote(
            "x\thttps://github.com/pounat/absorb-extras.git (fetch)\n"))

    def test_upstream_files_come_from_the_upstream_remote_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            git(tmp, "init", "-q")
            git(tmp, "config", "user.email", "t@example.com")
            git(tmp, "config", "user.name", "t")
            write(tmp, "lib/upstream.dart", "x\n")
            git(tmp, "add", ".")
            git(tmp, "commit", "-qm", "upstream")
            git(tmp, "remote", "add", "up", "https://github.com/pounat/absorb.git")
            git(tmp, "update-ref", "refs/remotes/up/main", "HEAD")
            write(tmp, "lib/fork_only.dart", "y\n")
            git(tmp, "add", ".")
            git(tmp, "commit", "-qm", "fork")

            ref = fl.resolve_upstream_ref(cwd=tmp)
            self.assertEqual(ref, "up/main")
            self.assertEqual(fl.upstream_files(ref, cwd=tmp), {"lib/upstream.dart"})
            self.assertEqual(fl.resolve_upstream_ref("abc", cwd=tmp), "abc")


if __name__ == "__main__":
    unittest.main()
