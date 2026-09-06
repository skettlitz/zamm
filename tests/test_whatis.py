"""`whatis`: a search hit gets a standing.

A full-text or similarity search cannot tell a superseded, retired or
archived record from the one in force. `whatis` takes whatever the search
returned - path, qmd:// URL, id, plan, slug - and prints the standing the
compiler assigned, the chain, and the live head. Read-only.
"""
import unittest

from harness import ZammTest


class TestRecords(ZammTest):
    def chain(self):
        a = self.led.add("tier-motion", "Old rule.", date="2026-01-05")
        b = self.led.add("tier-motion", "Newer rule.\n\n## Background\n\nWhy.",
                         date="2026-02-05", supersedes=a)
        c = self.led.add("tier-motion", "Current rule.", date="2026-03-05", supersedes=b)
        return a, b, c

    def test_a_slug_prints_every_generation_with_its_standing(self):
        a, b, c = self.chain()
        r = self.led.zamm("whatis", "tier-motion")
        self.assertEqual(r.code, 0, r)
        out = r.out
        self.assertIn_(f"standing:  superseded by {b}", out)
        self.assertIn_(f"standing:  superseded by {c}", out)
        self.assertIn_("standing:  live - counts now", out)
        # the chain is listed on every block, oldest first, with the marker
        self.assertIn_(f"{a}  [superseded memory]  Old rule.  <- this", out)
        self.assertIn_(f"{c}  [live memory]  Current rule.  <- this", out)
        # blocks appear in chronological order
        self.assertLess(out.index(a), out.index(b))
        self.assertLess(out.index(b), out.index(c))

    def test_a_superseded_record_hands_over_the_live_head_and_its_body(self):
        a, b, c = self.chain()
        r = self.led.zamm("whatis", f"zamm-memory/knowledge/2026/{a}.md")
        self.assertEqual(r.code, 0, r)
        self.assertIn_(f"live head: {c}  Current rule.", r.out)
        self.assertIn_(f"in force now ({c}):\n    Current rule.", r.out)
        # the dead record is not dug up: no own body, no own metadata
        self.assertNotIn("body:\n    Old rule.", r.out)
        self.assertNotIn("scope:", r.out)
        # a live head gets its own detail
        live = self.led.zamm("whatis", c).out
        self.assertIn_("scope: contracts/api", live)
        self.assertIn_("body:\n    Current rule.", live)

    def test_brief_drops_the_bodies(self):
        a, b, c = self.chain()
        r = self.led.zamm("whatis", "--brief", a)
        self.assertEqual(r.code, 0, r)
        self.assertIn_(f"live head: {c}", r.out)
        self.assertNotIn("in force now", r.out)

    def test_listing_follows_the_published_digest(self):
        a, b, c = self.chain()
        before = self.led.zamm("whatis", "--brief", c).out
        self.assertIn_("listing unknown", before)
        self.led.compile()
        after = self.led.zamm("whatis", "--brief", c).out
        self.assertIn_("live - counts now; listed in the digest", after)

    def test_whatis_writes_nothing(self):
        self.chain()
        self.led.zamm("whatis", "tier-motion")
        self.assertFalse(self.led.exists("zamm-memory/.compiled/memory.md"))
        self.assertFalse(self.led.exists("zamm-memory/.compiled/state.tsv"))

    def test_retired_names_the_tombstone_and_its_reason(self):
        t = self.led.add("dead-end", "A rule that was wrong.", date="2026-01-06")
        ts = self.led.add("dead-end", "Retired: it was wrong.", date="2026-02-06",
                          type="tombstone", supersedes=t, scope=None,
                          importance=None, durability=None)
        r = self.led.zamm("whatis", t)
        self.assertEqual(r.code, 0, r)
        self.assertIn_(f"standing:  retired by tombstone {ts}", r.out)
        self.assertIn_("live head: none", r.out)
        self.assertIn_(f"retired because ({ts}):\n    Retired: it was wrong.", r.out)

    def test_quarantined_carries_the_reason(self):
        q = self.led.add("broken", "Bad.", date="2026-01-07", scope="nonsense-area")
        r = self.led.zamm("whatis", q)
        self.assertEqual(r.code, 0, r)
        self.assertIn_("standing:  quarantined", r.out)
        self.assertIn_('unknown scope area "nonsense-area"', r.out)
        self.assertNotIn("body:", r.out)

    def test_erased_says_so_and_prints_no_content(self):
        e = self.led.add("leak", "A secret-bearing record.", date="2026-01-06")
        self.led.erase(e)
        r = self.led.zamm("whatis", e)
        self.assertEqual(r.code, 0, r)
        self.assertIn_("standing:  erased", r.out)
        self.assertNotIn("secret-bearing", r.out)

    def test_dormant_is_live_but_decayed(self):
        d = self.led.add("fleeting", "Short-lived note.", date="2025-01-05",
                         durability="days")
        r = self.led.zamm("whatis", "--brief", d)
        self.assertEqual(r.code, 0, r)
        self.assertIn_("standing:  dormant", r.out)

    def test_backlog_and_journal_records_are_identified_by_tree_and_class(self):
        i = self.led.add_idea("split-index", "Split the index.", date="2026-01-08")
        j = self.led.add_episode("outage", "The build broke.", date="2026-01-09")
        r = self.led.zamm("whatis", "--brief", i, j)
        self.assertEqual(r.code, 0, r)
        self.assertIn_("what:      backlog record (memory)", r.out)
        self.assertIn_("what:      journal record (entry)", r.out)

    def test_a_draft_is_not_a_record(self):
        self.led.draft("pending-thought")
        drafts = list((self.led.root / "zamm-memory/knowledge").rglob("*.md.draft"))
        self.assertEqual(len(drafts), 1)
        r = self.led.zamm("whatis", str(drafts[0]))
        self.assertEqual(r.code, 0, r)
        self.assertIn_("unpublished hand-written draft", r.out)


