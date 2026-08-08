"""Plan validation and plan/ledger reconciliation.

What `plan check` and the cross-check require of a plan for its declared
status, and the rule that a plan's own state and its ledger side effects must
agree before it can be called finished.

See references/invariants.md for the guarantees these suites protect.
"""

import tempfile

from harness import EXIT_CONTRACT, EXIT_OK, Ledger, ZammTest, review_plan

class TestPlanCheckHardening(ZammTest):
    """The pre-fix check validated only the SHAPE of `Last updated:` and the
    presence of a few fields, so an Implementing plan with no `Scope:` and
    `Last updated: 2026-99-99` passed with exit 0 — and `plan archive` trusts
    this check as its gate."""

    def _write_plan(self, slug, body):
        self.led.write(
            f"zamm-memory/active/plans/{slug}/{slug}.plan.md", body,
        )

    def test_the_exact_reproduction_is_now_rejected(self):
        """Implementing, no Scope, impossible Last updated."""
        self._write_plan(
            "2026-01-05-x",
            "# X\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: octopus\n"
            "Last updated: 2026-99-99\n\n## Done-when\n\n- [ ] thing\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("not a real", r.err)     # the fake date
        self.assertIn_("Scope", r.err)          # the missing scope

    def test_impossible_last_updated_is_rejected(self):
        self.led.add_plan("2026-01-05-p", status="Implementing")
        # overwrite just the date with a real-shaped but impossible one
        p = "zamm-memory/active/plans/2026-01-05-p/2026-01-05-p.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Last updated: 2026-01-05", "Last updated: 2026-02-30"))
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("not a real", r.err)

    def test_a_real_leap_day_last_updated_is_accepted(self):
        """The date check must not be over-broad."""
        self.led.add_plan("2024-02-29-leap", status="Implementing")
        p = "zamm-memory/active/plans/2024-02-29-leap/2024-02-29-leap.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Last updated: 2026-01-05", "Last updated: 2024-02-29"))
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_missing_scope_is_rejected_once_implementing(self):
        self._write_plan(
            "2026-01-05-noscope",
            "# N\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: gecko\n"
            "Last updated: 2026-01-05\n\n## Done-when\n\n- [ ] thing\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Scope", r.err)

    def test_empty_scope_scaffolding_is_rejected(self):
        """A `Scope:` with only the bare `* In:` / `* Out:` markers is empty."""
        self._write_plan(
            "2026-01-05-bare",
            "# B\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: gecko\n"
            "Last updated: 2026-01-05\n\nScope:\n* In:\n* Out:\n\n"
            "## Done-when\n\n- [ ] thing\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Scope", r.err)

    def test_no_done_when_items_is_rejected(self):
        self._write_plan(
            "2026-01-05-empty-dw",
            "# E\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: gecko\n"
            "Last updated: 2026-01-05\n\nScope:\n* In: real work.\n* Out: no.\n\n"
            "## Done-when\n\n(nothing yet)\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Done-when", r.err)

    def test_bogus_complexity_forecast_is_rejected(self):
        self._write_plan(
            "2026-01-05-animal",
            "# A\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: velociraptor\n"
            "Last updated: 2026-01-05\n\nScope:\n* In: work.\n* Out: no.\n\n"
            "## Done-when\n\n- [ ] thing\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("animal scale", r.err)

    def test_bogus_complexity_delta_is_rejected(self):
        self.led.add_plan("2026-01-05-rev", status="Review")
        p = "zamm-memory/active/plans/2026-01-05-rev/2026-01-05-rev.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Complexity-delta: as-expected", "Complexity-delta: sideways"))
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Complexity-delta", r.err)

    def test_bogus_complexity_felt_is_rejected(self):
        self.led.add_plan("2026-01-05-rev2", status="Review")
        p = "zamm-memory/active/plans/2026-01-05-rev2/2026-01-05-rev2.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Complexity-felt: gecko", "Complexity-felt: dragon"))
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("animal scale", r.err)

    def test_impossible_done_approved_at_is_rejected(self):
        self.led.add_plan("2026-01-05-done", status="Done")
        p = "zamm-memory/active/plans/2026-01-05-done/2026-01-05-done.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Done-approved-at: 2026-01-05", "Done-approved-at: 2026-13-40"))
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Done-approved-at", r.err)

    def test_the_well_formed_fixture_still_passes_and_archives(self):
        """Item 12: the strengthened fixture must remain valid end to end."""
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-good", status="Done")
        self.assertCode(self.led.plan_check(), EXIT_OK)
        self.assertCode(self.led.archive(), EXIT_OK)
        self.assertTrue(self.led.exists(
            "zamm-memory/archive/plans/2026-01-05-good"))


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


