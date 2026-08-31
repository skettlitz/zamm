"""The backlog: ideas as ordinary records in a third tree.

Latent intentions live in zamm-memory/backlog/ — same record contract, same
compiler — rendered into a PULLED lens (backlog list) instead of the pushed
session digest. The knowledge digest's entire standing exposure is one
summary line plus the small marked lane. These suites lock the tree's policy
switches (no guardrails, plan-less triage votes, no OTHER_MAX), the
uncapped lens, the marked-lane semantics (inheritance included), the
digest coupling, and the promote flow's rerun convergence (guarantee 2).
"""

import os
import re
import time

from harness import (
    EXIT_DEGRADED,
    EXIT_OK,
    EXIT_REFUSED_PUBLISH,
    EXIT_UNREADABLE,
    ZammTest,
    needs_permission_bits,
)


def knowledge_view(digest_text):
    """memory.md with the backlog-owned parts stripped.

    The digest legitimately changes its Backlog line and Marked section when
    ideas change, so knowledge-isolation assertions must normalize — a raw
    byte comparison would fail on the summary count alone, and a substring
    check would miss content smuggled elsewhere.
    """
    out, skipping = [], False
    for ln in digest_text.splitlines():
        if ln.startswith("## Marked backlog"):
            skipping = True
            continue
        if skipping:
            # the marked section ends where the summary line begins
            if ln.startswith("Backlog:"):
                skipping = False
            continue
        if ln.startswith("Backlog:") or ln.startswith("<!-- zamm-generation:"):
            continue
        out.append(ln)
    # the blank separator ahead of the Backlog line is backlog-owned too
    return "\n".join(out).rstrip("\n")


class TestBacklogLens(ZammTest):
    """The pulled lens: uncapped, hot-to-cold, dormant collapsed."""

    def test_lens_is_uncapped(self):
        """More live ideas than the knowledge HEADLINE_MAX (150) — every one
        is listed. The lens is pulled by someone in triage mode, and a triage
        read wants the whole live list; decay is the only cap."""
        for i in range(160):
            self.led.add_idea(f"idea{i}", f"Idea number {i}.")

        r = self.led.backlog("list")

        self.assertCode(r, EXIT_OK)
        listed = len(re.findall(r"^- ", r.out, flags=re.M))
        self.assertEqual(listed, 160, "every live idea must be listed")

    def test_dormant_ideas_collapse_to_counts(self):
        """A cooled idea leaves the listing but not the ledger."""
        self.led.add_idea("hot-idea", "A fresh idea.", date="2026-07-18")
        cold = self.led.add_idea("cold-idea", "An old whisper.",
                                 date="2026-01-05", importance="minor",
                                 durability="days")

        r = self.led.backlog("list")

        self.assertCode(r, EXIT_OK)
        self.assertNotIn_(cold, r.out, "a dormant idea is counted, not listed")
        self.assertIn_("Dormant", r.out)

    def test_list_all_names_the_dormant_ids(self):
        """Deep triage and resurrection need the ids without resorting to
        grep."""
        self.led.add_idea("hot-idea", "A fresh idea.", date="2026-07-18")
        cold = self.led.add_idea("cold-idea", "An old whisper.",
                                 date="2026-01-05", importance="minor",
                                 durability="days")

        r = self.led.backlog("list", "--all")

        self.assertCode(r, EXIT_OK)
        self.assertIn_(cold, r.out, "--all must name dormant ids")

    def test_lens_groups_by_area_hot_first(self):
        self.led.add_idea("tool-idea", "A tooling idea.", scope="tooling",
                          date="2026-07-18")
        self.led.add_idea("domain-idea", "A domain idea.", scope="domain",
                          date="2026-07-18")

        r = self.led.backlog("list")

        self.assertIn_("### tooling", r.out)
        self.assertIn_("### domain", r.out)

    def test_treeless_project_lists_a_clean_empty_backlog(self):
        """Absence is data: a project that never captured an idea is not a
        gap to report, and unlike the knowledge compile this is exit 0."""
        r = self.led.backlog("list")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("empty", r.out)

        r = self.led.backlog("check")
        self.assertCode(r, EXIT_OK, "nothing to check is not a failure")

    @needs_permission_bits
    def test_an_unreadable_backlog_tree_fails_closed(self):
        self.led.add_idea("an-idea", "A statement.")
        locked = self.led.root / "zamm-memory/backlog/2026"
        os.chmod(locked, 0o000)
        try:
            r = self.led.backlog("list")
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(r, EXIT_UNREADABLE)

    def test_all_quarantined_refuses_to_publish(self):
        """Same taxonomy as the digest: zero live plus quarantined must not
        read as an empty backlog."""
        self.led.write("zamm-memory/backlog/2026/2026-01-05-broken-abcde.md",
                       "---\ntype: memory\nscope: tooling\ncreated: 2026-01-05\n"
                       "schema: 9\n---\n\nBroken.\n")
        r = self.led.backlog("list")
        self.assertCode(r, EXIT_REFUSED_PUBLISH)