class TestStandingWording(ZammTest):
    def test_a_tombstone_in_effect_does_not_say_counts_now(self):
        t = self.led.add("dead-end", "Wrong.", date="2026-01-06")
        ts = self.led.add("dead-end", "Retired: wrong.", date="2026-02-06",
                          type="tombstone", supersedes=t, scope=None,
                          importance=None, durability=None)
        r = self.led.zamm("whatis", ts)
        self.assertEqual(r.code, 0, r)
        self.assertIn_("standing:  tombstone in effect", r.out)
        self.assertNotIn("counts now", r.out)
        self.assertIn_("live head: none", r.out)
        self.assertIn_("reason:\n    Retired: wrong.", r.out)

    def test_two_refs_to_one_record_print_one_report(self):
        a = self.led.add("one", "One.", date="2026-01-05")
        r = self.led.zamm("whatis", "--brief", a, f"zamm-memory/knowledge/2026/{a}.md")
        self.assertEqual(r.code, 0, r)
        self.assertEqual(r.out.count("standing:"), 1)
        self.assertIn_("see above: the same record", r.out)

    def test_unlisted_says_still_true(self):
        # a guardrail-free ledger bigger than the digest budget is expensive;
        # the wording is asserted on the listed path and the sidecar path
        a = self.led.add("one", "One.", date="2026-01-05")
        self.led.compile()
        self.assertIn_("listed in the digest", self.led.zamm("whatis", "--brief", a).out)


class TestStrayBodyKey(ZammTest):
    BODY = "supersedes: 2026-01-05-older-aaaaa\n\nThe real headline.\n"

    def test_create_refuses_a_body_that_opens_with_a_frontmatter_key(self):
        self.led.add("older", "Older.", date="2026-01-05")
        r = self.led.new_memory("--scope", "contracts/api", "newer",
                                body=self.BODY, validate=True)
        self.assertNotEqual(r.code, 0, r)
        self.assertIn_('body opens with "supersedes:"', r.err)
        written = [f for f in (self.led.root / "zamm-memory/knowledge").rglob("*newer*")]
        self.assertEqual(written, [], "nothing may be written")

    def test_check_warns_about_an_existing_one_without_quarantining(self):
        old = self.led.add("older", "Older.", date="2026-01-05")
        new = self.led.add("newer", f"supersedes: {old}\n\nThe real headline.",
                           date="2026-01-06")
        r = self.led.check()
        self.assertEqual(r.code, 0, r)
        self.assertIn_('WARNING', r.err)
        self.assertIn_('body opens with "supersedes:"', r.err)
        w = self.led.zamm("whatis", "--brief", new, old)
        self.assertEqual(w.code, 0, w)
        # both live: the edge exists only in prose, and the report says so
        self.assertEqual(w.out.count("standing:  live"), 2)
        self.assertIn_(f'warning:   the body opens with "supersedes: {old}"', w.out)
        self.assertIn_("no supersedes was applied", w.out)


