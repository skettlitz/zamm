"""Surfaces the suite never touched: zamm-status.sh, --overwrite-templates,
and --help.

Found by auditing every script flag against the suite. Two of these were
briefly mistaken for covered because the string appeared in a docstring —
check for the invocation, not the mention.
"""

import shutil

from harness import SKILL_DIR, ZammTest


class TestStatusScript(ZammTest):
    """zamm-status.sh had zero tests before this file."""

    def test_groups_plans_by_status_with_counts(self):
        self.led.add_plan("2026-01-05-drafting", status="Draft")
        self.led.add_plan("2026-01-06-building-a", status="Implementing")
        self.led.add_plan("2026-01-07-building-b", status="Implementing")
        self.led.add_plan("2026-01-08-awaiting", status="Review")

        r = self.led.plan_list()

        self.assertCode(r, 0)
        self.assertIn_("Draft: 1", r.out)
        self.assertIn_("Implementing: 2", r.out)
        self.assertIn_("Review: 1", r.out)
        self.assertIn_("Done: 0", r.out)
        self.assertIn_("2026-01-06-building-a", r.out)

    def test_handles_a_project_with_no_plans(self):
        r = self.led.plan_list()

        self.assertCode(r, 0)
        self.assertIn_("Plan directories scanned: 0", r.out)

    def test_reports_a_plan_directory_missing_its_plan_file(self):
        (self.led.root / "zamm-memory/active/plans/2026-01-05-empty-dir").mkdir(
            parents=True
        )
        r = self.led.plan_list()

        self.assertCode(r, 0)
        self.assertIn_("Missing main .plan.md: 1", r.out)

    def test_reads_project_root_rather_than_cwd(self):
        """Every rendered command passes --project-root; the script must
        honour it even when run from somewhere else entirely."""
        self.led.add_plan("2026-01-05-elsewhere", status="Implementing")

        r = self.led.plan_list(cwd=SKILL_DIR)

        self.assertCode(r, 0)
        self.assertIn_("2026-01-05-elsewhere", r.out)
        self.assertIn_(str(self.led.root), r.out)


class TestScaffoldRefresh(ZammTest):
    """scaffold is single-mode: it always re-renders the managed surfaces."""

    def setUp(self):
        super().setUp()
        shutil.rmtree(self.led.root / "zamm-memory")
        self.assertCode(self.led.scaffold(), 0)

    def test_rerenders_the_cursor_rule(self):
        rule = ".cursor/rules/zamm.mdc"
        self.led.write(rule, "hand-edited nonsense\n")

        r = self.led.scaffold()

        self.assertCode(r, 0)
        content = self.led.read(rule)
        self.assertNotIn_("hand-edited nonsense", content)
        self.assertIn_("Session Start", content)

    def test_always_rerenders_no_flag_needed(self):
        """The --overwrite-templates mode flag is gone: managed surfaces are
        generated and version-stamped, so refresh is what scaffold means.
        Leaving a stale rendered protocol behind was the strange half of the
        old two-mode behaviour."""
        rule = ".cursor/rules/zamm.mdc"
        self.led.write(rule, "stale local edit\n")

        self.assertCode(self.led.scaffold(), 0)

        self.assertNotIn_("stale local edit", self.led.read(rule))
        self.assertIn_("Session Start", self.led.read(rule))

    def test_does_not_delete_user_rules_from_cursorignore(self):
        """Before the managed-block fix, --overwrite-templates replaced the
        whole .cursorignore and took the user's rules with it."""
        # a user rule sitting above the scaffolded managed block
        self.led.write(".cursorignore", "node_modules/**\n" + self.led.read(".cursorignore"))

        r = self.led.scaffold()

        self.assertCode(r, 0)
        content = self.led.read(".cursorignore")
        self.assertIn_("node_modules/**", content)
        self.assertIn_("zamm-memory/archive/**", content)
        self.assertEqual(content.count("SKILL-BLOCK:zamm:BEGIN"), 1)

    def test_agents_block_is_rerendered_either_way(self):
        """Documented behaviour: the AGENTS.md managed block refreshes on a
        normal run too, since it carries the protocol."""
        agents = self.led.read("AGENTS.md")
        self.assertIn_("SKILL-BLOCK:zamm:BEGIN", agents)

        for run in (1, 2):
            with self.subTest(run=run):
                r = self.led.scaffold()
                self.assertCode(r, 0)
                content = self.led.read("AGENTS.md")
                self.assertEqual(content.count("SKILL-BLOCK:zamm:BEGIN"), 1)
                self.assertEqual(content.count("SKILL-BLOCK:zamm:END"), 1)
                self.assertIn_("Session Start", content)


class TestHelp(ZammTest):
    SCRIPTS = [
        "zamm-compile.sh",
        "zamm-new-memory.sh",
        "zamm-scaffold.sh",
        "zamm-archive.sh",
        "zamm-status.sh",
    ]

    def test_help_exits_zero_and_prints_usage(self):
        """Asking for help is not an error. Three scripts exited 1 until
        2026-07-20 because usage() served both --help and bad arguments.
        """
        for script in self.SCRIPTS:
            with self.subTest(script=script):
                r = self.led.run(script, "--help")
                self.assertCode(r, 0, f"{script} --help")
                self.assertIn_("Usage", r.output, script)

    def test_short_and_long_help_agree(self):
        for script in self.SCRIPTS:
            with self.subTest(script=script):
                self.assertEqual(
                    self.led.run(script, "-h").output,
                    self.led.run(script, "--help").output,
                )

    def test_an_unknown_argument_is_still_an_error(self):
        """The exit-0 fix must not make bad arguments look successful."""
        for script in self.SCRIPTS:
            with self.subTest(script=script):
                r = self.led.run(script, "--definitely-not-a-flag")
                self.assertNotEqual(r.code, 0, f"{script} accepted a bogus flag")

    def test_help_writes_nothing_to_the_project(self):
        before = sorted(p.name for p in self.led.root.iterdir())
        for script in self.SCRIPTS:
            self.led.run(script, "--help")
        self.assertEqual(before, sorted(p.name for p in self.led.root.iterdir()))
