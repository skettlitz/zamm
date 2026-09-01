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
import shutil
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

    def test_same_subpath_ideas_cluster_inside_their_area(self):
        """First user feedback: same-day lobby ideas interleaved with art
        and bare-domain entries by rank, which read as ungrouped. Inside an
        area block, entries now cluster by full primary scope — clusters by
        hottest member, rank order within — and the heading carries the
        counts (the statistics surface, no new metadata)."""
        # ranks interleave the subpaths on purpose: lobby, art, lobby, bare
        self.led.add_idea("lobby-hot", "Lobby door idea.",
                          scope="domain/lobby", date="2026-07-18")
        self.led.add_idea("art-mid", "Art wall idea.",
                          scope="domain/art", date="2026-07-17")
        self.led.add_idea("lobby-cool", "Lobby desk idea.",
                          scope="domain/lobby", date="2026-07-16",
                          importance="minor")
        self.led.add_idea("bare-domain", "General domain idea.",
                          scope="domain", date="2026-07-15",
                          importance="minor")

        r = self.led.backlog("list")

        self.assertCode(r, EXIT_OK)
        self.assertIn_("### domain (4: lobby 2, art 1)", r.out,
                       "the heading is the counts line")
        lines = [ln for ln in r.out.splitlines() if ln.startswith("- ")]
        order = [next(w for w in ("Lobby door", "Art wall", "Lobby desk",
                                  "General domain") if w in ln)
                 for ln in lines]
        self.assertEqual(order, ["Lobby door", "Lobby desk", "Art wall",
                                 "General domain"],
                         "clusters by hottest member, siblings adjacent, "
                         "rank order within the cluster")

    def test_a_subpath_free_area_counts_plainly(self):
        self.led.add_idea("plain", "A plain idea.", scope="tooling",
                          date="2026-07-18")
        r = self.led.backlog("list")
        self.assertIn_("### tooling (1)", r.out)

    def test_list_scope_filters_like_memory_list(self):
        """The query surface: prefix semantics over ANY tag (secondaries are
        selection doors), dormant excluded by default, --all adds it."""
        self.led.add_idea("lobby-idea", "Lobby door idea.",
                          scope="domain/lobby", date="2026-07-18")
        self.led.add_idea("art-idea", "Art wall idea.",
                          scope="domain/art", date="2026-07-18")
        self.led.add_idea("second-door", "Reachable via secondary.",
                          scope="tooling, domain", date="2026-07-18")
        cold = self.led.add_idea("cold-lobby", "A cooled lobby thought.",
                                 scope="domain/lobby", date="2026-01-05",
                                 importance="minor", durability="days")

        r = self.led.backlog("list", "--scope", "domain/lobby")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("lobby-idea", r.out)
        self.assertNotIn_("art-idea", r.out)
        self.assertNotIn_("cold-lobby", r.out,
                          "dormant is excluded by default")

        r = self.led.backlog("list", "--scope", "domain")
        self.assertIn_("lobby-idea", r.out, "prefix match: domain finds "
                                            "domain/lobby")
        self.assertIn_("art-idea", r.out)
        self.assertIn_("second-door", r.out,
                       "a secondary tag is a selection door here too")

        r = self.led.backlog("list", "--scope", "domain/lobby", "--all")
        self.assertIn_("cold-lobby", r.out, "--all adds the dormant tail")

        r = self.led.backlog("list", "--scope", "domain", "--bogus")
        self.assertNotEqual(r.code, 0, "unknown arguments still refuse")

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

    def test_same_day_unmark_survives_a_plain_reup(self):
        """PRE-FIX (second review round): decisions were resolved by
        lexically greatest id, but same-day ids order by RANDOM SUFFIX —
        so a same-day mark -> unmark -> re-up resurrected the mark
        whenever the mark record drew the greater suffix. Decisions now
        resolve by graph precedence: the unmark supersedes the mark, so
        it wins regardless of suffix order. Both directions locked."""
        for i, (msfx, usfx) in enumerate((("zzzzz", "22222"),
                                          ("22222", "zzzzz"))):
            with self.subTest(mark_suffix=msfx, unmark_suffix=usfx):
                led = self.led.__class__(self.led.root / f"sub{i}")
                led.add("a-fact", "A statement.")
                m1 = led.add_idea("flip", "The mark.", date="2026-07-01",
                                  marked="2026-07-01", sfx=msfx)
                m2 = led.add_idea("flip", "The unmark.", date="2026-07-01",
                                  marked="no", supersedes=m1, sfx=usfx)
                led.add_idea("flip", "The plain re-up.", date="2026-07-01",
                             supersedes=m2, sfx="77777")
                r = led.backlog("list")
                self.assertCode(r, EXIT_OK)
                # nothing in this fixture may be marked at all — stronger
                # than a format-coupled needle, which would pass vacuously
                # if the lane's line format changed
                self.assertNotIn_("## Marked", r.out,
                                  "the unmark is the descendant decision "
                                  "and overrides the mark")
                self.assertIn_("The plain re-up.", r.out,
                               "the re-up itself must stay live")

    def test_reviving_a_tombstoned_chain_does_not_inherit_the_mark(self):
        """A tombstone ends the lane for everything behind it as a property
        of the NODES, whichever record the revival supersedes. PRE-FIX
        (round 3, reproduced): the wall was path-based, so superseding the
        dead CONTENT record directly — the natural gesture, it carries the
        content — sidestepped the tombstone and inherited the dead mark.
        Both revival shapes locked."""
        for i, via in enumerate(("tombstone", "content-record")):
            with self.subTest(revival_supersedes=via):
                led = self.led.__class__(self.led.root / f"sub{i}")
                led.add("a-fact", "A statement.")
                a = led.add_idea("phoenix", "The chosen one.",
                                 date="2026-07-01", marked="2026-07-01")
                t = led.add_idea("phoenix", "Retired.", date="2026-07-02",
                                 type="tombstone", supersedes=a,
                                 scope=None, importance=None,
                                 durability=None)
                led.add_idea("phoenix", "The revival.", date="2026-07-03",
                             supersedes=(t if via == "tombstone" else a))
                r = led.backlog("list")
                self.assertCode(r, EXIT_OK)
                self.assertIn_("The revival.", r.out)
                self.assertNotIn_("## Marked", r.out,
                                  "reviving a retired chain starts outside "
                                  "the lane, whichever path it takes")

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
        """Replay identity is proven on the compiler's graph (round 3): the
        exact origin id, an ancestor id, and the bare slug all resolve to
        the same retired FAMILY, so every retry handle converges to the
        no-op — and none of them can adopt an unrelated same-slug idea,
        because that one sits in a different supersede component."""
        self.assertCode(self.led.backlog("promote", "build-the-frobnicator"),
                        EXIT_OK)
        pf = (self.led.root / "zamm-memory/active/plans/"
              "2026-07-19-build-the-frobnicator/"
              "2026-07-19-build-the-frobnicator.plan.md")
        m = re.search(r"^Origin-idea: (\S+)$", pf.read_text(), flags=re.M)
        self.assertIsNotNone(m, "the plan must carry its Origin-idea line")
        origin = m.group(1)

        for handle in (origin, "build-the-frobnicator"):
            with self.subTest(handle=handle):
                r = self.led.backlog("promote", handle)
                self.assertCode(r, EXIT_OK,
                                "a completed promote reruns as a no-op")
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

    def test_promoting_a_dead_idea_names_the_live_successor(self):
        """A stale ancestor id is neither 'retired' nor a shrug: the graph
        knows the family has a live head under a newer record, and the
        diagnostic names it (round 3 — the old probe called this same
        input 'retired' and pointed at tombstones that did not exist)."""
        idea = self.led.add_idea("gone", "A superseded idea.",
                                 date="2026-07-01")
        succ = self.led.add_idea("gone", "Its successor.", date="2026-07-02",
                                 supersedes=idea)
        r = self.led.backlog("promote", idea)
        self.assertNotEqual(r.code, 0)
        self.assertIn_("names a superseded record", r.output)
        self.assertIn_(succ, r.output, "the live head must be named")

    def test_retry_converges_after_the_head_advances(self):
        """Round-3 P1, reproduced pre-fix as a false 'Already promoted'
        no-op: promote crashes after the plan rename; the idea is then
        marked (head advances past the recorded origin); the retry — by the
        exact origin id the crash message prints, or by slug — must finish
        the tombstone against the CURRENT head, proven by graph ancestry,
        not report success while the idea stays live."""
        self.assertCode(self.led.backlog("promote", "build-the-frobnicator"),
                        EXIT_OK)
        pf = (self.led.root / "zamm-memory/active/plans/"
              "2026-07-19-build-the-frobnicator/"
              "2026-07-19-build-the-frobnicator.plan.md")
        m = re.search(r"^Origin-idea: (\S+)$", pf.read_text(), flags=re.M)
        self.assertIsNotNone(m, "the plan must carry its Origin-idea line")
        origin = m.group(1)
        self._tombstones()[0].unlink()          # crash state
        self.assertCode(self.led.backlog("mark", "build-the-frobnicator"),
                        EXIT_OK)                # head advances

        r = self.led.backlog("promote", origin)

        self.assertCode(r, EXIT_OK, "the retry must converge, not lie")
        self.assertIn_("Resumed an interrupted promote", r.out)
        self.assertEqual(len(self._tombstones()), 1,
                         "the tombstone lands against the current head")
        lens = self.led.backlog("list")
        self.assertNotIn_("Build the frobnicator.", lens.out,
                          "the whole chain is retired")

    def test_replay_survives_plan_archival(self):
        """Round-3 finding, reproduced: the origin scan read only PLANFILE
        rows, so archiving the promoted plan — its normal end state — broke
        the documented no-op replay."""
        self.assertCode(self.led.backlog("promote", "build-the-frobnicator"),
                        EXIT_OK)
        src = (self.led.root /
               "zamm-memory/active/plans/2026-07-19-build-the-frobnicator")
        src.rename(self.led.root /
                   "zamm-memory/archive/plans/2026-07-19-build-the-frobnicator")

        r = self.led.backlog("promote", "build-the-frobnicator")

        self.assertCode(r, EXIT_OK, "an archived plan still proves the "
                                    "promote happened")
        self.assertIn_("Already promoted", r.out)
        self.assertIn_("archive/plans", r.out)

    def test_an_ambiguous_slug_lists_the_live_ids(self):
        """Round-3 P1, reproduced pre-fix: the retired-idea probe fired on
        EVERY resolve failure, so two live ideas sharing a slug were
        reported as 'a retired idea' and the disambiguation listing was
        unreachable."""
        self.led.backlog("add", "First take.", "--slug", "dup")
        self.led.backlog("add", "Second take.", "--slug", "dup")

        r = self.led.backlog("promote", "dup")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("matches 2 live ideas", r.output)
        self.assertIn_("Use the full id", r.output)
        self.assertNotIn_("retired", r.output,
                          "two live ideas are not a retired one")

    def test_a_bogus_needle_gets_the_no_match_diagnostic(self):
        """The typo path stays locked (round-3 coverage finding), and a
        glob metacharacter is data, not a pattern — pre-fix, promoting '*'
        claimed a retired idea existed."""
        for needle in ("no-such-idea", "*"):
            with self.subTest(needle=needle):
                r = self.led.backlog("promote", needle)
                self.assertNotEqual(r.code, 0)
                self.assertIn_("no live idea matches", r.output)
                self.assertNotIn_("matches a retired idea", r.output)

    def test_a_retired_chain_without_a_plan_gets_the_pointer(self):
        """Manually tombstoned (never promoted): the pointer names the
        chain rather than claiming a plan exists."""
        a = self.led.add_idea("shelved", "Put away deliberately.",
                              date="2026-07-01")
        self.led.add_idea("shelved", "Retired by hand.", date="2026-07-02",
                          type="tombstone", supersedes=a, scope=None,
                          importance=None, durability=None)

        r = self.led.backlog("promote", "shelved")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("matches a retired idea", r.output)
        self.assertIn_("backlog show", r.output)

    def test_an_unrelated_same_slug_idea_is_never_adopted(self):
        """PRE-FIX (second review round, reproduced): replay detection
        accepted SLUG equality, so promoting a fresh idea that happened to
        share a slug with an already-promoted one 'resumed' the old promote
        — no new plan, and the fresh idea silently retired into a plan that
        never described it. Replay now keys on the exact Origin-idea id."""
        self.assertCode(self.led.backlog("promote", "build-the-frobnicator"),
                        EXIT_OK)
        add = self.led.backlog("add", "Build the frobnicator.")
        self.assertCode(add, EXIT_OK, "an unrelated idea may reuse the words")
        # the add prints the landed path — the one deterministic handle on
        # the fresh record (a glob over the tree orders by filesystem whim
        # and once picked the RETIRED record, turning this into a test of
        # the replay no-op instead)
        fresh = os.path.basename(add.out.strip())[:-3]

        r = self.led.backlog("promote", fresh)

        self.assertNotEqual(r.code, 0, "same title, same day: must refuse, "
                                       "never adopt the stranger's plan")
        self.assertIn_("plan already exists", r.output)
        self.assertEqual(len(self._tombstones()), 1,
                         "the fresh idea must NOT be retired")
        lens = self.led.backlog("list")
        self.assertIn_(fresh, lens.out, "the fresh idea stays live")

        r = self.led.backlog("promote", fresh, "Frobnicator, second attempt")
        self.assertCode(r, EXIT_OK,
                        "a distinct title promotes into its own plan")
        self.assertEqual(len(self._tombstones()), 2)

    def test_promote_refuses_on_a_damaged_plan_tree(self):
        """PRE-FIX (second review round, reproduced): the plan manifest
        represents damage as data rows while exiting 0, and promote read
        only PLANFILE rows — so it created and retired over a damaged tree.
        The origin scan is mutation authority; any anomaly row refuses
        before anything is created (G3)."""
        shutil.rmtree(self.led.root / "zamm-memory/archive/plans")

        r = self.led.backlog("promote", "build-the-frobnicator")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("the plan tree is damaged", r.output)
        self.assertIn_("MISSING", r.output)
        self.assertEqual(len(self._tombstones()), 0, "nothing may be retired")
        self.assertFalse(any(
            (self.led.root / "zamm-memory/active/plans").iterdir()),
            "nothing may be created")


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

    def test_status_survives_a_missing_sidecar(self):
        """PRE-FIX (second review round, reproduced): the sidecar reads ran
        as bare command substitutions under set -e, so a deleted
        backlog-state.tsv aborted status silently at exit 2 after the
        Ledger section. The pair now gets the knowledge sidecar's
        generation-coherence treatment: report, name the remedy, finish."""
        self.led.add_idea("an-idea", "A statement.", date="2026-07-18")
        self.assertCode(self.led.compile(), EXIT_OK)
        (self.led.root / "zamm-memory/.compiled/backlog-state.tsv").unlink()

        r = self.led.status()

        self.assertCode(r, EXIT_OK, "status must complete, not die mid-output")
        self.assertIn_("incoherent", r.out)
        self.assertIn_("memory digest", r.out, "the remedy must be named")
        self.assertIn_("Plans", r.out, "the sections after the backlog "
                                       "block must still render")

    def test_check_covers_the_backlog_exactly_when_present(self):
        self.assertCode(self.led.check_all(), EXIT_OK,
                        "a treeless project must stay green")

        self.led.add_idea("rated", "An idea.", importance="guardrail")
        r = self.led.check_all()
        self.assertNotEqual(r.code, 0, "a broken idea record must fail check")
        self.assertIn_("guardrail importance is not allowed", r.output)
