"""Ledger graph semantics: supersession, votes, erasure.

Domain rules rather than gates — what the compiler concludes from a set of
records. An invalid record must never retire a valid neighbour, votes must
not be mintable, and an erasure record must keep its targets out of the
digest even when a stray copy reappears.

See references/invariants.md for the guarantees these suites protect.
"""

import os
from pathlib import Path

from harness import (
    EXIT_CONTRACT, EXIT_DEGRADED, EXIT_OK, EXIT_UNREADABLE, ShimTest,
    ZammTest, archived_record, review_plan,
)

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


class Rev3TsvSafety(ZammTest):
    """PRE-FIX: --list-votes emitted the raw frontmatter lists. A TAB is legal
    whitespace inside a vote list, so "up: a,<TAB>b" produced a fifth TSV
    column and the cross-check read id-b as a downvote."""

    def test_tab_inside_a_vote_list_does_not_shift_columns(self):
        a = self.led.add("reca", "A.")
        b = self.led.add("recb", "B.")
        self.led.write(
            "zamm-memory/active/plans/2026-07-01-p/2026-07-01-p.plan.md",
            review_plan(f"{a}, {b}"),
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-07-02-votes-vvvvv.md",
            f"---\ntype: votes\nplan: 2026-07-01-p\nup: {a},\t{b}\ndown:\n"
            "created: 2026-07-02\nschema: 3\n---\n",
        )
        # the record is valid, and the cross-check must reconcile it
        self.assertCode(self.led.check_all(), EXIT_OK)
        # the TSV itself must hold exactly four columns per row
        lv = self.led.run("zamm-compile.sh", "--list-votes")
        for line in lv.out.splitlines():
            if not line.strip():
                continue
            self.assertEqual(len(line.split("\t")), 4, repr(line))


class Rev3PlanTraversal(ZammTest):
    """PRE-FIX: the compiler required only a non-empty plan:, and the
    cross-check used the value as a filesystem path — "..", "../plans" and
    "../../knowledge" all resolved to real directories, so an orphan votes
    record passed `check` and applied its votes."""

    def test_path_values_are_quarantined(self):
        m = self.led.add("real", "R.")
        for sfx, bad in (("vaaaa", ".."), ("vbbbb", "../plans"),
                         ("vcccc", "../../knowledge")):
            self.led.add(f"vote{sfx}", type="votes", plan=bad, up=m,
                         date="2026-01-06", sfx=sfx)
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("must be a plan directory slug", r.err)
        # quarantined, so no vote weight was minted
        c = self.led.compile()
        self.assertCode(c, EXIT_DEGRADED)
        self.assertIn_("Quarantined", self.led.digest())

    def test_empty_archived_directory_is_not_a_plan(self):
        m = self.led.add("real", "R.")
        os.makedirs(self.led.root / "zamm-memory/archive/plans/fake-plan")
        self.led.add("vote", type="votes", plan="fake-plan", up=m,
                     date="2026-01-06", sfx="vvvvv")
        r = self.led.check_all()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("no active or archived plan", r.err)


