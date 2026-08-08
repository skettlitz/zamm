"""What the ledger may contain on disk — invariant G5, plus the
filesystem realities the invariants promise to tolerate.

Real files and real directories, nothing else, so the ledger travels with its
repository. Duplicate ids from a sync client or an interrupted archive warn
and keep working; a genuine case-fold collision does not.

See references/invariants.md for the guarantees these suites protect.
"""

import os
import shutil

from harness import EXIT_CONTRACT, EXIT_OK, EXIT_UNREADABLE, ShimTest, ZammTest

class TestNoSymlinks(ZammTest):
    # Since round 8 made erasure a RECORD, a symlinked record is one the
    # compiler did not read and cannot classify — it could be an erasure
    # record, so skipping it can silently un-redact. Rejection is therefore
    # fatal (exit 4, previous digest untouched) rather than a per-record
    # error; the invariant "no symlinks in the ledger" is unchanged.
    def test_a_symlinked_record_is_rejected(self):
        real = self.led.add("real", "A real record.")
        # a symlink pointing at the real record, sitting under knowledge/
        link = self.led.root / "zamm-memory/knowledge/2026/2026-01-05-link-33333.md"
        link.symlink_to(self.led.root / f"zamm-memory/knowledge/2026/{real}.md")

        r = self.led.check()

        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("symlink", r.err)

    def test_a_dangling_symlink_is_rejected_too(self):
        self.led.add("real", "A real record.")
        link = self.led.root / "zamm-memory/knowledge/2026/2026-01-05-dangle-44444.md"
        link.symlink_to(self.led.root / "nonexistent-target.md")

        r = self.led.check()

        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("symlink", r.err)

    def test_a_plain_ledger_still_passes(self):
        self.led.add("real", "A real record.")
        self.assertCode(self.led.check(), EXIT_OK)


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


class Rev7RootSymlinks(ZammTest):
    """PRE-FIX: only `-d` tests (which follow symlinks) guarded the
    canonical roots. A symlinked knowledge/ compiled as a healthy EMPTY
    ledger and overwrote the real digest; a symlinked .compiled/, archive
    root, or zamm-memory parent routed reads and writes outside the
    project."""

    def _baseline(self):
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)
        return self.led.digest()

    def _swap_for_symlink(self, rel):
        """Move <rel> aside and replace it with a symlink to the moved copy
        (content intact, physically outside the canonical path)."""
        src = self.led.root / rel
        ext = self.led.root / ("external-" + rel.replace("/", "-"))
        os.rename(src, ext)
        os.symlink(ext, src)

    def test_symlinked_knowledge_root_fails_closed(self):
        before = self._baseline()
        self._swap_for_symlink("zamm-memory/knowledge")
        r = self.led.compile()
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("symlink", r.err)
        self.assertEqual(before, self.led.digest(),
                         "the previous digest must survive untouched")
        self.assertCode(self.led.check(), EXIT_UNREADABLE)
        # defense in depth: the internal compiler refuses on its own too
        d = self.led.run("zamm-compile.sh")
        self.assertCode(d, EXIT_UNREADABLE)

    def test_symlinked_zamm_memory_parent_fails_closed(self):
        self._baseline()
        self._swap_for_symlink("zamm-memory")
        for name, r in (("check", self.led.check_all()),
                        ("status", self.led.status()),
                        ("digest", self.led.compile())):
            self.assertCode(r, EXIT_UNREADABLE, f"{name} must refuse")
            self.assertIn_("symlink", r.err + r.out, name)

    def test_symlinked_compiled_dir_fails_closed(self):
        self._baseline()
        self._swap_for_symlink("zamm-memory/.compiled")
        r = self.led.compile()
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("symlink", r.err)

    def test_symlinked_archive_knowledge_fails_closed(self):
        self._baseline()
        ext = self.led.root / "external-archive-knowledge"
        ext.mkdir()
        os.symlink(ext, self.led.root / "zamm-memory/archive/knowledge")
        m = self.led.memory_archive()
        self.assertCode(m, EXIT_UNREADABLE)
        self.assertIn_("symlink", m.err)
        d = self.led.run("zamm-memory-archive.sh")
        self.assertCode(d, EXIT_UNREADABLE)

    def test_symlinked_archive_plans_fails_closed(self):
        self._baseline()
        self._swap_for_symlink("zamm-memory/archive/plans")
        a = self.led.archive("--list")
        self.assertCode(a, EXIT_UNREADABLE)
        d = self.led.run("zamm-archive.sh")
        self.assertCode(d, EXIT_UNREADABLE)

    def test_parent_component_symlink_cannot_bypass_leaf_checks(self):
        # zamm-memory/archive itself is the symlink; its children are real
        # directories behind it, so any final-component-only check passes
        before = self._baseline()
        self._swap_for_symlink("zamm-memory/archive")
        r = self.led.compile()
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("symlink", r.err)
        self.assertEqual(before, self.led.digest())
        d = self.led.run("zamm-compile.sh")
        self.assertCode(d, EXIT_UNREADABLE)

    def test_scaffold_refuses_a_poisoned_tree(self):
        self._baseline()
        self._swap_for_symlink("zamm-memory/knowledge")
        s = self.led.scaffold()
        self.assertCode(s, EXIT_UNREADABLE)
        self.assertIn_("symlink", s.err + s.out)


