"""Regression locks for the SECOND adversarial review of the remediation
(2026-07-21). Each reproduces a defect that survived the first remediation
and is closed under Phase 8 of
2026-07-20-command-surface-review-remediation.

Findings:
  22  compiler apply pass gave chain credit for edges into invalid targets
  23  --supersedes / --plan newline forged frontmatter keys
  24  multiline plan title injected Status:; --help mid-arg created a plan
  25  --date zero-month wrote an invalid ledger file
  26  plan check scanned the whole file for Done-when / Learnings
  27  archive signal traps resumed; move logged after the mv
  28  status --help / check --help ran instead of printing usage
  29  empty --project-root= fell through to auto-discovery
  30  stamp ignored runtime scripts; render-failure path untested
"""

import os
import subprocess

from harness import EXIT_CONTRACT, EXIT_OK, SCRIPTS, ZammTest

RUN = str(SCRIPTS / "zamm-run.sh")


# ----------------------------------------------------------------------
# 22 — an edge into an invalid target must not influence valid ranking
# ----------------------------------------------------------------------
class TestCompilerTargetAuthority(ZammTest):
    def _rank_order(self):
        return self.led.entries()

    def test_edge_into_a_quarantined_cycle_gives_no_chain_credit(self):
        # two same-scope competitors; zzz ranks above aaa on the id tiebreak
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-10-zzz-comp-22222.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: permanent\ncreated: 2026-01-10\nschema: 3\n---\nZZZ.\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-10-aaa-pre-33333.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: permanent\ncreated: 2026-01-10\nschema: 3\n---\nAAA.\n",
        )
        self.led.compile(today="2026-01-15")
        baseline = self._rank_order()

        # now aaa supersedes a member of a quarantined a<->b cycle
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-08-cyca-44444.md",
            "---\ntype: tombstone\nsupersedes: 2026-01-08-cycb-55555\n"
            "created: 2026-01-08\nschema: 3\n---\nCycle A.\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-08-cycb-55555.md",
            "---\ntype: tombstone\nsupersedes: 2026-01-08-cyca-44444\n"
            "created: 2026-01-08\nschema: 3\n---\nCycle B.\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-10-aaa-pre-33333.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: permanent\nsupersedes: 2026-01-08-cyca-44444\n"
            "created: 2026-01-10\nschema: 3\n---\nAAA.\n",
        )
        self.led.compile(today="2026-01-15")

        self.assertEqual(
            baseline, self._rank_order(),
            "an edge into a quarantined target must not change valid ranking",
        )

    def test_edge_into_a_parse_invalid_target_gives_no_credit(self):
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-10-zzz-comp-22222.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: permanent\ncreated: 2026-01-10\nschema: 3\n---\nZZZ.\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-10-aaa-pre-33333.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: permanent\ncreated: 2026-01-10\nschema: 3\n---\nAAA.\n",
        )
        self.led.compile(today="2026-01-15")
        baseline = self._rank_order()

        # a parse-invalid target (missing schema:) and aaa superseding it
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-09-broken-66666.md",
            "---\ntype: memory\nscope: contracts/api\ncreated: 2026-01-09\n---\nNo schema.\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-10-aaa-pre-33333.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: permanent\nsupersedes: 2026-01-09-broken-66666\n"
            "created: 2026-01-10\nschema: 3\n---\nAAA.\n",
        )
        self.led.compile(today="2026-01-15")

        self.assertEqual(baseline, self._rank_order())


# ----------------------------------------------------------------------
# 23 — frontmatter-value inputs must not carry control characters
# ----------------------------------------------------------------------
class TestWriterInputAuthority(ZammTest):
    def test_supersedes_newline_is_refused(self):
        inj = "%s\nseed-up: 50" % "2026-01-05-victim-22222"
        r = self.led.new_memory("--scope", "contracts/api", "--supersedes", inj, "forged")
        self.assertNotEqual(r.code, 0, "a newline in --supersedes must be refused")
        # nothing forged on disk
        for p in (self.led.root / "zamm-memory/knowledge").rglob("*.md"):
            self.assertNotIn_("seed-up", p.read_text())

    def test_plan_newline_is_refused(self):
        inj = "someplan\nup: 2026-01-05-x-22222"
        r = self.led.new_memory("--type", "votes", "--plan", inj, "closure")
        self.assertNotEqual(r.code, 0, "a newline in --plan must be refused")

    def test_ordinary_multi_target_supersedes_still_works(self):
        a = self.led.add("head-a", "A.")
        b = self.led.add("head-b", "B.")
        r = self.led.new_memory("--scope", "contracts/api",
                                "--supersedes", f"{a}, {b}", "merged")
        self.assertCode(r, EXIT_OK, "comma+space separated ids must still be accepted")