class TestBacklogPolicy(ZammTest):
    """Per-tree policy switches, locked in BOTH directions."""

    def test_guardrail_importance_is_refused_in_the_backlog(self):
        self.led.add_idea("rated", "An idea.", importance="guardrail")
        r = self.led.backlog("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("guardrail importance is not allowed in the backlog",
                       r.output)

    def test_backlog_add_refuses_guardrail_before_composing(self):
        r = self.led.backlog("add", "An urgent idea.",
                             "--importance", "guardrail")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("mark the idea instead", r.output)
        self.assertFalse((self.led.root / "zamm-memory/backlog").exists(),
                         "the refusal must come before anything is written")

    def test_a_knowledge_guardrail_is_still_legal(self):
        """The other direction: the backlog rule must not leak backwards."""
        self.led.add("a-rule", "A guardrail statement.", importance="guardrail")
        self.assertCode(self.led.check(), EXIT_OK)

    def test_backlog_votes_carry_no_plan(self):
        idea = self.led.add_idea("an-idea", "A statement.")
        self.led.add("triage", type="votes", up=idea, plan="some-plan",
                     tree="backlog", scope=None, importance=None,
                     durability=None)
        r = self.led.backlog("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("triage votes", r.output)

    def test_backlog_triage_votes_without_plan_count(self):
        idea = self.led.add_idea("an-idea", "A statement.")
        self.led.add("triage", type="votes", up=idea, tree="backlog",
                     scope=None, importance=None, durability=None)

        self.assertCode(self.led.backlog("check"), EXIT_OK)
        r = self.led.backlog("list")
        self.assertIn_(f"{idea} +1", r.out, "the triage vote must count")

    def test_a_knowledge_votes_record_still_requires_plan(self):
        """The relaxation must not leak backwards."""
        rid = self.led.add("a-fact", "A statement.")
        self.led.add("orphan-votes", type="votes", up=rid,
                     scope=None, importance=None, durability=None)
        r = self.led.check()
        self.assertNotEqual(r.code, 0)
        self.assertIn_("votes record missing plan:", r.output)

    def test_other_is_uncapped_in_the_backlog(self):
        """OTHER_MAX exists to force refiling of KNOWLEDGE; capture-cheap
        ideas legitimately default to other, and because candidate
        validation is an error-line diff the cap would make the sixth
        context-free add refuse outright."""
        for i in range(6):
            self.led.add_idea(f"loose{i}", f"Loose idea {i}.", scope="other")
        self.assertCode(self.led.backlog("check"), EXIT_OK)

        r = self.led.backlog("add", "A seventh loose idea.")
        self.assertCode(r, EXIT_OK,
                        "the seventh context-free add must succeed")

    def test_other_is_still_capped_in_knowledge(self):
        for i in range(6):
            self.led.add(f"loose{i}", f"Loose fact {i}.", scope="other")
        r = self.led.check()
        self.assertNotEqual(r.code, 0)
        self.assertIn_("other holds", r.output)

    def test_marked_is_refused_on_a_knowledge_record(self):
        self.led.add("a-fact", "A statement.",
                     extra={"marked": "2026-01-05"})
        r = self.led.check()
        self.assertNotEqual(r.code, 0)
        self.assertIn_("marked: is a backlog key", r.output)

    def test_a_malformed_marked_value_quarantines(self):
        """An unparseable value must not silently read as unmarked — that
        would drop an idea out of the pushed lane, the exact silent loss the
        lane exists to prevent."""
        self.led.add_idea("soon", "An idea.", marked="soonish")
        r = self.led.backlog("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_('marked: must be a real YYYY-MM-DD date or "no"',
                       r.output)


class TestDigestBacklogLine(ZammTest):
    """The knowledge digest's entire standing exposure to the backlog."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")

    def test_no_tree_means_no_line(self):
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("Backlog", self.led.digest(),
                          "absence is data: an unused feature is invisible")

    def test_line_format_without_marked(self):
        """The `, 0 marked` variant never renders."""
        self.led.add_idea("an-idea", "A statement.", date="2026-07-18")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("Backlog: 1 live (1 hot) - zamm-run.sh backlog list",
                       self.led.digest())
        self.assertNotIn_("0 marked", self.led.digest())

    def test_line_and_section_with_marked(self):
        self.led.add_idea("an-idea", "A statement.", date="2026-07-18",
                          marked="2026-07-01")
        self.led.add_idea("older-pick", "An older selection.",
                          date="2026-07-17", marked="2026-06-01")
        self.assertCode(self.led.compile(), EXIT_OK)
        digest = self.led.digest()
        self.assertIn_("Backlog: 2 live (2 hot, 2 marked)", digest)
        self.assertIn_("## Marked backlog (implement or unmark)", digest)
        # oldest commitment first
        self.assertLess(digest.index("(marked 2026-06-01)"),
                        digest.index("(marked 2026-07-01)"))

    def test_a_degraded_backlog_degrades_the_digest_visibly(self):
        """Exit 2 must always pair with a visible degradation notice in the
        published output."""
        self.led.add_idea("fine", "A statement.")
        self.led.write("zamm-memory/backlog/2026/2026-01-05-broke-abcde.md",
                       "---\ntype: memory\nscope: tooling\ncreated: 2026-01-05\n"
                       "schema: 9\n---\n\nBroken.\n")
        r = self.led.compile()
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_("Backlog: DEGRADED - run: zamm-run.sh backlog check",
                       self.led.digest())

    def test_ideas_never_reach_the_knowledge_content(self):
        """Defect-reinjection lock: whatever sits in the backlog — a plain
        idea, a marked one, a malformed record — the knowledge-owned regions
        of memory.md do not move, and no idea headline appears in them."""
        self.assertCode(self.led.compile(), EXIT_OK)
        before = knowledge_view(self.led.digest())

        self.led.add_idea("an-idea", "A distinctive idea headline.",
                          date="2026-07-18")
        self.assertCode(self.led.compile(), EXIT_OK)
        after = self.led.digest()
        self.assertEqual(before, knowledge_view(after))
        self.assertNotIn_("A distinctive idea headline.",
                          knowledge_view(after))

        self.led.write("zamm-memory/backlog/2026/2026-01-06-broke-abcde.md",
                       "---\ntype: memory\nscope: tooling\ncreated: 2026-01-06\n"
                       "schema: 9\n---\n\nBroken.\n")
        self.assertCode(self.led.compile(), EXIT_DEGRADED)
        self.assertEqual(before, knowledge_view(self.led.digest()),
                         "a broken idea must not leak degradation detail "
                         "into the knowledge sections")

    @needs_permission_bits
    def test_an_unreadable_backlog_tree_fails_the_digest(self):
        """G3: unreadable is an error — and the previous digest survives."""
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()
        self.led.add_idea("an-idea", "A statement.")
        locked = self.led.root / "zamm-memory/backlog/2026"
        os.chmod(locked, 0o000)
        try:
            r = self.led.compile()
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "previous digest left untouched")


class TestBacklogAdd(ZammTest):
    """Near-free capture: one quoted sentence is a complete invocation."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")

    def test_minimal_invocation(self):
        r = self.led.backlog("add", "We could cache the parse results.")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("zamm-memory/backlog/", r.out)

        lens = self.led.backlog("list")
        self.assertIn_("We could cache the parse results.", lens.out)

    def test_add_creates_the_tree_on_demand(self):
        """Capture must never answer 'run scaffold first'."""
        self.assertFalse((self.led.root / "zamm-memory/backlog").exists())
        r = self.led.backlog("add", "An idea from nowhere.")
        self.assertCode(r, EXIT_OK)
        self.assertTrue((self.led.root / "zamm-memory/backlog").is_dir())

    def test_piped_depth_lands_under_background(self):
        """Progressive disclosure: the sentence is the headline (all the
        lens shows), any depth — a paragraph or a book — parks under
        ## Background, which the record contract leaves unbounded."""
        book = "\n".join(f"Line {i} of the depth." for i in range(40))
        r = self.led.backlog("add", "A deep idea.", stdin=book)
        self.assertCode(r, EXIT_OK,
                        "40 plain lines must not trip the digest-block cap")
        path = r.out.strip()
        text = self.led.read(os.path.relpath(path, self.led.root))
        self.assertIn_("## Background", text)

        lens = self.led.backlog("list")
        self.assertIn_("+bg]", lens.out, "the lens must flag the depth")
        self.assertNotIn_("Line 5 of the depth.", lens.out,
                          "the lens shows the headline only")

    def test_structured_stdin_is_used_verbatim(self):
        body = "A short elaboration.\n\n## Background\n\nThe long tail.\n"
        r = self.led.backlog("add", "A structured idea.", stdin=body)
        self.assertCode(r, EXIT_OK)
        text = self.led.read(os.path.relpath(r.out.strip(), self.led.root))
        self.assertEqual(text.count("## Background"), 1,
                         "author-structured stdin must not be re-wrapped")

    def test_a_bad_supersedes_target_writes_nothing(self):
        self.led.add_idea("an-idea", "A statement.")
        r = self.led.backlog("add", "A sharpened statement.",
                             "--supersedes", "2026-01-01-ghost-aaaaa")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("nothing was written", r.output)

    def test_add_never_touches_knowledge(self):
        self.assertCode(self.led.compile(), EXIT_OK)
        before = knowledge_view(self.led.digest())
        knowledge_files = sorted(
            str(p) for p in
            (self.led.root / "zamm-memory/knowledge").rglob("*"))

        self.assertCode(
            self.led.backlog("add", "An idea that stays in its tree."),
            EXIT_OK)

        self.assertEqual(before, knowledge_view(self.led.digest()))
        self.assertEqual(knowledge_files, sorted(
            str(p) for p in
            (self.led.root / "zamm-memory/knowledge").rglob("*")))