class TestPlanLookupPrecedence(ZammTest):
    """`plan show alpha` used to report an ambiguous match against `alpha` and
    `alpha-beta` because it matched by substring only. Exact id wins, then
    exact slug, and only then substring."""

    def _plan(self, slug):
        self.led.add_plan(slug, status="Implementing")

    def test_exact_slug_beats_a_longer_prefix(self):
        self._plan("2026-01-02-alpha")
        self._plan("2026-01-03-alpha-beta")

        r = self.led.plan_show("alpha")

        self.assertCode(r, EXIT_OK, r.err)
        self.assertIn_("2026-01-02-alpha", r.out)
        self.assertNotIn_("alpha-beta", r.out)

    def test_exact_id_resolves(self):
        self._plan("2026-01-02-alpha")
        self._plan("2026-01-03-alpha-beta")

        r = self.led.plan_show("2026-01-03-alpha-beta")

        self.assertCode(r, EXIT_OK, r.err)
        self.assertIn_("2026-01-03-alpha-beta", r.out)

    def test_a_genuinely_ambiguous_substring_still_lists_candidates(self):
        self._plan("2026-01-02-alpha")
        self._plan("2026-01-03-alpha-beta")
        # "al" is a substring of both and an exact id/slug of neither
        r = self.led.plan_show("al")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("matches 2 plans", r.err)
        self.assertIn_("2026-01-02-alpha", r.err)
        self.assertIn_("2026-01-03-alpha-beta", r.err)

    def test_substring_still_works_when_unambiguous(self):
        """The convenience the substring tier preserves."""
        self._plan("2026-07-20-command-surface-v2")
        r = self.led.plan_show("surface")
        self.assertCode(r, EXIT_OK, r.err)
        self.assertIn_("command-surface-v2", r.out)


class Rev2OrphanAndCrossCheck(ZammTest):
    """F3/F4: cross-check must catch a votes record naming a nonexistent plan,
    must not be fooled by an id embedded in a longer id on a supersedes line,
    and must work under a project path containing spaces."""

    def _memory(self, slug, sfx, date="2026-01-05"):
        return self.led.add(slug, f"Record {slug}.", sfx=sfx, date=date)

    def test_orphan_votes_record_fails_check(self):
        m = self._memory("real", "rrrrr")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-v-vvvvv.md",
            f"---\ntype: votes\nplan: no-such-plan\nup: {m}\ndown:\n"
            "created: 2026-01-06\nschema: 3\n---\n",
        )
        r = self.led.check_all()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("no active or archived plan", r.err)

    def test_substring_id_on_a_supersedes_line_is_not_a_false_supersede(self):
        m = self._memory("help", "22222")
        self.led.write(
            "zamm-memory/active/plans/2026-07-01-p/2026-07-01-p.plan.md",
            "# P\nStatus: Review\nExecution-context-before: x\n"
            f"Complexity-forecast: gecko\nMemory-upvotes: {m}\n"
            "Last updated: 2026-07-19\n\nScope:\n* In: x\n* Out:\n\n"
            "## Done-when\n- [x] d\n\n## Learnings\n- L.\n\n"
            "Execution-friction-after: n\nComplexity-felt: gecko\n"
            "Complexity-delta: as-expected\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-07-19-v-vvvvv.md",
            f"---\ntype: votes\nplan: 2026-07-01-p\nup: {m}\ndown:\n"
            "created: 2026-07-19\nschema: 3\n---\n",
        )
        # an unrelated record whose id EMBEDS the votes id, on a supersedes line
        base = self._memory("base", "bbbbb", date="2026-01-04")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-07-x-2026-01-05-help-22222-e-33333.md",
            f"---\ntype: tombstone\nsupersedes: {base}\n"
            "created: 2026-01-07\nschema: 3\n---\nRetires base.\n",
        )
        # the votes record must NOT be seen as superseded, so the plan reconciles
        self.assertCode(self.led.check_all(), EXIT_OK)

    def test_cross_check_survives_a_path_with_spaces(self):
        import tempfile, pathlib
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td) / "has space" / "proj"
            root.mkdir(parents=True)
            led = self.__class__().__class__  # noqa: avoid re-init; build manually
            from harness import Ledger
            led = Ledger(root)
            m = led.add("help", "Helpful.", sfx="22222")
            led.write(
                "zamm-memory/active/plans/2026-07-01-p/2026-07-01-p.plan.md",
                "# P\nStatus: Review\nExecution-context-before: x\n"
                f"Complexity-forecast: gecko\nMemory-upvotes: {m}\n"
                "Last updated: 2026-07-19\n\nScope:\n* In: x\n* Out:\n\n"
                "## Done-when\n- [x] d\n\n## Learnings\n- L.\n\n"
                "Execution-friction-after: n\nComplexity-felt: gecko\n"
                "Complexity-delta: as-expected\n",
            )
            led.write(
                "zamm-memory/knowledge/2026/2026-07-19-v-vvvvv.md",
                f"---\ntype: votes\nplan: 2026-07-01-p\nup: {m}\ndown:\n"
                "created: 2026-07-19\nschema: 3\n---\n",
            )
            self.assertCode(led.check_all(), EXIT_OK)


