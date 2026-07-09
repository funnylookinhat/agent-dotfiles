import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

import gather_candidates as gc  # noqa: E402
import apply_candidates as ac  # noqa: E402


class TestCovers(unittest.TestCase):
    def test_exact_match(self):
        self.assertTrue(gc.covers("Bash(git rm *)", "Bash(git rm *)"))

    def test_colon_vs_space(self):
        self.assertTrue(gc.covers("Bash(git rm:*)", "Bash(git rm *)"))
        self.assertTrue(gc.covers("Bash(git rm:*)", "Bash(git rm lib/foo.ts)"))

    def test_glob_prefix(self):
        self.assertTrue(gc.covers("Read(//tmp/**)", "Read(//tmp/foo)"))

    def test_skill_wildcard(self):
        self.assertTrue(
            gc.covers("Skill(superpowers:*)", "Skill(superpowers:brainstorming)")
        )

    def test_mcp_server_level(self):
        self.assertTrue(gc.covers("mcp__honeycomb", "mcp__honeycomb__get_trace"))

    def test_bare_token_exact(self):
        self.assertTrue(gc.covers("WebFetch", "WebFetch"))
        self.assertFalse(gc.covers("WebFetch", "WebSearch"))

    def test_boundary_non_match(self):
        self.assertFalse(gc.covers("Bash(git r*)", "Bash(git rm *)"))

    def test_different_tools(self):
        self.assertFalse(gc.covers("Read(//tmp/**)", "Write(//tmp/foo)"))

    def test_not_covered(self):
        self.assertFalse(gc.covers("Bash(npm test *)", "Bash(npm list *)"))

    def test_is_covered_any(self):
        global_allow = ["Bash(git rm:*)", "mcp__honeycomb"]
        self.assertTrue(gc.is_covered("Bash(git rm foo)", global_allow))
        self.assertTrue(gc.is_covered("mcp__honeycomb__run_query", global_allow))
        self.assertFalse(gc.is_covered("Bash(npm list *)", global_allow))


class TestGather(unittest.TestCase):
    def _write(self, base, project, filename, perms):
        d = Path(base) / project / ".claude"
        d.mkdir(parents=True, exist_ok=True)
        (d / filename).write_text(json.dumps({"permissions": perms}))

    def test_provenance_and_dedup(self):
        with tempfile.TemporaryDirectory() as root, \
                tempfile.TemporaryDirectory() as gdir:
            self._write(root, "proj-a", "settings.local.json",
                        {"allow": ["Bash(npm list *)", "Bash(git rm *)"]})
            self._write(root, "proj-b", "settings.local.json",
                        {"allow": ["Bash(npm list *)"]})
            global_path = Path(gdir) / "settings.json"
            global_path.write_text(
                json.dumps({"permissions": {"allow": ["Bash(git rm:*)"]}})
            )
            result = gc.gather(Path(root), global_path)
            self.assertEqual(
                result["candidates"]["Bash(npm list *)"], ["proj-a", "proj-b"]
            )
            # git rm * is subsumed by global git rm:* -> excluded.
            self.assertNotIn("Bash(git rm *)", result["candidates"])
            self.assertEqual(result["files_scanned"], 2)

    def test_deny_ask_counted(self):
        with tempfile.TemporaryDirectory() as root, \
                tempfile.TemporaryDirectory() as gdir:
            self._write(root, "proj-a", "settings.json",
                        {"deny": ["Read(x)", "Read(y)"], "ask": ["Bash(z)"]})
            global_path = Path(gdir) / "settings.json"
            global_path.write_text(json.dumps({"permissions": {"allow": []}}))
            result = gc.gather(Path(root), global_path)
            self.assertEqual(result["skipped_deny_ask"], 3)
            self.assertEqual(result["candidates"], {})

    def test_malformed_file(self):
        with tempfile.TemporaryDirectory() as root, \
                tempfile.TemporaryDirectory() as gdir:
            d = Path(root) / "proj-a" / ".claude"
            d.mkdir(parents=True)
            (d / "settings.json").write_text("{ not valid json")
            global_path = Path(gdir) / "settings.json"
            global_path.write_text(json.dumps({"permissions": {"allow": []}}))
            result = gc.gather(Path(root), global_path)
            self.assertEqual(len(result["files_failed"]), 1)
            self.assertEqual(result["files_scanned"], 0)

    def test_project_name(self):
        p = Path("/x/seomoz/app-api/.claude/settings.local.json")
        self.assertEqual(gc.project_name(p), "app-api")

    def test_schema_invalid_does_not_crash(self):
        with tempfile.TemporaryDirectory() as root, \
                tempfile.TemporaryDirectory() as gdir:
            self._write(root, "proj-a", "settings.json", "oops")
            d = Path(root) / "proj-b" / ".claude"
            d.mkdir(parents=True)
            (d / "settings.json").write_text(
                json.dumps({"permissions": {"allow": "x", "deny": True}})
            )
            global_path = Path(gdir) / "settings.json"
            global_path.write_text(json.dumps({"permissions": {"allow": []}}))
            result = gc.gather(Path(root), global_path)
            self.assertNotIn("x", result["candidates"])
            self.assertEqual(result["skipped_deny_ask"], 0)
            self.assertEqual(result["files_failed"], [])

    def test_non_string_allow_elements(self):
        with tempfile.TemporaryDirectory() as root, \
                tempfile.TemporaryDirectory() as gdir:
            self._write(root, "proj-a", "settings.json",
                        {"allow": [1, 2, "Bash(ok *)"]})
            global_path = Path(gdir) / "settings.json"
            global_path.write_text(
                json.dumps({"permissions": {"allow": ["Bash(git rm:*)"]}})
            )
            result = gc.gather(Path(root), global_path)
            self.assertEqual(result["candidates"], {"Bash(ok *)": ["proj-a"]})

    def test_schema_invalid_global(self):
        with tempfile.TemporaryDirectory() as root, \
                tempfile.TemporaryDirectory() as gdir:
            self._write(root, "proj-a", "settings.json",
                        {"allow": ["Bash(npm list *)"]})
            global_path = Path(gdir) / "settings.json"
            global_path.write_text(json.dumps({"permissions": "oops"}))
            result = gc.gather(Path(root), global_path)
            self.assertEqual(result["candidates"], {"Bash(npm list *)": ["proj-a"]})

    def test_top_level_nondict_global(self):
        with tempfile.TemporaryDirectory() as root, \
                tempfile.TemporaryDirectory() as gdir:
            self._write(root, "proj-a", "settings.json",
                        {"allow": ["Bash(npm list *)"]})
            global_path = Path(gdir) / "settings.json"
            global_path.write_text('"oops"')
            result = gc.gather(Path(root), global_path)
            self.assertEqual(result["candidates"], {"Bash(npm list *)": ["proj-a"]})


