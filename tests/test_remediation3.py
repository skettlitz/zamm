"""Regression locks for the THIRD/FOURTH adversarial reviews of the
remediation (2026-07-21). Validator strictness, argument parsing, and the
last ungated mover.

  F1  plan check: heading prefix match + permissive checkbox markers
  F2  plan show counted checkboxes across the whole file
  F3  built-ins silently ignored unknown args / empty option values
  F4  archive helper ungated; ZAMM_TODAY not calendar-validated in plan create
"""

import os
import subprocess

from harness import EXIT_CONTRACT, EXIT_OK, SCRIPTS, ZammTest

RUN = str(SCRIPTS / "zamm-run.sh")


# ----------------------------------------------------------------------
# F1 — plan check must match headings exactly and checkbox markers strictly
# ----------------------------------------------------------------------
class TestPlanCheckStrictness(ZammTest):
    def _write(self, slug, body):
        self.led.write(f"zamm-memory/active/plans/{slug}/{slug}.plan.md", body)

    HEAD = ("# P\n\nStatus: {status}\nExecution-context-before: y\n"
            "Complexity-forecast: gecko\nLast updated: 2026-01-05\n\n"
            "Scope:\n* In: real.\n* Out: no.\n\n")

    TELE = ("## Learnings\n\n- A learning.\n\n"
            "Execution-friction-after: none\nComplexity-felt: gecko\n"
            "Complexity-delta: as-expected\n")

    def test_a_prefixed_heading_does_not_pose_as_done_when(self):
        # empty ## Done-when, but a decoy ## Done-when-not carries an item
        self._write("2026-01-05-a", self.HEAD.format(status="Implementing")
                    + "## Done-when\n\n(none)\n\n"
                    + "## Done-when-not\n\n- [ ] decoy\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Done-when", r.err)

    def test_prefixed_learnings_heading_does_not_satisfy_learnings(self):
        self._write("2026-01-05-l", self.HEAD.format(status="Review")
                    + "## Done-when\n\n- [x] done\n\n"
                    + "Execution-friction-after: none\nComplexity-felt: gecko\n"
                    + "Complexity-delta: as-expected\n\n"
                    + "## Learnings\n\n\n"
                    + "## Learnings-extra\n\n- decoy content\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Learnings", r.err)

    def test_malformed_checkbox_is_rejected(self):
        self._write("2026-01-05-m", self.HEAD.format(status="Done")
                    + "## Done-when\n\n- [?] unfinished\n\n" + self.TELE
                    + "Done-approved-by: x\nDone-approved-at: 2026-01-05\n"
                    + "Done-approval-evidence: e\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        # either "malformed" or "unchecked" — the point is it must NOT pass
        self.assertTrue(
            "malformed" in r.err or "unchecked" in r.err,
            f"a [?] item must not count as done:\n{r.err}",
        )

    def test_a_bracketless_marker_does_not_count_as_a_done_item(self):
        """`- [?]` must not satisfy the 'has Done-when items' requirement on
        its own."""
        self._write("2026-01-05-n", self.HEAD.format(status="Implementing")
                    + "## Done-when\n\n- [?] not a real item\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)

    def test_a_normal_plan_still_passes(self):
        self._write("2026-01-05-ok", self.HEAD.format(status="Review")
                    + "## Done-when\n\n- [x] one\n- [X] two\n\n" + self.TELE)
        self.assertCode(self.led.plan_check(), EXIT_OK)


# ----------------------------------------------------------------------
# F2 — plan show / compiled tail must count only the Done-when section
# ----------------------------------------------------------------------
class TestDoneWhenCountScoping(ZammTest):
    def _plan(self):
        self.led.write(
            "zamm-memory/active/plans/2026-01-05-c/2026-01-05-c.plan.md",
            "# C\n\nStatus: Implementing\nComplexity-forecast: gecko\n"
            "Last updated: 2026-01-05\n\n## Done-when\n\n- [x] real item\n\n"
            "## Approach\n\n- [ ] not a done-when item\n",
        )

    def test_plan_show_counts_only_done_when(self):
        self._plan()
        r = self.led.plan_show("2026-01-05-c")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("Done-when: 1/1", r.out)
        self.assertNotIn_("1/2", r.out)

    def test_compiled_plans_tail_counts_only_done_when(self):
        self._plan()
        self.led.add("a-rule", "A statement.")
        self.led.compile()
        # the compiled Plans tail reports done-when progress per plan
        tail = self.led.digest_section("Plans (active; compact entries)") \
            if self.led.has_section("Plans (active; compact entries)") else self.led.digest()
        self.assertIn_("done-when 1/1", self.led.digest())
        self.assertNotIn_("done-when 1/2", self.led.digest())


# ----------------------------------------------------------------------
# F3 — built-ins must reject unknown args and empty option values
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# F4 — the raw archive helper must apply the same plan-check gate
# ----------------------------------------------------------------------
class TestArchiveHelperGate(ZammTest):
    def test_raw_helper_refuses_an_invalid_done_plan(self):
        """`zamm-archive.sh --archive` invoked directly must not move a plan
        that fails plan check (the dispatcher already gates; the helper did
        not, so direct invocation bypassed the safety story)."""
        self.led.add("a-rule", "A statement.")
        # a Done plan with empty approval fields: fails plan check hard
        self.led.add_plan("2026-01-05-sloppy", status="Done", valid=False)

        r = self.led.run("zamm-archive.sh", "--archive")

        self.assertNotEqual(r.code, 0, "the helper must refuse an invalid ledger")
        self.assertTrue(
            self.led.exists("zamm-memory/active/plans/2026-01-05-sloppy"),
            "the invalid plan must stay in active/",
        )
        self.assertFalse(
            self.led.exists("zamm-memory/archive/plans/2026-01-05-sloppy"),
            "the invalid plan must not reach archive/",
        )

    def test_raw_helper_still_archives_a_valid_plan(self):
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-proper", status="Done")

        r = self.led.run("zamm-archive.sh", "--archive")

        self.assertCode(r, EXIT_OK)
        self.assertTrue(self.led.exists("zamm-memory/archive/plans/2026-01-05-proper"))


# ----------------------------------------------------------------------
# F4 — ZAMM_TODAY must be calendar-validated by plan create
# ----------------------------------------------------------------------
class TestPlanCreateClockValidation(ZammTest):
    def _plan_files(self):
        return sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*"))

    def test_invalid_clock_is_refused_without_debris(self):
        before = self._plan_files()
        r = self.led.plan_create("Weird Day", today="2026-00-01")
        self.assertNotEqual(r.code, 0, "an impossible clock must be refused")
        self.assertEqual(before, self._plan_files(), "no plan directory may be created")