class Rev7YearDirSymlinks(ZammTest):
    """PRE-FIX: the canonical-root check covered only the FIXED roots, but
    the year directories under knowledge/ and archive/knowledge/ are dynamic
    components written through with mkdir -p — `memory create` happily wrote
    a draft outside the project through knowledge/2026 -> /tmp/..., and
    `memory drafts` then said "No drafts" because find never follows the
    symlink."""

    def test_create_refuses_a_symlinked_year_dir(self):
        ext = self.led.root / "external-year"
        ext.mkdir()
        os.symlink(ext, self.led.root / "zamm-memory/knowledge/2026")
        r = self.led.zamm("memory", "create", "--scope", "contracts/api",
                          "escapee")
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertIn_("symlink", r.err)
        self.assertEqual(list(ext.iterdir()), [],
                         "nothing may be written through the symlink")

    def test_compile_rejects_a_symlinked_year_dir(self):
        self.led.add("alive", "A living record.", date="2025-03-05")
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()
        ext = self.led.root / "external-year"
        ext.mkdir()
        (ext / "2026-01-05-hidden-22222.md").write_text(
            "---\ntype: memory\nscope: internals\nimportance: useful\n"
            "durability: months\ncreated: 2026-01-05\nschema: 3\n---\nH.\n")
        os.symlink(ext, self.led.root / "zamm-memory/knowledge/2026")
        r = self.led.compile()
        self.assertCode(r, EXIT_UNREADABLE,
                        "a symlinked year dir hides its records: unreadable, "
                        "not smaller")
        self.assertIn_("symlink inside the ledger", r.err)
        self.assertCode(self.led.check(), EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "the previous digest must survive untouched")

    def test_dangling_year_symlink_fails_closed(self):
        """PRE-FIX: the directory-symlink guard probed with `-d`, which
        FOLLOWS the link and returns false once its target is gone — so a
        dangling knowledge/2026 passed as a harmless file symlink, compile
        returned 0, and the digest silently lost every 2026 record."""
        self.led.add("keeper", "Kept across years.", date="2025-03-05")
        self.led.add("doomed", "Must not vanish from the digest.",
                     date="2026-01-05")
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()
        self.assertIn_("Must not vanish", before)

        year = self.led.root / "zamm-memory/knowledge/2026"
        ext = self.led.root / "external-year"
        os.rename(year, ext)
        os.symlink(ext, year)
        shutil.rmtree(ext)          # now dangling: -d says "not a directory"

        r = self.led.compile()
        self.assertCode(r, EXIT_UNREADABLE,
                        "a dangling year symlink hides records: unreachable, "
                        "not smaller")
        self.assertIn_("symlink inside the ledger", r.err)
        self.assertEqual(before, self.led.digest(),
                         "the digest must not lose records to a dangling link")
        self.assertCode(self.led.check(), EXIT_UNREADABLE)

    def test_drafts_refuse_a_symlinked_year_dir(self):
        """PRE-FIX: draft enumeration checked only find's exit status, and
        find SUCCEEDS while silently skipping a symlinked directory — a real
        draft behind knowledge/2026 read as 'No drafts.' and publish said no
        match."""
        draft, rid = ShimTest._draft(self)  # a real, filled draft
        year = self.led.root / "zamm-memory/knowledge/2026"
        ext = self.led.root / "outside-year"
        os.rename(year, ext)
        os.symlink(ext, year)

        d = self.led.zamm("memory", "drafts")
        self.assertCode(d, EXIT_UNREADABLE)
        self.assertNotIn_("No drafts.", d.out)
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_UNREADABLE)
        self.assertNotIn_("no draft matches", p.err)
        self.assertCode(self.led.status(), EXIT_UNREADABLE)

    def test_memory_archive_refuses_a_symlinked_dest_year_dir(self):
        self.led.add("live-rule", "Still true.")
        rec = self.led.add("obsolete", "Old.", date="2026-01-05")
        self.led.add("retire", "No longer applies.", date="2026-01-06",
                     type="tombstone", supersedes=rec)
        self.assertCode(self.led.compile(), EXIT_OK)
        ext = self.led.root / "external-archive-year"
        ext.mkdir()
        dest_year = self.led.root / "zamm-memory/archive/knowledge/2026"
        dest_year.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(ext, dest_year)

        m = self.led.memory_archive()
        self.assertNotEqual(m.code, 0,
                            "archiving through a symlinked year dir must fail")
        # the compiler's ledger gate (which now rejects symlinked dirs in
        # either tree) fires before the helper's own preflight check, so
        # either refusal message is acceptable — what matters is the refusal
        self.assertTrue("symlink" in m.err or "refusing to archive" in m.err,
                        m.err)
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{rec}.md"),
            "no record may leave knowledge/ through the symlink")
        self.assertEqual(list(ext.iterdir()), [],
                         "nothing may be written through the symlink")


