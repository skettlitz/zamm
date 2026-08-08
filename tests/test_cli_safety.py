"""The command surface: help, argument handling, version and migration gates.

Help is read-only and reachable before any gate; arguments are data and never
program; a version or schema mismatch stops the toolchain instead of
operating on a tree it does not understand.

See references/invariants.md for the guarantees these suites protect.
"""

import os
import re
import shutil
import subprocess
import time

from harness import (
    EXIT_CONTRACT, EXIT_OK, EXIT_VERSION, HELP_PATHS, RUN, ZammTest,
)

class TestHelpIsReadOnly(ZammTest):
    """The reproduction: `zamm help plan create` created a plan directory
    named `<date>-help/` and exited 0, because the built-in plan_create read
    --help as a title. Help must be observably read-only for EVERY command."""

    def _snapshot(self):
        return {
            str(p.relative_to(self.led.root)): p.read_bytes()
            for p in sorted(self.led.root.rglob("*")) if p.is_file()
        }

    def _fixture(self):
        # a realistic tree: one record, one plan, a compiled digest
        self.led.add("a-rule", "A statement so the ledger is not empty.")
        self.led.add_plan("2026-01-05-open", status="Implementing")
        self.led.compile()

    def test_every_help_path_is_read_only_and_prints_usage(self):
        self._fixture()
        for args in HELP_PATHS:
            with self.subTest(args=" ".join(args)):
                before = self._snapshot()
                r = self.led.zamm(*args)
                after = self._snapshot()
                self.assertCode(r, EXIT_OK, f"help path must exit 0: {args}")
                self.assertTrue(
                    r.output.strip(),
                    f"help path must print something: {args}",
                )
                self.assertEqual(
                    before, after,
                    f"help path mutated the project tree: {args}\n"
                    f"added/changed: "
                    f"{set(after) ^ set(before) or 'content of an existing file'}",
                )

    def test_help_plan_create_does_not_create_a_plan(self):
        """The exact reproduction, pinned on its own."""
        before = self._snapshot()
        r = self.led.zamm("help", "plan", "create")
        self.assertCode(r, EXIT_OK)
        self.assertFalse(
            any("-help" in name for name in self._snapshot()),
            "help must not create a plan directory named for --help",
        )
        self.assertEqual(before, self._snapshot())


class TestTopLevelHelpForms(ZammTest):
    def test_status_help_prints_usage(self):
        self.led.add("a-rule", "A statement.")
        r = self.led.zamm("status", "--help")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("Usage", r.output)
        self.assertNotIn_("Ledger", r.output)  # did not run the status view

    def test_check_help_prints_usage_and_does_not_run(self):
        self.led.add("a-rule", "A statement.")
        r = self.led.zamm("check", "--help")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("Usage", r.output)
        self.assertNotIn_("check passed", r.output)


class TestEmptyProjectRoot(ZammTest):
    def test_empty_project_root_equals_is_rejected(self):
        sub = self.led.root / "sub"
        sub.mkdir()
        cp = subprocess.run(
            ["sh", RUN, "--project-root=", "status"],
            capture_output=True, text=True, cwd=str(sub),
            env={**os.environ, "ZAMM_TODAY": "2026-07-19"},
        )
        self.assertNotEqual(cp.returncode, 0, "empty --project-root= must error")

    def test_empty_project_root_space_form_is_rejected(self):
        sub = self.led.root / "sub"
        sub.mkdir()
        cp = subprocess.run(
            ["sh", RUN, "--project-root", "", "status"],
            capture_output=True, text=True, cwd=str(sub),
            env={**os.environ, "ZAMM_TODAY": "2026-07-19"},
        )
        self.assertNotEqual(cp.returncode, 0)


class TestArgumentRejection(ZammTest):
    def setUp(self):
        super().setUp()
        self.rid = self.led.add("a-rule", "A statement.")
        self.led.compile()

    def test_status_rejects_unknown_argument(self):
        r = self.led.zamm("status", "--bogus")
        self.assertNotEqual(r.code, 0)

    def test_check_rejects_unknown_argument(self):
        r = self.led.zamm("check", "--bogus")
        self.assertNotEqual(r.code, 0)

    def test_memory_show_rejects_extra_positional(self):
        r = self.led.memory_show(self.rid, "extra")
        self.assertNotEqual(r.code, 0)

    def test_plan_show_rejects_extra_positional(self):
        self.led.add_plan("2026-01-05-p", status="Implementing")
        r = self.led.plan_show("2026-01-05-p", "extra")
        self.assertNotEqual(r.code, 0)

    def test_memory_list_rejects_empty_scope(self):
        r = self.led.memory_list("--scope=")
        self.assertNotEqual(r.code, 0, "empty --scope= must error, not disable filtering")

    def test_memory_list_rejects_empty_scope_space_form(self):
        r = self.led.memory_list("--scope", "")
        self.assertNotEqual(r.code, 0)


