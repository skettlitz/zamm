"""The Blocked plan status: the block log, its invariant, and the two verbs.

Blocked is how an agent tells the rest of the team — human and agent — that it
cannot continue and the reason will outlive the session. Three things have to
hold for that to be worth anything:

  * the reason is REQUIRED and CLASSED, so a blocked plan always says what
    stopped it and who clears it;
  * the reason reaches the DIGEST, ranked above Review, because a reason
    nobody reads is a reason nobody acts on;
  * `Blocked` and "an open entry in the log" are the same fact, checked from
    the file alone — which is what makes "unblock without recording the
    resolution" impossible to express.

See references/plans-maintenance.md for the protocol these tests protect.
"""

import tempfile

from harness import EXIT_CONTRACT, EXIT_OK, Ledger, ZammTest

def fresh(case):
    """A second ledger in its own tree, cleaned up with the test."""
    tmp = tempfile.TemporaryDirectory()
    case.addCleanup(tmp.cleanup)
    return Ledger(tmp.name)


PLAN = "zamm-memory/active/plans/{0}/{0}.plan.md"


class TestBlockedInvariant(ZammTest):
    """`plan check` validates a SNAPSHOT, never a history. Blocked requires an
    open entry and every other status requires none: that one pair is what
    makes the resolution impossible to skip, needs no transition log, and lets
    several simultaneous blocks work with no extra machinery."""

    def test_blocked_without_an_open_entry_is_rejected(self):
        self.led.add_plan("2026-01-05-b", status="Blocked", valid=False)
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("no open entry", r.err)

    def test_blocked_with_an_open_entry_passes(self):
        self.led.add_plan("2026-01-05-b", status="Blocked")
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_an_open_entry_under_any_other_status_is_rejected(self):
        """The half of the invariant that forbids a silent unblock.

        Abandoned is excluded on purpose and covered below: it is the one
        status that may carry an open entry, because it is where a block that
        never cleared is closed out."""
        for status in ("Implementing", "Review", "Done", "Draft"):
            with self.subTest(status=status):
                led = fresh(self)
                led.add_plan("2026-01-05-p", status=status)
                p = PLAN.format("2026-01-05-p")
                led.write(p, led.read(p) + (
                    "\n## Blocked-on\n\n"
                    "- 2026-01-05 [human]: Still open.\n"))
                r = led.plan_check()
                self.assertCode(r, EXIT_CONTRACT)
                self.assertIn_("open entry", r.err)

    def test_a_fully_resolved_log_is_legal_in_any_status(self):
        """The log is execution telemetry and travels with the plan; only OPEN
        entries constrain the status."""
        self.led.add_plan("2026-01-05-p", status="Review")
        p = PLAN.format("2026-01-05-p")
        self.led.write(p, self.led.read(p) + (
            "\n## Blocked-on\n\n"
            "- 2026-01-05 [human]: Needed a ruling.\n"
            "  Resolved 2026-01-06: got the ruling.\n"))
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_blocked_is_not_terminal_so_it_is_never_archive_ready(self):
        self.led.add_plan("2026-01-05-b", status="Blocked")
        r = self.led.archive("--list")
        self.assertNotIn("2026-01-05-b", r.out)

    def test_blocked_carries_what_implementing_carries(self):
        """A blocked plan passed through Implementing, so its requirements
        cannot be dodged by blocking."""
        self.led.write(PLAN.format("2026-01-05-b"),
                       "# B\n\nStatus: Blocked\nLast updated: 2026-01-05\n\n"
                       "## Blocked-on\n\n- 2026-01-05 [human]: Stuck.\n")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Execution-context-before", r.err)
        self.assertIn_("Scope", r.err)


