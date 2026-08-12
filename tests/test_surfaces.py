"""Surfaces the suite never touched: zamm-status.sh, --overwrite-templates,
and --help.

Found by auditing every script flag against the suite. Two of these were
briefly mistaken for covered because the string appeared in a docstring —
check for the invocation, not the mention.
"""

import re
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
        self.assertIn_("Session start (MUST)", content)

    def test_always_rerenders_no_flag_needed(self):
        """The --overwrite-templates mode flag is gone: managed surfaces are
        generated and version-stamped, so refresh is what scaffold means.
        Leaving a stale rendered protocol behind was the strange half of the
        old two-mode behaviour."""
        rule = ".cursor/rules/zamm.mdc"
        self.led.write(rule, "stale local edit\n")

        self.assertCode(self.led.scaffold(), 0)

        self.assertNotIn_("stale local edit", self.led.read(rule))
        self.assertIn_("Session start (MUST)", self.led.read(rule))

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
                self.assertIn_("Session start (MUST)", content)


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


class TestHelpCoversEveryRoutedVerb(ZammTest):
    """Every verb the dispatcher routes must appear in the help output.

    `memory drafts` and `memory discard` shipped routed-but-undocumented:
    they reached `help memory` and never the top-level `help`, so the README
    and SKILL.md inherited the omission. Reading the dispatch tables here —
    the same `case` arms the dispatcher itself branches on — is what makes a
    new verb impossible to add without documenting it.

    The parse is indentation-anchored rather than brace-matched: a `case`
    block ends at an `esac` indented exactly like its `case`, so nested
    dispatches (the flag `case` inside `plan archive`) are skipped whole
    instead of leaking their flags in as verbs.
    """

    # Aliases and catch-alls: routed, but not verbs a user looks up.
    NOT_VERBS = {"*", "help", "--help", "-h"}

    GROUPS = ("memory", "plan")

    def setUp(self):
        super().setUp()
        self.lines = (SKILL_DIR / "scripts" / "zamm-run.sh").read_text().splitlines()

    @staticmethod
    def _indent(line):
        return len(line) - len(line.lstrip())

    def _arms_after(self, first_line):
        """Case-arm labels of the block opened at `first_line`."""
        indent = self._indent(self.lines[first_line])
        arm = re.compile(r"^ {%d}([a-z*|_-]+)\)" % (indent + 2))
        arms = set()
        for line in self.lines[first_line + 1:]:
            if line.strip() == "esac" and self._indent(line) == indent:
                break
            m = arm.match(line)
            if m:
                arms.update(m.group(1).split("|"))
        return {a for a in arms - self.NOT_VERBS if not a.startswith("-")}

    def _find(self, pattern, after=0):
        for i in range(after, len(self.lines)):
            if re.match(pattern, self.lines[i]):
                return i
        raise AssertionError(f"dispatch shape changed: no line matching {pattern!r}")

    def _top_verbs(self):
        return self._arms_after(self._find(r'^case "\$cmd" in'))

    def _group_verbs(self, group):
        at_group = self._find(r"^  %s\)" % group)
        return self._arms_after(self._find(r'^    case "\$verb" in', after=at_group))

    def test_top_level_help_lists_every_top_level_command(self):
        top = self._top_verbs()
        self.assertTrue(top, "parsed no top-level verbs; the dispatch shape changed")
        help_text = self.led.zamm("help").output
        for verb in sorted(top):
            with self.subTest(verb=verb):
                self.assertIn_(verb, help_text, f"top-level `{verb}` is undocumented")

    def test_top_level_help_lists_every_group_verb(self):
        """The group help is not enough: `help` is where a user starts."""
        help_text = self.led.zamm("help").output
        for group in self.GROUPS:
            verbs = self._group_verbs(group)
            self.assertTrue(verbs, f"parsed no {group} verbs; the dispatch shape changed")
            for verb in sorted(verbs):
                with self.subTest(group=group, verb=verb):
                    self.assertIn_(
                        f"{group} {verb}", help_text,
                        f"`{group} {verb}` is routed but missing from top-level help",
                    )

    def test_group_help_lists_every_verb_of_its_group(self):
        for group in self.GROUPS:
            group_text = self.led.zamm(group, "--help").output
            for verb in sorted(self._group_verbs(group)):
                with self.subTest(group=group, verb=verb):
                    self.assertIn_(
                        verb, group_text,
                        f"`{group} {verb}` is missing from `{group} --help`",
                    )
