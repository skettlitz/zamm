"""Absent is data, unreadable is an error — invariant G3.

A record that is not there does not exist; a tree that cannot be read is
reported and exits non-zero with the previous digest untouched. Every
enumeration and every read on every surface follows that one rule.

See references/invariants.md for the guarantees these suites protect.
"""

import os
import shutil
import time

from harness import (
    EXIT_CONTRACT, EXIT_OK, EXIT_UNREADABLE, ShimTest, ZammTest,
    needs_permission_bits,
)

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
    def test_unreadable_single_file_is_fatal_with_a_clear_reason(self):
        # Since erasure became a RECORD (round 8), an unreadable file may BE
        # an erasure record, and nothing can tell which — so an unreadable
        # record is fatal (exit 4) rather than a quarantine, the same rule
        # the old unreadable-shun.md guard applied.
        self.led.add("readable", "A readable record.")
        victim = self.led.add("locked", "An unreadable record.")
        vf = self.led.root / f"zamm-memory/knowledge/2026/{victim}.md"
        os.chmod(vf, 0o000)
        try:
            r = self.led.check()
        finally:
            os.chmod(vf, 0o644)
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("cannot read record file", r.err)


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


class Rev6ErasureFailClosed(ZammTest):
    """PRE-FIX (shun.md era): a redaction list that could not be read
    compiled as an empty set, and the digest resurrected content the
    erasure procedure had removed. The invariant is mechanism-independent:
    a failing READ must never un-redact."""

    def _erased_fixture(self):
        self.led.add("alive", "A living record.")
        secret = self.led.add("secret", "REDACTED SECRET CONTENT.")
        eid = self.led.erase(secret)
        self.led.delete(secret)
        self.assertCode(self.led.compile(), EXIT_OK)
        digest = self.led.digest()
        self.assertNotIn_("REDACTED SECRET CONTENT", digest)
        return digest, secret, eid

    @needs_permission_bits
    def test_unreadable_erasure_record_refuses_and_preserves_digest(self):
        before, _secret, eid = self._erased_fixture()
        locked = self.led.root / f"zamm-memory/knowledge/2026/{eid}.md"
        os.chmod(locked, 0o000)
        try:
            r = self.led.compile()
            c = self.led.check()
        finally:
            os.chmod(locked, 0o644)
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("cannot read record file", r.err)
        self.assertCode(c, EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "previous digest must survive an unreadable erasure record")

    def test_symlinked_erasure_record_is_refused(self):
        before, _secret, eid = self._erased_fixture()
        rec = self.led.root / f"zamm-memory/knowledge/2026/{eid}.md"
        real = self.led.root / "real-erasure.md"
        rec.rename(real)
        os.symlink(real, rec)
        r = self.led.compile()
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("symlink", r.err)
        self.assertCode(self.led.check(), EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "previous digest must survive a symlinked record")

    def test_a_stray_copy_of_an_erased_record_stays_out(self):
        """The job a one-time delete cannot do: git makes a deleted file
        coming back routine (a merge, an old branch, a restore), and the
        erasure record keeps it out of the digest for good."""
        _before, secret, _eid = self._erased_fixture()
        self.led.write(
            f"zamm-memory/knowledge/2026/{secret}.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\nschema: 3\n---\n"
            "REDACTED SECRET CONTENT.\n")
        self.led.compile()
        self.assertNotIn_("REDACTED SECRET CONTENT", self.led.digest(),
                          "a resurrected copy must stay redacted")

    def test_no_erasure_record_is_a_legal_empty_set(self):
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)


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


class Rev7DraftEnumFailClosed(ShimTest):
    """PRE-FIX: memory drafts / publish / discard and the status draft and
    record counts ran `find ... 2>/dev/null` under command substitution: an
    unreadable year directory read as "No drafts." / "no draft matches", and
    an existing draft became unreachable without any diagnostic."""

    @needs_permission_bits
    def test_unreadable_year_dir_fails_every_draft_consumer(self):
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)
        draft, rid = self._draft(slug="hidden")
        locked = self.led.root / "zamm-memory/knowledge/2026"
        os.chmod(locked, 0o000)
        try:
            dr = self.led.zamm("memory", "drafts")
            pu = self.led.memory_publish("hidden")
            di = self.led.zamm("memory", "discard", "hidden")
            st = self.led.status()
        finally:
            os.chmod(locked, 0o755)
        for name, r in (("drafts", dr), ("publish", pu),
                        ("discard", di), ("status", st)):
            self.assertCode(r, EXIT_UNREADABLE,
                            f"memory {name} must fail loudly, not read the "
                            "unreadable tree as empty")
            self.assertIn_("unreadable, not empty", r.err, name)
            self.assertNotIn_("No drafts.", r.out, name)
            self.assertNotIn_("no draft matches", r.err, name)
        self.assertTrue(os.path.exists(draft), "the draft must be untouched")