class TestMergeAllow(unittest.TestCase):
    def test_appends_new_skips_dupes(self):
        settings = {"permissions": {"allow": ["Bash(a)"]}, "model": "opus"}
        result, added, skipped = ac.merge_allow(settings, ["Bash(a)", "Bash(b)"])
        self.assertEqual(result["permissions"]["allow"], ["Bash(a)", "Bash(b)"])
        self.assertEqual((added, skipped), (1, 1))
        self.assertEqual(result["model"], "opus")

    def test_creates_missing_keys(self):
        result, added, skipped = ac.merge_allow({}, ["Bash(a)"])
        self.assertEqual(result["permissions"]["allow"], ["Bash(a)"])
        self.assertEqual((added, skipped), (1, 0))

    def test_merge_allow_coerces_non_dict(self):
        result, added, skipped = ac.merge_allow({"permissions": None}, ["Bash(a)"])
        self.assertEqual(result["permissions"]["allow"], ["Bash(a)"])
        self.assertEqual((added, skipped), (1, 0))
        result2, added2, _ = ac.merge_allow({"permissions": {"allow": "x"}}, ["Bash(a)"])
        self.assertEqual(result2["permissions"]["allow"], ["Bash(a)"])
        self.assertEqual(added2, 1)


class TestApply(unittest.TestCase):
    def test_apply_backs_up_and_writes(self):
        with tempfile.TemporaryDirectory() as gdir:
            global_path = Path(gdir) / "settings.json"
            global_path.write_text(
                json.dumps({"permissions": {"allow": ["Bash(a)"]}, "theme": "dark"})
            )
            original = global_path.read_text()
            summary = ac.apply(global_path, ["Bash(b)", "Bash(a)"])
            data = json.loads(global_path.read_text())
            self.assertEqual(data["permissions"]["allow"], ["Bash(a)", "Bash(b)"])
            self.assertEqual(data["theme"], "dark")
            self.assertEqual(summary["added"], 1)
            self.assertEqual(summary["skipped"], 1)
            self.assertTrue(Path(summary["backup"]).is_file())
            self.assertEqual(Path(summary["backup"]).read_text(), original)


if __name__ == "__main__":
    unittest.main()