class Rev6InertGraphNodes(ZammTest):
    """PRE-FIX: pass 1a accepted archived/shunned supersede targets as known
    while pass 1c dropped the edge, so two successors of one retired id lost
    their union-find group and the Needs reconciliation section silently
    vanished — the exact conflict the digest exists to surface."""

    def _successors(self, target):
        a = self.led.add("succ-one", "Successor one.", date="2026-01-06",
                         sfx="66666", supersedes=target)
        b = self.led.add("succ-two", "Successor two.", date="2026-01-07",
                         sfx="77777", supersedes=target)
        return a, b

    def _reconciliation_section(self, digest):
        # the SECTION, not the entry-format legend line (which mentions the
        # words "Needs reconciliation" in every digest and made the pre-fix
        # loss of this section invisible to a naive substring assertion)
        self.assertIn_("## Needs reconciliation", digest)
        return digest.split("## Needs reconciliation", 1)[1].split("\n## ", 1)[0]

    def test_two_successors_of_an_archived_target_reconcile(self):
        target = "2026-01-05-basetgt-55555"
        self.led.write(
            f"zamm-memory/archive/knowledge/2026/{target}.md",
            archived_record("2026-01-05", "ARCHIVED BODY TEXT."))
        a, b = self._successors(target)
        self.assertCode(self.led.compile(), EXIT_OK)
        digest = self.led.digest()
        sec = self._reconciliation_section(digest)
        self.assertIn_(a, sec)
        self.assertIn_(b, sec)
        self.assertNotIn_("ARCHIVED BODY TEXT", digest,
                          "archived content must stay out of the digest")

    def test_two_successors_of_an_erased_target_reconcile(self):
        target = "2026-01-05-erased-55555"
        self.led.erase(target)
        a, b = self._successors(target)
        self.assertCode(self.led.compile(), EXIT_OK)
        sec = self._reconciliation_section(self.led.digest())
        self.assertIn_(a, sec)
        self.assertIn_(b, sec)

    def test_successors_at_different_points_of_one_archived_chain_group(self):
        older = "2026-01-04-chain-a-44444"
        newer = "2026-01-05-chain-b-55555"
        self.led.write(
            f"zamm-memory/archive/knowledge/2026/{older}.md",
            archived_record("2026-01-04", "Chain node A."))
        self.led.write(
            f"zamm-memory/knowledge/../archive/knowledge/2026/{newer}.md",
            archived_record("2026-01-05", "Chain node B.", supersedes=older))
        a = self.led.add("newsucc-a", "New successor of A.", date="2026-01-06",
                         sfx="66666", supersedes=older)
        b = self.led.add("newsucc-b", "New successor of B.", date="2026-01-07",
                         sfx="77777", supersedes=newer)
        self.assertCode(self.led.compile(), EXIT_OK)
        digest = self.led.digest()
        sec = self._reconciliation_section(digest)
        self.assertEqual(digest.count("### Heads of"), 1,
                         "both successors must meet in ONE group")
        self.assertIn_(a, sec)
        self.assertIn_(b, sec)


