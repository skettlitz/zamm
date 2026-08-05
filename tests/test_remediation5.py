"""Regression locks for the second-round review remediation (2026-08-03),
plan: zamm-memory/active/plans/2026-08-03-second-review-remediation/.

One class per fixed defect:

  P0-1  no-op `plan archive` must not crash (unbound array under set -u)
  P0-2  record enumeration fails closed (exit 4, previous digest preserved)
  P0-3  every supersede cycle is detected (iterative Tarjan SCC)
  P0-4  vote/ancestry aggregation walks only applied edges (+ High-1: no cap)
  P0-5  the dispatcher enforces the protocol version centrally (exit 5)
  P0-6  dangling references degrade the publish (exit 2), not a healthy exit 0
  High-2  vote-record forgery (dup / up-and-down / two-active-per-plan)
  High-3  migration seed values are bounded and provenance-checked
  High-4  a new record may supersede an archived record
  High-6  the abandon checker matches the documented Draft->Abandoned transition
  High-7  top-level check reconciles plans with their votes records
  6.1-6.3 generator hardening + the draft/publish lifecycle
  7.1/7.2 status and memory list read the state sidecar, not the Markdown
  8       the drift stamp covers all normative inputs
  9.3     plan archive has a real list-only preview

Second-pass review (2026-08-04) found ten more; locks for those live in the
Rev2* classes at the end of this file.
"""

import os

from harness import (
    needs_permission_bits,
    EXIT_CONTRACT,
    EXIT_DEGRADED,
    EXIT_OK,
    EXIT_UNREADABLE,
    EXIT_VERSION,
    ZammTest,
)


# ----------------------------------------------------------------------
# P0-1 — no-op plan archive exits cleanly
# ----------------------------------------------------------------------
class TestPlanArchiveNoActivePlans(ZammTest):
    """Falsified on CI, not locally: pre-fix, GitHub's ubuntu runner bash
    dies with `READY_SLUGS: unbound variable` (zamm-archive.sh line 112,
    run of 2026-07-28 on main), while macOS bash 3.2 tolerates the unset
    array — so this lock guards a failure only CI can reproduce."""

    def test_no_plans_at_all(self):
        r = self.led.zamm("plan", "archive")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("No archive-ready plan directories", r.out)

    def test_active_plans_but_none_terminal(self):
        self.led.add_plan("2026-01-05-busy", status="Implementing")
        r = self.led.zamm("plan", "archive")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("No archive-ready plan directories", r.out)


# ----------------------------------------------------------------------
# P0-5 — the dispatcher enforces the protocol version centrally
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# P0-2 — record enumeration fails closed
# ----------------------------------------------------------------------
class TestEnumerationFailsClosed(ZammTest):
    """PRE-FIX: `{ find; find; } | sort | awk` reported only awk's exit
    status, so a find that could not read a subtree returned 0 and the
    digest silently dropped those records. Now a traversal failure exits 4
    and leaves the previous (good) digest untouched."""

    @needs_permission_bits
    def test_unreadable_subtree_refuses_and_preserves_digest(self):
        self.led.add("alpha", "A.", date="2026-01-05")
        self.led.add("hidden", "H, in the 2025 subtree.", date="2025-03-05")
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()

        locked = self.led.root / "zamm-memory/knowledge/2025"
        os.chmod(locked, 0o000)
        try:
            r = self.led.compile()
        finally:
            os.chmod(locked, 0o755)

        self.assertCode(r, EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "an unreadable ledger must not overwrite a good digest")

    @needs_permission_bits
    def test_unreadable_single_file_quarantines_with_a_clear_reason(self):
        self.led.add("readable", "A readable record.")
        victim = self.led.add("locked", "An unreadable record.")
        vf = self.led.root / f"zamm-memory/knowledge/2026/{victim}.md"
        os.chmod(vf, 0o000)
        try:
            r = self.led.check()
        finally:
            os.chmod(vf, 0o644)
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("cannot read record file", r.err)


