"""Regression locks for the THIRD-pass review (2026-08-04 re-review of the
second-review remediation). One class per confirmed finding:

  Rev3PublishBlame        publish judged the candidate by grepping its id in
                          --check stderr; now judged by a before/after error
                          DIFF (new error lines = the candidate's fault)
  Rev3PublishInterrupt    automated Ctrl-C (process-group SIGINT) mid-publish:
                          rollback trap restores the draft, rc 130
  Rev3PlanTraversal       plan: is a slug, never a path ("..", "../plans");
                          an empty archive/plans/<dir> is not a plan
  Rev3VoteLaundering      vote bookkeeping cannot be laundered through an
                          Abandoned status or by archiving the plan
  Rev3ZeroLive            invalid/duplicate votes still degrade (exit 2) when
                          no live memory record survives
  Rev3TsvSafety           --list-votes emits normalized lists; a legal TAB
                          inside a vote list cannot shift TSV columns
  Rev3Generation          digest and state sidecar carry one generation token;
                          consumers refuse a mismatched (interrupted) pair
  Rev3AbandonedScope      a worked-on Abandoned plan inherits Scope/Done-when
                          validation (empty scope, '- [?]' malformed boxes)
  Rev3CrosscheckFailClosed  the cross-check fails when the compiler cannot
                          enumerate votes records, instead of passing on an
                          empty list

A fourth pass (2026-08-04) confirmed all of the above fixed and found two
remaining defects, locked as:

  Rev4ConcurrentPublish   two interleaved publishes could both report success
                          while the final digest/sidecar (older snapshot,
                          published last) silently omitted one record; the
                          compiler now serializes publish-mode runs with a
                          lock held from enumeration through the rename
  Rev4PlanFieldTabs       tabs in a plan's Memory-upvotes/downvotes made
                          semantically equal sets disagree in the cross-check

A fifth pass found one race in the stale-lock recovery itself, locked as:

  Rev5StaleLockReap       two contenders could both authorize removal of one
                          dead-owner lock; the slower rm destroyed the lock
                          the faster contender had already reacquired, putting
                          two compiles back in flight — reaping now happens
                          only under a reaper mutex with the same owner
                          revalidated while holding it, and the cleanup trap
                          releases the lock only while its pid file still
                          names the exiting process
"""

import os
import signal
import subprocess
import time
import unittest

from harness import (
    needs_permission_bits,
    EXIT_CONTRACT,
    EXIT_DEGRADED,
    EXIT_OK,
    SCRIPTS,
    PINNED_TODAY,
    ZammTest,
)


BROKEN_RECORD = (
    "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
    "durability: years\ncreated: 2026-01-06\n---\nNo schema line.\n"
)


def review_plan(upvotes, status="Review", extra_head=""):
    """A plan file text that passes plan check at the given status."""
    head = f"# P\nStatus: {status}\n{extra_head}"
    head += ("Execution-context-before: x\nComplexity-forecast: gecko\n"
             f"Memory-upvotes: {upvotes}\nLast updated: 2026-07-19\n\n"
             "Scope:\n* In: x\n* Out: nothing.\n\n"
             "## Done-when\n- [x] d\n\n## Learnings\n- L.\n\n")
    if status == "Abandoned":
        head += "## Loose ends\n\n- Abandoned for a synthetic reason.\n\n"
    head += ("Execution-friction-after: n\nComplexity-felt: gecko\n"
             "Complexity-delta: as-expected\n")
    if status == "Done":
        head += ("Done-approved-by: fixture\nDone-approved-at: 2026-07-19\n"
                 "Done-approval-evidence: synthetic\n")
    return head