class TestMarkedLane(ZammTest):
    """The selected stage between latent and active."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")

    def test_mark_and_unmark_roundtrip(self):
        self.led.backlog("add", "A candidate idea.")
        r = self.led.backlog("mark", "a-candidate-idea")
        self.assertCode(r, EXIT_OK)
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("## Marked backlog", self.led.digest())

        r = self.led.backlog("mark", "a-candidate-idea")
        self.assertNotEqual(r.code, 0, "marking twice must refuse")
        self.assertIn_("already marked", r.output)

        r = self.led.backlog("unmark", "a-candidate-idea")
        self.assertCode(r, EXIT_OK)
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("## Marked backlog", self.led.digest())

        r = self.led.backlog("unmark", "a-candidate-idea")
        self.assertNotEqual(r.code, 0, "unmarking the unmarked must refuse")
        self.assertIn_("not marked", r.output)

    def test_a_plain_supersede_inherits_the_lane(self):
        """The contract: a marked idea leaves the lane only by promote,
        unmark, or tombstone — an ordinary re-up that omits the key must
        not silently drop it, and the original date survives."""
        old = self.led.add_idea("keeper", "The first cut.",
                                date="2026-07-01", marked="2026-07-02")
        self.led.add_idea("keeper", "The sharpened cut.",
                          date="2026-07-10", supersedes=old)

        r = self.led.backlog("list")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("The sharpened cut.", r.out)
        self.assertIn_("(marked 2026-07-02)", r.out,
                       "the lane and its original date are inherited")

    def test_the_newest_decision_wins_a_merge(self):
        """Two parents with conflicting decisions resolve deterministically:
        the marking decision carried by the newest record id decides."""
        a = self.led.add_idea("fork-a", "Head A.", date="2026-07-01",
                              marked="2026-07-01")
        b = self.led.add_idea("fork-b", "Head B.", date="2026-07-05",
                              marked="no")
        self.led.add_idea("merged", "The union.", date="2026-07-10",
                          supersedes=[a, b])
        r = self.led.backlog("list")
        self.assertNotIn_("## Marked", r.out,
                          "the newer decision (no) must win")

        c = self.led.add_idea("fork-c", "Head C.", date="2026-07-11",
                              marked="no")
        d = self.led.add_idea("fork-d", "Head D.", date="2026-07-12",
                              marked="2026-07-12")
        self.led.add_idea("merged2", "The other union.", date="2026-07-13",
                          supersedes=[c, d])
        r = self.led.backlog("list")
        self.assertIn_("The other union.", r.out)
        self.assertIn_("(marked 2026-07-12)", r.out,
                       "the newer decision (a date) must win")

    def test_a_marked_idea_never_goes_dormant(self):
        """The dormancy exemption, the backlog's mirror of guardrails: a
        selected item never fades silently."""
        self.led.add_idea("faded", "A cold but chosen idea.",
                          date="2026-01-05", importance="minor",
                          durability="days", marked="2026-01-05")
        r = self.led.backlog("list")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("A cold but chosen idea.", r.out)

        # falsification: the identical unmarked idea is dormant
        self.led.add_idea("faded-twin", "A cold unchosen idea.",
                          date="2026-01-05", importance="minor",
                          durability="days")
        r = self.led.backlog("list")
        self.assertNotIn_("A cold unchosen idea.", r.out)

    def test_the_marked_cap_nags(self):
        for i in range(8):
            self.led.add_idea(f"pick{i}", f"Selected idea {i}.",
                              date="2026-07-18", marked="2026-07-18")
        r = self.led.backlog("list")
        self.assertIn_("exceeds the soft cap", r.out)
        self.assertCode(self.led.compile(), EXIT_OK,
                        "the cap warns; it must not degrade the digest")
        self.assertIn_("over the soft cap", self.led.digest())


class TestPromote(ZammTest):
    """backlog promote: idea -> plan, rerun-convergent (guarantee 2)."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")
        self.led.backlog("add", "Build the frobnicator.")

    def _tombstones(self):
        return [p for p in
                (self.led.root / "zamm-memory/backlog").rglob("*.md")
                if "type: tombstone" in p.read_text()]

    def test_promote_creates_plan_and_retires_the_idea(self):
        r = self.led.backlog("promote", "build-the-frobnicator")
        self.assertCode(r, EXIT_OK)

        pf = self.led.root / ("zamm-memory/active/plans/"
                              "2026-07-19-build-the-frobnicator/"
                              "2026-07-19-build-the-frobnicator.plan.md")
        self.assertTrue(pf.is_file(), "the plan directory must exist")
        self.assertIn_("Origin-idea: ", pf.read_text(),
                       "provenance is rendered into the plan")
        self.assertEqual(len(self._tombstones()), 1)

        lens = self.led.backlog("list")
        self.assertNotIn_("Build the frobnicator.", lens.out,
                          "the promoted idea leaves the lens")

    def test_promote_takes_an_explicit_title(self):
        r = self.led.backlog("promote", "build-the-frobnicator",
                             "Frobnicator: phase one")
        self.assertCode(r, EXIT_OK)
        self.assertTrue((self.led.root / "zamm-memory/active/plans/"
                         "2026-07-19-frobnicator-phase-one").is_dir())

    def test_rerun_after_completion_converges(self):
        self.assertCode(self.led.backlog("promote", "build-the-frobnicator"),
                        EXIT_OK)
        r = self.led.backlog("promote", "build-the-frobnicator")
        self.assertCode(r, EXIT_OK, "a completed promote reruns as a no-op")
        self.assertIn_("Already promoted", r.out)
        self.assertEqual(len(self._tombstones()), 1,
                         "no second tombstone is written")

    def test_rerun_finishes_an_interrupted_promote(self):
        """Kill window: the plan rename landed, the tombstone did not. The
        origin line was rendered BEFORE the rename, so the retry recognizes
        its own partial result and finishes the job."""
        self.assertCode(self.led.backlog("promote", "build-the-frobnicator"),
                        EXIT_OK)
        ts = self._tombstones()[0]
        ts.unlink()  # simulate the crash by rewinding the second step

        r = self.led.backlog("promote", "build-the-frobnicator")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("Resumed an interrupted promote", r.out)
        self.assertEqual(len(self._tombstones()), 1)

    def test_an_unrelated_same_slug_plan_refuses(self):
        """A plan without the matching origin is a stranger's; promote must
        never adopt it."""
        self.assertCode(
            self.led.plan_create("Build the frobnicator"), EXIT_OK)
        r = self.led.backlog("promote", "build-the-frobnicator")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("plan already exists", r.output)
        self.assertEqual(len(self._tombstones()), 0,
                         "no tombstone may land without a promote plan")

    def test_promoting_a_dead_idea_refuses(self):
        idea = self.led.add_idea("gone", "A superseded idea.",
                                 date="2026-07-01")
        self.led.add_idea("gone", "Its successor.", date="2026-07-02",
                          supersedes=idea)
        r = self.led.backlog("promote", idea)
        self.assertNotEqual(r.code, 0)
        self.assertIn_("no live idea matches", r.output)