class Rev7ArchivedHeaderFatal(ZammTest):
    """PRE-FIX: an unreadable archived record degraded to an id-only inert
    node with a WARNING, silently waiving the type-transition checks — a
    memory record superseding an archived votes record (a forbidden
    transition) passed `memory check` with exit 0."""

    ARCHIVED_VOTES = (
        "---\ntype: votes\nplan: some-plan\nup: 2026-01-05-x-22222\ndown:\n"
        "created: 2025-03-05\nschema: 3\n---\n"
    )

    @needs_permission_bits
    def test_unreadable_archived_header_is_exit_4(self):
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()

        target = "2025-03-05-oldvotes-88888"
        self.led.write(
            f"zamm-memory/archive/knowledge/2025/{target}.md",
            self.ARCHIVED_VOTES)
        self.led.add("succ", "Supersedes a votes record (forbidden).",
                     date="2026-01-06", supersedes=target)
        locked = self.led.root / f"zamm-memory/archive/knowledge/2025/{target}.md"
        os.chmod(locked, 0o000)
        try:
            c = self.led.check()
            d = self.led.compile()
        finally:
            os.chmod(locked, 0o644)
        self.assertCode(c, EXIT_UNREADABLE,
                        "an unreadable archived header must not pass check")
        self.assertIn_("unreadable, not empty", c.err)
        self.assertCode(d, EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "the previous digest must survive untouched")


class Rev7MissingPlanRoots(ZammTest):
    """PRE-FIX: the plan manifest treated an absent tree root as a legal
    empty tree, so deleting active/plans/ (or archive/plans/) made every
    consumer report a clean zero-plan project."""

    def _assert_damage(self, deleted_rel):
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()
        shutil.rmtree(self.led.root / deleted_rel)

        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_UNREADABLE, "plan check must refuse")
        self.assertIn_("structural damage", pc.err)
        self.assertCode(self.led.check_all(), EXIT_UNREADABLE)
        self.assertCode(self.led.compile(), EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "the previous digest must survive untouched")
        st = self.led.status()
        self.assertCode(st, EXIT_UNREADABLE, "status must refuse")

    def test_missing_active_plans_root(self):
        self._assert_damage("zamm-memory/active/plans")

    def test_missing_archive_plans_root(self):
        self._assert_damage("zamm-memory/archive/plans")


