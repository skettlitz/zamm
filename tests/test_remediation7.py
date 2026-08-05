"""Regression locks for the third EXTERNAL review (2026-08-04, "Updated
Revision"). One class per confirmed finding; the numbering follows the
review's own regression list (section 14):

  Rev6ShunFailClosed      1,2  an unreadable or symlinked shun.md aborts the
                               compile (exit 4, previous digest untouched)
                               instead of resurrecting erased content through
                               an empty substitute shun set
  Rev6PlanTreeFailClosed  3,4  an unreadable plan tree (active or archive) is
                               exit 4 in every consumer, never "0 plans"
  Rev6PlanSymlinks        5,6  symlinked plan directories and plan files are
                               rejected and their content never reaches the
                               digest
  Rev6PublishAtomic       7    a rejected candidate never touches the live
                               namespace, digest, or sidecar; status reports
                               sidecar-vs-disk divergence
  Rev6InertGraphNodes     8,9  archived and shunned supersede targets keep
                               union-find grouping: competing successors of a
                               retired id surface under Needs reconciliation
  Rev6WarningSeverity     10   a warning-only candidate publishes cleanly
                               beside unrelated pre-existing errors
  Rev6PlanIdUniqueness    11   plan ids are unique across active AND archive
                               (create-time refusal, check-time detection)
  Rev6DraftVisibility     12   memory drafts / status draft count / stale
                               flag / memory discard
  Rev6ArchiveGate         13   plan archive refuses a plan whose votes record
                               disagrees with its declared votes

Item 14 (root-awareness) is the `needs_permission_bits` skip decorator in
harness.py, applied to every permission-bit fault-injection test — including
the ones here.
"""

import os
import shutil
import time

from harness import (
    needs_permission_bits,
    EXIT_CONTRACT,
    EXIT_OK,
    EXIT_UNREADABLE,
    ZammTest,
)


ARCHIVED_MEMORY = (
    "---\ntype: memory\nscope: internals\nimportance: useful\n"
    "durability: months\ncreated: {date}\nschema: 3\n{extra}---\n{body}\n"
)


def archived_record(date, body, supersedes=""):
    extra = f"supersedes: {supersedes}\n" if supersedes else ""
    return ARCHIVED_MEMORY.format(date=date, extra=extra, body=body)


# ----------------------------------------------------------------------
# review items 1, 2 — shun.md fails closed
# ----------------------------------------------------------------------
class Rev6ShunFailClosed(ZammTest):
    """PRE-FIX: read_shun had no getline error probe, so an unreadable
    shun.md compiled with an EMPTY substitute shun set and the digest
    resurrected content the erasure procedure had removed; a symlinked
    shun.md was skipped by the manifest (`-type f`) with the same effect."""

    def _erased_fixture(self):
        self.led.add("alive", "A living record.")
        secret = self.led.add("secret", "REDACTED SECRET CONTENT.")
        self.led.shun(secret)
        self.led.delete(secret)
        self.assertCode(self.led.compile(), EXIT_OK)
        digest = self.led.digest()
        self.assertNotIn_("REDACTED SECRET CONTENT", digest)
        return digest

    @needs_permission_bits
    def test_unreadable_shun_refuses_and_preserves_digest(self):
        before = self._erased_fixture()
        locked = self.led.root / "zamm-memory/knowledge/shun.md"
        os.chmod(locked, 0o000)
        try:
            r = self.led.compile()
            c = self.led.check()
        finally:
            os.chmod(locked, 0o644)
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("cannot read the shun file", r.err)
        self.assertCode(c, EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "previous digest must survive an unreadable shun.md")
        self.assertNotIn_("REDACTED SECRET CONTENT", self.led.digest(),
                          "shun-read failure must never resurrect erased content")

    def test_symlinked_shun_is_refused(self):
        before = self._erased_fixture()
        shun = self.led.root / "zamm-memory/knowledge/shun.md"
        real = self.led.root / "real-shun.md"
        shun.rename(real)
        os.symlink(real, shun)
        r = self.led.compile()
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("symlink", r.err)
        self.assertEqual(before, self.led.digest())

    def test_missing_shun_stays_a_legal_empty_set(self):
        self.led.add("alive", "A living record.")
        self.assertFalse(self.led.exists("zamm-memory/knowledge/shun.md"))
        self.assertCode(self.led.compile(), EXIT_OK)