class TestRuntimeVersionGate(ZammTest):
    """PRE-FIX: the scaffold refused an incompatible VERSION, but every
    OPERATIONAL command (digest, list, check, plan ...) ignored it and
    parsed the ledger under v3 rules regardless."""

    def _break_version(self, value=None):
        if value is None:
            (self.led.root / "zamm-memory/VERSION").unlink()
        else:
            self.led.version(value)

    def test_digest_refuses_on_wrong_version(self):
        self.led.add("rule", "A statement.")
        self._break_version("2")
        r = self.led.zamm("memory", "digest")
        self.assertCode(r, EXIT_VERSION)
        self.assertIn_("protocol version", r.err)

    def test_digest_refuses_when_version_missing(self):
        self.led.add("rule", "A statement.")
        self._break_version(None)
        self.assertCode(self.led.zamm("memory", "digest"), EXIT_VERSION)

    def test_top_level_check_refuses_on_wrong_version(self):
        self.led.add("rule", "A statement.")
        self._break_version("99")
        self.assertCode(self.led.zamm("check"), EXIT_VERSION)

    def test_status_reports_mismatch_without_refusing(self):
        self.led.add("rule", "A statement.")
        self.led.compile()
        self._break_version("2")
        r = self.led.zamm("status")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("PROTOCOL MISMATCH", r.out)

    def test_scaffold_is_exempt(self):
        # scaffold must still run to perform the upgrade itself.
        self._break_version(None)
        r = self.led.zamm("scaffold")
        self.assertCode(r, EXIT_OK)


class Rev2HelpBypassesVersionGate(ZammTest):
    """F9: help must never require interpreting the ledger."""

    def test_help_paths_exit_zero_on_a_mismatched_version(self):
        self.led.version("2")
        for args in (
            ("help", "memory"),
            ("memory", "list", "--help"),
            ("memory", "create", "--help"),
            ("memory", "publish", "--help"),
            ("memory", "show", "--help"),
            ("plan", "create", "--help"),
            ("plan", "check", "--help"),
        ):
            r = self.led.zamm(*args)
            self.assertCode(r, EXIT_OK, f"help path must exit 0: {args}")
        # a real command still refuses
        self.assertCode(self.led.zamm("memory", "list"), EXIT_VERSION)


class TestDriftDetection(ZammTest):
    """The stamp was the git short SHA in a checkout, identical for a clean
    and a dirty tree, so `status` reported rendered surfaces current while the
    skill had actually changed. And staleness watched knowledge/ only, though
    the digest embeds active plans too."""

    def _scaffold_fresh(self):
        shutil.rmtree(self.led.root / "zamm-memory")
        self.assertCode(self.led.scaffold(), EXIT_OK)

    def test_stamp_is_content_derived_not_a_git_sha(self):
        self._scaffold_fresh()
        stamp = re.search(r"version=(\S+)", self.led.read("AGENTS.md")).group(1)
        # content hash, even though the skill dir is itself a git checkout
        self.assertTrue(stamp.startswith("sha:"), f"expected sha: stamp, got {stamp}")

    def test_status_is_current_right_after_scaffold(self):
        self._scaffold_fresh()
        self.led.add("a-rule", "A statement.")
        self.led.compile()

        r = self.led.status()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("rendered surfaces:", r.out)
        self.assertNotIn_("STALE", r.out)

    def test_status_reports_surface_drift_when_the_stamp_differs(self):
        """A stamp that no longer matches the skill's content reads STALE —
        the case a dirty git checkout used to hide."""
        self._scaffold_fresh()
        self.led.add("a-rule", "A statement.")
        self.led.compile()
        agents = self.led.read("AGENTS.md")
        # simulate a project scaffolded from an older skill version
        agents = re.sub(r"version=\S+", "version=sha:000000000000", agents, count=1)
        self.led.write("AGENTS.md", agents)

        r = self.led.status()

        self.assertIn_("STALE", r.out)
        self.assertIn_("scaffold", r.out)

    def test_staleness_watches_active_plans_too(self):
        """A plan edited after the last compile makes the digest stale, since
        the digest embeds the active plans."""
        import time

        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-open", status="Implementing")
        self.led.compile()
        time.sleep(1.1)
        # edit the plan file after the digest was built
        p = "zamm-memory/active/plans/2026-01-05-open/2026-01-05-open.plan.md"
        self.led.write(p, self.led.read(p) + "\nAn edit after compiling.\n")

        self.assertIn_("STALE", self.led.status().out)

    def test_overwrite_templates_flag_is_gone(self):
        """The legacy mode flag is removed from the scaffold script itself,
        not just hidden by the dispatcher."""
        r = self.led.run("zamm-scaffold.sh", "--overwrite-templates")
        self.assertNotEqual(r.code, 0, "the removed flag must be rejected")
        self.assertIn_("unknown argument", r.output)