class Rev7SelfFoundGaps(ShimTest):
    """Four fail-open reads of the same class, found while auditing the
    round-8 fixes rather than reported by the review: a verification step
    that cannot run must not read as "verified", an enumeration that cannot
    read must not read as "absent", preserved bytes must be discoverable,
    and an unknown age must not read as fresh."""

    def test_status_sees_an_edited_archived_record(self):
        """PRE-FIX: the staleness scan covered live knowledge and active
        plans but not archive/knowledge, although the compiler parses
        archived headers for the graph — so editing one left status
        reporting a current digest."""
        self.led.add("alive", "A living record.")
        self.led.write(
            "zamm-memory/archive/knowledge/2025/2025-03-05-old-88888.md",
            "---\ntype: memory\nscope: internals\nimportance: useful\n"
            "durability: months\ncreated: 2025-03-05\nschema: 3\n---\nOld.\n")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("STALE", self.led.status().out,
                          "a freshly compiled ledger is not stale")

        target = (self.led.root /
                  "zamm-memory/archive/knowledge/2025/2025-03-05-old-88888.md")
        time.sleep(1.1)          # mtime granularity: make "newer" unambiguous
        with open(target, "a") as fh:
            fh.write("An edit to the archived record.\n")

        st = self.led.status()
        self.assertIn_("STALE", st.out,
                       "an edited archived record must make the digest stale")

    @needs_permission_bits
    def test_status_refuses_when_an_archived_record_is_unreadable(self):
        """PRE-FIX: the inert-chain probe discarded the compiler's output
        AND its status, so an unreadable archived record — which the
        compiler now treats as a fatal unreadable ledger — left status
        printing a clean report."""
        self.led.add("alive", "A living record.")
        self.led.write(
            "zamm-memory/archive/knowledge/2025/2025-03-05-old-88888.md",
            "---\ntype: memory\nscope: internals\nimportance: useful\n"
            "durability: months\ncreated: 2025-03-05\nschema: 3\n---\nOld.\n")
        self.assertCode(self.led.compile(), EXIT_OK)
        locked = (self.led.root /
                  "zamm-memory/archive/knowledge/2025/2025-03-05-old-88888.md")
        os.chmod(locked, 0o000)
        try:
            st = self.led.status()
        finally:
            os.chmod(locked, 0o644)
        self.assertCode(st, EXIT_UNREADABLE,
                        "status must not look healthy over a ledger it "
                        "could not read")
        self.assertIn_("could not be read", st.err + st.out)

    @needs_permission_bits
    def test_record_resolution_fails_closed(self):
        """PRE-FIX: resolve_record ran `find … 2>/dev/null`, so an unreadable
        year directory produced 'no record matches' — the same
        unreadable-reads-as-absent defect already fixed for drafts, plans
        and the ledger."""
        rid = self.led.add("findme", "A record to resolve.")
        self.assertCode(self.led.compile(), EXIT_OK)
        locked = self.led.root / "zamm-memory/knowledge/2026"
        os.chmod(locked, 0o000)
        try:
            r = self.led.memory_show("findme")
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("unreadable, not empty", r.err)
        self.assertNotIn_("no record matches", r.err)
        self.assertCode(self.led.memory_show("findme"), EXIT_OK,
                        f"{rid} must resolve again once readable")

    @needs_permission_bits
    def test_plan_resolution_fails_closed(self):
        """PRE-FIX: plan show ran its own silenced find instead of the
        checked manifest, so an unreadable plan tree produced 'no plan
        matches' rather than saying it could not look."""
        self.led.add_plan("2026-01-05-findable", status="Implementing")
        locked = self.led.root / "zamm-memory/active/plans"
        os.chmod(locked, 0o000)
        try:
            r = self.led.plan_show("findable")
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertNotIn_("no plan matches", r.err)
        self.assertCode(self.led.plan_show("findable"), EXIT_OK,
                        "the plan must resolve again once readable")

    def test_plan_show_never_reads_through_a_symlinked_plan_dir(self):
        """Keep-working companion (passes pre-fix as well): find never
        descends a symlink, so plan show did not display external content
        by accident. Routing it through the manifest makes that a
        guarantee — the manifest tags such entries and never opens them —
        rather than a side effect of the flag find happened to use."""
        self.led.add("alive", "A living record.")
        ext = self.led.root / "external-plan"
        ext.mkdir()
        (ext / "evil.plan.md").write_text(
            "Status: Implementing\nLast updated: 2026-01-05\n\n"
            "# EXTERNAL UNTRACKED PLAN\n")
        os.symlink(ext, self.led.root / "zamm-memory/active/plans/evil")

        r = self.led.plan_show("evil")
        self.assertNotEqual(r.code, 0,
                            "a symlinked plan directory must not resolve")
        self.assertNotIn_("EXTERNAL UNTRACKED PLAN", r.out,
                          "content behind a symlink must never be displayed")

    def test_leftover_write_temporaries_are_surfaced(self):
        """PRE-FIX (same shape): the files a record write leaves behind
        matched no enumeration — not *.md, not *.md.draft — so bytes sat in
        the tree unmentioned by every command. With the one-step write there
        is exactly one kind of leftover, and it still must be visible."""
        draft, rid = self._draft(slug="orphan")
        year = self.led.root / "zamm-memory/knowledge/2026"
        (year / f".{rid}.md.pending.a1b2c3").write_text(
            "---\ntype: memory\n---\nAn interrupted write.\n")
        (year / ".2026-01-09-other-99999.md.pending.d4e5f6").write_text("x\n")

        d = self.led.zamm("memory", "drafts")
        self.assertCode(d, EXIT_OK)
        self.assertIn_("Leftover temporary files", d.out)
        self.assertIn_(f".{rid}.md.pending.a1b2c3", d.out)
        self.assertIn_(".2026-01-09-other-99999.md.pending.d4e5f6", d.out)
        st = self.led.status()
        self.assertIn_("RECOVERY FILES: 2", st.out)


if __name__ == "__main__":
    unittest.main()
