"""The single entrypoint: routing, root resolution, and the status view.

The rest of the suite reaches the scripts THROUGH zamm-run.sh, so routing is
exercised constantly. These tests cover the dispatcher's own behaviour —
the parts nothing else would notice if they broke.
"""

import os
import subprocess

from harness import (
    EXIT_CONTRACT,
    EXIT_OK,
    EXIT_REFUSED_PUBLISH,
    SCRIPTS,
    ZammTest,
)

RUN = str(SCRIPTS / "zamm-run.sh")


class TestRouting(ZammTest):
    def test_each_subcommand_reaches_its_script(self):
        self.led.add("a-rule", "A statement.")
        for args, expect in [
            (["memory", "digest"], "ZAMM Memory Digest"),  # digest prints, not just builds
            (["memory", "check"], "check passed"),
            (["plan", "list"], "plan status snapshot"),
            (["plan", "archive"], "plan archive helper"),
        ]:
            with self.subTest(args=args):
                r = self.led.zamm(*args)
                self.assertCode(r, EXIT_OK)
                self.assertIn_(expect, r.output)

    def test_check_injects_the_flag_rather_than_writing_a_digest(self):
        """`memory check` is `compile --check`; it must validate and write
        nothing."""
        self.led.add("a-rule", "A statement.")

        r = self.led.zamm("memory", "check")

        self.assertCode(r, EXIT_OK)
        self.assertFalse(
            self.led.exists("zamm-memory/.compiled/memory.md"),
            "check must not publish a digest",
        )

    def test_unknown_command_and_unknown_subcommand_are_rejected(self):
        for args in (["bogus"], ["memory", "bogus"], ["plan", "bogus"]):
            with self.subTest(args=args):
                r = self.led.zamm(*args)
                self.assertNotEqual(r.code, 0)
                self.assertIn_("unknown command", r.err)

    def test_help_paths_exit_zero(self):
        for args in ([], ["help"], ["help", "memory"], ["help", "plan"],
                     ["memory"], ["plan"], ["help", "scaffold"],
                     ["help", "memory", "digest"]):
            with self.subTest(args=args):
                r = self.led.zamm(*args)
                self.assertCode(r, EXIT_OK, f"zamm-run.sh {' '.join(args)}")
                self.assertIn_("Usage", r.output)

    def test_help_forwards_to_the_underlying_script(self):
        r = self.led.zamm("help", "memory", "digest")
        self.assertIn_("zamm-compile.sh", r.output)

    def test_group_help_lists_that_groups_commands(self):
        self.assertIn_("record", self.led.zamm("help", "memory").output)
        self.assertIn_("archive", self.led.zamm("help", "plan").output)


class TestArgumentHandling(ZammTest):
    def test_exit_codes_pass_through_unchanged(self):
        """Load-bearing: 3 means 'records exist but none survived, previous
        digest kept' and 1 means 'contract violation'. A dispatcher that
        flattened 3 to 1 would destroy that distinction."""
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-05-broken-22222.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\n---\nNo schema.\n",
        )
        self.assertCode(self.led.zamm("memory", "digest"), EXIT_REFUSED_PUBLISH)
        self.assertCode(self.led.zamm("memory", "check"), EXIT_CONTRACT)

        self.led.add("good", "A valid statement.")
        self.led.delete("2026-01-05-broken-22222")
        self.assertCode(self.led.zamm("memory", "check"), EXIT_OK)

    def test_quoted_argument_with_space_and_comma_survives(self):
        """Two layers of shell between the caller and the script — the
        classic place forwarding breaks."""
        r = self.led.zamm(
            "memory", "create",
            "--scope", "contracts/api, conventions",
            "quoted-slug",
        )
        self.assertCode(r, EXIT_OK)
        with open(r.out.strip()) as fh:
            content = fh.read()
        self.assertIn_("scope: contracts/api, conventions", content)

    def test_project_root_accepted_in_any_position(self):
        self.led.add("a-rule", "A statement.")
        root = str(self.led.root)
        for argv in (
            ["--project-root", root, "memory", "check"],
            ["memory", "check", "--project-root", root],
            ["memory", "--project-root", root, "check"],
            [f"--project-root={root}", "memory", "check"],
        ):
            with self.subTest(argv=argv):
                cp = subprocess.run(
                    ["sh", RUN, *argv], capture_output=True, text=True,
                    cwd=os.sep, env={**os.environ, "ZAMM_TODAY": "2026-07-19"},
                )
                self.assertEqual(cp.returncode, 0, cp.stderr)

    def test_environment_seams_pass_through(self):
        """ZAMM_TODAY must survive the hop, or every golden test rots."""
        self.led.add("a-rule", "A statement.")
        self.led.zamm("memory", "digest", today="2026-01-01")
        self.assertIn_("2026-01-01", self.led.digest().splitlines()[0])