class FilesystemRealitiesAreTolerated(ZammTest):
    """Sync folders, interrupted cross-device moves and half-finished
    archives all produce the same shape: one record id present twice. None of
    them is damage under references/invariants.md — the ledger still describes
    a real state and a rerun repairs it — so they warn rather than fail.

    What must NOT happen is silence (a duplicated record is exactly what
    nobody goes looking for) or a misleading diagnostic."""

    def test_same_id_live_and_archived_warns_and_keeps_working(self):
        rid = self.led.add("both", "The live copy.")
        arch = self.led.root / "zamm-memory/archive/knowledge/2026"
        arch.mkdir(parents=True)
        (arch / f"{rid}.md").write_text(
            (self.led.root / f"zamm-memory/knowledge/2026/{rid}.md").read_text())

        c = self.led.check()
        self.assertCode(c, EXIT_OK, "a half-finished archive is not damage")
        self.assertIn_("exists both live and archived", c.err)
        self.assertIn_("the live copy is used", c.err)

        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("The live copy.", self.led.digest())

    def test_identical_names_in_two_year_dirs_are_not_called_a_case_collision(self):
        """PRE-FIX: the case-fold check compared lowercased basenames without
        checking they actually differ, so a plain duplicate id also reported a
        'case-fold collision' — a second, misleading error on top of the one
        the user has to act on."""
        rid = self.led.add("twice", "A body.")
        src = self.led.root / f"zamm-memory/knowledge/2026/{rid}.md"
        other = self.led.root / "zamm-memory/knowledge/2025"
        other.mkdir()
        (other / f"{rid}.md").write_text(src.read_text())

        c = self.led.check()
        self.assertCode(c, EXIT_CONTRACT)
        self.assertIn_("duplicate record id", c.err)
        self.assertNotIn_("case-fold collision", c.err)

    def test_a_genuine_case_fold_collision_is_still_reported(self):
        self.require_case_sensitive()
        rid = self.led.add("cased", "A body.")
        src = self.led.root / f"zamm-memory/knowledge/2026/{rid}.md"
        src.with_name(rid.upper() + ".md").write_text(src.read_text())

        c = self.led.check()
        self.assertCode(c, EXIT_CONTRACT)
        self.assertIn_("case-fold collision", c.err)


class Rev6ShunMigrationRefused(ZammTest):
    """A project carrying the old shun.md must not compile silently under a
    toolchain that no longer reads it — that would lapse every erasure it
    records. Testing the PATH (not a find) makes every file type equal:
    the old parser only saw regular files, so a DIRECTORY named shun.md
    silently emptied the redaction set."""

    def _plant(self, kind):
        p = self.led.root / "zamm-memory/knowledge/shun.md"
        if kind == "file":
            p.write_text("2026-01-05-secret-22222\n")
        elif kind == "dir":
            p.mkdir()
        else:
            os.symlink(self.led.root / "elsewhere.md", p)

    def test_every_form_of_a_leftover_shun_file_refuses(self):
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()
        for kind in ("file", "dir", "symlink"):
            with self.subTest(kind=kind):
                self._plant(kind)
                try:
                    r = self.led.compile()
                    self.assertCode(r, EXIT_UNREADABLE)
                    self.assertIn_("erasure RECORDS", r.err)
                    self.assertIn_("Migrate", r.err)
                    self.assertEqual(before, self.led.digest())
                finally:
                    p = self.led.root / "zamm-memory/knowledge/shun.md"
                    if p.is_symlink() or p.is_file():
                        p.unlink()
                    elif p.is_dir():
                        p.rmdir()


if __name__ == "__main__":
    unittest.main()