# ----------------------------------------------------------------------
# 24 — multiline plan title injection + mid-arg help
# ----------------------------------------------------------------------
class TestPlanCreateInjection(ZammTest):
    def _plan_files(self):
        return sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*")
        )

    def test_multiline_title_is_refused(self):
        title = "Innocent\nStatus: Done\nDone-approved-by: x"
        before = self._plan_files()
        r = self.led.plan_create(title)
        self.assertNotEqual(r.code, 0, "a multiline title must be refused")
        self.assertEqual(before, self._plan_files(), "no plan directory may be created")

    def test_help_in_any_position_does_not_create_a_plan(self):
        before = self._plan_files()
        r = self.led.plan_create("My Plan", "--help")
        self.assertCode(r, EXIT_OK)
        self.assertEqual(before, self._plan_files(),
                         "plan create <title> --help must not create a plan")
        self.assertIn_("Usage", r.output)


# ----------------------------------------------------------------------
# 25 — --date must reject a zero month/day
# ----------------------------------------------------------------------
class TestDateZeroMonth(ZammTest):
    def _count(self):
        return len(list((self.led.root / "zamm-memory/knowledge").rglob("*.md")))

    def test_zero_month_is_refused(self):
        before = self._count()
        r = self.led.new_memory("--scope", "contracts/api", "--date", "2026-00-01", "z")
        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._count(), "no file may be written")

    def test_zero_day_is_refused(self):
        before = self._count()
        r = self.led.new_memory("--scope", "contracts/api", "--date", "2026-01-00", "z")
        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._count())

    def test_all_zero_is_refused(self):
        before = self._count()
        r = self.led.new_memory("--scope", "contracts/api", "--date", "0000-00-00", "z")
        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._count())

    def test_a_real_backdate_still_works(self):
        r = self.led.new_memory("--scope", "contracts/api", "--date", "2025-08-09", "b")
        self.assertCode(r, EXIT_OK, "08/09 must not trip octal parsing")