class TestBacklogStatusAndCheck(ZammTest):
    """status watches the lens; check covers the tree exactly when it exists."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")

    def test_status_is_silent_without_a_tree(self):
        self.led.compile()
        r = self.led.status()
        self.assertCode(r, EXIT_OK)
        self.assertNotIn_("Backlog", r.out)

    def test_status_reports_the_backlog_and_staleness(self):
        self.led.add_idea("an-idea", "A statement.", date="2026-07-18")
        self.assertCode(self.led.compile(), EXIT_OK)
        r = self.led.status()
        self.assertIn_("Backlog", r.out)
        self.assertNotIn_("STALE: 1 file(s) newer than the lens", r.out)

        time.sleep(1.1)  # mtime granularity: make "newer" unambiguous
        self.led.add_idea("late-idea", "A later thought.", date="2026-07-19")
        r = self.led.status()
        self.assertIn_("newer than the lens", r.out)

    def test_check_covers_the_backlog_exactly_when_present(self):
        self.assertCode(self.led.check_all(), EXIT_OK,
                        "a treeless project must stay green")

        self.led.add_idea("rated", "An idea.", importance="guardrail")
        r = self.led.check_all()
        self.assertNotEqual(r.code, 0, "a broken idea record must fail check")
        self.assertIn_("guardrail importance is not allowed", r.output)