# ----------------------------------------------------------------------
# Rev3 finding 2 — publish candidate attribution
# ----------------------------------------------------------------------
class Rev3PublishBlame(ZammTest):
    """PRE-FIX: `grep -Fq "$rid" errfile` decided the candidate's fate. That
    rejected a valid draft when an unrelated error mentioned a longer id
    embedding the draft id, and PUBLISHED a bad draft whenever the new error
    named some other record (duplicate votes blame the canonical id) or none
    at all ("other holds 6 live records")."""

    def _draft(self, slug="short", scope="contracts/api"):
        r = self.led.zamm("memory", "create", "--scope", scope, slug)
        self.assertCode(r, EXIT_OK)
        draft = r.out.strip()
        with open(draft, "a") as fh:
            fh.write("A valid body.\n")
        rid = os.path.basename(draft)[: -len(".md.draft")]
        return draft, rid

    def test_embedded_id_in_an_unrelated_error_does_not_reject(self):
        self.led.add("live", "A live record.")
        draft, rid = self._draft()
        # unrelated invalid record whose FILENAME embeds the draft id: its
        # --check error line contains rid as a substring, in both the baseline
        # and the after run
        self.led.write(
            f"zamm-memory/knowledge/2026/2026-01-07-x-{rid}-e-33333.md",
            BROKEN_RECORD,
        )
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{rid}.md"),
            "valid draft must land despite an unrelated error embedding its id")

    def test_capacity_violation_names_no_record_but_still_rejects(self):
        # five live `other` records pass --check; the candidate makes six.
        # The diagnostic ("other holds 6 live records") names no record id.
        for i in range(5):
            self.led.add(f"otherrec{i}", f"Other {i}.", scope="other")
        draft, rid = self._draft(slug="sixth", scope="other")
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("other holds", p.err)
        self.assertTrue(os.path.exists(draft), "rejected draft must be restored")
        self.assertFalse(
            self.led.exists(f"zamm-memory/knowledge/2026/{rid}.md"),
            "a capacity-violating record must not stay live")

    def test_second_votes_record_blaming_the_canonical_still_rejects(self):
        m = self.led.add("real", "R.")
        # existing canonical votes record (newest id wins)
        self.led.add("votes", type="votes", plan="someplan", up=m,
                     date="2026-01-06", sfx="vvvvv")
        # the candidate sorts OLDER, so the duplicate-votes diagnostic names
        # only the plan and the CANONICAL record - never the candidate
        did = "2026-01-05-morevotes-22222"
        self.led.write(
            f"zamm-memory/knowledge/2026/{did}.md.draft",
            f"---\ntype: votes\nplan: someplan\nup: {m}\ndown:\n"
            "created: 2026-01-05\nschema: 3\n---\n",
        )
        p = self.led.memory_publish(did)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("active votes records for one plan", p.err)
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{did}.md.draft"))
        self.assertFalse(
            self.led.exists(f"zamm-memory/knowledge/2026/{did}.md"))

    def test_preexisting_unrelated_errors_still_do_not_block(self):
        self.led.add("live", "A live record.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-bbbbb.md",
            BROKEN_RECORD,
        )
        draft, rid = self._draft()
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)

    def test_validation_failure_does_not_claim_interruption(self):
        r = self.led.zamm("memory", "create", "--scope", "contracts/api", "e")
        draft = r.out.strip()  # body left empty -> invalid
        rid = os.path.basename(draft)[: -len(".md.draft")]
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("did not validate", p.err)
        self.assertNotIn_("publish interrupted", p.err)

    @needs_permission_bits
    def test_unvalidatable_ledger_fails_closed(self):
        self.led.add("alpha", "A.")
        self.led.add("hidden", "H.", date="2025-03-05")
        draft, rid = self._draft()
        locked = self.led.root / "zamm-memory/knowledge/2025"
        os.chmod(locked, 0o000)
        try:
            p = self.led.memory_publish(rid)
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("could not validate", p.err)
        self.assertTrue(os.path.exists(draft), "draft must be restored")


# ----------------------------------------------------------------------
# Rev3 test-quality finding — automated SIGINT publish test
# ----------------------------------------------------------------------
@unittest.skipUnless(hasattr(os, "killpg"), "needs POSIX process groups")
class Rev3PublishInterrupt(ZammTest):
    """A faithful Ctrl-C is a process-group SIGINT. Interrupting the publish
    mid-validation must fire the rollback trap: the record returns to a draft
    and no live .md remains."""

    def test_sigint_mid_validation_restores_the_draft(self):
        # enough records that the post-rename --check leaves a wide window
        self.led.add_many(60)
        r = self.led.zamm("memory", "create", "--scope", "contracts/api", "victim")
        draft = r.out.strip()
        with open(draft, "a") as fh:
            fh.write("A valid body.\n")
        rid = os.path.basename(draft)[: -len(".md.draft")]
        final = draft[: -len(".draft")]

        env = dict(os.environ)
        env["ZAMM_TODAY"] = PINNED_TODAY
        proc = subprocess.Popen(
            ["sh", str(SCRIPTS / "zamm-run.sh"), "--project-root",
             str(self.led.root), "memory", "publish", rid],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env=env, cwd=str(self.led.root), preexec_fn=os.setsid,
        )
        try:
            # the rename precedes validation; once the final .md exists the
            # publish is inside its validation window
            deadline = time.time() + 20
            while not os.path.exists(final) and time.time() < deadline:
                if proc.poll() is not None:
                    break
                time.sleep(0.005)
            self.assertTrue(proc.poll() is None and os.path.exists(final),
                            "publish finished before it could be interrupted")
            os.killpg(os.getpgid(proc.pid), signal.SIGINT)
            out, err = proc.communicate(timeout=30)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()

        self.assertEqual(proc.returncode, 130, err)
        self.assertTrue(os.path.exists(draft),
                        "interrupted publish must restore the draft")
        self.assertFalse(os.path.exists(final),
                         "interrupted publish must not leave a live record")