class TestBlockClasses(ZammTest):
    """The class says WHO CLEARS THE BLOCK — the one thing a reader needs in
    order to know whether it is their move. It is required, never defaulted:
    a default is a class nobody thinks about."""

    def _with_log(self, entry, status="Blocked"):
        self.led.add_plan("2026-01-05-b", status=status, valid=False)
        p = PLAN.format("2026-01-05-b")
        body = self.led.read(p).replace(
            "Status: Blocked",
            "Status: Blocked\nExecution-context-before: x\n"
            "Complexity-forecast: gecko")
        self.led.write(p, body +
                       "\nScope:\n* In: a thing.\n* Out: nothing.\n"
                       "\n## Blocked-on\n\n" + entry + "\n")
        return self.led.plan_check()

    def test_every_named_class_is_accepted(self):
        for kind in ("human", "external", "defect"):
            with self.subTest(kind=kind):
                led = fresh(self)
                led.add_plan("2026-01-05-b", status="Blocked",
                             blocked_kind=kind)
                self.assertCode(led.plan_check(), EXIT_OK)

    def test_an_unclassified_entry_is_rejected(self):
        r = self._with_log("- 2026-01-05: no class here.")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("has no class", r.err)

    def test_an_unknown_class_is_rejected(self):
        r = self._with_log("- 2026-01-05 [stuck]: bad class.")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_('unknown class "stuck"', r.err)

    def test_the_plan_class_must_name_a_plan(self):
        r = self._with_log("- 2026-01-05 [plan]: which plan?")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("must name the plan", r.err)

    def test_an_entry_with_no_reason_sentence_is_rejected(self):
        r = self._with_log("- 2026-01-05 [human]:")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("no reason sentence", r.err)

    def test_an_unclassified_open_entry_still_counts_as_open(self):
        """A malformed class must not also make the entry invisible to the
        invariant — tab is IFS whitespace, and an empty class field used to
        collapse into its neighbour and shift every field after it."""
        r = self._with_log("- 2026-01-05: no class here.",
                           status="Implementing")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("open entry", r.err)

    def test_prose_in_the_section_is_not_mistaken_for_an_entry(self):
        led = fresh(self)
        led.add_plan("2026-01-05-b", status="Blocked")
        p = PLAN.format("2026-01-05-b")
        led.write(p, led.read(p) + "- 2026-01-05 was when we first hit this.\n")
        self.assertCode(led.plan_check(), EXIT_OK)


class TestPlanDependency(ZammTest):
    """`[plan:<id>]` is spelled differently from the other classes because it
    is machine-checkable — and the payoff is the warning below: a dependency
    that lands is exactly the one nobody notices."""

    def _blocked_on(self, dep):
        self.led.add_plan("2026-01-05-b", status="Blocked",
                          blocked_kind=f"plan:{dep}")

    def test_a_dangling_dependency_is_rejected(self):
        self._blocked_on("2026-01-05-ghost")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("names a plan that does not exist", r.err)

    def test_a_live_dependency_is_accepted_quietly(self):
        self.led.add_plan("2026-01-05-dep", status="Implementing")
        self._blocked_on("2026-01-05-dep")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_OK)
        self.assertNotIn("dependency landed", r.err)

    def test_a_plan_cannot_wait_on_itself(self):
        self.led.add_plan("2026-01-05-b", status="Blocked",
                          blocked_kind="plan:2026-01-05-b")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("waits on itself", r.err)

    def test_a_landed_dependency_is_reported(self):
        """The whole reason this class exists."""
        self.led.add_plan("2026-01-05-dep", status="Done")
        self._blocked_on("2026-01-05-dep")
        r = self.led.plan_check()
        self.assertCode(r, EXIT_OK)          # advisory, never a failure
        self.assertIn_("the dependency landed", r.err)

    def test_an_archived_dependency_is_reported(self):
        self.led.add_plan("2026-01-05-dep", status="Done")
        self._blocked_on("2026-01-05-dep")
        self.assertCode(self.led.archive(), EXIT_OK)
        r = self.led.plan_check()
        self.assertIn_("which is archived", r.err)

    def test_a_resolved_entry_against_a_landed_plan_is_silent(self):
        """Only OPEN entries can be waiting on anything."""
        self.led.add_plan("2026-01-05-dep", status="Done")
        self.led.add_plan("2026-01-05-p", status="Implementing")
        p = PLAN.format("2026-01-05-p")
        self.led.write(p, self.led.read(p) + (
            "\n## Blocked-on\n\n"
            "- 2026-01-05 [plan:2026-01-05-dep]: waited on it.\n"
            "  Resolved 2026-01-06: it landed.\n"))
        r = self.led.plan_check()
        self.assertNotIn("dependency landed", r.err)