class Rev7ErasureRecords(ShimTest):
    """Round 8 replaced the shun.md redaction list with erasure RECORDS.
    The capability is unchanged — redact content, keep successors valid,
    survive a resurrected copy — but it now rides the enumeration,
    validation, symlink refusal and unreadable handling every record gets,
    instead of a bespoke parser that needed a fail-closed patch per file
    type (unreadable, symlinked, and finally a DIRECTORY named shun.md,
    which the `-type f` scan skipped and which silently emptied the set)."""

    def _leak_and_redact(self):
        leaky = self.led.add("leaky", "A SECRET pasted by mistake.")
        successor = self.led.add("clean", "The redacted version.",
                                 date="2026-01-06", supersedes=leaky)
        eid = self.led.erase(leaky, reason="Credential leak; rotated.")
        self.led.delete(leaky)
        return leaky, successor, eid

    def test_erasure_redacts_without_breaking_the_ledger(self):
        leaky, successor, eid = self._leak_and_redact()
        self.assertCode(self.led.check(), EXIT_OK,
                        "erasure must not leave successors dangling")
        self.assertCode(self.led.compile(), EXIT_OK)
        digest = self.led.digest()
        self.assertNotIn_("A SECRET pasted by mistake", digest)
        self.assertNotIn_("Dangling", digest)
        self.assertIn_(successor, digest, "the successor stays live")
        self.assertIn_(
            "Credential leak", self.led.read(
                f"zamm-memory/knowledge/2026/{eid}.md"),
            "the reason is recorded where the erasure is")

    def test_a_directory_named_shun_md_can_no_longer_empty_the_set(self):
        """The defect that motivated the replacement: `find -type f` skipped
        a directory named shun.md, so the redaction set silently emptied and
        erased content came back with exit 0 and a passing check. There is
        no shun.md path left to poison — its mere presence now refuses."""
        self._leak_and_redact()
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()
        (self.led.root / "zamm-memory/knowledge/shun.md").mkdir()
        r = self.led.compile()
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("erasure RECORDS", r.err)
        self.assertEqual(before, self.led.digest())

    def test_erasure_contract_is_enforced(self):
        self.led.add("alive", "A living record.")
        cases = {
            "no-targets": ("---\ntype: erasure\ncreated: 2026-01-07\n"
                           "schema: 3\n---\nA reason.\n",
                           "missing erases:"),
            "no-reason": ("---\ntype: erasure\nerases: 2026-01-05-x-22222\n"
                          "created: 2026-01-07\nschema: 3\n---\n\n",
                          "no body"),
            "supersedes": ("---\ntype: erasure\nerases: 2026-01-05-x-22222\n"
                           "supersedes: 2026-01-05-y-33333\n"
                           "created: 2026-01-07\nschema: 3\n---\nA reason.\n",
                           "must not carry supersedes:"),
        }
        for i, (name, (text, needle)) in enumerate(cases.items()):
            with self.subTest(case=name):
                rel = f"zamm-memory/knowledge/2026/2026-01-07-bad{i}-2222{i}.md"
                self.led.write(rel, text)
                c = self.led.check()
                self.assertCode(c, EXIT_CONTRACT)
                self.assertIn_(needle, c.err)
                (self.led.root / rel).unlink()

    def test_self_erasure_is_rejected(self):
        self.led.add("alive", "A living record.")
        rid = "2026-01-07-selferase-22223"
        self.led.write(
            f"zamm-memory/knowledge/2026/{rid}.md",
            f"---\ntype: erasure\nerases: {rid}\ncreated: 2026-01-07\n"
            "schema: 3\n---\nA reason.\n")
        c = self.led.check()
        self.assertCode(c, EXIT_CONTRACT)
        self.assertIn_("erases itself", c.err)

    def test_generator_writes_erasure_records(self):
        leaky = self.led.add("leaky", "A SECRET pasted by mistake.")
        r = self.led.new_memory("--type", "erasure", "--erases", leaky,
                                "redact-leak",
                                body="A credential was pasted in by mistake.\n")
        self.assertCode(r, EXIT_OK)
        written = Path(r.out.strip()).read_text()
        self.assertIn_(f"erases: {leaky}", written)
        self.assertIn_("pasted in by mistake", written)
        self.assertIn_("delete the erased record", r.err)

    def test_generator_requires_targets_and_rejects_stray_erases(self):
        r = self.led.zamm("memory", "create", "--type", "erasure", "noargs")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("--erases is required", r.err)
        r = self.led.zamm("memory", "create", "--scope", "internals",
                          "--erases", "2026-01-05-x-22222", "wrongtype")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("only meaningful on --type erasure", r.err)


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


class TestSecondaryScopeSearch(ZammTest):
    """`memory list --scope X` filtered on the primary scope only, so a record
    tagged `contracts/api, conventions` was invisible to `--scope conventions`
    even though the data model calls secondary tags selection doors."""

    def test_finds_a_record_by_its_secondary_scope(self):
        self.led.add("multi", "A record with a secondary tag.",
                     scope="contracts/api, conventions")
        self.led.add("other", "An unrelated record.", scope="ops/migrations")
        self.led.compile()

        r = self.led.memory_list("--scope", "conventions")

        self.assertCode(r, EXIT_OK)
        self.assertIn_("multi", r.out)
        self.assertNotIn_("other", r.out)

    def test_primary_scope_still_matches(self):
        self.led.add("multi", "A record with a secondary tag.",
                     scope="contracts/api, conventions")
        self.led.compile()

        r = self.led.memory_list("--scope", "contracts")

        self.assertCode(r, EXIT_OK)
        self.assertIn_("multi", r.out)
        # the listing still displays the primary scope as the home
        self.assertIn_("contracts/api", r.out)

    def test_a_non_matching_area_excludes_the_record(self):
        self.led.add("multi", "A record with a secondary tag.",
                     scope="contracts/api, conventions")
        self.led.compile()

        r = self.led.memory_list("--scope", "ops")

        self.assertEqual(r.out.strip(), "", "no record has an ops tag")


if __name__ == "__main__":
    unittest.main()