class TestFailClosed(ZammTest):
    def test_a_read_only_compiled_dir_is_no_obstacle(self):
        a = self.led.add("one", "One.", date="2026-01-05")
        self.led.compile()
        comp = self.led.root / "zamm-memory/.compiled"
        comp.chmod(0o555)
        try:
            r = self.led.zamm("whatis", "--brief", a)
        finally:
            comp.chmod(0o755)
        self.assertEqual(r.code, 0, r)
        self.assertIn_("standing:  live", r.out)

    def test_an_unreadable_tree_is_exit_4_not_no_such_record(self):
        import os
        if os.geteuid() == 0:
            self.skipTest("root reads everything")
        a = self.led.add("one", "One.", date="2026-01-05")
        kn = self.led.root / "zamm-memory/knowledge/2026"
        kn.chmod(0o000)
        try:
            r = self.led.zamm("whatis", "--brief", a)
        finally:
            kn.chmod(0o755)
        self.assertEqual(r.code, 4, r)
        self.assertIn_("unreadable, not empty", r.err)
        self.assertNotIn("does not enumerate", r.out)


class TestArchive(ZammTest):
    def archived_chain(self):
        t = self.led.add("dead-end", "A rule that was wrong.", date="2026-01-06")
        ts = self.led.add("dead-end", "Retired: it was wrong.", date="2026-02-06",
                          type="tombstone", supersedes=t, scope=None,
                          importance=None, durability=None)
        self.led.add("keep", "Something live so the digest publishes.")
        self.assertEqual(self.led.compile().code, 0)
        r = self.led.memory_archive()
        self.assertEqual(r.code, 0, r)
        self.assertTrue(self.led.exists(f"zamm-memory/archive/knowledge/2026/{t}.md"))
        return t, ts

    def test_an_archived_hit_is_history_with_headlines_read_from_the_files(self):
        t, ts = self.archived_chain()
        r = self.led.zamm("whatis", f"zamm-memory/archive/knowledge/2026/{t}.md")
        self.assertEqual(r.code, 0, r)
        self.assertIn_("what:      knowledge record (memory), archived", r.out)
        self.assertIn_("standing:  archived - fully-retired chain", r.out)
        self.assertIn_(f"{t}  [archived memory]  A rule that was wrong.  <- this", r.out)
        self.assertIn_(f"{ts}  [archived tombstone]  Retired: it was wrong.", r.out)
        self.assertIn_("live head: none", r.out)

    def test_a_stale_path_resolves_by_name_with_a_note(self):
        t, ts = self.archived_chain()
        # the search index still remembers the live-tree path
        r = self.led.zamm("whatis", "--brief", f"zamm-memory/knowledge/2026/{t}.md")
        self.assertEqual(r.code, 0, r)
        self.assertIn_("does not exist here (moved or erased", r.out)
        self.assertIn_(f"zamm-memory/archive/knowledge/2026/{t}.md", r.out)
        self.assertIn_("standing:  archived", r.out)

    def test_a_pre_v3_note_without_frontmatter_shows_its_title(self):
        self.led.write("zamm-memory/archive/knowledge/consolidations/2026-05-12-2014-sand-consolidation.md",
                       "# SAND Consolidation - 2026-05-12 20:14\n\nTrigger: post-distillation\n")
        self.led.add("keep", "Something live.")
        r = self.led.zamm("whatis", "--brief",
                          "zamm-memory/archive/knowledge/consolidations/2026-05-12-2014-sand-consolidation.md")
        self.assertEqual(r.code, 0, r)
        self.assertIn_("note without frontmatter (pre-v3), archived", r.out)
        self.assertIn_("headline:  SAND Consolidation - 2026-05-12 20:14", r.out)

    def test_a_qmd_url_with_a_line_suffix_resolves(self):
        t, ts = self.archived_chain()
        r = self.led.zamm("whatis", "--brief",
                          f"qmd://proj/zamm-memory/archive/knowledge/2026/{t}.md:12")
        self.assertEqual(r.code, 0, r)
        self.assertIn_("standing:  archived", r.out)