class TestStaleness(ZammTest):
    """Blocked is the only non-terminal status nothing pushes forward, so age
    is the only pressure on it. One threshold for every class would cry wolf:
    an unanswered question at a week means someone dropped it; an upstream
    release at a week is just Tuesday."""

    # PINNED_TODAY is 2026-07-19; these dates sit either side of each nag.
    def _age(self, kind, since):
        led = fresh(self)
        led.add_plan("2026-01-05-b", status="Blocked",
                     blocked_kind=kind, blocked_since=since)
        return led.plan_check()

    def test_a_fresh_block_of_every_class_is_quiet(self):
        for kind in ("human", "external", "defect"):
            with self.subTest(kind=kind):
                r = self._age(kind, "2026-07-18")
                self.assertCode(r, EXIT_OK)
                self.assertNotIn("unblock or abandon", r.err)

    def test_a_human_block_nags_at_seven_days(self):
        r = self._age("human", "2026-07-12")
        self.assertIn_("blocked 7 days on [human]", r.err)
        self.assertCode(r, EXIT_OK)          # advisory, never a failure

    def test_an_external_block_is_still_quiet_at_seven_days(self):
        """The point of per-class thresholds."""
        r = self._age("external", "2026-07-12")
        self.assertNotIn("unblock or abandon", r.err)

    def test_an_external_block_nags_at_thirty_days(self):
        r = self._age("external", "2026-06-19")
        self.assertIn_("blocked 30 days on [external]", r.err)

    def test_a_future_dated_block_never_reads_as_stale(self):
        r = self._age("human", "2026-08-01")
        self.assertNotIn("unblock or abandon", r.err)


class TestDigestTail(ZammTest):
    """A reason nobody reads is a reason nobody acts on."""

    def test_a_blocked_plan_leads_the_tail_with_its_reason(self):
        self.led.add_plan("2026-01-05-b", status="Blocked",
                          title="Blocked work")
        self.assertCode(self.led.compile(), EXIT_OK)
        tail = self.led.digest().split("## Plans")[1]
        self.assertIn("- Blocked: 2026-01-05-b", tail)
        self.assertIn("blocked[human]: Synthetic obstruction", tail)
        self.assertIn("blocked 195d", tail)   # 2026-01-05 -> PINNED_TODAY

    def test_blocked_outranks_review(self):
        self.led.add_plan("2026-01-05-r", status="Review")
        self.led.add_plan("2026-01-05-b", status="Blocked")
        self.assertCode(self.led.compile(), EXIT_OK)
        tail = self.led.digest().split("## Plans")[1]
        self.assertLess(tail.index("- Blocked:"), tail.index("- Review:"))

    def test_every_open_block_is_rendered_and_resolved_ones_are_not(self):
        self.led.add_plan("2026-01-05-b", status="Blocked")
        p = PLAN.format("2026-01-05-b")
        self.led.write(p, self.led.read(p) + (
            "- 2026-01-06 [external]: Upstream release pending.\n"
            "- 2026-01-07 [defect]: Already handled.\n"
            "  Resolved 2026-01-08: fixed upstream.\n"))
        self.assertCode(self.led.compile(), EXIT_OK)
        tail = self.led.digest().split("## Plans")[1]
        self.assertIn("blocked[external]: Upstream release pending.", tail)
        self.assertNotIn("Already handled", tail)

    def test_a_plan_with_no_block_log_renders_exactly_as_before(self):
        self.led.add_plan("2026-01-05-p", status="Implementing")
        self.assertCode(self.led.compile(), EXIT_OK)
        tail = self.led.digest().split("## Plans")[1]
        self.assertNotIn("blocked", tail)

    def test_plan_list_groups_blocked(self):
        self.led.add_plan("2026-01-05-b", status="Blocked")
        r = self.led.plan_list()
        self.assertCode(r, EXIT_OK)
        self.assertIn("Blocked: 1", r.out)


