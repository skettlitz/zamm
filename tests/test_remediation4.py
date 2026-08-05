"""Regression locks for the three leftover cleanups requested after the
review rounds (2026-07-22):

  A  the plan archiver (zamm-archive.sh) is transactional like the memory one
  B  seed-up/seed-dn require migrated-from (hand-forged vote weight rejected)
  C  symlinked records under knowledge/ are rejected, not silently skipped
"""

import os

from harness import EXIT_CONTRACT, EXIT_OK, ZammTest


# ----------------------------------------------------------------------
# A — plan archiver is transactional
# ----------------------------------------------------------------------
class TestPlanArchiverTransactional(ZammTest):
    def _plan_dirs(self, area):
        base = self.led.root / f"zamm-memory/{area}/plans"
        return sorted(p.name for p in base.iterdir() if p.is_dir()) \
            if base.exists() else []

    def test_a_collision_refuses_the_whole_batch(self):
        """A pre-existing archive destination refuses the batch before any
        move, rather than SKIP-ing it and archiving the rest (a partial
        archive). The refusal now fires at the plan-check gate (the manifest
        reports the cross-tree duplicate id) before the archiver's own
        preflight ever runs."""
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-one", status="Done")
        self.led.add_plan("2026-01-06-two", status="Done")
        # plant a colliding archive destination for the second plan
        (self.led.root / "zamm-memory/archive/plans/2026-01-06-two").mkdir(parents=True)

        r = self.led.archive()

        self.assertNotEqual(r.code, 0)
        self.assertIn_("exists in both active and archive", r.err)
        # NOTHING moved — the first plan must still be active (all-or-nothing)
        self.assertIn_("2026-01-05-one", self._plan_dirs("active"))
        self.assertIn_("2026-01-06-two", self._plan_dirs("active"))

    def test_a_clean_batch_archives_every_plan(self):
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-one", status="Done")
        self.led.add_plan("2026-01-06-two", status="Abandoned")

        r = self.led.archive()

        self.assertCode(r, EXIT_OK, r.err)
        self.assertEqual(self._plan_dirs("active"), [])
        self.assertEqual(self._plan_dirs("archive"),
                         ["2026-01-05-one", "2026-01-06-two"])

    def test_a_mid_batch_failure_rolls_back(self):
        """A move failure partway through the batch restores every plan that
        already moved (no partial archive)."""
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-one", status="Done")
        self.led.add_plan("2026-01-06-two", status="Done")
        before = self._plan_dirs("active")

        shim = self.led.root / ".shims"
        shim.mkdir(exist_ok=True)
        # a `mv` that fails on the 2nd move into archive/plans; the first plan
        # commits, the second aborts, rollback must restore the first
        (shim / "mv").write_text(
            "#!/bin/sh\n"
            'case " $* " in\n'
            '  *archive/plans*)\n'
            '    d=$(dirname "$0")\n'
            '    n=$(cat "$d/.c" 2>/dev/null || echo 0); n=$((n + 1))\n'
            '    printf "%s\\n" "$n" > "$d/.c"\n'
            '    if [ "$n" = "2" ]; then echo "shim mv: forced failure" >&2; exit 1; fi\n'
            '    ;;\n'
            'esac\n'
            'for c in /bin/mv /usr/bin/mv; do [ -x "$c" ] && exec "$c" "$@"; done\n'
            "exit 127\n"
        )
        (shim / "mv").chmod(0o755)
        # git mv would bypass the shim; force the mv fallback by disabling git
        (shim / "git").write_text("#!/bin/sh\nexit 1\n")
        (shim / "git").chmod(0o755)
        env = {"PATH": f"{shim}:{os.environ['PATH']}"}

        r = self.led.archive(env=env)

        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._plan_dirs("active"),
                         "a failed batch move must roll every plan back")
        self.assertEqual(self._plan_dirs("archive"), [],
                         "nothing may remain in archive after rollback")


# ----------------------------------------------------------------------
# B — seed-up/seed-dn require migrated-from
# ----------------------------------------------------------------------
class TestSeedRequiresMigration(ZammTest):
    def test_seed_up_without_migrated_from_is_rejected(self):
        self.led.add("forged", "Claims 50 upvotes it never earned.",
                     extra={"seed-up": "50"})
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("migrated-from", r.err)

    def test_seed_dn_without_migrated_from_is_rejected(self):
        self.led.add("forged", "Body.", extra={"seed-dn": "3"})
        self.assertCode(self.led.check(), EXIT_CONTRACT)

    def test_a_real_migration_record_is_accepted(self):
        self.led.add("migrated", "Carried over from v2.",
                     extra={"migrated-from": "B3", "seed-up": "5"})
        self.assertCode(self.led.check(), EXIT_OK)

    def test_forged_seed_does_not_influence_ranking(self):
        """The forged record is quarantined, so its fabricated weight never
        reaches the digest."""
        self.led.add("forged", "Forged weight.", extra={"seed-up": "99"})
        self.led.add("honest", "An honest record.")
        self.led.compile()
        # forged is quarantined -> not in the digest entries
        self.assertNotIn_("forged", "\n".join(self.led.entries()))
        self.assertIn_("honest", "\n".join(self.led.entries()))


# ----------------------------------------------------------------------
# C — no symlinked records in the ledger
# ----------------------------------------------------------------------
class TestNoSymlinks(ZammTest):
    def test_a_symlinked_record_is_rejected(self):
        real = self.led.add("real", "A real record.")
        # a symlink pointing at the real record, sitting under knowledge/
        link = self.led.root / "zamm-memory/knowledge/2026/2026-01-05-link-33333.md"
        link.symlink_to(self.led.root / f"zamm-memory/knowledge/2026/{real}.md")

        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("symlink", r.err)

    def test_a_dangling_symlink_is_rejected_too(self):
        self.led.add("real", "A real record.")
        link = self.led.root / "zamm-memory/knowledge/2026/2026-01-05-dangle-44444.md"
        link.symlink_to(self.led.root / "nonexistent-target.md")

        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("symlink", r.err)

    def test_a_plain_ledger_still_passes(self):
        self.led.add("real", "A real record.")
        self.assertCode(self.led.check(), EXIT_OK)