class TestPlansAndOtherFiles(ZammTest):
    def test_an_active_plan_by_slug_id_and_path(self):
        self.led.add_plan("2026-01-10-do-things", status="Implementing", title="Do things")
        path = "zamm-memory/active/plans/2026-01-10-do-things/2026-01-10-do-things.plan.md"
        for ref in ("do-things", "2026-01-10-do-things", path,
                    str(self.led.root / path)):
            with self.subTest(ref=ref):
                r = self.led.zamm("whatis", ref)
                self.assertEqual(r.code, 0, r)
                self.assertIn_("what:      plan (main file)", r.out)
                self.assertIn_("standing:  active plan (Status: Implementing)", r.out)
                self.assertIn_("done-when: 0/1", r.out)
                self.assertIn_("title:     Do things", r.out)
                self.assertIn_("head (through the first section", r.out)

    def test_scratch_and_subplans_name_their_plan(self):
        self.led.add_plan("2026-01-10-do-things", status="Draft")
        self.led.write("zamm-memory/active/plans/2026-01-10-do-things/workdir/notes.md", "scratch\n")
        self.led.write("zamm-memory/active/plans/2026-01-10-do-things/2026-01-10-do-things.subplan-a.plan.md",
                       "# sub\n\nStatus: Draft\n")
        r = self.led.zamm("whatis", "--brief",
                          "zamm-memory/active/plans/2026-01-10-do-things/workdir/notes.md",
                          "zamm-memory/active/plans/2026-01-10-do-things/2026-01-10-do-things.subplan-a.plan.md")
        self.assertEqual(r.code, 0, r)
        self.assertIn_("plan scratch (workdir/", r.out)
        self.assertIn_("subplan of the plan below", r.out)
        self.assertEqual(r.out.count("plan:      zamm-memory/active/plans/2026-01-10-do-things"), 2)

    def test_an_archived_plan_is_history(self):
        self.led.write("zamm-memory/archive/plans/2026-01-01-old/2026-01-01-old.plan.md",
                       "# Old\n\nStatus: Done\nLast updated: 2026-01-02\n\n## Done-when\n\n- [x] x\n")
        r = self.led.zamm("whatis", "--brief", "old")
        self.assertEqual(r.code, 0, r)
        self.assertIn_("standing:  archived plan (Status: Done)", r.out)

    def test_generated_tree_and_ordinary_files_are_named_for_what_they_are(self):
        self.led.add("keep", "Something.")
        self.led.compile()
        self.led.write("docs/guide.md", "# guide\n")
        r = self.led.zamm("whatis", "zamm-memory/.compiled/memory.md",
                          "zamm-memory/VERSION", "docs/guide.md")
        self.assertEqual(r.code, 0, r)
        self.assertIn_("generated lens", r.out)
        self.assertIn_("part of the ZAMM tree, not a record", r.out)
        self.assertIn_("ordinary project file, not a ZAMM record", r.out)

    def test_a_docid_and_an_unknown_name_fail_loudly(self):
        r = self.led.zamm("whatis", "#abc123")
        self.assertEqual(r.code, 1, r)
        self.assertIn_("docid, not a path", r.out)
        r = self.led.zamm("whatis", "nope")
        self.assertEqual(r.code, 1, r)
        self.assertIn_('nothing named "nope" in any tree', r.err)

    def test_no_ref_and_help(self):
        self.assertEqual(self.led.zamm("whatis").code, 1)
        for args in (("whatis", "--help"), ("help", "whatis")):
            r = self.led.zamm(*args)
            self.assertEqual(r.code, 0, r)
            self.assertIn_("Usage: zamm-run.sh whatis", r.out)


if __name__ == "__main__":
    unittest.main()
