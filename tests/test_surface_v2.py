"""The commands added with the v2 surface: memory list/show/archive,
plan show/check/create, and top-level check.

memory archive is the only one that moves data, so it carries the most
tests: the inert rule is the single place in the toolchain where getting a
graph question wrong silently changes rankings.
"""

from harness import EXIT_CONTRACT, EXIT_OK, ZammTest


class TestMemoryList(ZammTest):
    def test_lists_digest_records_slug_first(self):
        self.led.add("first-rule", "Always snapshot before migrating.",
                     scope="ops/migrations")
        self.led.add("second-rule", "Batch endpoint over per-item calls.",
                     scope="contracts/api")
        self.led.compile()

        r = self.led.memory_list()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("first-rule", r.out)
        self.assertIn_("ops/migrations", r.out)
        self.assertEqual(len(r.out.strip().splitlines()), 2)

    def test_scope_filter_narrows_by_area(self):
        self.led.add("a", "One.", scope="contracts/api")
        self.led.add("b", "Two.", scope="conventions/naming")
        self.led.compile()

        r = self.led.memory_list("--scope", "contracts")

        self.assertEqual(len(r.out.strip().splitlines()), 1)
        self.assertIn_("contracts/api", r.out)

    def test_all_includes_records_below_the_digest_budget(self):
        """The default view is what is influencing the agent; --all is the
        complete live set."""
        self.led.add_many(240)
        self.led.compile()

        default = self.led.memory_list()
        everything = self.led.memory_list("--all")

        self.assertEqual(len(default.out.strip().splitlines()), 225)
        self.assertEqual(len(everything.out.strip().splitlines()), 240)

    def test_superseded_records_are_not_listed(self):
        old = self.led.add("rule", "Old statement.")
        self.led.add("rule", "New statement.", date="2026-01-06", supersedes=old)
        self.led.compile()

        r = self.led.memory_list("--all")

        self.assertIn_("New statement.", r.out)
        self.assertNotIn_("Old statement.", r.out)


class TestMemoryShow(ZammTest):
    def test_resolves_a_slug(self):
        self.led.add("findable-rule", "A statement worth reading.")

        r = self.led.memory_show("findable-rule")

        self.assertCode(r, EXIT_OK)
        self.assertIn_("A statement worth reading.", r.out)
        self.assertIn_("scope:", r.out)

    def test_resolves_a_full_id(self):
        """Agents copy ids straight out of the digest brackets."""
        rid = self.led.add("findable-rule", "A statement.")

        r = self.led.memory_show(rid)

        self.assertCode(r, EXIT_OK)
        self.assertIn_(rid, r.out)

    def test_ambiguous_slug_lists_the_generations(self):
        """Superseding records reuse the slug, so the disambiguation prompt
        doubles as the history of a statement."""
        old = self.led.add("shared-slug", "First.", date="2026-01-05")
        self.led.add("shared-slug", "Second.", date="2026-01-06", supersedes=old)

        r = self.led.memory_show("shared-slug")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("matches 2 records", r.err)
        self.assertIn_("2026-01-05-shared-slug", r.err)
        self.assertIn_("2026-01-06-shared-slug", r.err)

    def test_missing_record_says_so(self):
        r = self.led.memory_show("no-such-thing")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("no record matches", r.err)