# ----------------------------------------------------------------------
# review items 3, 4 — the plan tree fails closed in every consumer
# ----------------------------------------------------------------------
class Rev6PlanTreeFailClosed(ZammTest):
    """PRE-FIX: every consumer enumerated plans with a private glob or find;
    a chmod-000 active/plans expanded to nothing and `plan check`, `check`,
    `status` and the digest all reported a healthy zero-plan project."""

    @needs_permission_bits
    def test_unreadable_active_plans_fails_every_consumer(self):
        self.led.add("alive", "A living record.")
        self.led.add_plan("2026-01-05-real", status="Implementing")
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()

        locked = self.led.root / "zamm-memory/active/plans"
        os.chmod(locked, 0o000)
        try:
            pc = self.led.plan_check()
            ca = self.led.check_all()
            st = self.led.status()
            pl = self.led.plan_list()
            dg = self.led.compile()
        finally:
            os.chmod(locked, 0o755)

        for name, r in (("plan check", pc), ("check", ca),
                        ("status", st), ("plan list", pl), ("digest", dg)):
            self.assertCode(r, EXIT_UNREADABLE,
                            f"{name} must fail loudly on an unreadable plan tree")
        self.assertNotIn_("0 plan(s)", pc.out + pc.err)
        self.assertEqual(before, self.led.digest(),
                         "an unreadable plan tree must not overwrite the digest")

    @needs_permission_bits
    def test_unreadable_archive_plans_fails_too(self):
        self.led.add("alive", "A living record.")
        self.led.add_plan("2026-01-05-real", status="Implementing")
        locked = self.led.root / "zamm-memory/archive/plans"
        os.chmod(locked, 0o000)
        try:
            pc = self.led.plan_check()
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(pc, EXIT_UNREADABLE)


# ----------------------------------------------------------------------
# review items 5, 6 — plan symlinks are rejected, not followed
# ----------------------------------------------------------------------
class Rev6PlanSymlinks(ZammTest):
    """PRE-FIX: `[ -d "$pd" ]` in the compiler plans tail follows symlinks,
    so a symlinked plan directory rendered EXTERNAL untracked content into
    the digest even while plan check was erroring about it."""

    def test_symlinked_plan_dir_fails_check_and_never_reaches_digest(self):
        self.led.add("alive", "A living record.")
        ext = self.led.root / "external-plan"
        ext.mkdir()
        (ext / "evil.plan.md").write_text(
            "Status: Implementing\nLast updated: 2026-01-05\n\n"
            "# EXTERNAL UNTRACKED PLAN\n\n## Done-when\n- [ ] anything\n")
        os.symlink(ext, self.led.root / "zamm-memory/active/plans/evil")

        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("symlink", pc.err)

        r = self.led.compile()
        self.assertIn(r.code, (EXIT_OK, 2))
        self.assertNotIn_("EXTERNAL UNTRACKED PLAN", self.led.digest(),
                          "external content must never reach the digest")

    def test_symlinked_main_plan_file_is_rejected(self):
        self.led.add("alive", "A living record.")
        ext = self.led.root / "external.plan.md"
        ext.write_text("Status: Done\nLast updated: 2026-01-05\n"
                       "# EXTERNAL FILE BODY\n")
        pd = self.led.root / "zamm-memory/active/plans/2026-01-05-linked"
        pd.mkdir(parents=True)
        os.symlink(ext, pd / "2026-01-05-linked.plan.md")

        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("symlink", pc.err)

        self.assertIn(self.led.compile().code, (EXIT_OK, 2))
        self.assertNotIn_("EXTERNAL FILE BODY", self.led.digest())