class Rev2AbandonWorkDone(ZammTest):
    """F6: a worked-on Abandoned plan must carry the forward-direction fields
    and a Loose-ends rationale, not only the retrospective."""

    def _plan(self, body):
        d = self.led.root / "zamm-memory/active/plans/2026-07-02-p"
        d.mkdir(parents=True)
        (d / "2026-07-02-p.plan.md").write_text(body)

    _RETRO = ("## Learnings\n- Something.\n\n"
              "Execution-friction-after: none\nComplexity-felt: gecko\n"
              "Complexity-delta: as-expected\n")

    def test_work_done_but_empty_loose_ends_fails(self):
        self._plan(
            "# P\nStatus: Abandoned\nExecution-context-before: started\n"
            "Complexity-forecast: gecko\nLast updated: 2026-07-19\n\n"
            "Scope:\n* In: x\n* Out:\n\n## Done-when\n- [x] one\n\n"
            + self._RETRO + "\n## Loose ends\n\n"
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Loose ends", r.err)

    def test_work_done_but_empty_context_and_forecast_fails(self):
        self._plan(
            "# P\nStatus: Abandoned\nExecution-context-before:\n"
            "Complexity-forecast:\nLast updated: 2026-07-19\n\n"
            "Scope:\n* In: x\n* Out:\n\n## Done-when\n- [x] one\n\n"
            + self._RETRO + "\n## Loose ends\nRan out of time.\n"
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Execution-context-before", r.err)

    def test_fully_filled_work_done_abandon_passes(self):
        self._plan(
            "# P\nStatus: Abandoned\nExecution-context-before: started\n"
            "Complexity-forecast: gecko\nLast updated: 2026-07-19\n\n"
            "Scope:\n* In: x\n* Out:\n\n## Done-when\n- [x] one\n\n"
            + self._RETRO + "\n## Loose ends\nAbandoned: superseded.\n"
        )
        self.assertCode(self.led.plan_check(), EXIT_OK)


class Rev3VoteLaundering(ZammTest):
    """PRE-FIX: agreement checking covered only ACTIVE Review/Done plans, so a
    mismatch could be laundered by abandoning the plan (Abandoned skipped) or
    archiving it (the archive tree skipped)."""

    def test_worked_abandoned_plan_declaring_votes_needs_a_votes_record(self):
        m = self.led.add("real", "R.")
        self.led.write(
            "zamm-memory/active/plans/2026-07-01-p/2026-07-01-p.plan.md",
            review_plan(m, status="Abandoned"),
        )
        r = self.led.check_all()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("no active votes record names this plan", r.err)

    def test_archived_disagreement_is_still_caught(self):
        a = self.led.add("recorda", "A.")
        b = self.led.add("recordb", "B.")
        self.led.write(
            "zamm-memory/archive/plans/2026-07-01-q/2026-07-01-q.plan.md",
            review_plan(a, status="Done"),
        )
        self.led.add("votes", type="votes", plan="2026-07-01-q", up=b,
                     date="2026-07-02", sfx="vvvvv")
        r = self.led.check_all()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Memory-upvotes disagree", r.err)

    def test_archiving_a_mismatched_plan_does_not_launder_it(self):
        m = self.led.add("real", "R.")
        # a Done plan declaring an upvote with NO votes record in the ledger
        self.led.add_plan("2026-07-01-q", status="Done")
        pf = "zamm-memory/active/plans/2026-07-01-q/2026-07-01-q.plan.md"
        self.led.write(pf, self.led.read(pf).replace(
            "Status: Done", f"Status: Done\nMemory-upvotes: {m}"))

        before = self.led.check_all()
        self.assertCode(before, EXIT_CONTRACT, "mismatch must fail while active")
        # the archive gate now refuses OUTRIGHT: the mismatch is printed and
        # the plan stays active, instead of moving it and relying on the
        # archived-tree check to keep reporting it
        arch = self.led.archive()
        self.assertNotEqual(arch.code, 0, "archive must refuse the mismatch")
        self.assertIn_("no active votes record names this plan", arch.err)
        self.assertTrue(
            (self.led.root / "zamm-memory/active/plans/2026-07-01-q").exists(),
            "the mismatched plan must stay in active/")

    def test_legacy_archived_plans_with_card_ids_still_pass(self):
        # pre-v3 archived plans declare legacy card ids (W2, S18); their votes
        # were migrated as record seeds, so there is no votes record to match
        self.led.add("real", "R.")
        self.led.write(
            "zamm-memory/archive/plans/2026-02-17-legacy/2026-02-17-legacy.plan.md",
            review_plan("W2, W3", status="Done"),
        )
        self.assertCode(self.led.check_all(), EXIT_OK)


class Rev3AbandonedScope(ZammTest):
    """PRE-FIX: Scope and Done-when validation ran only for
    Implementing|Review|Done, so a worked-on Abandoned plan with an empty
    Scope and a malformed '- [?]' checkbox passed plan check."""

    def test_worked_abandoned_with_empty_scope_and_bad_checkbox_fails(self):
        self.led.write(
            "zamm-memory/active/plans/2026-07-01-p/2026-07-01-p.plan.md",
            "# P\nStatus: Abandoned\nExecution-context-before: got started\n"
            "Complexity-forecast: gecko\nLast updated: 2026-07-19\n\n"
            "Scope:\n* In:\n* Out:\n\n"
            "## Done-when\n- [?] malformed\n\n## Learnings\n- L.\n\n"
            "## Loose ends\n\n- A rationale.\n\n"
            "Execution-friction-after: n\nComplexity-felt: gecko\n"
            "Complexity-delta: as-expected\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Scope: has no In/Out content", r.err)
        self.assertIn_("malformed checkbox", r.err)

    def test_never_started_abandoned_needs_only_the_rationale(self):
        self.led.write(
            "zamm-memory/active/plans/2026-07-01-p/2026-07-01-p.plan.md",
            "# P\nStatus: Abandoned\nLast updated: 2026-07-19\n\n"
            "## Loose ends\n\n- Decided against it before starting.\n",
        )
        self.assertCode(self.led.plan_check(), EXIT_OK)


class Rev4PlanFieldTabs(ZammTest):
    """PRE-FIX: the cross-check normalized comma/space only, so a legal TAB in
    a plan's Memory-upvotes/downvotes made semantically identical sets
    disagree with the votes record."""

    def test_tabs_in_plan_vote_fields_reconcile(self):
        a = self.led.add("reca", "A.")
        b = self.led.add("recb", "B.")
        c = self.led.add("recc", "C.")
        self.led.write(
            "zamm-memory/active/plans/2026-07-01-p/2026-07-01-p.plan.md",
            review_plan(f"{a},\t{b}",
                        extra_head=f"Memory-downvotes: {c}\t\n"),
        )
        # same sets, different order and separators, on the ledger side
        self.led.add("votes", type="votes", plan="2026-07-01-p",
                     up=f"{b}, {a}", down=c, date="2026-07-02", sfx="vvvvv")
        self.assertCode(self.led.check_all(), EXIT_OK)


class TestPlanVotesCrossCheck(ZammTest):
    def _review_plan(self, upvotes=""):
        line = f"Memory-upvotes: {upvotes}\n" if upvotes else ""
        self.led.write(
            "zamm-memory/active/plans/2026-07-01-p/2026-07-01-p.plan.md",
            "# A review plan\nStatus: Review\n"
            "Execution-context-before: work\nComplexity-forecast: gecko\n"
            f"{line}Last updated: 2026-07-19\n\nScope:\n* In: stuff\n* Out:\n\n"
            "## Done-when\n- [x] done\n\n## Learnings\n- Durable.\n\n"
            "Execution-friction-after: none\nComplexity-felt: gecko\n"
            "Complexity-delta: as-expected\n",
        )

    def test_plan_upvote_without_a_votes_record_fails(self):
        helpful = self.led.add("help", "A helpful record.")
        self._review_plan(upvotes=helpful)
        r = self.led.check_all()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("no active votes record", r.err)

    def test_matching_votes_record_passes(self):
        helpful = self.led.add("help", "A helpful record.")
        self._review_plan(upvotes=helpful)
        self.led.write(
            "zamm-memory/knowledge/2026/2026-07-19-v-vvvvv.md",
            f"---\ntype: votes\nplan: 2026-07-01-p\nup: {helpful}\ndown:\n"
            "created: 2026-07-19\nschema: 3\n---\n",
        )
        self.assertCode(self.led.check_all(), EXIT_OK)

    def test_votes_record_disagreeing_with_the_plan_fails(self):
        helpful = self.led.add("help", "A helpful record.")
        other = self.led.add("other", "A different record.")
        self._review_plan(upvotes=helpful)
        self.led.write(
            "zamm-memory/knowledge/2026/2026-07-19-v-vvvvv.md",
            f"---\ntype: votes\nplan: 2026-07-01-p\nup: {other}\ndown:\n"
            "created: 2026-07-19\nschema: 3\n---\n",
        )
        r = self.led.check_all()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("disagree", r.err)


class TestAbandonHeuristic(ZammTest):
    """PRE-FIX: the checker required the full retrospective for EVERY
    Abandoned plan, so the documented Draft->Abandoned (rationale under
    Loose ends, no work done) failed four unrelated checks."""

    def _plan(self, body):
        d = self.led.root / "zamm-memory/active/plans/2026-07-02-p"
        d.mkdir(parents=True)
        (d / "2026-07-02-p.plan.md").write_text(body)

    def test_never_started_draft_abandon_passes_with_only_a_rationale(self):
        self._plan(
            "# A draft we dropped\nStatus: Abandoned\n"
            "Last updated: 2026-07-19\n\nScope:\n* In:\n* Out:\n\n"
            "## Done-when\n- [ ] never started\n\n## Learnings\n\n"
            "## Loose ends\nDropped at draft stage: superseded by the new roadmap.\n"
        )
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_never_started_draft_abandon_still_needs_a_rationale(self):
        self._plan(
            "# A draft we dropped\nStatus: Abandoned\n"
            "Last updated: 2026-07-19\n\nScope:\n* In:\n* Out:\n\n"
            "## Done-when\n- [ ] never started\n\n## Learnings\n\n"
            "## Loose ends\n- (none yet)\n"
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Loose ends", r.err)

    def test_work_done_abandon_still_requires_the_retrospective(self):
        self._plan(
            "# Abandoned mid-flight\nStatus: Abandoned\n"
            "Execution-context-before: started the parser refactor\n"
            "Complexity-forecast: gecko\nLast updated: 2026-07-19\n\n"
            "Scope:\n* In: parser\n* Out:\n\n## Done-when\n- [x] first step\n\n"
            "## Learnings\n\n## Loose ends\nRan out of scope.\n"
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Execution-friction-after", r.err)


if __name__ == "__main__":
    unittest.main()