# ----------------------------------------------------------------------
# P0-3 — every cycle is detected (SCC), not just the first
# ----------------------------------------------------------------------
class TestAllCyclesDetected(ZammTest):
    """PRE-FIX: the early-return DFS left stale grey state, so a second
    disjoint cycle reachable through a shared node was missed and its
    members were silently applied. Ordered so the merge record sorts FIRST
    (the ordering that hid the second cycle)."""

    def _two_cycles(self):
        # R supersedes A and C; A<->B; C->R. Two SCCs: {A,B} and {C,R}.
        A, B, C, R = ("2026-01-05-ba-aaaaa", "2026-01-05-bb-bbbbb",
                      "2026-01-05-bc-ccccc", "2026-01-05-ar-rrrrr")
        self.led.add("ba", "A.", sfx="aaaaa", supersedes=B)
        self.led.add("bb", "B.", sfx="bbbbb", supersedes=A)
        self.led.add("bc", "C.", sfx="ccccc", supersedes=R)
        self.led.add("ar", "R.", sfx="rrrrr", supersedes=[A, C])
        self.led.add("bd", "D, an unrelated live record.", sfx="ddddd")
        return A, B, C, R

    def test_both_cycles_are_quarantined(self):
        self._two_cycles()
        r = self.led.compile()
        # The SCC-specific assertions come FIRST so that, run against the pre-fix
        # (early-return DFS) compiler, this lock fails for the RIGHT reason — the
        # second cycle {bc, ar} escaping quarantine (quarantined=2, bc/ar absent
        # from Degraded) — rather than merely tripping the new degraded exit code.
        self.assertIn_("quarantined=4", self.header())
        deg = self.led.digest_section("Degraded")
        for slug in ("ba", "bb", "bc", "ar"):
            self.assertIn_(slug, deg, f"{slug} must be quarantined")
        self.assertCode(r, EXIT_DEGRADED)

    def header(self):
        return self.led.digest().splitlines()[0]


# ----------------------------------------------------------------------
# P0-4 / High-1 — aggregation walks only APPLIED edges
# ----------------------------------------------------------------------
class TestAppliedEdgeAggregation(ZammTest):
    def test_vote_does_not_leak_through_a_quarantined_ancestor(self):
        """PRE-FIX: chainagg walked raw supersedes:, so H inherited A's vote
        through a quarantined middle record I."""
        A = self.led.add("aa", "A, the original claim.", sfx="aaaaa")
        self.led.add("va", type="votes", date="2026-01-06",
                     plan="2026-01-06-p", up=A, sfx="vvvvv")
        # I: malformed (no importance/durability) -> quarantined; supersedes A
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-07-ii-jjjjj.md",
            f"---\ntype: memory\nscope: contracts/api\nsupersedes: {A}\n"
            "created: 2026-01-07\nschema: 3\n---\nMalformed middle.\n",
        )
        self.led.add("hh", "H, valid successor of the malformed I.",
                     sfx="hhhhh", date="2026-01-08",
                     supersedes="2026-01-07-ii-jjjjj")
        self.led.compile()
        digest = self.led.digest()
        self.assertIn_(f"{A} +1", digest, "A keeps its own vote")
        self.assertNotIn_("hh-hhhhh +1", digest,
                          "H must NOT inherit A's vote through quarantined I")

    def test_vote_reaches_the_head_of_a_long_chain(self):
        """PRE-FIX: chainagg stopped after 500 enqueued nodes, so a vote on
        the oldest of a 510-long chain never reached the live head."""
        prev, first = None, None
        for i in range(510):
            rid = self.led.add(f"c{i:03d}", f"link {i}.", supersedes=prev)
            if first is None:
                first = rid
            prev = rid
        self.led.add("vf", type="votes", date="2026-01-06",
                     plan="2026-01-06-p", up=first, sfx="vvvvv")
        self.led.compile()
        self.assertIn_(f"{prev} +1", self.led.digest(),
                       "the live head must inherit the oldest ancestor's vote")


# ----------------------------------------------------------------------
# P0-6 — dangling supersedes targets degrade the publish, not exit 0
# ----------------------------------------------------------------------
class TestDanglingReferenceIsDegraded(ZammTest):
    """PRE-FIX: a supersedes: target that did not exist printed an error to
    stderr but exited 0 with quarantined=0 and no Degraded section — a
    healthy-looking digest hiding a broken reference."""

    def test_normal_compile_is_degraded_and_lists_the_reference(self):
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-05-xx-xxxxx.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\nsupersedes: 2026-01-01-ghost-zzzzz\n"
            "created: 2026-01-05\nschema: 3\n---\nX supersedes a ghost.\n",
        )
        self.led.add("ok", "A normal live record.")
        r = self.led.compile()
        self.assertCode(r, EXIT_DEGRADED)
        deg = self.led.digest_section("Degraded")
        self.assertIn_("2026-01-01-ghost-zzzzz", deg)
        self.assertIn_("X supersedes a ghost.", self.led.digest(),
                       "the referencing record stays live")

    def test_check_mode_fails_on_the_dangling_reference(self):
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-05-xx-xxxxx.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\nsupersedes: 2026-01-01-ghost-zzzzz\n"
            "created: 2026-01-05\nschema: 3\n---\nX supersedes a ghost.\n",
        )
        self.assertCode(self.led.check(), EXIT_CONTRACT)