# ----------------------------------------------------------------------
# Rev3 finding 1 — plan: path traversal
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# Rev3 finding 3 — vote bookkeeping laundering
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# Rev3 finding 4 — zero-live ledgers still degrade
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# Rev3 finding 5 — --list-votes is a safe TSV surface
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# Rev3 finding 6 — digest/sidecar generation coherence
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# Rev3 finding 7 — worked Abandoned inherits Scope/Done-when validation
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# Rev3 (second reviewer) — cross-check fails closed
# ----------------------------------------------------------------------
class Rev3CrosscheckFailClosed(ZammTest):
    """PRE-FIX: `--list-votes ... || true` swallowed a compiler failure, so an
    unenumerable ledger produced an empty votes list and the cross-check
    reported success on a ledger nobody actually read."""

    @needs_permission_bits
    def test_cross_check_refuses_when_the_compiler_cannot_enumerate(self):
        self.led.add("alpha", "A.")
        self.led.add("hidden", "H.", date="2025-03-05")
        locked = self.led.root / "zamm-memory/knowledge/2025"
        os.chmod(locked, 0o000)
        try:
            r = self.led.run("zamm-crosscheck.sh")
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("could not list votes records", r.err)


# ----------------------------------------------------------------------
# Rev4 — concurrent publishes must not lose a record from the digest
# ----------------------------------------------------------------------
@unittest.skipUnless(hasattr(os, "killpg"), "needs POSIX process control")
class Rev4ConcurrentPublish(ZammTest):
    """PRE-FIX: each compile snapshots the ledger into a private manifest and
    unconditionally renames its result into place, so an older, slower compile
    could overwrite a newer digest — two publishes both reported success while
    the final digest/sidecar pair (internally coherent, so the generation
    token cannot catch it) silently omitted one record. The compiler now holds
    a lock from enumeration through the rename, making published views
    monotonically fresh.

    Deterministic interleaving via an awk shim on PATH: the FIRST publish-mode
    compile awk (publish 1's final recompile, whose manifest predates record
    beta) pauses until a release file appears; publish 2 runs meanwhile."""

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

    def test_two_interleaved_publishes_both_reach_the_digest(self):
        import shutil
        import stat
        import subprocess
        import tempfile
        import time

        from harness import PINNED_TODAY, SCRIPTS

        self.led.add("seed", "Seed record.")
        rids, drafts = {}, {}
        for slug in ("alpha", "beta"):
            r = self.led.zamm("memory", "create", "--scope", "contracts/api", slug)
            self.assertCode(r, EXIT_OK)
            d = r.out.strip()
            with open(d, "a") as fh:
                fh.write(f"Publish {slug}.\n")
            drafts[slug] = d
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
                # wait until publish 1 is inside its final recompile: alpha is
                # renamed live, and the compile's manifest predates beta
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
                # pre-fix, publish 2 completes here (and its fresh digest is
                # about to be overwritten); post-fix it blocks on the lock
                deadline = time.time() + 2.5
                while p2.poll() is None and time.time() < deadline:
                    time.sleep(0.02)

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
        digest = self.led.digest()
        self.assertIn_("Publish alpha.", digest)
        self.assertIn_("Publish beta.", digest,
                       "a completed publish vanished from the final digest")
        state = self.led.read("zamm-memory/.compiled/state.tsv")
        for slug in ("alpha", "beta"):
            self.assertIn_(f"select\t{rids[slug]}", state)