# ----------------------------------------------------------------------
# 26 — plan check must scan only the relevant sections
# ----------------------------------------------------------------------
class TestPlanCheckSectionScoping(ZammTest):
    def _write(self, slug, body):
        self.led.write(f"zamm-memory/active/plans/{slug}/{slug}.plan.md", body)

    HEAD = ("# P\n\nStatus: {status}\nExecution-context-before: y\n"
            "Complexity-forecast: gecko\nLast updated: 2026-01-05\n\n"
            "Scope:\n* In: real.\n* Out: no.\n\n")

    def test_checkbox_outside_done_when_does_not_satisfy_it(self):
        self._write("2026-01-05-a", self.HEAD.format(status="Implementing")
                    + "## Done-when\n\n(nothing here)\n\n"
                    + "## Approach\n\n- [ ] unrelated\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Done-when", r.err)

    def test_unchecked_box_outside_done_when_does_not_block_closure(self):
        self._write("2026-01-05-b", self.HEAD.format(status="Review")
                    + "## Done-when\n\n- [x] done\n\n"
                    + "## Approach\n\n- [ ] not a done-when item\n\n"
                    + "## Learnings\n\n- A learning.\n\n"
                    + "Execution-friction-after: none\nComplexity-felt: gecko\n"
                    + "Complexity-delta: as-expected\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_OK, r.err)

    def test_learnings_as_the_final_heading_is_read(self):
        self._write("2026-01-05-c", self.HEAD.format(status="Review")
                    + "## Done-when\n\n- [x] done\n\n"
                    + "Execution-friction-after: none\nComplexity-felt: gecko\n"
                    + "Complexity-delta: as-expected\n\n"
                    + "## Learnings\n\n- The only durable learning, last section.\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_OK, r.err)

    def test_genuinely_empty_learnings_still_caught(self):
        """The fix must not become permissive."""
        self._write("2026-01-05-d", self.HEAD.format(status="Review")
                    + "## Done-when\n\n- [x] done\n\n"
                    + "Execution-friction-after: none\nComplexity-felt: gecko\n"
                    + "Complexity-delta: as-expected\n\n"
                    + "## Learnings\n\n\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Learnings", r.err)


# ----------------------------------------------------------------------
# 27 — a caught signal must terminate and roll back, not resume
# ----------------------------------------------------------------------
class TestArchiveSignalRollback(ZammTest):
    def _retired_chain(self, slug):
        rec = self.led.add(slug, f"Retired: {slug}.")
        self.led.add(f"retire-{slug}", "Gone.", date="2026-01-06",
                     type="tombstone", supersedes=rec)
        return rec

    def _knowledge_snapshot(self):
        snap = {}
        for sub in ("zamm-memory/knowledge", "zamm-memory/archive/knowledge"):
            for p in (self.led.root / sub).rglob("*.md"):
                snap[str(p.relative_to(self.led.root))] = p.read_bytes()
        return snap

    def _run_signal_case(self, signal):
        self.led.add("live-rule", "Still true.")
        self._retired_chain("obsolete")   # two inert records -> two moves
        self.led.compile()
        before = self._knowledge_snapshot()

        shim = self.led.root / ".shims"
        shim.mkdir(exist_ok=True)
        # a `mv` that, after completing the 2nd move into archive/knowledge,
        # sends the signal to the archive script — the exact "killed mid-loop"
        # window. Correct handling terminates and rolls back; the buggy version
        # resumed after cleanup deleted the work dir.
        mv = shim / "mv"
        mv.write_text(
            "#!/bin/sh\n"
            'case " $* " in\n'
            '  *archive/knowledge*)\n'
            '    d=$(dirname "$0")\n'
            '    n=$(cat "$d/.count" 2>/dev/null || echo 0); n=$((n + 1))\n'
            '    printf "%s\\n" "$n" > "$d/.count"\n'
            '    for c in /bin/mv /usr/bin/mv; do [ -x "$c" ] && { "$c" "$@"; rc=$?; break; }; done\n'
            f'    if [ "$n" = "2" ]; then kill -{signal} "$PPID" 2>/dev/null; sleep 2; fi\n'
            '    exit ${rc:-0} ;;\n'
            'esac\n'
            'for c in /bin/mv /usr/bin/mv; do [ -x "$c" ] && exec "$c" "$@"; done\n'
            "exit 127\n"
        )
        mv.chmod(0o755)
        env = {"PATH": f"{shim}:{os.environ['PATH']}"}

        r = self.led.memory_archive(env=env)

        self.assertNotEqual(r.code, 0, f"a {signal} must not produce a success exit")
        self.assertEqual(before, self._knowledge_snapshot(),
                         f"a caught {signal} must roll every record back")
        stranded = list(
            (self.led.root / "zamm-memory/archive/knowledge").rglob("*.md"))
        self.assertEqual(stranded, [], "no record may be stranded under archive/")

    def test_a_signal_mid_move_rolls_back_and_strands_nothing(self):
        # the plan claims HUP/INT/TERM fault-injection coverage — exercise all
        for signal in ("TERM", "INT", "HUP"):
            with self.subTest(signal=signal):
                self.setUp()   # fresh tree per signal
                self._run_signal_case(signal)


# ----------------------------------------------------------------------
# 30 (R3#5) — a forced render failure leaves no plan debris
# ----------------------------------------------------------------------
class TestPlanCreateRenderFailure(ZammTest):
    def test_a_template_that_renders_invalid_leaves_no_debris(self):
        # a template with neither placeholder nor a Status line: the render
        # "succeeds" but validation rejects it, exercising the cleanup path
        bad = self.led.root / "bad.template.md"
        bad.write_text("# not a real template\nno status here\n")
        before = sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*"))

        r = self.led.plan_create("Some Title",
                                 env={"ZAMM_PLAN_TEMPLATE": str(bad)})

        self.assertNotEqual(r.code, 0, "an invalid render must be refused")
        self.assertIn_("Status: Draft", r.err)
        after = sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*"))
        self.assertEqual(before, after, "no plan directory or .tmp-plan- debris")
        self.assertFalse(any(".tmp-plan-" in n for n in after))


# ----------------------------------------------------------------------
# 28 — status/check --help print usage instead of running
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# 29 — empty --project-root= is an error, not auto-discovery
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# 30 — stamp covers runtime scripts; --list-live documented in --help
# ----------------------------------------------------------------------
class TestStampAndDocs(ZammTest):
    def test_list_live_is_in_compile_help(self):
        r = self.led.run("zamm-compile.sh", "--help")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("--list-live", r.output)