# ----------------------------------------------------------------------
# High-2 — vote-record forgery is rejected
# ----------------------------------------------------------------------
class TestVoteForgery(ZammTest):
    def test_duplicate_target_in_up_quarantines_the_record(self):
        A = self.led.add("aa", "The voted-on record.", sfx="aaaaa")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-vd-vvvv2.md",
            f"---\ntype: votes\nplan: plan-x\nup: {A}, {A}, {A}\ndown:\n"
            "created: 2026-01-06\nschema: 3\n---\n",
        )
        self.assertCode(self.led.check(), EXIT_CONTRACT)
        r = self.led.compile()
        self.assertCode(r, EXIT_DEGRADED)
        # the forged record is quarantined, so A carries no votes
        self.assertNotIn_("aa-aaaaa +", self.led.digest())

    def test_target_in_both_up_and_down_quarantines_the_record(self):
        A = self.led.add("aa", "The voted-on record.", sfx="aaaaa")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-vd-vvvv2.md",
            f"---\ntype: votes\nplan: plan-x\nup: {A}\ndown: {A}\n"
            "created: 2026-01-06\nschema: 3\n---\n",
        )
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("both up: and down:", r.err)

    def test_two_active_votes_records_for_one_plan_count_only_the_newest(self):
        A = self.led.add("aa", "The voted-on record.", sfx="aaaaa")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-v1-vvvv2.md",
            f"---\ntype: votes\nplan: plan-x\nup: {A}\ndown:\n"
            "created: 2026-01-06\nschema: 3\n---\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-07-v2-vvvv3.md",
            f"---\ntype: votes\nplan: plan-x\nup: {A}\ndown:\n"
            "created: 2026-01-07\nschema: 3\n---\n",
        )
        self.assertCode(self.led.check(), EXIT_CONTRACT)
        r = self.led.compile()
        self.assertCode(r, EXIT_DEGRADED)
        # counted once (+1), not doubled (+2)
        self.assertIn_(f"{A} +1", self.led.digest())
        self.assertNotIn_(f"{A} +2", self.led.digest())
        self.assertIn_("active votes records", self.led.digest_section("Degraded"))


# ----------------------------------------------------------------------
# High-3 — migration seed values are constrained
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# High-6 — the abandon checker matches the documented transition
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# High-7 — top-level check reconciles plans with their votes records
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# High-4 / Phase 2c — a new record may supersede an archived record
# ----------------------------------------------------------------------
class TestSupersedeArchivedRecord(ZammTest):
    def test_archived_target_is_known_inert_not_dangling(self):
        old = self.led.add("old-truth", "The archived claim.", sfx="aaaaa")
        self.led.add("kill", type="tombstone", date="2026-01-06",
                     supersedes=old, sfx="ttttt", body="Retired.")
        self.led.compile()
        self.assertCode(self.led.memory_archive(), EXIT_OK)
        # a new record reviving the archived lineage
        self.led.add("new-truth", "New truth, reviving the lineage.",
                     date="2026-02-01", supersedes=old, sfx="nwwww")
        r = self.led.check()
        self.assertCode(r, EXIT_OK)
        self.assertNotIn_("not found", r.err)


# ----------------------------------------------------------------------
# 6.1-6.3 — generator hardening and the draft/publish lifecycle
# ----------------------------------------------------------------------
class TestMemoryCreateHardening(ZammTest):
    def test_option_missing_its_value_is_a_controlled_error(self):
        # PRE-FIX: `$2` under set -u aborted with a raw "unbound variable".
        for opt in ("--scope", "--type", "--durability", "--importance"):
            r = self.led.zamm("memory", "create", "topic", opt)
            self.assertCode(r, EXIT_CONTRACT, opt)
            self.assertIn_("requires a value", r.err)
            self.assertNotIn_("unbound variable", r.err)

    def test_generator_rejects_a_scope_the_checker_would_reject(self):
        # PRE-FIX: the shell split dropped the empty component, so the generator
        # wrote a record the compiler then quarantined.
        r = self.led.zamm("memory", "create", "--immediate",
                          "--scope", "domain,,quality", "bad")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("empty component", r.err)

    def test_draft_is_invisible_until_published(self):
        r = self.led.zamm("memory", "create", "--scope", "contracts/api", "myrule")
        self.assertCode(r, EXIT_OK)
        draft = r.out.strip()
        self.assertTrue(draft.endswith(".md.draft"), r)
        # an unfilled draft must not degrade or appear in the compile
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("not been initialized", self.led.digest())

    def test_publish_lands_a_filled_draft(self):
        r = self.led.zamm("memory", "create", "--scope", "contracts/api", "myrule")
        draft = r.out.strip()
        with open(draft, "a") as fh:
            fh.write("The actual rule body.\n")
        rid = os.path.basename(draft)[: -len(".md.draft")]
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)
        self.led.compile()
        self.assertIn_("The actual rule body.", self.led.digest())

    def test_publish_rolls_back_an_invalid_draft(self):
        r = self.led.zamm("memory", "create", "--scope", "contracts/api", "myrule")
        draft = r.out.strip()
        # leave the body empty -> invalid; publish must refuse and keep the draft
        rid = os.path.basename(draft)[: -len(".md.draft")]
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertTrue(os.path.exists(draft), "invalid draft must stay a draft")
        self.assertFalse(os.path.exists(draft[: -len(".draft")]),
                         "no live .md must be left behind")