class TestRootResolution(ZammTest):
    def _run_from(self, cwd, *args):
        return subprocess.run(
            ["sh", RUN, *args], capture_output=True, text=True, cwd=str(cwd),
            env={**os.environ, "ZAMM_TODAY": "2026-07-19"},
        )

    def test_resolves_upward_from_a_nested_directory(self):
        """The bug this replaces: scripts resolving against cwd silently
        targeted the wrong tree when run from a subdirectory."""
        self.led.add("a-rule", "A statement.")
        nested = self.led.root / "src" / "deep" / "nested"
        nested.mkdir(parents=True)

        cp = self._run_from(nested, "memory", "check")

        self.assertEqual(cp.returncode, 0, cp.stderr)

    def test_explicit_flag_beats_auto_resolution(self):
        """Standing in one project while targeting another must work."""
        self.led.add("a-rule", "A statement.")
        other = self.led.root / "other-project"
        (other / "zamm-memory" / "knowledge").mkdir(parents=True)
        (other / "zamm-memory" / "knowledge" / "2026").mkdir()
        (other / "zamm-memory" / "knowledge" / "2026" / "2026-01-05-x-22222.md").write_text(
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\n---\nBroken on purpose.\n"
        )

        cp = self._run_from(self.led.root, "--project-root", str(other), "memory", "check")

        self.assertNotEqual(cp.returncode, 0, "should have checked the OTHER tree")
        self.assertIn("other-project", cp.stderr)

    def test_failure_names_what_was_tried(self):
        import tempfile

        with tempfile.TemporaryDirectory() as bare:
            cp = self._run_from(bare, "memory", "check")

            self.assertNotEqual(cp.returncode, 0)
            self.assertIn("cannot find a project root", cp.stderr)
            self.assertIn("zamm-memory/", cp.stderr)
            self.assertIn("git top level", cp.stderr)

    def test_scaffold_works_where_no_ledger_exists_yet(self):
        """Installing into a fresh project is the one case where the walk-up
        finds nothing and must not fail."""
        import tempfile

        with tempfile.TemporaryDirectory() as fresh:
            cp = self._run_from(fresh, "scaffold")

            self.assertEqual(cp.returncode, 0, cp.stderr)
            self.assertTrue((os.path.join(fresh, "zamm-memory", "VERSION")))


class TestStatusView(ZammTest):
    def test_reports_ledger_and_plan_state(self):
        self.led.add_many(6)
        self.led.add("guard", "A safety rule.", importance="guardrail",
                     durability="permanent")
        self.led.add_plan("2026-01-05-open", status="Implementing")
        self.led.compile()

        r = self.led.status()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("7 records, 7 live, 0 quarantined", r.out)
        self.assertIn_("guardrails: 1/15", r.out)
        self.assertIn_("1 implementing", r.out)

    def test_flags_a_pending_reconciliation(self):
        root = self.led.add("root", "Forked.")
        for b in ("a", "b"):
            self.led.add(f"head-{b}", f"Branch {b}.", date="2026-01-06",
                         supersedes=root)
        self.led.compile()

        self.assertIn_("RECONCILIATION PENDING", self.led.status().out)

    def test_flags_archive_ready_plans(self):
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-finished", status="Done")
        self.led.compile()

        self.assertIn_("ARCHIVE-READY", self.led.status().out)

    def test_reports_a_missing_digest_instead_of_building_one(self):
        """A status command that regenerates state makes 'check the state'
        change the state."""
        self.led.add("a-rule", "A statement.")

        r = self.led.status()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("no compiled digest", r.out)
        self.assertFalse(self.led.exists("zamm-memory/.compiled/memory.md"))

    def test_reports_a_stale_digest(self):
        import time

        self.led.add("a-rule", "A statement.")
        self.led.compile()
        time.sleep(1.1)
        self.led.add("later", "Written after the digest.", date="2026-01-06")

        self.assertIn_("STALE", self.led.status().out)

    def test_is_read_only(self):
        self.led.add_many(4)
        self.led.add_plan("2026-01-05-open")
        self.led.compile()

        before = {
            p: p.stat().st_mtime_ns
            for p in self.led.root.rglob("*") if p.is_file()
        }
        self.led.status()
        after = {
            p: p.stat().st_mtime_ns
            for p in self.led.root.rglob("*") if p.is_file()
        }

        self.assertEqual(before, after, "status must not touch the tree")