class TestMemoryArchive(ZammTest):
    def _retired_chain(self, slug):
        rec = self.led.add(slug, f"Retired knowledge: {slug}.")
        self.led.add(f"retire-{slug}", "No longer applies.", date="2026-01-06",
                     type="tombstone", supersedes=rec)
        return rec

    def test_moves_fully_retired_chains(self):
        self.led.add("live-rule", "Still true.")
        self._retired_chain("obsolete")
        self.led.compile()

        r = self.led.memory_archive()

        self.assertCode(r, EXIT_OK)
        self.assertTrue(self.led.exists(
            "zamm-memory/archive/knowledge/2026/2026-01-05-obsolete-22223.md"))
        self.assertFalse(self.led.exists(
            "zamm-memory/knowledge/2026/2026-01-05-obsolete-22223.md"))

    def test_never_moves_an_ancestor_of_a_live_head(self):
        """The dangerous case. Votes aggregate over the ancestor chain, so a
        superseded ancestor of something living is load-bearing: moving it
        would drop its descendant's vote signal and dangle the reference."""
        old = self.led.add("evolving", "First version.")
        self.led.add("evolving", "Current version.", date="2026-01-06",
                     supersedes=old)
        self.led.compile()

        r = self.led.memory_archive()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("No inert records", r.out)
        self.assertTrue(self.led.exists(
            f"zamm-memory/knowledge/2026/{old}.md"), "ancestor must stay")

    def test_never_moves_a_live_votes_record(self):
        target = self.led.add("voted", "A statement with a vote.")
        self.led.add("closure", type="votes", date="2026-01-06", plan="p",
                     up=target)
        self.led.compile()

        r = self.led.memory_archive()

        self.assertIn_("No inert records", r.out)

    def test_the_digest_is_unchanged_by_archiving(self):
        """The defining property: archiving removes only records that
        influence nothing, so the digest below the header must not move.
        The generation trailer is pairing metadata over the WHOLE file
        (header included, whose files= count legitimately drops), so it is
        excluded like the header itself."""

        def body(text):
            return [ln for ln in text.splitlines()[1:]
                    if not ln.startswith("<!-- zamm-generation: ")]

        self.led.add("live-rule", "Still true.")
        self.led.add_many(4)
        self._retired_chain("obsolete")
        self.led.compile()
        before = body(self.led.digest())

        self.led.memory_archive()

        self.assertEqual(before, body(self.led.digest()))

    def test_archived_ids_stay_resolvable_and_greppable(self):
        rec = self._retired_chain("obsolete")
        self.led.add("live-rule", "Still true.")
        self.led.compile()
        self.led.memory_archive()

        self.assertCode(self.led.check(), EXIT_OK, "no dangling reference")
        r = self.led.memory_show(rec)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("ARCHIVED", r.out)

    def test_dry_run_moves_nothing(self):
        self._retired_chain("obsolete")
        self.led.compile()

        r = self.led.memory_archive("--dry-run")

        self.assertCode(r, EXIT_OK)
        self.assertIn_("Dry run", r.out)
        self.assertTrue(self.led.exists(
            "zamm-memory/knowledge/2026/2026-01-05-obsolete-22222.md"))

    def test_refuses_to_archive_from_an_invalid_ledger(self):
        """The inert rule is a graph conclusion; a broken graph cannot
        support one."""
        self._retired_chain("obsolete")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-07-broken-99999.md",
            "---\ntype: memory\nscope: contracts/api\ncreated: 2026-01-07\n---\nBroken.\n",
        )

        r = self.led.memory_archive()

        self.assertNotEqual(r.code, 0)
        self.assertIn_("refusing to archive", r.err)


class TestPlanCommands(ZammTest):
    def test_plan_show_reports_done_when_progress(self):
        self.led.add_plan("2026-01-05-working", status="Implementing")
        r = self.led.plan_show("working")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("Done-when: 0/1", r.out)
        self.assertIn_("Status: Implementing", r.out)

    def test_plan_create_makes_a_usable_plan(self):
        r = self.led.plan_create("Try Something New")

        self.assertCode(r, EXIT_OK)
        path = r.out.strip()
        self.assertIn_("try-something-new", path)
        self.assertTrue(self.led.exists(path))
        self.assertTrue(self.led.exists(f"{path.rsplit('/', 1)[0]}/workdir"))
        self.assertIn_("# Try Something New", self.led.read(path))

    def test_plan_create_refuses_a_duplicate(self):
        self.led.plan_create("Same Title")
        r = self.led.plan_create("Same Title")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("already exists", r.err)

    def test_plan_check_passes_a_well_formed_plan(self):
        self.led.add_plan("2026-01-05-fine", status="Implementing")
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_plan_check_catches_a_done_plan_without_approval(self):
        """External review High 2: the archive script trusted the Status
        word alone, so a Done plan with empty approval fields archived
        cleanly."""
        self.led.add_plan("2026-01-05-sloppy", status="Done", valid=False)

        r = self.led.plan_check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Done-approved-by", r.err)

    def test_plan_check_catches_unchecked_work_at_closure(self):
        self.led.add_plan("2026-01-05-early", status="Review", valid=False)
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("unchecked", r.err)

    def test_plan_check_catches_an_unknown_status(self):
        self.led.write(
            "zamm-memory/active/plans/2026-01-05-odd/2026-01-05-odd.plan.md",
            "# Odd\n\nStatus: Marinating\nLast updated: 2026-01-05\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("unknown Status", r.err)

    def test_archive_refuses_a_plan_that_fails_check(self):
        """The consequence that closes High 2: a plan that cannot pass
        validation must not become archived history."""
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-sloppy", status="Done", valid=False)

        r = self.led.archive()

        self.assertNotEqual(r.code, 0)
        self.assertIn_("refusing to archive", r.err)
        self.assertTrue(self.led.exists(
            "zamm-memory/active/plans/2026-01-05-sloppy"))

    def test_archive_accepts_a_properly_closed_plan(self):
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-proper", status="Done")

        r = self.led.archive()

        self.assertCode(r, EXIT_OK)
        self.assertTrue(self.led.exists(
            "zamm-memory/archive/plans/2026-01-05-proper"))


class TestTopLevelCheck(ZammTest):
    def test_passes_when_both_halves_pass(self):
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-fine", status="Implementing")
        self.assertCode(self.led.check_all(), EXIT_OK)

    def test_fails_when_the_ledger_is_invalid(self):
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-05-broken-22222.md",
            "---\ntype: memory\nscope: contracts/api\ncreated: 2026-01-05\n---\nBad.\n",
        )
        self.assertCode(self.led.check_all(), EXIT_CONTRACT)

    def test_fails_when_a_plan_is_invalid(self):
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-sloppy", status="Done", valid=False)
        self.assertCode(self.led.check_all(), EXIT_CONTRACT)