# ----------------------------------------------------------------------
# Rev5 — stale-lock recovery must not destroy the new owner's lock
# ----------------------------------------------------------------------
@unittest.skipUnless(hasattr(os, "killpg"), "needs POSIX process control")
class Rev5StaleLockReap(ZammTest):
    """PRE-FIX: every contender independently read the stale owner pid,
    decided it was dead, and ran `rm -rf` on the lock. Two contenders could
    both authorize removal; one removed and reacquired, then the other's
    delayed rm deleted the NEW owner's lock and two compiles ran concurrently
    — the older snapshot, published last, silently dropped a record. Reaping
    now happens only under a reaper mutex, revalidating the same dead owner
    while holding it.

    Deterministic setup: a dead-pid lock; contender B's `rm` is shimmed to
    pause whenever it targets the lock dir (under the fix B holds the reaper
    mutex at that moment); contender A (awk shimmed to pause its publish, rm
    real) races the recovery meanwhile."""

    RM_SHIM = """#!/bin/sh
case "$*" in
  *'.compile.lock'*)
    : > "$ZAMM_TEST_BARRIER/b_at_rm"
    while [ ! -e "$ZAMM_TEST_BARRIER/go_rm" ]; do /bin/sleep 0.02; done
    ;;
esac
exec {REAL_RM} "$@"
"""

    AWK_SHIM = """#!/bin/sh
hit=0
for a in "$@"; do
  case "$a" in
    check=0) hit=1 ;;
    listinert=1|listlive=1|listvotes=1) hit=0; break ;;
  esac
done
if [ "$hit" = 1 ] && mkdir "$ZAMM_TEST_BARRIER/once" 2>/dev/null; then
  : > "$ZAMM_TEST_BARRIER/a_paused"
  while [ ! -e "$ZAMM_TEST_BARRIER/go_a" ]; do /bin/sleep 0.02; done
fi
exec {REAL_AWK} "$@"
"""

    def _shim(self, tddir, name, template, real):
        import stat
        d = os.path.join(tddir, name + "dir")
        os.mkdir(d)
        path = os.path.join(d, name)
        with open(path, "w") as fh:
            fh.write(template.replace("{REAL_" + name.upper() + "}", f'"{real}"'))
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
        return d

    def test_concurrent_reap_cannot_lose_a_record(self):
        import shutil
        import subprocess
        import tempfile
        import time

        from harness import PINNED_TODAY, SCRIPTS

        self.led.add("alpha", "Alpha is live.")
        self.assertCode(self.led.compile(), EXIT_OK)
        lock = self.led.root / "zamm-memory/.compiled/.compile.lock"
        lock.mkdir()
        (lock / "pid").write_text("99999999\n")

        real_rm = shutil.which("rm")
        real_awk = shutil.which("awk")
        cmd = ["sh", str(SCRIPTS / "internal/zamm-compile.sh"),
               "--project-root", str(self.led.root)]
        with tempfile.TemporaryDirectory() as td:
            barrier = os.path.join(td, "barrier")
            os.mkdir(barrier)
            rm_dir = self._shim(td, "rm", self.RM_SHIM, real_rm)
            awk_dir = self._shim(td, "awk", self.AWK_SHIM, real_awk)
            base = dict(os.environ, ZAMM_TODAY=PINNED_TODAY,
                        ZAMM_TEST_BARRIER=barrier)
            env_b = dict(base, PATH=rm_dir + os.pathsep + os.environ["PATH"])
            env_a = dict(base, PATH=awk_dir + os.pathsep + os.environ["PATH"])

            b = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True,
                                 env=env_b, cwd=str(self.led.root))
            a = None
            try:
                deadline = time.time() + 20
                at_rm = os.path.join(barrier, "b_at_rm")
                while not os.path.exists(at_rm) and time.time() < deadline:
                    if b.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(os.path.exists(at_rm),
                                "contender B never reached the stale-lock rm")

                a = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True,
                                     env=env_a, cwd=str(self.led.root))
                # PRE-FIX, A reaps the stale lock itself (its rm is real),
                # reacquires, and pauses at its publish awk with a manifest
                # that predates beta. POST-FIX, A cannot reap while B holds
                # the reaper mutex, so the pause marker cannot appear.
                deadline = time.time() + 3
                a_paused = os.path.join(barrier, "a_paused")
                while not os.path.exists(a_paused) and time.time() < deadline:
                    if a.poll() is not None:
                        break
                    time.sleep(0.01)
                pre_fix_interleave = os.path.exists(a_paused)

                self.led.add("beta", "Beta is live.", date="2026-01-06")
                if not pre_fix_interleave:
                    # fixed behavior: A must never pause while holding the
                    # lock (B would starve on it), so release its awk first
                    with open(os.path.join(barrier, "go_a"), "w"):
                        pass
                with open(os.path.join(barrier, "go_rm"), "w"):
                    pass
                bout, berr = b.communicate(timeout=90)
                if pre_fix_interleave:
                    with open(os.path.join(barrier, "go_a"), "w"):
                        pass
                aout, aerr = a.communicate(timeout=90)
            finally:
                for p in (a, b):
                    if p is not None and p.poll() is None:
                        p.kill()
                        p.communicate()

        self.assertEqual(b.returncode, 0, berr)
        self.assertEqual(a.returncode, 0, aerr)
        digest = self.led.digest()
        self.assertIn_("Alpha is live.", digest)
        self.assertIn_("Beta is live.", digest,
                       "a record was lost to a raced stale-lock recovery")
        self.assertFalse(
            self.led.exists("zamm-memory/.compiled/.compile.lock"),
            "no lock may remain after both compiles exited")
        self.assertFalse(
            self.led.exists("zamm-memory/.compiled/.compile.reaper"),
            "no reaper mutex may remain after both compiles exited")


# ----------------------------------------------------------------------
# Rev4 — tabs in plan vote fields must not cause false disagreement
# ----------------------------------------------------------------------
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