class TestBlockVerb(ZammTest):
    """Entering Blocked costs one sentence and nothing else, on purpose: a
    transition that costs anything at the moment you hit a wall is a
    transition nobody makes."""

    def setUp(self):
        super().setUp()
        self.led.add_plan("2026-01-05-p", status="Implementing")
        self.p = PLAN.format("2026-01-05-p")

    def test_a_block_lands_and_flips_the_status(self):
        r = self.led.plan_block("--kind", "human", "2026-01-05-p",
                                "Need a ruling on the cache policy.", stdin="")
        self.assertCode(r, EXIT_OK)
        body = self.led.read(self.p)
        self.assertIn("Status: Blocked", body)
        self.assertIn("- 2026-07-19 [human]: Need a ruling on the cache policy.",
                      body)
        self.assertIn("Last updated: 2026-07-19", body)
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_the_detail_paragraph_arrives_on_stdin(self):
        r = self.led.plan_block("--kind", "defect", "2026-01-05-p",
                                "Shard reader returns stale offsets.",
                                stdin="Tried pinning 0.8; the API is 0.9 only.\n")
        self.assertCode(r, EXIT_OK)
        self.assertIn("  Tried pinning 0.8; the API is 0.9 only.",
                      self.led.read(self.p))

    def test_the_class_is_required(self):
        r = self.led.plan_block("2026-01-05-p", "No class given.", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("--kind is required", r.err)
        self.assertIn("Status: Implementing", self.led.read(self.p))

    def test_an_unknown_class_is_refused(self):
        r = self.led.plan_block("--kind", "stuck", "2026-01-05-p", "x", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("unknown --kind", r.err)

    def test_kind_plan_must_name_its_dependency(self):
        r = self.led.plan_block("--kind", "plan", "2026-01-05-p", "x", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("--on <plan-id>", r.err)

    def test_on_belongs_only_to_kind_plan(self):
        r = self.led.plan_block("--kind", "human", "--on", "2026-01-05-p",
                                "2026-01-05-p", "x", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("belongs only to --kind plan", r.err)

    def test_a_dangling_dependency_fails_before_the_file_is_touched(self):
        r = self.led.plan_block("--kind", "plan", "--on", "nope",
                                "2026-01-05-p", "x", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn("Status: Implementing", self.led.read(self.p))

    def test_a_dependency_is_recorded_by_its_canonical_id(self):
        self.led.add_plan("2026-01-05-dep", status="Implementing")
        r = self.led.plan_block("--kind", "plan", "--on", "dep",
                                "2026-01-05-p", "Waiting on the writer.",
                                stdin="")
        self.assertCode(r, EXIT_OK)
        self.assertIn("[plan:2026-01-05-dep]:", self.led.read(self.p))

    def test_a_plan_cannot_block_on_itself(self):
        r = self.led.plan_block("--kind", "plan", "--on", "2026-01-05-p",
                                "2026-01-05-p", "x", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("cannot wait on itself", r.err)

    def test_blocking_is_refused_from_every_status_but_implementing(self):
        for status, needle in (("Draft", "is a Draft"),
                               ("Review", "in Review"),
                               ("Done", "terminal"),
                               ("Abandoned", "terminal")):
            with self.subTest(status=status):
                led = fresh(self)
                led.add_plan("2026-01-05-q", status=status)
                r = led.plan_block("--kind", "human", "2026-01-05-q", "x",
                                   stdin="")
                self.assertCode(r, EXIT_CONTRACT)
                self.assertIn_(needle, r.err)

    def test_a_second_independent_block_is_allowed(self):
        self.assertCode(self.led.plan_block(
            "--kind", "human", "2026-01-05-p", "First.", stdin=""), EXIT_OK)
        self.assertCode(self.led.plan_block(
            "--kind", "external", "2026-01-05-p", "Second.", stdin=""), EXIT_OK)
        body = self.led.read(self.p)
        self.assertIn("[human]: First.", body)
        self.assertIn("[external]: Second.", body)
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_a_multi_line_sentence_is_refused(self):
        r = self.led.plan_block("--kind", "human", "2026-01-05-p",
                                "One.\nTwo.", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("single line", r.err)

    def test_the_sentence_survives_backslashes_and_quotes(self):
        """It travels through the environment, not `awk -v`, which would run
        escape processing over it."""
        r = self.led.plan_block("--kind", "human", "2026-01-05-p",
                                r"Path C:\tmp\new breaks it; 'quoted' too.",
                                stdin="")
        self.assertCode(r, EXIT_OK)
        self.assertIn(r"Path C:\tmp\new breaks it; 'quoted' too.",
                      self.led.read(self.p))

    def test_an_archived_plan_cannot_be_blocked(self):
        self.led.add_plan("2026-01-05-old", status="Done")
        self.assertCode(self.led.archive(), EXIT_OK)
        r = self.led.plan_block("--kind", "human", "2026-01-05-old", "x",
                                stdin="")
        self.assertCode(r, EXIT_CONTRACT)


class TestUnblockVerb(ZammTest):
    """Leaving Blocked costs one sentence too — and the resolution cannot be
    skipped, because the invariant refuses an Implementing plan with an open
    entry."""

    def setUp(self):
        super().setUp()
        self.led.add_plan("2026-01-05-p", status="Implementing")
        self.p = PLAN.format("2026-01-05-p")
        self.led.plan_block("--kind", "human", "2026-01-05-p",
                            "Need a ruling.", stdin="")

    def test_unblocking_resolves_the_entry_and_restores_implementing(self):
        r = self.led.plan_unblock("2026-01-05-p", "Got the ruling.", stdin="")
        self.assertCode(r, EXIT_OK)
        body = self.led.read(self.p)
        self.assertIn("Status: Implementing", body)
        self.assertIn("  Resolved 2026-07-19: Got the ruling.", body)
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_the_original_entry_is_never_deleted(self):
        self.led.plan_unblock("2026-01-05-p", "Got the ruling.", stdin="")
        self.assertIn("[human]: Need a ruling.", self.led.read(self.p))

    def test_unblocking_a_plan_that_is_not_blocked_is_refused(self):
        self.led.plan_unblock("2026-01-05-p", "Got the ruling.", stdin="")
        r = self.led.plan_unblock("2026-01-05-p", "Again.", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("nothing to clear", r.err)

    def test_two_open_blocks_refuse_one_resolution_sentence(self):
        self.led.plan_block("--kind", "external", "2026-01-05-p", "Second.",
                            stdin="")
        r = self.led.plan_unblock("2026-01-05-p", "Both cleared.", stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("has 2 open blocks", r.err)
        self.assertIn_("[external]", r.err)
        self.assertIn("Status: Blocked", self.led.read(self.p))

    def test_all_clears_every_open_block(self):
        self.led.plan_block("--kind", "external", "2026-01-05-p", "Second.",
                            stdin="")
        r = self.led.plan_unblock("--all", "2026-01-05-p", "Both cleared.",
                                  stdin="")
        self.assertCode(r, EXIT_OK)
        body = self.led.read(self.p)
        self.assertEqual(2, body.count("Resolved 2026-07-19: Both cleared."))
        self.assertIn("Status: Implementing", body)
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_a_block_unblock_round_trip_leaves_a_valid_plan(self):
        for i in range(3):
            self.led.plan_unblock("2026-01-05-p", f"Cleared {i}.", stdin="")
            self.assertCode(self.led.plan_check(), EXIT_OK)
            self.led.plan_block("--kind", "defect", "2026-01-05-p",
                                f"Blocked again {i}.", stdin="")
            self.assertCode(self.led.plan_check(), EXIT_OK)
        self.assertEqual(4, self.led.read(self.p).count("- 2026-07-19 ["))


class TestBlockLogPlacement(ZammTest):
    """`plan block` has to find the existing log wherever the author put it.
    Deciding that from a single pass means guessing at `## Learnings` whether
    a `## Blocked-on` follows; guessing wrong gave a plan BOTH a freshly
    inserted section and an append to its real one — two open blocks from one
    `plan block`, after which `plan unblock` refused without `--all`."""

    def _plan_with_log_after_learnings(self):
        self.led.add_plan("2026-01-05-p", status="Implementing")
        p = PLAN.format("2026-01-05-p")
        self.led.write(p, self.led.read(p) +
                       "\n## Learnings\n\n- nothing yet\n"
                       "\n## Blocked-on\n\n- (no blocks recorded)\n")
        return p

    def test_a_log_after_learnings_is_used_not_duplicated(self):
        p = self._plan_with_log_after_learnings()
        r = self.led.plan_block("--kind", "human", "2026-01-05-p",
                                "Only one block.", stdin="")
        self.assertCode(r, EXIT_OK)
        body = self.led.read(p)
        self.assertEqual(1, body.count("## Blocked-on"))
        self.assertEqual(1, body.count("[human]: Only one block."))
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_that_plan_then_unblocks_without_all(self):
        """The user-visible symptom of the duplicate: one block went in, so
        one sentence must be able to clear it."""
        self._plan_with_log_after_learnings()
        self.led.plan_block("--kind", "human", "2026-01-05-p", "One.", stdin="")
        r = self.led.plan_unblock("2026-01-05-p", "Cleared.", stdin="")
        self.assertCode(r, EXIT_OK)
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_a_plan_with_no_log_at_all_gets_one(self):
        """The insertion path still has to work — the fix must not have turned
        it off for plans that predate the section."""
        self.led.add_plan("2026-01-05-q", status="Implementing")
        p = PLAN.format("2026-01-05-q")
        self.assertNotIn("## Blocked-on", self.led.read(p))
        r = self.led.plan_block("--kind", "defect", "2026-01-05-q",
                                "Something is broken.", stdin="")
        self.assertCode(r, EXIT_OK)
        body = self.led.read(p)
        self.assertEqual(1, body.count("## Blocked-on"))
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_the_archived_plan_message_has_no_stray_escape(self):
        """`\\e` is not an escape in double quotes, so the refusal printed a
        literal backslash at the reader."""
        self.led.add_plan("2026-01-05-old", status="Done")
        self.assertCode(self.led.archive(), EXIT_OK)
        r = self.led.plan_block("--kind", "human", "2026-01-05-old", "x",
                                stdin="")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertNotIn("\\", r.err)


class TestBlockedToAbandoned(ZammTest):
    """`Blocked -> Abandoned` is a documented transition, so it has to be
    reachable without hand-editing the file.

    It was not. `plan check` rejected an Abandoned plan carrying an open
    entry, `plan archive` refuses anything that fails `plan check`, and the
    remedy the error named — `plan unblock` — dies on a plan that is no longer
    Blocked. The only escapes were a hand-edit or an un-abandon/unblock/
    re-abandon dance, and both of them make the log lie: `plan unblock` writes
    a `Resolved` line, and nothing resolved. The obstruction is why the plan
    died; it stays open, and Abandoned is the one status that allows that."""

    def _abandoned_still_blocked(self, led=None, kind="human"):
        led = led or self.led
        led.add_plan("2026-01-05-fatal", status="Blocked", blocked_kind=kind)
        p = PLAN.format("2026-01-05-fatal")
        body = led.read(p).replace("Status: Blocked", "Status: Abandoned")
        # what Implementing -> Abandoned requires, which Blocked -> Abandoned
        # inherits: a blocked plan already passed through Implementing
        body += ("\n## Learnings\n\n- The obstruction proved fatal.\n"
                 "\n## Loose ends\n\n- Abandoned; nothing to clean up.\n"
                 "\nExecution-friction-after: waited on an answer that never came\n"
                 "Complexity-felt: gecko\n"
                 "Complexity-delta: as-expected\n")
        led.write(p, body)
        return led, p

    def test_an_abandoned_plan_may_keep_its_open_block(self):
        led, _ = self._abandoned_still_blocked()
        self.assertCode(led.plan_check(), EXIT_OK)

    def test_it_archives(self):
        """The consequence that made the gap matter: archive refuses anything
        failing plan check, so a fatally blocked plan could never be filed."""
        led, _ = self._abandoned_still_blocked()
        self.assertCode(led.zamm("plan", "archive"), EXIT_OK)

    def test_the_open_entry_survives_the_abandonment(self):
        """The entry is the record of why the plan died; deleting it, or
        writing a Resolved line over it, is the failure mode the exemption
        exists to prevent."""
        led, p = self._abandoned_still_blocked()
        self.assertCode(led.zamm("plan", "archive"), EXIT_OK)
        arch = led.read(p.replace("active/", "archive/"))
        self.assertIn("[human]: Synthetic obstruction", arch)
        self.assertNotIn("Resolved", arch)

    def test_it_does_not_nag_about_a_dependency_that_landed(self):
        """`plan check` warns a BLOCKED plan when the plan it waits on lands,
        because that is advice to act. An abandoned plan keeps its entry open
        forever by design and nobody is waiting, so the same warning there is
        noise pointing at a verb that would refuse."""
        led = fresh(self)
        led.add_plan("2026-01-04-dep", status="Done")
        self._abandoned_still_blocked(led, kind="plan:2026-01-04-dep")
        r = led.plan_check()
        self.assertCode(r, EXIT_OK)
        self.assertNotIn("the dependency landed", r.err)

    def test_a_blocked_plan_still_nags_about_it(self):
        """The other side of that gate: the warning is the payoff of the
        machine-checkable plan class, so it must still fire where it helps."""
        led = fresh(self)
        led.add_plan("2026-01-04-dep", status="Done")
        led.add_plan("2026-01-05-w", status="Blocked",
                     blocked_kind="plan:2026-01-04-dep")
        r = led.plan_check()
        self.assertIn_("the dependency landed", r.err)

    def test_the_rejection_elsewhere_names_abandoned_as_a_way_out(self):
        """The old message offered only `plan unblock`, which is exactly the
        wrong verb when the obstruction was fatal."""
        led = fresh(self)
        led.add_plan("2026-01-05-i", status="Implementing")
        p = PLAN.format("2026-01-05-i")
        led.write(p, led.read(p) +
                  "\n## Blocked-on\n\n- 2026-01-05 [human]: Still open.\n")
        r = led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Abandoned", r.err)


class TestBlockedIsCountedLikeEveryOtherStatus(ZammTest):
    """Blocked arrived after the status tally was written, and the tally
    listed the five statuses it knew. A blocked plan therefore counted as
    nothing: `status` reported "none active" over a project whose only plan
    was stuck waiting on a human — the one state that must never look idle.
    """

    def test_status_counts_a_blocked_plan(self):
        self.led.add_plan("2026-01-05-stuck", status="Blocked")

        r = self.led.status()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("1 blocked", r.out)
        self.assertNotIn("none active", r.out)

    def test_status_counts_blocked_alongside_the_others(self):
        self.led.add_plan("2026-01-05-stuck", status="Blocked")
        self.led.add_plan("2026-01-06-going", status="Implementing")

        out = self.led.status().out

        self.assertIn_("1 implementing", out)
        self.assertIn_("1 blocked", out)