class TestStampAndDocs(ZammTest):
    def test_list_live_is_in_compile_help(self):
        r = self.led.run("zamm-compile.sh", "--help")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("--list-live", r.output)


class TestStampCoverage(ZammTest):
    """PRE-FIX: the stamp hashed only references/scaffold, references/templates
    and scripts, so edits to SKILL.md or references/distillation-triggers.md
    (both normative) did not register as drift."""

    def _stamp(self, skill_dir):
        import subprocess
        return subprocess.run(
            ["sh", str(skill_dir / "scripts/internal/zamm-skill-stamp.sh")],
            capture_output=True, text=True,
        ).stdout.strip()

    def test_skill_md_and_references_affect_the_stamp(self):
        import shutil, pathlib
        src = pathlib.Path(__file__).resolve().parent.parent
        dst = self.led.root / "skillcopy"
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns(
            ".git", "__pycache__", "zamm-memory"))
        base = self._stamp(dst)
        with (dst / "SKILL.md").open("a") as fh:
            fh.write("\nExtra normative sentence.\n")
        after_skill = self._stamp(dst)
        self.assertNotEqual(base, after_skill, "SKILL.md must affect the stamp")
        with (dst / "references/distillation-triggers.md").open("a") as fh:
            fh.write("\nx\n")
        after_ref = self._stamp(dst)
        self.assertNotEqual(after_skill, after_ref,
                            "references/ must affect the stamp")


class TestSeedRequiresMigration(ZammTest):
    def test_seed_up_without_migrated_from_is_rejected(self):
        self.led.add("forged", "Claims 50 upvotes it never earned.",
                     extra={"seed-up": "50"})
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("migrated-from", r.err)

    def test_seed_dn_without_migrated_from_is_rejected(self):
        self.led.add("forged", "Body.", extra={"seed-dn": "3"})
        self.assertCode(self.led.check(), EXIT_CONTRACT)

    def test_a_real_migration_record_is_accepted(self):
        self.led.add("migrated", "Carried over from v2.",
                     extra={"migrated-from": "B3", "seed-up": "5"})
        self.assertCode(self.led.check(), EXIT_OK)

    def test_forged_seed_does_not_influence_ranking(self):
        """The forged record is quarantined, so its fabricated weight never
        reaches the digest."""
        self.led.add("forged", "Forged weight.", extra={"seed-up": "99"})
        self.led.add("honest", "An honest record.")
        self.led.compile()
        # forged is quarantined -> not in the digest entries
        self.assertNotIn_("forged", "\n".join(self.led.entries()))
        self.assertIn_("honest", "\n".join(self.led.entries()))


class TestMigrationSeedConstraints(ZammTest):
    def _seeded(self, up="5", dn="0", frm="v2-card-b3"):
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-05-seed-sssss.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            f"durability: years\nseed-up: {up}\nseed-dn: {dn}\n"
            f"migrated-from: {frm}\ncreated: 2026-01-05\nschema: 3\n---\nSeeded.\n",
        )
        self.led.add("live", "A live sibling.")

    def test_huge_seed_up_is_rejected(self):
        self._seeded(up="999999999")
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("seed-up", r.err)

    def test_negative_seed_dn_is_rejected(self):
        self._seeded(dn="-1000")
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("seed-dn", r.err)

    def test_garbage_migrated_from_is_rejected(self):
        self._seeded(frm="made up here")
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("migrated-from", r.err)

    def test_a_bounded_seed_with_real_provenance_is_accepted(self):
        self._seeded(up="12", dn="3", frm="v2-card-tier1-3")
        self.assertCode(self.led.check(), EXIT_OK)


if __name__ == "__main__":
    unittest.main()