# ----------------------------------------------------------------------
# 7.1 / 7.2 — status and memory list read the state sidecar, not Markdown
# ----------------------------------------------------------------------
class TestStateSidecar(ZammTest):
    def _two_contested_guardrails(self):
        parent = self.led.add("parent", "The original rule.", sfx="ppppp")
        self.led.add("g1", "Never skip the backup.", sfx="gaaaa",
                     date="2026-01-06", importance="guardrail", supersedes=parent)
        self.led.add("g2", "Always use a feature flag.", sfx="gbbbb",
                     date="2026-01-07", importance="guardrail", supersedes=parent)

    def test_status_counts_contested_guardrails_once(self):
        # PRE-FIX: status grepped '^- !' across the whole digest, so a
        # contested guardrail (Digest + reconciliation index) counted twice.
        self._two_contested_guardrails()
        self.led.compile()
        out = self.led.status().out
        self.assertIn_("guardrails: 2/15", out)

    def test_sidecar_is_published_beside_the_digest(self):
        self.led.add("a", "A record.")
        self.led.compile()
        self.assertTrue(self.led.exists("zamm-memory/.compiled/state.tsv"))

    def test_memory_list_ignores_ids_that_only_appear_in_plan_text(self):
        # PRE-FIX: memory list default grepped the whole digest, including the
        # appended Plans tail, so an unlisted record id written into a plan
        # title was returned as if the digest had selected it.
        ids = [self.led.add(f"rec{i:03d}", f"Filler record {i}.")
               for i in range(230)]
        self.led.compile()
        # find a live record the digest did NOT select
        import subprocess
        listed = set(self.led.memory_list().out.split())
        unlisted = None
        for rid in ids:
            slug = rid[11:-6]
            if slug not in listed:
                unlisted = rid
                break
        self.assertIsNotNone(unlisted, "need at least one unlisted live record")
        # plant its id in a plan title
        self.led.write(
            "zamm-memory/active/plans/2026-07-01-decoy/2026-07-01-decoy.plan.md",
            f"# Investigate [{unlisted}] regression\nStatus: Draft\n"
            "Last updated: 2026-07-01\n\n## Done-when\n- [ ] look\n",
        )
        self.led.compile()
        out = self.led.memory_list().out
        self.assertNotIn_(unlisted[11:-6], out,
                          "an id only present in a plan title must not be listed")


# ----------------------------------------------------------------------
# 8 — the drift stamp covers all normative inputs
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# 9.3 — plan archive has a real list-only preview via the dispatcher
# ----------------------------------------------------------------------
class TestPlanArchiveListPreview(ZammTest):
    def test_list_previews_without_moving(self):
        self.led.add_plan("2026-01-05-done", status="Done")
        r = self.led.zamm("plan", "archive", "--list")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("2026-01-05-done", r.out)
        self.assertIn_("Dry run", r.out)
        # nothing moved
        self.assertTrue(self.led.exists(
            "zamm-memory/active/plans/2026-01-05-done"))
        self.assertFalse(self.led.exists(
            "zamm-memory/archive/plans/2026-01-05-done"))


# ======================================================================
# Second-pass review remediation (2026-08-04)
# ======================================================================

