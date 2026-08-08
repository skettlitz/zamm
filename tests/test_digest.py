"""The digest is derived and disposable — invariant G2.

It is never protected, only recomputed: the compiler owns every derived
value, the digest and its sidecar are published as a coherent pair, and
concurrent compiles may leave it one record behind without the ledger ever
losing anything.

See references/invariants.md for the guarantees these suites protect.
"""

import os
import shutil
import stat
import subprocess
import tempfile
import time

from harness import (
    EXIT_CONTRACT, EXIT_DEGRADED, EXIT_OK, PINNED_TODAY, SCRIPTS, ZammTest,
)

class TestCompilerAuthority(ZammTest):
    """The invariant: invalid input degrades itself, never its neighbours.

    A record that fails the contract is quarantined; every supersede edge it
    carries must be dropped, INCLUDING edges the compiler only rejects while
    walking the edge list (type mismatch, duplicate target, cycle). The
    pre-fix compiler applied `dead[tgt]` before rejecting, so the target
    vanished from the digest with exit 0 — silent data loss.
    """

    def _survives(self, victim):
        entries = self.led.entries()
        self.assertIn_(
            victim, "\n".join(entries),
            "the valid supersede target must stay live in the digest",
        )

    def test_votes_superseding_a_memory_record_keeps_the_target(self):
        victim = self.led.add("victim", "Valid knowledge that must survive.")
        survivor = self.led.add("survivor", "A live sibling so the ledger is not empty.")
        # a parse-valid votes record (has plan:, up:) whose supersedes: points
        # at a memory record — rejected by the type-compat rule mid-loop
        self.led.add(
            "badvote", type="votes", date="2026-01-06", plan="2026-01-06-p",
            up=survivor, supersedes=victim,
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(victim)
        self.assertIn_("live=2", self.header(),
                       "both memory records must be live")

    def test_memory_superseding_a_votes_record_keeps_the_votes_alive(self):
        # a votes record is a valid target for nothing but another votes
        # record; a memory record trying to retire it is rejected mid-loop.
        # The harm the pre-fix compiler did was subtler than a vanished entry:
        # it applied dead[votes-record], silently DISABLING the vote. So the
        # assertion is that the vote still counts, not just that the target
        # is listed.
        target = self.led.add("voted", "A statement carrying a vote.")
        closer = self.led.add("closer", type="votes", date="2026-01-06",
                              plan="2026-01-06-p", up=target)
        # this memory record illegally supersedes the votes record
        self.led.add("bad-memory", "Tries to retire a votes record.",
                     date="2026-01-07", supersedes=closer)

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_(target, "\n".join(self.led.entries()))
        self.assertIn_("+1]", self.led.digest(),
                       "the vote must survive: the illegal superseder is "
                       "quarantined, so the votes record is never marked dead")

    def test_duplicate_target_after_a_valid_one_voids_the_whole_record(self):
        """A record whose edge list is `A, A` is malformed. The first edge
        is valid in isolation, but the record is quarantined, so NEITHER
        edge may apply — the target must survive."""
        target = self.led.add("dup-target", "Must not be retired by a bad record.")
        self.led.add("other", "A live sibling.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-08-dupsup-33333.md",
            "---\ntype: tombstone\n"
            f"supersedes: {target}, {target}\n"
            "created: 2026-01-08\nschema: 3\n---\nRetires it twice.\n",
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(target)

    def test_self_supersede_alongside_a_valid_target_voids_the_record(self):
        target = self.led.add("real-target", "Must survive a self-referential record.")
        self.led.add("other", "A live sibling.")
        rid = "2026-01-08-selfsup-44444"
        self.led.write(
            f"zamm-memory/knowledge/2026/{rid}.md",
            "---\ntype: tombstone\n"
            f"supersedes: {target}, {rid}\n"
            "created: 2026-01-08\nschema: 3\n---\nRetires target and itself.\n",
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(target)

    def test_cycle_member_pointing_at_an_external_target_spares_it(self):
        """Two records supersede each other (a cycle) and one also points at
        an innocent external memory record. The cycle members are
        quarantined; the external target must not be dragged down with them."""
        external = self.led.add("bystander", "Innocent record outside the cycle.")
        self.led.add("live", "Keeps the ledger non-empty.")
        # a <-> b cycle, and a also supersedes the bystander
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-08-cyc-a-55555.md",
            "---\ntype: tombstone\n"
            f"supersedes: 2026-01-08-cyc-b-66666, {external}\n"
            "created: 2026-01-08\nschema: 3\n---\nA.\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-08-cyc-b-66666.md",
            "---\ntype: tombstone\n"
            "supersedes: 2026-01-08-cyc-a-55555\n"
            "created: 2026-01-08\nschema: 3\n---\nB.\n",
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(external)

    def test_parse_time_quarantine_still_drops_edges(self):
        """The pre-fix compiler already handled this case correctly (a record
        rejected before the edge loop contributes nothing); lock it so the
        rewrite does not regress it."""
        victim = self.led.add("guarded", "Must survive an unreadable superseder.")
        self.led.add("live", "A live sibling.")
        # missing schema: -> quarantined at parse time, before edges walk
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-09-noschema-77777.md",
            "---\ntype: tombstone\n"
            f"supersedes: {victim}\n"
            "created: 2026-01-09\n---\nNo schema, retires the victim.\n",
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(victim)

    def test_check_still_reports_the_violation(self):
        """Quarantine-then-drop must not silence --check: the record is still
        invalid and the ledger must fail validation."""
        victim = self.led.add("victim", "Valid knowledge.")
        self.led.add("badvote", type="votes", date="2026-01-06",
                     plan="2026-01-06-p", up=victim, supersedes=victim)

        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("votes record", r.err)


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


class Rev3Generation(ZammTest):
    """PRE-FIX: memory.md and state.tsv are two separate renames; a compile
    dying between them paired a fresh sidecar with a stale digest, and memory
    list served records the published digest never surfaced."""

    def test_mismatched_pair_is_refused_by_memory_list(self):
        self.led.add("one", "First.")
        self.assertCode(self.led.compile(), EXIT_OK)
        old_digest = self.led.digest()
        self.led.add("two", "Second.", date="2026-01-06")
        self.assertCode(self.led.compile(), EXIT_OK)
        # simulate a compile interrupted between the renames: the digest is
        # from the previous generation, the sidecar from the new one
        self.led.write("zamm-memory/.compiled/memory.md", old_digest)
        r = self.led.memory_list()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("different compiles", r.err)
        # --all does not consume the sidecar and must still work
        self.assertCode(self.led.memory_list("--all"), EXIT_OK)

    def test_mismatched_pair_downgrades_status_counts(self):
        self.led.add("one", "First.")
        self.assertCode(self.led.compile(), EXIT_OK)
        old_digest = self.led.digest()
        self.led.add("two", "Second.", date="2026-01-06")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.led.write("zamm-memory/.compiled/memory.md", old_digest)
        r = self.led.status()
        self.assertCode(r, EXIT_OK)
        self.assertIn_("counts unavailable", r.out)

    def test_coherent_pair_lists_normally(self):
        self.led.add("one", "First.")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertCode(self.led.memory_list(), EXIT_OK)


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


class ConcurrentPublishesKeepBothRecords(ZammTest):
    """The digest is derived and disposable (references/invariants.md, G2), so
    two concurrent publishes may well leave it one record behind — the older
    compile renames its result into place last and wins. What must hold is
    stronger and simpler than the lock this used to need: both RECORDS land in
    the ledger, and one ordinary recompile shows both again.

    This is the deliberate trade recorded in the invariants: a stale digest is
    normal operation under eventual consistency, a lost record is not.

    Deterministic interleaving via an awk shim on PATH: the FIRST publish-mode
    compile awk (publish 1's recompile, whose manifest predates record beta)
    pauses until a release file appears; publish 2 runs meanwhile."""

    SHIM = """#!/bin/sh
# pause the FIRST publish-mode compile awk until the release file appears.
# Publish mode is check=0 with no list flags — the main awk invocation gets
# all of them as explicit var=value arguments.
hit=0
for a in "$@"; do
  case "$a" in
    check=0) hit=1 ;;
    listinert=1|listlive=1|listvotes=1) hit=0; break ;;
  esac
done
if [ "$hit" = 1 ] && mkdir "$ZAMM_TEST_BARRIER/once" 2>/dev/null; then
  : > "$ZAMM_TEST_BARRIER/paused"
  while [ ! -e "$ZAMM_TEST_BARRIER/go" ]; do sleep 0.02; done
fi
exec {REAL_AWK} "$@"
"""

    def test_both_records_land_and_one_recompile_shows_both(self):
        import shutil
        import stat
        import tempfile

        self.led.add("seed", "Seed record.")
        rids = {}
        for slug in ("alpha", "beta"):
            d = self.led.draft(slug, f"Publish {slug}.")
            rids[slug] = os.path.basename(d)[: -len(".md.draft")]

        real_awk = shutil.which("awk")
        self.assertTrue(real_awk, "no awk on PATH")
        with tempfile.TemporaryDirectory() as td:
            barrier = os.path.join(td, "barrier")
            os.mkdir(barrier)
            shim = os.path.join(td, "awk")
            with open(shim, "w") as fh:
                fh.write(self.SHIM.replace("{REAL_AWK}", f'"{real_awk}"'))
            os.chmod(shim, os.stat(shim).st_mode | stat.S_IEXEC)

            base_env = dict(os.environ, ZAMM_TODAY=PINNED_TODAY)
            shim_env = dict(base_env,
                            PATH=td + os.pathsep + os.environ["PATH"],
                            ZAMM_TEST_BARRIER=barrier)
            cmd = ["sh", str(SCRIPTS / "zamm-run.sh"),
                   "--project-root", str(self.led.root), "memory", "publish"]

            p1 = subprocess.Popen(cmd + [rids["alpha"]],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, env=shim_env, cwd=str(self.led.root))
            p2 = None
            try:
                # wait until publish 1 is inside its recompile: alpha is
                # already live, and the compile's manifest predates beta
                deadline = time.time() + 20
                paused = os.path.join(barrier, "paused")
                while not os.path.exists(paused) and time.time() < deadline:
                    if p1.poll() is not None:
                        break
                    time.sleep(0.01)
                if not os.path.exists(paused):
                    try:
                        out, err = p1.communicate(timeout=10)
                    except subprocess.TimeoutExpired:
                        out, err = "", "(publish 1 still running, no pause marker)"
                    self.fail(f"publish 1 never reached its recompile: {out} {err}")

                p2 = subprocess.Popen(cmd + [rids["beta"]],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      text=True, env=base_env, cwd=str(self.led.root))
                p2.wait(timeout=90)
                with open(os.path.join(barrier, "go"), "w"):
                    pass
                out1, err1 = p1.communicate(timeout=90)
                out2, err2 = p2.communicate(timeout=90)
            finally:
                for p in (p1, p2):
                    if p is not None and p.poll() is None:
                        p.kill()
                        p.communicate()

        self.assertEqual(p1.returncode, 0, err1)
        self.assertEqual(p2.returncode, 0, err2)

        # the ledger is the truth, and it kept both
        for slug in ("alpha", "beta"):
            self.assertTrue(
                self.led.exists(f"zamm-memory/knowledge/2026/{rids[slug]}.md"),
                f"{slug} was lost from the ledger")

        # the digest may lag by one record; a rerun is the whole repair
        self.assertCode(self.led.compile(), EXIT_OK)
        digest = self.led.digest()
        self.assertIn_("Publish alpha.", digest)
        self.assertIn_("Publish beta.", digest)
        state = self.led.read("zamm-memory/.compiled/state.tsv")
        for slug in ("alpha", "beta"):
            self.assertIn_(f"select\t{rids[slug]}", state)


class Rev3ZeroLive(ZammTest):
    """PRE-FIX: the zero-live branch exited 0 with a clean "not initialized"
    digest even when the ledger held invalid vote references or duplicate
    votes records — known graph defects rendered as a healthy empty ledger."""

    def test_ghost_vote_ref_with_no_live_memory_degrades(self):
        self.led.add("votes", type="votes", plan="someplan",
                     up="2026-01-01-ghost-zzzzz", date="2026-01-05", sfx="vvvvv")
        r = self.led.compile()
        self.assertCode(r, EXIT_DEGRADED)
        d = self.led.digest()
        self.assertIn_("not been initialized", d)
        self.assertIn_("Invalid vote references", d)

    def test_duplicate_votes_with_no_live_memory_degrade(self):
        for date, sfx in (("2026-01-05", "vaaaa"), ("2026-01-06", "vbbbb")):
            self.led.add("votes", type="votes", plan="someplan",
                         up="2026-01-01-ghost-zzzzz", date=date, sfx=sfx)
        r = self.led.compile()
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_("Duplicate vote records", self.led.digest())

    def test_truly_empty_ledger_still_exits_clean(self):
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("not been initialized", self.led.digest())


class Rev6WarningSeverity(ZammTest):
    """PRE-FIX: publish diffed UNDIFFERENTIATED check stderr, so when any
    pre-existing error made the overall check fail, a candidate whose only
    output was a WARNING was rejected with that warning shown under "New
    errors"."""

    def test_warning_only_candidate_publishes_beside_preexisting_error(self):
        self.led.add("alive", "A living record.")
        # pre-existing, unrelated ERROR: a dangling supersedes target
        self.led.add("dangler", "Points at a missing target.",
                     date="2026-01-06", sfx="66666",
                     supersedes="2026-01-01-nonexistent-77777")
        self.assertCode(self.led.check(), EXIT_CONTRACT)

        cand = "2026-01-07-warnonly-88888"
        self.led.write(
            f"zamm-memory/knowledge/2026/{cand}.md.draft",
            "---\ntype: memory\nscope: internals\nfuturekey: value\n"
            "importance: useful\ndurability: months\ncreated: 2026-01-07\n"
            "schema: 3\n---\nA perfectly valid record body.\n")

        p = self.led.memory_publish(cand)
        self.assertCode(p, EXIT_OK,
                        "a warning-only candidate must publish cleanly")
        self.assertTrue(self.led.exists(f"zamm-memory/knowledge/2026/{cand}.md"))
        self.assertNotIn_("New errors", p.err)


if __name__ == "__main__":
    unittest.main()
