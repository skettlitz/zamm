"""A Draft in the digest's Plans tail: one line, after the plans in work.

Session start is where every agent pays for every line, and a Draft is not
work in progress. It used to take the same three-line entry as an
Implementing plan and differ only by ranking last, so an unstarted plan that
had sat for a month read like the work above it. What these tests hold:

  * a Draft takes ONE line, listed after the entries: its title, its plan id
    and the date it was last touched;
  * the title stays, because Session Start matches the request against this
    tail and a Draft nobody can see gets a second plan beside it;
  * anything irregular about a Draft (an open block, an annotated status)
    keeps the full entry, because both are `plan check` errors and an error
    must not be the quiet line.

See references/plans-reading.md for the tail these tests describe.
"""

from harness import EXIT_OK, ZammTest

PLAN = "zamm-memory/active/plans/{0}/{0}.plan.md"
FULL = "zamm-memory/.compiled/zamm-digest-full.md"


def tail_of(text):
    return text.split("## Plans")[1]


class TestDraftsInTheDigestTail(ZammTest):

    def _tail(self):
        self.assertCode(self.led.compile(), EXIT_OK)
        return tail_of(self.led.digest())

    def test_a_draft_takes_one_line_after_the_plans_in_work(self):
        self.led.add_plan("2026-01-05-w", status="Implementing",
                          title="Work in progress")
        self.led.add_plan("2026-01-06-d", status="Draft",
                          title="Sketch the thing")
        tail = self._tail()

        self.assertIn_("- Implementing: 2026-01-05-w", tail)
        self.assertIn_("Drafts (1; not started):\n"
                       "- Sketch the thing [2026-01-06-d] (last 2026-01-05)\n",
                       tail)
        self.assertLess(tail.index("- Implementing:"), tail.index("Drafts ("))
        # the Draft has no entry of its own: no status line, no scope, no
        # progress (the fixture gives every plan a scope and a Done-when)
        self.assertNotIn_("- Draft:", tail)
        self.assertEqual(1, tail.count("in: synthetic in-scope note."), tail)
        self.assertEqual(1, tail.count("done-when"), tail)

    def test_the_full_digest_lists_a_draft_the_same_way(self):
        self.led.add("rule", "A statement.")
        self.led.add_plan("2026-01-06-d", status="Draft",
                          title="Sketch the thing")
        tail = self._tail()

        self.assertEqual(tail_of(self.led.read(FULL)).split("<!--")[0],
                         tail.split("<!--")[0])

    def test_only_drafts_means_no_active_plans_and_a_drafts_list(self):
        self.led.add_plan("2026-01-06-d", status="Draft",
                          title="Sketch the thing")
        tail = self._tail()

        self.assertIn_("(no active plans)", tail)
        self.assertIn_("Drafts (1; not started):", tail)
        self.assertLess(tail.index("(no active plans)"), tail.index("Drafts ("))

    def test_drafts_are_listed_oldest_plan_id_first(self):
        self.led.add_plan("2026-02-01-newer", status="Draft", title="Apple")
        self.led.add_plan("2026-01-01-older", status="Draft", title="Zebra")
        tail = self._tail()

        self.assertIn_("Drafts (2; not started):", tail)
        self.assertLess(tail.index("[2026-01-01-older]"),
                        tail.index("[2026-02-01-newer]"))

    def test_drafts_come_before_the_recently_archived_list(self):
        self.led.add_plan("2026-01-06-d", status="Draft")
        self.led.write("zamm-memory/archive/plans/2026-01-01-old/2026-01-01-old.plan.md",
                       "# Old\n\nStatus: Done\nLast updated: 2026-01-02\n\n"
                       "## Done-when\n\n- [x] x\n")
        tail = self._tail()

        self.assertLess(tail.index("Drafts ("), tail.index("Recently archived"))

    def test_a_long_title_is_cut_and_a_missing_one_is_named(self):
        self.led.add_plan("2026-01-06-long", status="Draft", title="T" * 140)
        self.led.write(PLAN.format("2026-01-07-bare"),
                       "Status: Draft\nLast updated: 2026-01-07\n")
        tail = self._tail()

        self.assertIn_("- " + "T" * 97 + "... [2026-01-06-long]", tail)
        self.assertIn_("- (untitled) [2026-01-07-bare] (last 2026-01-07)", tail)

    def test_a_draft_with_an_open_block_keeps_its_full_entry(self):
        """An open block under Draft is a `plan check` error, and the tail
        renders every open block whatever the status says. One line would
        hide it."""
        self.led.add_plan("2026-01-06-d", status="Draft")
        p = PLAN.format("2026-01-06-d")
        self.led.write(p, self.led.read(p) + (
            "\n## Blocked-on\n\n"
            "- 2026-01-05 [human]: Still open.\n"))
        tail = self._tail()

        self.assertIn_("- Draft: 2026-01-06-d", tail)
        self.assertIn_("blocked[human]: Still open.", tail)
        self.assertNotIn_("Drafts (", tail)

    def test_a_resolved_block_does_not_hold_a_draft_among_the_entries(self):
        self.led.add_plan("2026-01-06-d", status="Draft")
        p = PLAN.format("2026-01-06-d")
        self.led.write(p, self.led.read(p) + (
            "\n## Blocked-on\n\n"
            "- 2026-01-05 [human]: Needed a ruling.\n"
            "  Resolved 2026-01-06: got the ruling.\n"))
        tail = self._tail()

        self.assertIn_("Drafts (1; not started):", tail)
        self.assertNotIn_("- Draft:", tail)

    def test_an_annotated_draft_status_keeps_its_full_entry(self):
        """Only the exact status qualifies. `Draft (waiting)` is not a status
        `plan check` accepts, and the entry is where its label is shown."""
        self.led.write(PLAN.format("2026-01-06-d"),
                       "# Sketch\n\nStatus: Draft (waiting)\n"
                       "Last updated: 2026-01-05\n\n## Done-when\n\n- [ ] x\n")
        tail = self._tail()

        self.assertIn_("- Draft (waiting): 2026-01-06-d", tail)
        self.assertNotIn_("Drafts (", tail)

    def test_a_draft_that_starts_moves_to_the_entries(self):
        self.led.add_plan("2026-01-06-d", status="Draft", title="Sketch")
        self.assertIn_("Drafts (1; not started):", self._tail())

        p = PLAN.format("2026-01-06-d")
        self.led.write(p, self.led.read(p).replace(
            "Status: Draft",
            "Status: Implementing\nExecution-context-before: x\n"
            "Complexity-forecast: gecko"))
        tail = self._tail()

        self.assertIn_("- Implementing: 2026-01-06-d [gecko] done-when 0/1", tail)
        self.assertNotIn_("Drafts (", tail)