class Rev2InvalidVoteRefDegrades(ZammTest):
    """F2: a votes record naming a missing or wrong-typed target printed to
    stderr but published with exit 0 and no Degraded section — normal compile
    and --check disagreed about ledger health."""

    def test_ghost_vote_target_degrades_the_publish(self):
        self.led.add("real", "A live record.", sfx="rrrrr")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-v-vvvvv.md",
            "---\ntype: votes\nplan: p\nup: 2026-01-01-ghost-zzzzz\ndown:\n"
            "created: 2026-01-06\nschema: 3\n---\n",
        )
        r = self.led.compile()
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_("Invalid vote references", self.led.digest_section("Degraded"))
        self.assertCode(self.led.check(), EXIT_CONTRACT)

    def test_vote_on_a_tombstone_degrades_the_publish(self):
        self.led.add("live", "A live record so the ledger is not empty.",
                     sfx="22222")
        a = self.led.add("a", "A record.", sfx="aaaaa")
        self.led.add("t", type="tombstone", date="2026-01-06", supersedes=a,
                     sfx="ttttt", body="Retired.")
        # vote targets the tombstone (a non-memory record)
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-07-v-vvvvv.md",
            "---\ntype: votes\nplan: p\nup: 2026-01-06-t-ttttt\ndown:\n"
            "created: 2026-01-07\nschema: 3\n---\n",
        )
        self.assertCode(self.led.compile(), EXIT_DEGRADED)


class Rev2PublishOnDegradedLedger(ZammTest):
    """F1/F5 sibling: publishing a valid draft into a ledger already degraded
    by UNRELATED records must succeed (the recompile returns exit 2, which is a
    successful publish), not abort."""

    def test_publish_succeeds_despite_unrelated_degradation(self):
        # an unrelated quarantined record makes every compile exit 2
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-bbbbb.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-06\n---\nNo schema.\n",
        )
        r = self.led.zamm("memory", "create", "--scope", "contracts/api", "good")
        draft = r.out.strip()
        with open(draft, "a") as fh:
            fh.write("A valid body.\n")
        rid = os.path.basename(draft)[: -len(".md.draft")]
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)
        self.assertTrue(self.led.exists(
            "zamm-memory/knowledge/2026/" + rid + ".md"))


class Rev2PlanArchiveDegraded(ZammTest):
    """F5: plan archive rejected a successful (exit 2) recompile, so unrelated
    ledger degradation blocked archiving a valid terminal plan."""

    def test_archive_succeeds_despite_unrelated_degradation(self):
        self.led.add("live", "A live record so the digest is not empty.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-bbbbb.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-06\n---\nNo schema.\n",
        )
        self.led.add_plan("2026-01-05-done", status="Done")
        self.assertCode(self.led.compile(), EXIT_DEGRADED)
        r = self.led.archive()
        self.assertCode(r, EXIT_OK)
        self.assertTrue(self.led.exists(
            "zamm-memory/archive/plans/2026-01-05-done"))
        self.assertFalse(self.led.exists(
            "zamm-memory/active/plans/2026-01-05-done"))


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


class Rev2ScopeNormalized(ZammTest):
    """F7: the generator validated a trimmed scope tag but wrote the raw
    argument, so a leading newline survived into an invalid record."""

    def test_newline_scope_is_normalized_or_rejected(self):
        r = self.led.zamm("memory", "create", "--immediate",
                          "--scope", "\ncontracts/api", "topic")
        # either rejected outright, or written normalized so check finds no
        # scope problem (an empty skeleton body is the only allowed complaint)
        if r.code == 0:
            path = r.out.strip()
            with open(path) as fh:
                body = fh.read()
            self.assertIn_("scope: contracts/api\n", body)
            self.assertNotIn_("scope: \n", body)
            chk = self.led.check()
            self.assertNotIn_("scope", chk.err)
        else:
            self.assertCode(r, EXIT_CONTRACT)


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


class Rev2SidecarNoBuggyFallback(ZammTest):
    """F8: with the sidecar missing, status and default memory list must ask
    for a recompile rather than reproduce the reverse-parsing bugs."""

    def test_memory_list_default_requires_the_sidecar(self):
        self.led.add("a", "A record.")
        self.led.compile()
        (self.led.root / "zamm-memory/.compiled/state.tsv").unlink()
        r = self.led.memory_list()
        self.assertNotEqual(r.code, 0)
        self.assertIn_("memory digest", r.err)
        # --all does not depend on the sidecar
        self.assertCode(self.led.memory_list("--all"), EXIT_OK)

    def test_status_notes_recompile_when_sidecar_missing(self):
        self.led.add("a", "A record.")
        self.led.compile()
        (self.led.root / "zamm-memory/.compiled/state.tsv").unlink()
        out = self.led.status().out
        self.assertIn_("memory digest", out)