# ----------------------------------------------------------------------
# review item 7 — publication is atomic: no rollback residue anywhere
# ----------------------------------------------------------------------
class Rev6PublishAtomic(ZammTest):
    """PRE-FIX: publish renamed the draft into the live namespace BEFORE
    validating, and a rejection renamed it back without recompiling — so a
    concurrent compile in that window published a digest and sidecar naming
    a quarantined record whose file was a draft again, and nothing ever
    reported the divergence."""

    def test_rejected_candidate_is_never_visible_live(self):
        """Deterministic probe of the pre-fix window: the verdict pipeline
        calls `comm`, which pre-fix ran while the candidate had already been
        renamed into the live namespace — exactly when a concurrent compile
        could publish a digest naming it. A PATH shim on comm records
        whether the candidate is a live .md at that instant."""
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)
        digest_before = self.led.digest()
        state_before = self.led.read("zamm-memory/.compiled/state.tsv")

        bad = "2026-01-06-badrec-33333"
        self.led.write(
            f"zamm-memory/knowledge/2026/{bad}.md.draft",
            "---\ntype: memory\nscope: internals\nimportance: not-an-enum\n"
            "durability: months\ncreated: 2026-01-06\nschema: 3\n---\nBody.\n")

        live = self.led.root / f"zamm-memory/knowledge/2026/{bad}.md"
        marker = self.led.root / "candidate-was-live"
        shim = self.led.root / "shim"
        shim.mkdir()
        real_comm = shutil.which("comm")
        (shim / "comm").write_text(
            "#!/bin/sh\n"
            f'[ -e "{live}" ] && touch "{marker}"\n'
            f'exec "{real_comm}" "$@"\n')
        os.chmod(shim / "comm", 0o755)

        p = self.led.memory_publish(
            bad, env={"PATH": f"{shim}:{os.environ['PATH']}"})
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("did not validate", p.err)
        self.assertFalse(
            marker.exists(),
            "an unvalidated candidate must never be visible in the live "
            "namespace, not even transiently")
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{bad}.md.draft"),
            "the rejected candidate must still be a draft")
        self.assertFalse(
            self.led.exists(f"zamm-memory/knowledge/2026/{bad}.md"),
            "the rejected candidate must never appear in the live namespace")
        self.assertEqual(digest_before, self.led.digest(),
                         "a rejected publish must not change the digest")
        self.assertEqual(state_before,
                         self.led.read("zamm-memory/.compiled/state.tsv"),
                         "a rejected publish must not change the sidecar")
        self.assertNotIn_(bad, self.led.status().out,
                          "status must not report a record that never landed")

    def test_status_reports_divergence_when_a_record_vanishes(self):
        self.led.add("alive", "A living record.")
        gone = self.led.add("vanish", "A record that will vanish.",
                            date="2026-01-06", sfx="77777")
        self.assertCode(self.led.compile(), EXIT_OK)
        # simulate the reviewer scenario OUTSIDE any publish path: the live
        # file is hand-moved back to a draft, so nothing is newer than the
        # digest and only the count comparison can notice
        src = self.led.root / f"zamm-memory/knowledge/2026/{gone}.md"
        src.rename(str(src) + ".draft")

        st = self.led.status()
        self.assertIn_("on disk but the last compile saw", st.out,
                       "status must report sidecar-vs-disk divergence")


# ----------------------------------------------------------------------
# review items 8, 9 — archived and shunned targets are inert graph nodes
# ----------------------------------------------------------------------
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

    def test_two_successors_of_a_shunned_target_reconcile(self):
        target = "2026-01-05-erased-55555"
        self.led.shun(target)
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


# ----------------------------------------------------------------------
# review item 10 — publish verdicts are severity-aware
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# review item 11 — plan ids are unique across both trees
# ----------------------------------------------------------------------
class Rev6PlanIdUniqueness(ZammTest):
    """PRE-FIX: `plan create` checked only active/, so a slug still resolvable
    from the archive could be minted again, making every by-slug reference
    (votes records, archive moves) ambiguous."""

    def test_create_refuses_a_slug_that_is_archived(self):
        self.led.add("alive", "A living record.")
        # plan create stamps ZAMM_TODAY (pinned 2026-07-19) into the id
        taken = self.led.root / "zamm-memory/archive/plans/2026-07-19-taken-title"
        taken.mkdir(parents=True)
        r = self.led.plan_create("Taken Title")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("already archived", r.err)
        self.assertFalse(
            self.led.exists("zamm-memory/active/plans/2026-07-19-taken-title"))

    def test_check_reports_a_handmade_collision(self):
        self.led.add("alive", "A living record.")
        self.led.add_plan("2026-01-05-doubled", status="Implementing")
        dup = self.led.root / "zamm-memory/archive/plans/2026-01-05-doubled"
        dup.mkdir(parents=True)
        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("exists in both active and archive", pc.err)


# ----------------------------------------------------------------------
# review item 12 — drafts are visible, discardable, and age-flagged
# ----------------------------------------------------------------------
class Rev6DraftVisibility(ZammTest):
    """PRE-FIX: an unpublished .md.draft was invisible to every read surface
    (check, digest, status, list), so a create that was never followed by
    publish rotted silently forever."""

    def _draft(self, slug="pending"):
        r = self.led.zamm("memory", "create", "--scope", "internals", slug)
        self.assertCode(r, EXIT_OK)
        draft = r.out.strip().splitlines()[0]
        with open(draft, "a") as fh:
            fh.write("A body.\n")
        return draft

    def test_drafts_are_listed_and_counted_in_status(self):
        self.led.add("alive", "A living record.")
        draft = self._draft()
        rid = os.path.basename(draft)[: -len(".md.draft")]

        d = self.led.zamm("memory", "drafts")
        self.assertCode(d, EXIT_OK)
        self.assertIn_(rid, d.out)

        st = self.led.status()
        self.assertIn_("drafts: 1 unpublished", st.out)

    def test_old_drafts_are_flagged_stale(self):
        self.led.add("alive", "A living record.")
        draft = self._draft()
        old = time.time() - 8 * 86400
        os.utime(draft, (old, old))

        d = self.led.zamm("memory", "drafts")
        self.assertIn_("STALE", d.out)
        st = self.led.status()
        self.assertIn_("STALE DRAFTS: 1", st.out)

    def test_discard_removes_a_draft_and_only_a_draft(self):
        self.led.add("alive", "A living record.")
        draft = self._draft()

        r = self.led.zamm("memory", "discard", "pending")
        self.assertCode(r, EXIT_OK)
        self.assertFalse(os.path.exists(draft))

        # a published record is out of discard's reach: no draft matches
        live = self.led.add("keepme", "A published record.",
                            date="2026-01-06", sfx="66666")
        r2 = self.led.zamm("memory", "discard", "keepme")
        self.assertCode(r2, EXIT_CONTRACT)
        self.assertIn_("no draft matches", r2.err)
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{live}.md"))


# ----------------------------------------------------------------------
# review item 13 — archival gates on the plan/ledger cross-check
# ----------------------------------------------------------------------
class Rev6ArchiveGate(ZammTest):
    """PRE-FIX: the archive gate ran only plan check, so a plan whose votes
    record disagreed with its declared Memory-upvotes moved into history with
    the mismatch unresolved (see also Rev3VoteLaundering, which locks the
    missing-votes-record variant)."""

    def test_archive_refuses_a_disagreeing_votes_record(self):
        a = self.led.add("recorda", "A.")
        b = self.led.add("recordb", "B.", date="2026-01-06", sfx="66666")
        self.led.add_plan("2026-01-05-closing", status="Done")
        pf = "zamm-memory/active/plans/2026-01-05-closing/2026-01-05-closing.plan.md"
        self.led.write(pf, self.led.read(pf).replace(
            "Status: Done", f"Status: Done\nMemory-upvotes: {a}"))
        # the votes record upvotes B, the plan declares A
        self.led.add("votes", type="votes", plan="2026-01-05-closing", up=b,
                     date="2026-01-07", sfx="vvvvv")

        arch = self.led.archive()
        self.assertNotEqual(arch.code, 0, "archive must refuse the mismatch")
        self.assertIn_("disagree", arch.err)
        self.assertTrue(
            self.led.exists("zamm-memory/active/plans/2026-01-05-closing"),
            "the mismatched plan must stay in active/")
