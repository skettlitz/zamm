"""The journal: episodes as ordinary records in a fourth tree.

Things that happened and are worth a trace — implying no action and asserting
no durable claim — live in zamm-memory/journal/ under the same record
contract and the same compiler, rendered into a PULLED timeline lens
(journal list). Three record classes share the tree and resolve by value:
entries (type: memory), elevations (type: digest, stored digests of a
period) and watermarks (reviewed-through: coverage claims). Digestion is a
trichotomy: compiled views (journal digest, never stored), triage behind a
max-of-dates watermark (review/settle) and elevation (journal elevate). The
knowledge digest's entire standing exposure is one Journal: line, present
only when digestion is due.

These suites lock the tree's policy switches, the class rules, the watermark
semantics (max-of-dates, inclusive boundary, never dormant), the capture
contract, the read seams (search, stats, export), the digestion trichotomy,
and the digest line's due-logic.
"""

import os
import re

from harness import (
    SKILL_DIR,
    EXIT_DEGRADED,
    EXIT_OK,
    EXIT_REFUSED_PUBLISH,
    EXIT_UNREADABLE,
    ZammTest,
    needs_permission_bits,
)

# every journal write in the suite pins its clock and identity, so ids,
# lens order and stamps are deterministic
STAMPS = {"ZAMM_TIME": "14:12", "ZAMM_AGENT": "claude-fable-5",
          "ZAMM_USER": "ske"}

EXPORT_COLUMNS = ("id\tclass\tcreated\ttime\tagent\tuser\tcue\tkind\tcovers"
                  "\tpass\treviewed-through\tscope\tsalience\tstate"
                  "\treviewed\tbg\taxes\theadline\tpasses")


def knowledge_view(digest_text):
    """memory.md with the journal-owned line stripped.

    The digest legitimately gains a Journal: line when digestion is due, so
    knowledge-isolation assertions normalize — a raw byte comparison would
    fail on that line alone.
    """
    out = []
    for ln in digest_text.splitlines():
        if ln.startswith("Journal:") or ln.startswith("<!-- zamm-generation:"):
            continue
        out.append(ln)
    return "\n".join(out).rstrip("\n")


class TestJournalLens(ZammTest):
    """The timeline lens: months newest first, dormant collapsed."""

    def test_timeline_is_newest_first_with_time_as_the_intra_day_key(self):
        self.led.add_episode("early", "The early one.", date="2026-07-10",
                             time="09:00")
        self.led.add_episode("late", "The late one.", date="2026-07-10",
                             time="17:30")
        self.led.add_episode("untimed", "The untimed one.",
                             date="2026-07-10")
        self.led.add_episode("june", "A June episode.", date="2026-06-02")

        r = self.led.journal("list")

        self.assertCode(r, EXIT_OK)
        order = []
        for ln in r.out.splitlines():
            if ln.startswith("## "):
                order.append(ln[3:10])
            elif ln.startswith("- "):
                order.append(next(w for w in ("late", "early", "untimed",
                                              "June") if w in ln))
        self.assertEqual(order, ["2026-07", "late", "early", "untimed",
                                 "2026-06", "June"],
                         "months newest first; within a day the latest "
                         "time first and an untimed entry last")

    def test_dormant_entries_collapse_to_month_counts(self):
        """A cooled episode leaves the listing but not the record of what
        happened: counted per month, listed by --all."""
        self.led.add_episode("fresh", "A fresh episode.", date="2026-07-18")
        cold = self.led.add_episode("cold", "An old whisper.",
                                    date="2026-01-05", importance="minor",
                                    durability="days")

        r = self.led.journal("list")
        self.assertCode(r, EXIT_OK)
        self.assertNotIn_(cold, r.out, "a dormant entry is counted, not listed")
        self.assertIn_("1 entries dormant: 2026-01 x1", r.out)

        r = self.led.journal("list", "--all")
        self.assertIn_(cold, r.out, "--all must name dormant ids")

    def test_the_lens_marks_elevated_months_and_hides_elevations(self):
        self.led.add_episode("june", "A June episode.", date="2026-06-02")
        elev = self.led.add_elevation("monthly", "2026-06",
                                      "June in one sentence.",
                                      date="2026-07-01")
        r = self.led.journal("list")
        self.assertIn_("## 2026-06 - elevated: monthly", r.out)
        self.assertNotIn_(elev, r.out,
                          "an elevation is not an entry in the timeline")
        self.assertIn_("Never reviewed; 1 undigested.", r.out)

    def test_treeless_project_lists_a_clean_empty_journal(self):
        """Absence is data, exit 0 — like the backlog, unlike knowledge."""
        r = self.led.journal("list")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("empty", r.out)
        r = self.led.journal("check")
        self.assertCode(r, EXIT_OK, "nothing to check is not a failure")
        r = self.led.journal("review")
        self.assertCode(r, EXIT_OK)

    @needs_permission_bits
    def test_an_unreadable_journal_tree_fails_closed(self):
        self.led.add_episode("an-episode", "A statement.")
        locked = self.led.root / "zamm-memory/journal/2026"
        os.chmod(locked, 0o000)
        try:
            r = self.led.journal("list")
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(r, EXIT_UNREADABLE)

    def test_all_quarantined_refuses_to_publish(self):
        self.led.write("zamm-memory/journal/2026/2026-01-05-broken-abcde.md",
                       "---\ntype: memory\nscope: other\ncreated: 2026-01-05\n"
                       "schema: 9\n---\n\nBroken.\n")
        r = self.led.journal("list")
        self.assertCode(r, EXIT_REFUSED_PUBLISH)

    def test_list_filters_print_a_row_listing(self):
        self.led.add_episode("quest", "A side quest.", cue="side-quest",
                             scope="tooling/ci", date="2026-07-10")
        self.led.add_episode("outage", "An outage.",
                             cue="exceptional-occurrence", date="2026-07-11")
        r = self.led.journal("list", "--cue", "side-quest")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("A side quest.", r.out)
        self.assertNotIn_("An outage.", r.out)
        r = self.led.journal("list", "--scope", "tooling")
        self.assertIn_("A side quest.", r.out, "prefix match on the area")
        r = self.led.journal("list", "--since", "2026-07-11")
        self.assertNotIn_("A side quest.", r.out)
        self.assertIn_("An outage.", r.out)


class TestJournalPolicy(ZammTest):
    """Per-tree policy switches, locked in both directions."""

    def test_guardrail_importance_is_refused(self):
        self.led.add_episode("rated", "An episode.", importance="guardrail")
        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("guardrail importance is not allowed in the journal",
                       r.output)
        r = self.led.journal("add", "An urgent episode.",
                             "--importance", "guardrail", env=STAMPS)
        self.assertNotEqual(r.code, 0, "refused before composing anything")

    def test_votes_are_refused(self):
        ep = self.led.add_episode("an-episode", "A statement.")
        self.led.add("triage", type="votes", up=ep, tree="journal",
                     scope=None, importance=None, durability=None)
        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("votes records are not allowed in the journal", r.output)

    def test_marked_is_refused(self):
        self.led.add_episode("chosen", "An episode.",
                             extra={"marked": "2026-07-01"})
        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("marked: is a backlog key", r.output)

    def test_journal_keys_are_refused_in_the_other_trees(self):
        """A journal-only key on a knowledge or backlog record is a misfile,
        not a typo: an error, never a warning."""
        self.led.add("a-fact", "A statement.", extra={"cue": "side-quest"})
        r = self.led.check()
        self.assertNotEqual(r.code, 0)
        self.assertIn_("cue: is a journal key", r.output)

        self.led.add_idea("an-idea", "A statement.",
                          extra={"axis-mood": "+3"})
        r = self.led.backlog("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("axis-mood: is a journal key", r.output)

    def test_type_digest_is_refused_outside_the_journal(self):
        """The one tree-local record type: safe in a tree older toolchains
        never scan, refused everywhere they do."""
        self.led.add("a-digest", "A stored digest.", type="digest",
                     extra={"digest": "monthly", "covers": "2026-06"})
        r = self.led.check()
        self.assertNotEqual(r.code, 0)
        self.assertIn_("type: digest is the journal elevation record type",
                       r.output)

    def test_x_keys_stay_warning_free_in_the_journal(self):
        self.led.add_episode("tagged", "An episode.",
                             extra={"x-myapp-tag": "alpha"})
        r = self.led.journal("check")
        self.assertCode(r, EXIT_OK)
        self.assertNotIn_("WARNING", r.output)

    def test_other_is_uncapped_and_capture_is_never_refused(self):
        """The capture contract: validation never rate-limits or refuses a
        well-formed capture. OTHER_MAX (5) is the one global cap that would
        have refused the sixth context-free add through the candidate
        error-diff; a reinjected cap must fail this test."""
        for i in range(7):
            self.led.add_episode(f"loose{i}", f"Loose episode {i}.")
        self.assertCode(self.led.journal("check"), EXIT_OK)
        r = self.led.journal("add", "An eighth loose episode.", env=STAMPS)
        self.assertCode(r, EXIT_OK)

    def test_knowledge_policy_does_not_leak(self):
        """The other direction: knowledge keeps its cap and its guardrails."""
        for i in range(6):
            self.led.add(f"loose{i}", f"Loose fact {i}.", scope="other")
        self.assertNotEqual(self.led.check().code, 0)


class TestJournalClasses(ZammTest):
    """Entry, elevation, watermark: one class per record, rules per value."""

    def test_an_elevation_needs_its_class_pair(self):
        self.led.add("half", "A half elevation.", type="digest", tree="journal",
                     scope="other", extra={"digest": "monthly"})
        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("needs both digest: <kind> and covers:", r.output)

    def test_a_bare_elevation_fails_the_contract(self):
        """REVIEW FINDING (2026-09-04): class validation ran only for
        records carrying a journal KEY, and a bare type: digest carries
        none - so it passed check and reached the export as an elevation
        with no kind and no period. Journal records are validated as
        classes whether or not they carry a key."""
        self.led.write("zamm-memory/journal/2026/2026-06-02-bare-22229.md",
                       "---\ntype: digest\nscope: other\nimportance: useful\n"
                       "durability: years\ncreated: 2026-06-02\nschema: 3\n"
                       "---\nAn elevation with no class pair.\n")

        r = self.led.journal("check")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("needs both digest: <kind> and covers:", r.output)

    def test_class_keys_are_mutually_exclusive(self):
        self.led.add_elevation("monthly", "2026-06", "June.",
                               extra={"cue": "summary"})
        self.led.add_elevation("monthly", "2026-05", "May.",
                               extra={"reviewed-through": "2026-05-31"})
        self.led.add_watermark("2026-06-30", extra={"salience": 3})
        self.led.add_episode("stray", "An entry with a kind.",
                             extra={"digest": "monthly"})
        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("cue:/salience: are entry keys", r.output)
        self.assertIn_("a record is exactly one class", r.output)
        self.assertIn_("a watermark claims coverage only", r.output)
        self.assertIn_("digest:/covers: belong to type: digest", r.output)

    def test_axis_values_are_self_describing_by_sign(self):
        """Two types, no registry: unsigned 0..10, signed -5..+5 (+0 in,
        -0 out); salience keeps its short spelling."""
        good = self.led.add_episode("good", "Rated.", date="2026-07-10",
                                    axes={"mood": "+0", "depth": "10",
                                          "heat": "-5"})
        self.assertCode(self.led.journal("check"), EXIT_OK)
        cases = {"eleven": {"depth": "11"}, "minus-six": {"heat": "-6"},
                 "minus-zero": {"heat": "-0"}, "alias": {"salience": "3"},
                 "float": {"depth": "3.5"}}
        for name, axes in cases.items():
            with self.subTest(case=name):
                rid = self.led.add_episode(name, "Badly rated.", axes=axes)
                r = self.led.journal("check")
                self.assertNotEqual(r.code, 0)
                self.assertIn_(rid, r.output)
                path = self.led.root / f"zamm-memory/journal/2026/{rid}.md"
                path.unlink()
        self.assertCode(self.led.journal("check"), EXIT_OK)
        self.assertIn_(good, self.led.journal("list").out)

    def test_time_pass_and_salience_grammar(self):
        self.led.add_episode("clock", "Bad clock.", time="25:00")
        self.led.add_episode("loud", "Too loud.", salience="11")
        self.led.add_watermark("2026-06-30", pass_="triage")
        self.led.add_episode("passless", "A pass without a claim.",
                             extra={"pass": "release"})
        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("time: must be HH:MM", r.output)
        self.assertIn_("salience: must be an integer 1..10", r.output)
        self.assertIn_("pass: triage is the default pass", r.output)
        self.assertIn_("pass: scopes a watermark", r.output)

    def test_an_entry_cannot_supersede_an_elevation(self):
        elev = self.led.add_elevation("monthly", "2026-06", "June.",
                                      date="2026-07-01")
        self.led.add_episode("usurper", "Not a digest.", date="2026-07-02",
                             supersedes=elev)
        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("an entry cannot supersede an elevation", r.output)


class TestWatermarks(ZammTest):
    """Coverage claims resolve by value: max of dates, inclusive, never
    dormant."""

    def test_effective_watermark_is_the_max_of_concurrent_claims(self):
        """Two reviewers' claims are both true; the larger covers more."""
        self.led.add_episode("a", "Before both.", date="2026-06-01")
        self.led.add_episode("b", "Between the claims.", date="2026-06-20")
        self.led.add_episode("c", "After both.", date="2026-07-10")
        self.led.add_watermark("2026-06-10", date="2026-06-11")
        self.led.add_watermark("2026-07-01", date="2026-07-02")
        r = self.led.journal("review", "--headlines")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("reviewed through 2026-07-01", r.out)
        self.assertIn_("After both.", r.out)
        self.assertNotIn_("Between the claims.", r.out)

    def test_the_boundary_is_inclusive(self):
        """created >= watermark is undigested: fail-open, so a same-day
        entry is never skipped forever."""
        self.led.add_episode("same-day", "Written on the claim day.",
                             date="2026-07-01")
        self.led.add_watermark("2026-07-01", date="2026-07-01")
        r = self.led.journal("review", "--headlines")
        self.assertIn_("Written on the claim day.", r.out)
        self.assertIn_("1 entry undigested", r.out)

    def test_a_retired_claim_drops_out(self):
        """Retirement of every kind counts: a tombstoned claim leaves the
        max, so the effective watermark moves backwards by withdrawal."""
        self.led.add_episode("mid", "Between the claims.", date="2026-06-20")
        self.led.add_watermark("2026-06-10", date="2026-06-11")
        wrong = self.led.add_watermark("2026-07-01", date="2026-07-02")
        self.assertNotIn_("Between the claims.",
                          self.led.journal("review", "--headlines").out)
        self.led.add("retract", "An overclaim.", type="tombstone",
                     tree="journal", supersedes=wrong, scope=None,
                     importance=None, durability=None, date="2026-07-03")
        r = self.led.journal("review", "--headlines")
        self.assertIn_("reviewed through 2026-06-10", r.out)
        self.assertIn_("Between the claims.", r.out)

    def test_a_claim_never_goes_dormant(self):
        """PRE-FIX (second read-through of the design): a claim at the
        default weeks durability would have dropped out of 'live' after its
        decay window and silently reopened everything behind it. Watermarks
        and elevations are retired only by supersede, tombstone or
        erasure."""
        self.led.add_episode("old", "Long ago.", date="2026-01-03",
                             durability="days", importance="minor")
        self.led.add_episode("new", "Recent.", date="2026-07-10")
        self.led.add_watermark("2026-01-05", date="2026-01-05",
                               durability="days")
        elev = self.led.add_elevation("monthly", "2026-01", "January.",
                                      date="2026-02-01", durability="days")
        r = self.led.journal("review", "--headlines")
        self.assertIn_("reviewed through 2026-01-05", r.out,
                       "the claim survives its durability window")
        self.assertNotIn_("Long ago.", r.out)
        self.assertIn_("Recent.", r.out)
        self.assertIn_("Elevated months with no listed entries: 2026-01 (monthly)",
                       self.led.journal("list").out,
                       "the elevation survives its durability window")
        self.assertIn_(elev, self.led.journal("export").out)

    def test_settle_claims_today_or_a_partial_boundary(self):
        self.led.add_episode("a", "First.", date="2026-07-01")
        self.led.add_episode("b", "Second.", date="2026-07-15")
        r = self.led.journal("settle", "--through", "2026-07-10", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("reviewed through 2026-07-10 (1 entries covered)",
                       r.out)
        review = self.led.journal("review", "--headlines")
        self.assertNotIn_("First.", review.out)
        self.assertIn_("Second.", review.out)

        r = self.led.journal("settle", "--through", "2026-07-10", env=STAMPS)
        self.assertNotEqual(r.code, 0, "a non-advancing claim is a mistake")
        self.assertIn_("not beyond the current triage watermark", r.output)
        r = self.led.journal("settle", "--through", "2026-07-20", env=STAMPS)
        self.assertNotEqual(r.code, 0, "a future date is an overclaim")
        self.assertIn_("future date", r.output)

        r = self.led.journal("settle", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("reviewed through 2026-07-19", r.out,
                       "settle alone claims today")
        files = list((self.led.root / "zamm-memory/journal/2026").glob(
            "2026-07-19-reviewed-through-2026-07-19-*.md"))
        self.assertEqual(len(files), 1)
        text = files[0].read_text()
        self.assertIn_("reviewed-through: 2026-07-19", text)
        self.assertIn_("agent: claude-fable-5", text)
        self.assertIn_("Reviewed 1 entries through 2026-07-19.", text)

    def test_a_late_arrival_is_not_absorbed_by_a_claim(self):
        """REVIEW FINDING (2026-09-05): coverage was a DATE, so an entry
        written or merged in afterwards - dated before the boundary -
        counted as reviewed by a claim that never saw it, and no rerun
        brought it back. A claim now names the entries it covered."""
        self.led.journal("add", "Written before the claim.",
                         "--date", "2026-07-18", env=STAMPS)
        r = self.led.journal("settle", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        wm = [p for p in (self.led.root / "zamm-memory/journal/2026")
              .glob("*reviewed-through*")][0].read_text()
        self.assertIn_("covered: 2026-07-18-written-before-the-claim-", wm)

        # arrives now, dated inside the settled range
        r = self.led.journal("add", "Backdated, arriving later.",
                             "--date", "2026-07-02", env=STAMPS)
        self.assertCode(r, EXIT_OK)

        review = self.led.journal("review", "--headlines")
        self.assertIn_("Backdated, arriving later.", review.out,
                       "an entry the claim never saw is still undigested")
        self.assertNotIn_("Written before the claim.", review.out)
        export = self.led.journal("export").out
        for line in export.splitlines()[2:]:
            f = line.split("\t")
            if f[1] != "entry":
                continue
            if "Backdated" in f[17]:
                self.assertEqual(f[14], "no")
                self.assertEqual(f[18], "-", "covered by no pass")
            else:
                self.assertEqual(f[14], "yes")
                self.assertEqual(f[18], "triage")

    def test_a_claim_naming_an_unreadable_record_covers_nothing(self):
        """REVIEW FINDING (2026-09-05): covered: ids were checked for
        SYNTAX only, so a claim could name a quarantined record - one
        nobody could read, so one nobody reviewed - and absorb it the
        moment it was repaired. A claim whose list does not hold up now
        carries no coverage at all: fail closed on authority, which here
        means fail open on the entries."""
        self.led.add_episode("readable", "A readable episode.",
                             date="2026-07-10")
        self.led.write("zamm-memory/journal/2026/2026-07-11-broke-2222e.md",
                       "---\ntype: memory\nscope: other\n"
                       "created: 2026-07-11\nschema: 9\n---\n\nBroken.\n")
        self.led.write("zamm-memory/journal/2026/2026-07-12-claim-2222f.md",
                       "---\ntype: memory\nscope: other\nimportance: useful\n"
                       "durability: weeks\ncreated: 2026-07-12\n"
                       "reviewed-through: 2026-07-12\n"
                       "covered: 2026-07-10-readable-22222, "
                       "2026-07-11-broke-2222e\nschema: 3\n---\n"
                       "\nA claim naming a record nobody could read.\n")

        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("which is quarantined - nobody could have reviewed it",
                       r.output)

        lens = self.led.journal("list")
        self.assertCode(lens, EXIT_DEGRADED)
        self.assertIn_("Void coverage claims", lens.out)
        self.assertIn_("A readable episode.",
                       self.led.journal("review", "--headlines").out,
                       "a void claim covers nothing, not even the ids it "
                       "named legitimately")

    def test_a_claim_cannot_name_what_it_could_not_have_seen(self):
        """The rest of the same rule: a covered id must be an entry OF
        this journal, and one the claim could reach."""
        wm = self.led.add_watermark("2026-07-05", date="2026-07-05")
        cases = {
            "after the boundary": "2026-07-30-later-2222g",
            "absent entirely": "2026-07-01-ghost-2222h",
            "not an entry": wm,
        }
        self.led.add_episode("later", "After the boundary.",
                             date="2026-07-30", sfx="2222g")
        for name, target in cases.items():
            with self.subTest(case=name):
                path = ("zamm-memory/journal/2026/"
                        "2026-07-20-claim-2222j.md")
                self.led.write(path,
                               "---\ntype: memory\nscope: other\n"
                               "importance: useful\ndurability: weeks\n"
                               "created: 2026-07-20\n"
                               "reviewed-through: 2026-07-20\n"
                               f"covered: {target}\nschema: 3\n---\n"
                               "\nA claim overreaching.\n")
                r = self.led.journal("check")
                self.assertNotEqual(r.code, 0, name)
                self.assertIn_("covered: names", r.output)
                (self.led.root / path).unlink()
        self.assertCode(self.led.journal("check"), EXIT_OK)

    def test_a_watermark_may_not_supersede_an_entry(self):
        """REVIEW FINDING (2026-09-05): entries and watermarks are both
        type: memory, so type compatibility alone let a coverage claim
        supersede an episode - retiring it out of the timeline and out of
        the export, against the rule that digestion never retires what it
        summarizes. Supersession joins compatible CLASSES; a tombstone is
        how a wrong record is retired."""
        ep = self.led.add_episode("victim", "An episode that must survive.",
                                  date="2026-07-10")
        self.led.write("zamm-memory/journal/2026/2026-07-19-eater-2222k.md",
                       "---\ntype: memory\nscope: other\n"
                       f"supersedes: {ep}\nimportance: useful\n"
                       "durability: weeks\ncreated: 2026-07-19\n"
                       "reviewed-through: 2026-07-19\ncovered:\n"
                       "schema: 3\n---\n\nA claim that ate an entry.\n")

        r = self.led.journal("check")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("a watermark may not supersede an entry", r.output)
        self.assertIn_(ep, self.led.journal("export").out,
                       "the episode must still be there")

    def test_a_stray_archived_copy_does_not_waive_the_class_rule(self):
        """REVIEW FINDING (2026-09-05): an interrupted archive leaves a
        record live AND archived, and edge validation took the archived
        header while the apply pass acted on the live copy. The header
        carries a type but no journal class, so a watermark could supersede
        an entry and retire it with check none the wiser. Validation reads
        the copy the edge will actually kill."""
        ep = self.led.add_episode("victim", "An episode that must survive.",
                                  date="2026-07-10")
        (self.led.root / "zamm-memory/archive/journal/2026").mkdir(
            parents=True, exist_ok=True)
        (self.led.root / f"zamm-memory/archive/journal/2026/{ep}.md").write_text(
            (self.led.root / f"zamm-memory/journal/2026/{ep}.md").read_text())
        self.led.write("zamm-memory/journal/2026/2026-07-19-eater-2222q.md",
                       "---\ntype: memory\nscope: other\n"
                       f"supersedes: {ep}\nimportance: useful\n"
                       "durability: weeks\ncreated: 2026-07-19\n"
                       "reviewed-through: 2026-07-19\ncovered:\n"
                       "schema: 3\n---\n\nA claim that ate an entry.\n")

        r = self.led.journal("check")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("a watermark may not supersede an entry", r.output)
        self.assertIn_(ep, self.led.journal("export").out)

    def test_an_erasure_redacts_only_in_its_own_tree(self):
        """REVIEW FINDING (2026-09-05): the docs routed every secret to the
        knowledge erasure command. Each tree compiles on its own, so an
        erasure record in knowledge/ leaves a journal record visible, and
        deleting the original afterwards leaves a returning copy
        unprotected. The journal's own writer redacts it."""
        ep = self.led.add_episode("leak", "Leaked TOKEN=abc123 in a log.",
                                  date="2026-06-01")

        self.led.add("leaked-token", "A token leaked.", type="erasure",
                     erases=ep, date="2026-06-02")
        self.assertIn_("TOKEN=abc123", self.led.journal("list").out,
                       "an erasure in knowledge/ does not reach the journal")

        r = self.led.journal("add", "--type", "erasure", "--erases", ep,
                             "leaked-token", stdin="A token leaked.\n")
        self.assertCode(r, EXIT_OK)
        self.assertNotIn("TOKEN=abc123", self.led.journal("list").out)
        self.assertNotIn("TOKEN=abc123", self.led.journal("export").out)
        self.assertCode(self.led.journal("check"), EXIT_OK)

    def test_a_stray_archived_copy_does_not_waive_coverage_validation(self):
        """REVIEW FINDING (2026-09-05): cover_ok took the archived exemption
        before looking for a live copy, so a claim could name a live entry
        dated AFTER its own boundary and pass - the entry was retired
        unread, check was clean, review reported nothing outstanding. The
        archived exemption applies only when no live copy exists, the same
        condition every other pass uses."""
        ep = self.led.add_episode("late", "A late entry.", date="2026-07-18")
        (self.led.root / "zamm-memory/archive/journal/2026").mkdir(
            parents=True, exist_ok=True)
        (self.led.root / f"zamm-memory/archive/journal/2026/{ep}.md").write_text(
            (self.led.root / f"zamm-memory/journal/2026/{ep}.md").read_text())
        self.led.add_watermark("2026-07-10", date="2026-07-10",
                               extra={"covered": ep})

        r = self.led.journal("check")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("not before the claim boundary", r.output)
        self.assertIn_(ep, self.led.journal("review", "--headlines").out,
                       "the entry is still undigested")

    def test_a_headline_with_backslashes_is_printed_verbatim(self):
        """REVIEW FINDING (2026-09-05): the read verbs printed stored text
        with echo, which under dash and under macOS /bin/sh interprets
        backslash escapes: a literal \\t became a tab and \\c discarded the
        rest of the line - the headline AND its record pointer. Export kept
        the text; search, review and the month digest did not."""
        text = r"Use \t for tabs and \c to stop; the rest matters."
        ep = self.led.add_episode("backslashes", text, date="2026-06-03")

        for args in (("search", "--class", "entry"),
                     ("review", "--headlines"),
                     ("digest", "2026-06", "--detail", "headlines"),
                     ("digest", "2026-06", "--detail", "blocks")):
            with self.subTest(view=" ".join(args)):
                out = self.led.journal(*args).out
                self.assertIn_(text, out)
                self.assertIn_(ep, out, "the pointer survives too")

    def test_a_claim_cannot_reach_past_its_own_date(self):
        """REVIEW FINDING (2026-09-05): settle refused a future date at the
        CLI, but a hand-written or merged record is committed content like
        any other - one line claiming the year 9999 marked every entry
        reviewed and passed check."""
        self.led.add_episode("an-episode", "A statement.", date="2026-07-10")
        self.led.write("zamm-memory/journal/2026/2026-07-11-forged-2222b.md",
                       "---\ntype: memory\nscope: other\nimportance: useful\n"
                       "durability: weeks\ncreated: 2026-07-11\n"
                       "reviewed-through: 9999-12-31\nschema: 3\n---\n"
                       "\nA forged claim.\n")

        r = self.led.journal("check")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("is later than the record date", r.output)

    def test_settle_records_only_what_the_claim_covers(self):
        """REVIEW FINDING (2026-09-04): the covered count included entries
        dated ON the boundary, and it is written into an immutable body -
        a permanent claim the very next read contradicts. What a claim
        covers is created < its date, because the boundary is inclusive."""
        self.led.add_episode("before", "Yesterday.", date="2026-07-18")
        self.led.add_episode("onthe", "Today.", date="2026-07-19")

        r = self.led.journal("settle", env=STAMPS)

        self.assertCode(r, EXIT_OK)
        self.assertIn_("(1 entries covered)", r.out)
        self.assertIn_("Not named by this claim: 1 entry dated 2026-07-19",
                       r.out)
        body = self.led.read(os.path.relpath(
            [str(p) for p in (self.led.root / "zamm-memory/journal/2026")
             .glob("*reviewed-through*")][0], self.led.root))
        self.assertIn_("Reviewed 1 entries through 2026-07-19.", body)
        self.assertIn_("Not named: 1 entry dated 2026-07-19.", body)
        self.assertNotIn_("Reviewed 2 entries", body,
                          "the permanent record must not claim the boundary "
                          "day it does not cover")

    def test_a_same_day_claim_says_what_it_cannot_clear(self):
        """PRE-FIX (probe, 2026-09-04): settle reported "26 entries covered"
        while review immediately listed the same 26 as undigested, because a
        claim dated D cannot cover the entries of D under the inclusive
        boundary. The semantics stay (fail-open: same-day work is never
        silently skipped); both surfaces now say so."""
        for i in range(3):
            self.led.add_episode(f"today{i}", f"Written today {i}.",
                                 date="2026-07-19")
        r = self.led.journal("settle", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("Not named by this claim: 3 entries dated 2026-07-19",
                       r.out)
        r = self.led.journal("review", "--headlines")
        self.assertIn_("3 entries are dated on the watermark itself "
                       "(2026-07-19) and unnamed by the claim", r.out)

    def test_a_claim_that_covers_nothing_is_still_exact(self):
        """REVIEW FINDING (2026-09-05): settle omitted --covered when it
        covered no new entries, so the record fell back to the blunt
        date-only form and absorbed whatever merged in later - the exact
        loss the covered: key exists to prevent. Settling twice on
        different days is ordinary."""
        self.led.add_episode("first", "An early entry.", date="2026-07-04")
        self.assertCode(self.led.journal("settle", "--through", "2026-07-05",
                                         env=STAMPS), EXIT_OK)
        r = self.led.journal("settle", "--through", "2026-07-10", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("(0 entries covered)", r.out)
        second = [p for p in (self.led.root / "zamm-memory/journal/2026")
                  .glob("*reviewed-through-2026-07-10*")][0].read_text()
        self.assertIn_("\ncovered:\n", second,
                       "a claim that named nothing still names nothing "
                       "explicitly - absent means the blunt date form")

        self.assertCode(self.led.journal("add", "Merged in later.",
                                         "--date", "2026-07-08", env=STAMPS),
                        EXIT_OK)
        self.assertIn_("Merged in later.",
                       self.led.journal("review", "--headlines").out,
                       "no claim named it, so it is still undigested")

    def test_custom_passes_have_their_own_watermark(self):
        self.led.add_episode("a", "An episode.", date="2026-07-01")
        r = self.led.journal("settle", "--pass", "release", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("release reviewed through 2026-07-19", r.out)
        self.assertIn_("An episode.",
                       self.led.journal("review", "--headlines").out,
                       "the triage pass is untouched")
        self.assertNotIn_("An episode.",
                          self.led.journal("review", "--headlines",
                                           "--pass", "release").out)
        export = self.led.journal("export", "--class", "watermark").out
        self.assertIn_("\trelease\t2026-07-19\t", export,
                       "the seam carries pass and claim date")


class TestCapture(ZammTest):
    """Near-free capture, stamped provenance, knowledge untouched."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")

    def test_minimal_invocation_creates_the_tree(self):
        self.assertFalse((self.led.root / "zamm-memory/journal").exists())
        r = self.led.journal("add", "CI was red four hours; upstream outage.",
                             env=STAMPS)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("zamm-memory/journal/", r.out)
        self.assertIn_("CI was red four hours; upstream outage.",
                       self.led.journal("list").out)

    def test_keys_and_stamps_land(self):
        r = self.led.journal(
            "add", "--cue", "exceptional-occurrence", "--salience", "6",
            "--axis", "emotion-direction=-3", "--axis", "profoundness=7",
            "--x", "note=hello world", "--scope", "tooling/ci",
            "An outage afternoon.", stdin="Status-page incident.\n",
            env=STAMPS)
        self.assertCode(r, EXIT_OK)
        text = self.led.read(os.path.relpath(r.out.strip(), self.led.root))
        for line in ("durability: weeks", "time: 14:12",
                     "agent: claude-fable-5", "user: ske",
                     "cue: exceptional-occurrence", "salience: 6",
                     "axis-emotion-direction: -3", "axis-profoundness: 7",
                     "x-note: hello world", "## Background"):
            with self.subTest(line=line):
                self.assertIn_(line, text)
        lens = self.led.journal("list").out
        self.assertIn_("+bg]", lens)
        self.assertNotIn_("Status-page", lens, "the lens shows headlines only")

    def test_the_clock_stamp_cannot_smuggle_arguments(self):
        """REVIEW FINDING (2026-09-05): the three provenance stamps were
        joined into one string that every caller expanded unquoted, so a
        ZAMM_TIME carrying spaces injected flags - turning an ordinary
        `journal add` into a valid date-only watermark that hid every
        backdated episode written afterwards."""
        env = dict(STAMPS)
        env["ZAMM_TIME"] = "12:00 --reviewed-through 2026-07-19"
        r = self.led.journal("add", "An ordinary episode.", env=env)
        self.assertNotEqual(r.code, 0)
        self.assertIn_("ZAMM_TIME must be HH:MM", r.output)
        self.assertEqual([], list((self.led.root / "zamm-memory/journal")
                                  .rglob("*.md")),
                         "nothing may be written")
        self.assertCode(self.led.journal("add", "A well-timed episode.",
                                         env=STAMPS), EXIT_OK)

    def test_x_cannot_inject_frontmatter_lines(self):
        """REVIEW FINDING (2026-09-05): the frontmatter was emitted with
        `echo`, which expands backslash escapes on a POSIX /bin/sh (dash,
        which is what CI runs) - so a value holding \\n broke out of its own
        line and forged further keys. `journal add` never refuses, so this
        turned capture into a way to write a coverage claim over the whole
        journal. Values are data: the emitter uses printf."""
        r = self.led.journal(
            "add", "--x", "note=x\\nreviewed-through: 2026-07-19",
            "An innocent-looking episode.", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        text = self.led.read(os.path.relpath(r.out.strip(), self.led.root))
        self.assertIn_("x-note: x\\nreviewed-through: 2026-07-19", text)
        for line in text.splitlines():
            self.assertFalse(line.startswith("reviewed-through:"),
                             "the escape hatch forged a coverage claim")
        self.assertNotIn_("Reviewed through",
                          self.led.journal("list").out,
                          "and the lens must not believe one")

    def test_the_frontmatter_emitter_never_uses_echo(self):
        """The source-level half of the lock above: `echo` is
        implementation-defined for backslashes, so one reintroduced call in
        this function is an injection vector again on a shell this suite
        may not be running under."""
        text = (SKILL_DIR / "scripts" / "internal" /
                "zamm-new-memory.sh").read_text()
        body = text[text.index("emit_frontmatter() {"):]
        body = body[:body.index("\n}\n")]
        offenders = [ln.strip() for ln in body.splitlines()
                     if ln.strip().startswith("echo ")]
        self.assertEqual(offenders, [],
                         "frontmatter must be emitted with printf")

    def test_x_cannot_write_a_policy_key(self):
        """--x is auto-prefixed into the experimental namespace."""
        r = self.led.journal("add", "--x", "cue=forged", "An episode.",
                             env=STAMPS)
        self.assertCode(r, EXIT_OK)
        text = self.led.read(os.path.relpath(r.out.strip(), self.led.root))
        self.assertIn_("x-cue: forged", text)
        self.assertNotIn_("\ncue: forged", text)

    def test_unstamped_identity_is_a_notice_not_a_refusal(self):
        env = {"ZAMM_TIME": "09:00", "ZAMM_AGENT": "", "ZAMM_USER": "",
               "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
               "HOME": str(self.led.root)}
        r = self.led.journal("add", "An anonymous episode.", env=env)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("agent: omitted", r.err)

    def test_a_bad_supersedes_target_writes_nothing(self):
        r = self.led.journal("add", "A sharpened episode.", "--supersedes",
                             "2026-01-01-ghost-aaaaa", env=STAMPS)
        self.assertNotEqual(r.code, 0)
        self.assertIn_("nothing was written", r.output)

    def test_add_never_touches_knowledge(self):
        self.assertCode(self.led.compile(), EXIT_OK)
        before = knowledge_view(self.led.digest())
        files = sorted(str(p) for p in
                       (self.led.root / "zamm-memory/knowledge").rglob("*"))
        self.assertCode(self.led.journal("add", "An episode in its tree.",
                                         env=STAMPS), EXIT_OK)
        self.assertEqual(before, knowledge_view(self.led.digest()))
        self.assertEqual(files, sorted(
            str(p) for p in
            (self.led.root / "zamm-memory/knowledge").rglob("*")))


class TestReadSeams(ZammTest):
    """search, stats, export: one predicate grammar, coverage-honest."""

    def setUp(self):
        super().setUp()
        self.quest = self.led.add_episode(
            "quest", "Fixed the flaky test; unplanned.", cue="side-quest",
            scope="tooling/ci", salience="5", date="2026-07-10",
            axes={"emotion-direction": "+2"}, agent="codex", user="ske")
        self.outage = self.led.add_episode(
            "outage", "CI was red four hours.", cue="exceptional-occurrence",
            salience="7", date="2026-07-11",
            axes={"emotion-direction": "-3", "profoundness": "8"},
            agent="claude", user="ske")
        self.quiet = self.led.add_episode("quiet", "Nothing rated.",
                                          date="2026-06-05")
        self.elev = self.led.add_elevation("monthly", "2026-06", "June.",
                                           date="2026-07-01")

    def test_export_is_versioned_and_named(self):
        r = self.led.journal("export")
        self.assertCode(r, EXIT_OK)
        lines = r.out.splitlines()
        self.assertEqual(lines[0], "# zamm-journal-export v1")
        self.assertEqual(lines[1], EXPORT_COLUMNS,
                         "readers map by name: the column row is the contract")
        rows = [ln.split("\t") for ln in lines[2:]]
        self.assertEqual([len(r) for r in rows], [19] * 4)
        self.assertEqual([r[0] for r in rows],
                         [self.outage, self.quest, self.elev, self.quiet],
                         "newest first")
        self.assertEqual(rows[2][1], "elevation")
        self.assertIn_("emotion-direction=-3 profoundness=8", lines[2])
        r = self.led.journal("export", "--class", "elevation",
                             "--covers", "2026")
        self.assertEqual(len(r.out.splitlines()), 3)

    def test_treeless_export_is_a_well_formed_empty_seam(self):
        led = self.led.__class__(self.led.root / "sub")
        r = led.journal("export")
        self.assertCode(r, EXIT_OK)
        self.assertEqual(r.out.splitlines(),
                         ["# zamm-journal-export v1", EXPORT_COLUMNS])

    def test_search_predicates(self):
        cases = [
            (["--axis", "emotion-direction<-2"], [self.outage]),
            (["--axis", "emotion-direction>0"], [self.quest]),
            (["--axis", "profoundness"], [self.outage]),
            (["--cue", "!side-quest", "--class", "entry"],
             [self.outage, self.quiet]),
            (["--class", "elevation", "--kind", "monthly", "--covers", "2026"],
             [self.elev]),
            (["--scope", "tooling"], [self.quest]),
            (["--agent", "codex"], [self.quest]),
            (["--since", "2026-07-11"], [self.outage]),
            (["--until", "2026-06"], [self.quiet]),
            (["--cue", "side-quest", "--cue", "exceptional-occurrence"],
             [self.outage, self.quest]),
        ]
        for args, want in cases:
            with self.subTest(args=args):
                r = self.led.journal("search", *args)
                self.assertCode(r, EXIT_OK)
                got = [ln.split("  ")[0] for ln in r.out.splitlines()]
                self.assertEqual(got, want)

    def test_an_axis_predicate_needs_a_real_operand(self):
        """REVIEW FINDING (2026-09-04): only the first character was
        checked, and awk coerces the operand with `+ 0` - so
        `--axis mood=garbage` quietly became `mood == 0` and returned rows
        nobody asked for."""
        for bad in ("mood=garbage", "mood>", "mood<=3", "=3", "Mood=1"):
            with self.subTest(predicate=bad):
                r = self.led.journal("search", "--axis", bad)
                self.assertNotEqual(r.code, 0, "a malformed axis predicate "
                                               "must refuse, never match zero")
                self.assertIn_("--axis takes", r.output)
        for good in ("emotion-direction", "emotion-direction=+2",
                     "emotion-direction>-1", "profoundness<9"):
            with self.subTest(predicate=good):
                self.assertCode(self.led.journal("search", "--axis", good),
                                EXIT_OK)

    def test_a_malformed_text_pattern_refuses(self):
        """REVIEW FINDING (2026-09-04): grep exits 2 for a pattern it
        cannot compile and for a file it cannot read alike, and both were
        swallowed as "no match" - so a typo returned an honest-looking
        empty result under exit 0."""
        r = self.led.journal("search", "--text", "[")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("not a valid pattern", r.output)
        self.assertCode(self.led.journal("search", "--text", "flaky"), EXIT_OK)

    def test_search_text_and_files(self):
        r = self.led.journal("search", "--text", "flaky", "--files")
        self.assertCode(r, EXIT_OK)
        self.assertEqual(r.out.strip(),
                         f"zamm-memory/journal/2026/{self.quest}.md")

    def test_review_selects_through_the_shared_grammar(self):
        """review is the fifth consumer of the one predicate grammar, so its
        --scope means what search --scope means: any tag, prefix semantics.

        This lock guards a design choice, not a fixed defect: it passes
        against the pre-refactor scripts too, where review carried a private
        copy of the matcher that happened to agree. What it protects is the
        agreement itself, which only stays true while both read jp_filter.
        """
        r = self.led.journal("review", "--period", "2026-07",
                             "--scope", "tooling", "--headlines")
        self.assertCode(r, EXIT_OK)
        self.assertIn_(self.quest, r.out, "prefix match: tooling finds "
                                          "tooling/ci")
        self.assertNotIn_(self.outage, r.out)
        search = self.led.journal("search", "--scope", "tooling",
                                  "--class", "entry")
        self.assertIn_(self.quest, search.out)
        self.assertNotIn_(self.outage, search.out)

    def test_stats_overview_shows_coverage(self):
        r = self.led.journal("stats")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("3 entries", r.out)
        self.assertIn_("emotion-direction        bipolar   2/3 rated (67%)",
                       r.out)
        self.assertIn_("profoundness             unipolar  1/3 rated (33%)",
                       r.out)
        self.assertIn_("cues: exceptional-occurrence 1, side-quest 1, (none) 1",
                       r.out)
        self.assertIn_("agents: claude 1, codex 1, (unstamped) 1", r.out)
        self.assertNotIn_(self.elev, r.out,
                          "elevations never enter the entry statistics")

    def test_stats_drill_uses_nearest_rank_and_splits_signs(self):
        for i, v in enumerate(("-4", "-1", "+0", "+3")):
            self.led.add_episode(f"m{i}", f"May {i}.", date="2026-05-0%d" % (i + 1),
                                 axes={"emotion-direction": v})
        r = self.led.journal("stats", "--axis", "emotion-direction")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("# axis emotion-direction (bipolar -5..+5)", r.out)
        # four values: nearest rank p25 = 1st, median = 2nd, p75 = 3rd
        self.assertRegex(r.out, r"2026-05\s+4\s+4\s+-4\s+-1\s+\+0\s+2\s+1\s+1")
        self.assertIn_("coverage: 6/7 entries rate this axis (86%)", r.out)

    def test_stats_flags_mixed_signs_as_drift(self):
        self.led.add_episode("drift", "Unsigned by mistake.",
                             date="2026-07-12",
                             axes={"emotion-direction": "3"})
        r = self.led.journal("stats", "--axis", "emotion-direction")
        self.assertIn_("probable spelling drift", r.out)
        self.assertIn_("(unipolar 0..10)", r.out)
        self.assertIn_("(bipolar -5..+5)", r.out)


class TestDigestion(ZammTest):
    """The trichotomy: compile (never stored), triage, elevate."""

    def setUp(self):
        super().setUp()
        self.a = self.led.add_episode("a", "First June thing.",
                                      date="2026-06-03", cue="side-quest",
                                      salience="4")
        self.b = self.led.add_episode("b", "Second June thing.\n\n"
                                      "An elaboration line.\n\n## Background\n"
                                      "Deep.", date="2026-06-20",
                                      salience="8")
        self.c = self.led.add_episode("c", "A July thing.", date="2026-07-02")

    def test_month_view_is_stats_elevations_entries(self):
        elev = self.led.add_elevation("monthly", "2026-06",
                                      "June was two things.\n\n## Background\n"
                                      "Detail.", date="2026-07-01")
        r = self.led.journal("digest", "2026-06")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("# Journal digest 2026-06 (2 entries, 1 elevation;",
                       r.out)
        self.assertIn_("## Stats", r.out)
        self.assertIn_("axis salience (unipolar): 2/2 rated, median 4, p25 4, p75 8", r.out)
        self.assertIn_(f"### monthly 2026-06 [{elev}]", r.out)
        self.assertIn_("June was two things.", r.out)
        self.assertNotIn_("Detail.", r.out, "blocks detail: no Background")
        self.assertIn_("- 20  Second June thing. [", r.out)
        self.assertIn_("  An elaboration line.", r.out)
        self.assertNotIn_("A July thing.", r.out)
        self.assertFalse(list((self.led.root / "zamm-memory").rglob(
            "*digest-2026-06*")), "compiled views are never stored")

        r = self.led.journal("digest", "2026-06", "--elevations", "only",
                             "--stats", "none")
        self.assertNotIn_("## Entries", r.out)
        self.assertNotIn_("## Stats", r.out)
        r = self.led.journal("digest", "2026-06", "--elevations", "none",
                             "--detail", "full", "--cue", "side-quest")
        self.assertNotIn_("## Elevations", r.out)
        self.assertIn_("First June thing.", r.out)
        self.assertNotIn_("Second June thing.", r.out, "predicates select")

    def test_year_view_reads_the_grain_below(self):
        self.led.add_elevation("monthly", "2026-06", "June in one line.",
                               date="2026-07-01")
        r = self.led.journal("digest", "2026")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("the digest of digests", r.out)
        self.assertIn_("entries by month: 2026-06 2, 2026-07 1", r.out)
        self.assertIn_("### 2026-07 (unelevated: entry headlines)", r.out)
        self.assertIn_("- 02  A July thing.", r.out)
        self.assertIn_("### 2026-06 (elevated)", r.out)
        self.assertIn_("June in one line.", r.out)
        self.assertNotIn_("First June thing.", r.out,
                          "an elevated month shows its elevation, not its "
                          "raw entries")
        self.assertLess(r.out.index("### 2026-07"), r.out.index("### 2026-06"))

    def test_elevate_writes_the_record_that_is_the_coverage(self):
        r = self.led.journal("elevate", "monthly", "2026-06",
                             stdin="June condensed.\n", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        files = list((self.led.root / "zamm-memory/journal/2026").glob(
            "2026-07-19-monthly-2026-06-*.md"))
        self.assertEqual(len(files), 1, "slug is <kind>-<period>")
        text = files[0].read_text()
        for line in ("type: digest", "digest: monthly", "covers: 2026-06",
                     "scope: other", "durability: years",
                     "agent: claude-fable-5"):
            self.assertIn_(line, text)
        review = self.led.journal("review", "--headlines")
        self.assertNotIn_("June condensed.", review.out,
                          "elevations are not in the undigested set")
        self.assertIn_("## 2026-06 - elevated: monthly",
                       self.led.journal("list").out)
        r = self.led.journal("elevate", "yearly", "2027", stdin="x\n",
                             env=STAMPS)
        self.assertNotEqual(r.code, 0)
        self.assertIn_("is not over yet", r.output)
        r = self.led.journal("elevate", "monthly", "2026-07", stdin="x\n",
                             env=STAMPS)
        self.assertNotEqual(r.code, 0, "the current month is not over either")
        self.assertIn_("is not over yet", r.output)

    def test_an_open_period_cannot_be_elevated(self):
        """REVIEW FINDING (2026-09-05): elevating a period still running
        froze it - the year view renders an elevation INSTEAD of its
        period's entries, so everything the period gained afterwards was
        invisible there, with nothing falling due to correct it. The live
        answer for a running period is the compiled view."""
        r = self.led.journal("elevate", "monthly", "2026-07",
                             stdin="July so far.\n", env=STAMPS)
        self.assertNotEqual(r.code, 0)
        self.assertIn_("is not over yet", r.output)
        self.assertIn_("journal digest 2026-07", r.output,
                       "the message names the surface that IS live")
        self.assertCode(self.led.journal("elevate", "monthly", "2026-06",
                                         stdin="June.\n", env=STAMPS),
                        EXIT_OK, "a completed period elevates")

    def test_an_elevation_names_what_it_saw(self):
        """REVIEW FINDING (2026-09-05): an entry merged into an already
        elevated period stayed invisible in the year view forever. The
        elevation carries the same claim identity a watermark does, so an
        entry outside it makes the elevation stale: surfaced in the lens,
        listed under the month in the year view, and due again."""
        self.assertCode(self.led.journal("elevate", "monthly", "2026-06",
                                         stdin="June was two things.\n",
                                         env=STAMPS), EXIT_OK)
        elev = [p for p in (self.led.root / "zamm-memory/journal/2026")
                .glob("*monthly-2026-06*")][0]
        self.assertIn_("covered: ", elev.read_text())

        self.assertCode(self.led.journal("add", "A late June episode.",
                                         "--date", "2026-06-15", env=STAMPS),
                        EXIT_OK)

        lens = self.led.journal("list")
        self.assertIn_("Stale elevations - entries they never saw, elevate "
                       "again: monthly 2026-06 (1 uncovered)", lens.out)
        year = self.led.journal("digest", "2026")
        self.assertIn_("Not covered by this elevation:", year.out)
        self.assertIn_("A late June episode.", year.out,
                       "the year view must not hide what the elevation "
                       "never saw")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("monthly due (2026-06)", self.led.digest(),
                       "a stale elevation falls due again")

    def test_the_year_view_reads_coverage_from_the_compiler(self):
        """REVIEW FINDING (2026-09-05): the renderer re-derived coverage by
        parsing the elevation record itself, with stricter rules than the
        compiler - it rejected `covered :` and a CRLF file, both of which
        the compiler accepts. The compiler then reported the elevation
        stale while the year view silently dropped the entry it missed.
        WHICH entries an elevation missed is one answer, and the compiler
        owns it."""
        for name, (sep, eol) in {"spaced key": ("covered : ", "\n"),
                                 "crlf record": ("covered: ", "\r\n")}.items():
            with self.subTest(case=name):
                led = self.led.__class__(self.led.root / name.replace(" ", "-"))
                led.add("a-fact", "A statement.")
                seen = led.add_episode("seen", "The one it summarized.",
                                       date="2026-06-03")
                led.add_episode("missed", "The one it never saw.",
                                date="2026-06-20")
                led.write(
                    "zamm-memory/journal/2026/2026-07-01-monthly-2026-06-2222m.md",
                    eol.join(["---", "type: digest", "scope: other",
                              "importance: useful", "durability: years",
                              "created: 2026-07-01", "digest: monthly",
                              "covers: 2026-06", sep + seen, "schema: 3",
                              "---", "", "June, summarized.", ""]))

                self.assertCode(led.journal("check"), EXIT_OK)
                self.assertIn_("Stale elevations", led.journal("list").out)
                year = led.journal("digest", "2026")
                self.assertIn_("Not covered by this elevation:", year.out)
                self.assertIn_("The one it never saw.", year.out)
                self.assertNotIn_("The one it summarized.", year.out,
                                  "what the elevation named stays covered")
                # ... and the elevation itself must render. Its body is what
                # SUBSTITUTES for the entries it covers in this view, so
                # losing it leaves the period described by nothing at all.
                self.assertIn_("June, summarized.", year.out,
                               "the elevation text is the year view answer "
                               "for a covered month")
                month = led.journal("digest", "2026-06", "--detail", "full")
                self.assertIn_("June, summarized.", month.out)

    def test_a_crlf_record_body_survives_the_write_path(self):
        """The same body reader feeds `backlog mark`, which copies a body
        forward into the superseding record. An empty read there is not a
        missing line of output but a refused write - and the copy lands
        normalized to LF, which is what .gitattributes asks for."""
        self.led.write("zamm-memory/backlog/2026/2026-06-05-crlf-2222p.md",
                       "\r\n".join(["---", "type: memory", "scope: tooling",
                                    "importance: useful",
                                    "durability: months",
                                    "created: 2026-06-05", "schema: 3",
                                    "---", "", "A CRLF idea.", ""]))

        r = self.led.backlog("mark", "2026-06-05-crlf-2222p")

        self.assertCode(r, EXIT_OK)
        landed = [p for p in (self.led.root / "zamm-memory/backlog/2026")
                  .glob("*crlf*") if "2222p" not in p.name]
        self.assertEqual(len(landed), 1)
        text = landed[0].read_text()
        self.assertIn_("A CRLF idea.", text)
        self.assertNotIn_("\r", text, "the copy is normalized to LF")

    def test_a_void_elevation_claim_covers_nothing(self):
        """REVIEW FINDING (2026-09-05): an invalid covered: list was
        treated like an absent one, so it fell back to date coverage - a
        claim that does not hold up went on suppressing the entries it
        named. Exact-and-broken means empty, not blunt."""
        self.led.add_episode("june", "A June episode.", date="2026-06-03")
        self.led.write(
            "zamm-memory/journal/2026/2026-07-01-monthly-2026-06-2222n.md",
            "---\ntype: digest\nscope: other\nimportance: useful\n"
            "durability: years\ncreated: 2026-07-01\ndigest: monthly\n"
            "covers: 2026-06\ncovered: 2026-06-09-ghost-zzzzz\nschema: 3\n"
            "---\n\nJune, summarized.\n")

        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("Stale elevations", self.led.journal("list").out)
        year = self.led.journal("digest", "2026")
        self.assertIn_("Not covered by this elevation:", year.out)
        self.assertIn_("A June episode.", year.out,
                       "a void claim suppresses nothing")

    def test_an_elevation_cannot_predate_its_period(self):
        self.led.write("zamm-memory/journal/2026/2026-06-01-early-2222c.md",
                       "---\ntype: digest\nscope: other\nimportance: useful\n"
                       "durability: years\ncreated: 2026-06-01\n"
                       "digest: yearly\ncovers: 2027\nschema: 3\n---\n"
                       "\nNext year, summarized early.\n")
        r = self.led.journal("check")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("begins after the record date", r.output)

    def test_the_newest_unretired_elevation_wins(self):
        old = self.led.add_elevation("monthly", "2026-06", "First take.",
                                     date="2026-07-01")
        new = self.led.add_elevation("monthly", "2026-06", "Second take.",
                                     date="2026-07-05")
        state = self.led.journal("list") and self.led.journal_state()
        self.assertIn_(f"elev\tmonthly\t2026-06\t{new}", state)
        self.assertNotIn_(f"elev\tmonthly\t2026-06\t{old}", state)
        r = self.led.journal("digest", "2026-06", "--elevations", "only")
        self.assertIn_("Second take.", r.out)
        self.assertNotIn_("First take.", r.out)

    def test_digest_predicates_select_elevations_too(self):
        """REVIEW FINDING (2026-09-04): elevations came straight from the
        state sidecar, so predicates narrowed the entries and left every
        elevation in - a saved style could not be trusted to mean one
        thing. Effectiveness stays the sidecar; WHICH to render is the
        shared grammar."""
        self.led.add_elevation("monthly", "2026-06", "June monthly.",
                               date="2026-07-01")
        self.led.add_elevation("yearly", "2026", "The year.",
                               date="2026-07-02")

        r = self.led.journal("digest", "2026", "--kind", "monthly",
                             "--elevations", "only")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("June monthly.", r.out)
        self.assertNotIn_("The year.", r.out,
                          "--kind monthly must exclude the yearly elevation")

        r = self.led.journal("digest", "2026", "--elevations", "only")
        self.assertIn_("The year.", r.out, "unfiltered, both are rendered")
        self.assertIn_("June monthly.", r.out)

    def test_digest_class_predicate_is_evaluated_per_section(self):
        """REVIEW FINDING (2026-09-04): any --class suppressed the entry
        default, so --class watermark listed watermarks under Entries, and
        a repeated or negated class was read from a single last-value
        variable. Each section now ANDs its own class onto the caller
        predicate through a separate key."""
        self.led.add_watermark("2026-06-01", date="2026-06-01")
        self.led.add_elevation("monthly", "2026-06", "June monthly.",
                               date="2026-07-01")

        r = self.led.journal("digest", "2026-06", "--class", "watermark")
        self.assertCode(r, EXIT_OK)
        self.assertNotIn_("Reviewed through", r.out,
                          "a watermark is not an entry")
        self.assertNotIn_("June monthly.", r.out,
                          "nor an elevation")

        r = self.led.journal("digest", "2026-06", "--class", "elevation")
        self.assertIn_("June monthly.", r.out)
        self.assertNotIn_("First June thing.", r.out)

        r = self.led.journal("digest", "2026-06", "--class", "entry")
        self.assertIn_("First June thing.", r.out)
        self.assertNotIn_("June monthly.", r.out)

    def test_digest_period_bounds_intersect_caller_predicates(self):
        """REVIEW FINDING (2026-09-05): the period bounds were added under
        the caller keys, and repeated values of one key OR together - so
        `digest 2026-06 --since 2026-06-15` widened back to all of June,
        and `--until 2026-07` pulled July into June's digest."""
        self.led.add_episode("early", "Early June.", date="2026-06-03")
        self.led.add_episode("late", "Late June.", date="2026-06-20")
        self.led.add_episode("july", "July.", date="2026-07-05")

        r = self.led.journal("digest", "2026-06", "--since", "2026-06-15")
        self.assertIn_("Late June.", r.out)
        self.assertNotIn_("Early June.", r.out, "--since must narrow")

        r = self.led.journal("digest", "2026-06", "--until", "2026-07")
        self.assertIn_("Late June.", r.out)
        self.assertNotIn_("July.", r.out,
                          "--until must never reach outside the period")

        r = self.led.journal("digest", "2026-06")
        self.assertIn_("Early June.", r.out)
        self.assertIn_("Late June.", r.out)
        self.assertNotIn_("July.", r.out)

    def test_the_summary_splits_an_axis_by_type(self):
        """REVIEW FINDING (2026-09-05): the digest summary grouped by axis
        NAME, taking the type from whichever value arrived first - so one
        name carrying both spellings reported a bipolar median under a
        unipolar label. A name and a type together are the axis."""
        self.led.add_episode("signed", "Signed.", date="2026-06-03",
                             axes={"mood": "-3"})
        self.led.add_episode("unsigned", "Unsigned.", date="2026-06-04",
                             axes={"mood": "7"})

        r = self.led.journal("digest", "2026-06", "--stats", "summary")

        self.assertCode(r, EXIT_OK)
        self.assertIn_("axis mood (bipolar): 1/4 rated, median -3", r.out)
        self.assertIn_("axis mood (unipolar): 1/4 rated, median 7", r.out)

    def test_full_stats_follow_the_filter(self):
        """REVIEW FINDING (2026-09-04): the detailed table came from the
        unfiltered sidecar, so a filtered view printed statistics for the
        very records its own summary excluded."""
        self.led.add_episode("quest", "A side quest.", date="2026-06-04",
                             cue="side-quest", salience="4")
        self.led.add_episode("outage", "An outage.", date="2026-06-05",
                             cue="exceptional-occurrence", salience="9")

        r = self.led.journal("digest", "2026-06", "--cue", "side-quest",
                             "--stats", "full")

        self.assertCode(r, EXIT_OK)
        table = r.out[r.out.index("month x cue x axis"):]
        self.assertIn_("side-quest", table)
        self.assertNotIn_("exceptional-occurrence", table,
                          "the detail must not exceed the selection")

    def test_competing_elevations_are_surfaced_not_silently_picked(self):
        """REVIEW FINDING (2026-09-04): two live elevations for one period
        were resolved by the greater record id, which within a day is the
        RANDOM SUFFIX - the backlog learned the same lesson in its round 2.
        A correction supersedes (which retires the loser outright); two
        that do not are competing claims, and the tiebreak is deterministic
        but arbitrary, so it is shown rather than hidden. The fix is not to
        consult time: - that is display metadata, never causality."""
        self.led.add_elevation("monthly", "2026-06", "Morning take.",
                               date="2026-07-01", sfx="aaaab")
        self.led.add_elevation("monthly", "2026-06", "Evening take.",
                               date="2026-07-01", sfx="zzzzz")

        lens = self.led.journal("list")
        self.assertCode(lens, EXIT_OK)
        self.assertIn_("Competing elevations - supersede one to decide it: "
                       "monthly 2026-06 (2 live", lens.out)
        r = self.led.journal("digest", "2026-06")
        self.assertIn_("note: monthly 2026-06 has 2 live elevations", r.out)

        # and the write path names the id to supersede, before the second
        # competing claim exists
        r = self.led.journal("elevate", "monthly", "2026-06",
                             stdin="A third take.\n", env=STAMPS)
        self.assertCode(r, EXIT_OK, "capture is never refused")
        self.assertIn_("already exists", r.err)
        self.assertIn_("--supersedes", r.err)

    def test_review_reads_oldest_first_and_period_ignores_the_watermark(self):
        self.led.add_watermark("2026-06-10", date="2026-06-11")
        r = self.led.journal("review")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("2 entries undigested (triage reviewed through "
                       "2026-06-10; coverage is by record, not by date)",
                       r.out)
        self.assertLess(r.out.index("Second June thing."),
                        r.out.index("A July thing."), "oldest first")
        self.assertIn_("Deep.", r.out, "the full body is the review surface")
        self.assertNotIn_("First June thing.", r.out)
        self.assertIn_("journal settle", r.out)

        r = self.led.journal("review", "--period", "2026-06", "--headlines")
        self.assertIn_("2 entries in 2026-06", r.out)
        self.assertIn_("First June thing.", r.out,
                       "a calendar span reads triaged entries too")
        self.assertNotIn_("journal settle", r.out,
                          "no coverage claim follows a period read")

        r = self.led.journal("review", "--cue", "side-quest", "--headlines")
        self.assertIn_("a reading aid, never a coverage unit", r.out)

    def test_review_survives_a_low_salience_entry(self):
        """REVIEW FINDING (2026-09-05): the sort key was written %02d, so
        salience 1 produced "09" and the metadata line evaluated
        $((10 - 09)) - an invalid octal literal. The default full-detail
        read aborted mid-record on any entry rated 1 or 2."""
        for sal in ("1", "2", "9"):
            self.led.add_episode(f"rated{sal}", f"Rated {sal}.",
                                 date="2026-07-1%s" % sal, salience=sal)

        r = self.led.journal("review")

        self.assertCode(r, EXIT_OK)
        for sal in ("1", "2", "9"):
            self.assertIn_(f"Rated {sal}.", r.out)
            self.assertIn_(f"salience: {sal}", r.out)

    def test_an_elevation_of_an_empty_period_is_still_exact(self):
        """REVIEW FINDING (2026-09-05): elevate omitted --covered when the
        period held no entries, so the elevation degraded to the date-only
        form; an entry landing in the period afterwards was invisible in
        the year view and never reported stale. Elevating a quiet month is
        a first-class case - the lens has a line for it."""
        led = self.led.__class__(self.led.root / "quiet")
        led.add("a-fact", "A statement.")
        self.assertCode(led.journal("elevate", "monthly", "2026-06",
                                    stdin="A quiet June.\n", env=STAMPS),
                        EXIT_OK)
        elev = [p for p in (led.root / "zamm-memory/journal/2026")
                .glob("*monthly-2026-06*")][0].read_text()
        self.assertIn_("\ncovered:\n", elev)

        self.assertCode(led.journal("add", "A June entry, arriving later.",
                                    "--date", "2026-06-15", env=STAMPS),
                        EXIT_OK)
        self.assertIn_("Stale elevations", led.journal("list").out)
        year = led.journal("digest", "2026")
        self.assertIn_("Not covered by this elevation:", year.out)
        self.assertIn_("A June entry, arriving later.", year.out)

    def test_a_hot_journal_reviews_headlines_only(self):
        for i in range(51):
            self.led.add_episode(f"burst{i}", f"Burst {i}.", date="2026-07-10")
        r = self.led.journal("review")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("exceed JOURNAL_REVIEW_MAX=50", r.err)
        self.assertNotIn_("## 2026-07-10-burst", r.out,
                          "no full bodies above the cap")
        self.assertEqual(len(re.findall(r"^- 2026-", r.out, flags=re.M)), 54)


class TestDegradedReads(ZammTest):
    """REVIEW FINDING (2026-09-04): only the lens propagated a degraded
    tree; search, stats, export, review and digest handed back an
    incomplete dataset under exit 0. The export seam is an application
    contract, and an application cannot see the ## Degraded section."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")
        self.led.add_episode("fine", "A good episode.", date="2026-07-18")

    READS = (("list",), ("search", "--cue", "side-quest"), ("stats",),
             ("export",), ("review",), ("digest", "2026-07"))

    def test_a_healthy_tree_reads_clean(self):
        for args in self.READS:
            with self.subTest(read=args[0]):
                self.assertCode(self.led.journal(*args), EXIT_OK)

    def test_every_read_propagates_a_degraded_tree(self):
        self.led.write("zamm-memory/journal/2026/2026-01-05-broke-22228.md",
                       "---\ntype: memory\nscope: other\n"
                       "created: 2026-01-05\nschema: 9\n---\n\nBroken.\n")
        for args in self.READS:
            with self.subTest(read=args[0]):
                r = self.led.journal(*args)
                self.assertCode(r, EXIT_DEGRADED)
                if args[0] != "list":
                    self.assertIn_("the journal tree is degraded", r.err,
                                   "exit 2 always pairs with a visible notice")

    def test_coverage_writes_refuse_while_degraded(self):
        """REVIEW FINDING (2026-09-04): settle and elevate wrote coverage
        over a tree holding quarantined records. Nobody could review those
        records, and once repaired they fall behind the claim by date -
        unreviewed, with no rerun that recovers them (guarantee 2). Capture
        stays unrefusable; only the coverage verbs require a clean tree."""
        self.led.write("zamm-memory/journal/2026/2026-07-01-broke-22226.md",
                       "---\ntype: memory\nscope: other\n"
                       "created: 2026-07-01\nschema: 9\n---\n\nBroken.\n")

        r = self.led.journal("settle", env=STAMPS)
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_("Refusing to write coverage", r.err)
        r = self.led.journal("elevate", "monthly", "2026-06",
                             stdin="June.\n", env=STAMPS)
        self.assertCode(r, EXIT_DEGRADED)
        self.assertEqual([], list((self.led.root / "zamm-memory/journal/2026")
                                  .glob("*reviewed-through*")))
        self.assertEqual([], list((self.led.root / "zamm-memory/journal/2026")
                                  .glob("*monthly-2026-06*")))

        self.assertCode(self.led.journal("add", "Still capturable.",
                                         env=STAMPS), EXIT_OK,
                        "the capture contract holds even here")

        # repaired: the claim can be made honestly
        self.led.write("zamm-memory/journal/2026/2026-07-01-broke-22226.md",
                       "---\ntype: memory\nscope: other\nimportance: useful\n"
                       "durability: weeks\ncreated: 2026-07-01\nschema: 3\n"
                       "---\n\nRepaired.\n")
        r = self.led.journal("settle", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        self.assertIn_("Repaired.", "".join(
            p.read_text() for p in
            (self.led.root / "zamm-memory/journal/2026").glob("*broke*")))

    def test_a_tree_of_coverage_records_still_publishes(self):
        """REVIEW FINDING (2026-09-05): the refuse-to-publish gate counted
        entries only, but the journal keeps three live classes - so a tree
        holding an elevation, a watermark and one malformed file refused
        outright (exit 3, no output at all) while export happily returned
        the survivors. Two reads disagreeing about one tree."""
        led = self.led.__class__(self.led.root / "coveronly")
        led.add("a-fact", "A statement.")
        led.add_elevation("monthly", "2026-06", "June.", date="2026-07-01")
        led.add_watermark("2026-07-01", date="2026-07-01")
        led.write("zamm-memory/journal/2026/2026-06-03-broke-2222d.md",
                  "---\ntype: memory\nscope: other\ncreated: 2026-06-03\n"
                  "schema: 9\n---\n\nBroken.\n")

        for args in (("list",), ("review",), ("stats",), ("export",)):
            with self.subTest(read=args[0]):
                r = led.journal(*args)
                self.assertCode(r, EXIT_DEGRADED,
                                "degraded, not refused")
                self.assertNotEqual(r.out.strip(), "",
                                    "the survivors must still be shown")
        lens = led.journal("list").out
        self.assertIn_("elevations=1 watermarks=1", lens,
                       "the header counts every live class")

    def test_the_export_seam_stays_parsable_while_degraded(self):
        """The notice goes to stderr: stdout is still a v1 TSV stream."""
        self.led.write("zamm-memory/journal/2026/2026-01-05-broke-22227.md",
                       "---\ntype: memory\nscope: other\n"
                       "created: 2026-01-05\nschema: 9\n---\n\nBroken.\n")
        r = self.led.journal("export")
        self.assertCode(r, EXIT_DEGRADED)
        self.assertEqual(r.out.splitlines()[0], "# zamm-journal-export v1")
        self.assertEqual(r.out.splitlines()[1], EXPORT_COLUMNS)
        self.assertIn_("A good episode.", r.out)


class TestDigestLine(ZammTest):
    """The knowledge digest's entire standing exposure: one line, only when
    digestion is due."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")

    def test_absent_and_quiet_trees_are_byte_identical(self):
        self.assertCode(self.led.compile(), EXIT_OK)
        without = self.led.digest()
        self.assertNotIn_("Journal", without)
        self.led.add_episode("quiet", "A quiet episode.", date="2026-07-18")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertEqual(knowledge_view(without),
                         knowledge_view(self.led.digest()))
        self.assertNotIn_("Journal", self.led.digest(),
                          "nothing due means no line at all")

    def test_triage_due_by_count(self):
        for i in range(25):
            self.led.add_episode(f"ep{i}", f"Episode {i}.", date="2026-07-10")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("Journal: triage due (25 undigested, oldest 2026-07-10)"
                       " - zamm-run.sh journal review", self.led.digest())

    def test_triage_due_by_age(self):
        self.led.add_episode("stale", "An old undigested episode.",
                             date="2026-05-01")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("Journal: triage due (1 undigested, oldest 2026-05-01)",
                       self.led.digest())
        self.led.add_watermark("2026-05-02", date="2026-05-02")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("Journal", self.led.digest(),
                          "a claim past the entry clears the nudge")

    def test_elevation_due_is_opt_in_by_practice(self):
        self.led.add_episode("june", "A June episode.", date="2026-06-05")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("monthly due", self.led.digest(),
                          "no elevation of the kind: never nagged")
        self.led.add_elevation("monthly", "2026-05", "May.", date="2026-06-01")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("Journal: monthly due (2026-06) - zamm-run.sh journal review",
                       self.led.digest())
        self.led.add_elevation("monthly", "2026-06", "June.", date="2026-07-01")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("Journal", self.led.digest(),
                          "the current month is not a completed period")

    def test_a_lapsed_practice_goes_silent(self):
        """A due period more than three grains beyond the newest elevated
        one means the habit stopped; the line must not nag it back."""
        self.led.add_episode("june", "A June episode.", date="2026-06-05")
        self.led.add_elevation("monthly", "2026-02", "February.",
                               date="2026-03-01")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("monthly due", self.led.digest())
        # the grain is the kind's own: a yearly practice measures in years
        self.led.add_episode("last-year", "A 2025 episode.",
                             date="2025-11-05")
        self.led.add_elevation("yearly", "2024", "2024.", date="2025-01-02")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("yearly due (2025)", self.led.digest())

    def test_segments_join_in_fixed_order_on_one_line(self):
        for i in range(25):
            self.led.add_episode(f"ep{i}", f"Episode {i}.", date="2026-06-10")
        self.led.add_elevation("monthly", "2026-05", "May.", date="2026-06-01")
        self.assertCode(self.led.compile(), EXIT_OK)
        lines = [ln for ln in self.led.digest().splitlines()
                 if ln.startswith("Journal:")]
        self.assertEqual(lines, ["Journal: triage due (25 undigested, oldest "
                                 "2026-06-10); monthly due (2026-06) - "
                                 "zamm-run.sh journal review"])

    def test_a_same_day_burst_does_not_stick_the_nudge(self):
        """PRE-FIX (probe, 2026-09-04): 26 same-day entries nagged
        `triage due (26 undigested)` in every digest, and the settle the line
        asked for was then refused as non-advancing - the nudge could not be
        cleared on the day the work happened. The due decision now counts
        only what a settle WOULD clear, so it is always actionable."""
        for i in range(26):
            self.led.add_episode(f"burst{i}", f"Burst {i}.",
                                 date="2026-07-19")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("Journal:", self.led.digest(),
                          "no claim can cover today's entries today")
        r = self.led.journal("settle", env=STAMPS)
        self.assertCode(r, EXIT_OK)
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_("Journal:", self.led.digest())

        # the next day they ARE clearable: the nudge fires, and one settle
        # clears it for good
        tomorrow = "2026-07-20"
        self.assertCode(self.led.compile(today=tomorrow), EXIT_OK)
        self.assertIn_("Journal: triage due (26 undigested, oldest "
                       "2026-07-19)", self.led.digest())
        self.assertCode(self.led.journal("settle", today=tomorrow, env=STAMPS),
                        EXIT_OK)
        self.assertCode(self.led.compile(today=tomorrow), EXIT_OK)
        self.assertNotIn_("Journal:", self.led.digest())

    def test_the_age_threshold_counts_real_days(self):
        """REVIEW FINDING (2026-09-04): the 60-day boundary ran on
        daynum(), which models every month as 31 days and is documented as
        unfit where exactness matters - so a 31 January entry was "older
        than 60 days" on 1 April, when it is exactly 60."""
        self.led.add_episode("boundary", "Sixty days before April.",
                             date="2026-01-31")

        self.assertCode(self.led.compile(today="2026-04-01"), EXIT_OK)
        self.assertNotIn_("Journal:", self.led.digest(),
                          "exactly 60 days is not older than 60 days")
        self.assertCode(self.led.compile(today="2026-04-02"), EXIT_OK)
        self.assertIn_("Journal: triage due (1 undigested, oldest "
                       "2026-01-31)", self.led.digest())

    def test_a_degraded_journal_degrades_the_digest_visibly(self):
        self.led.add_episode("fine", "A statement.")
        self.led.write("zamm-memory/journal/2026/2026-01-05-broke-abcde.md",
                       "---\ntype: memory\nscope: other\ncreated: 2026-01-05\n"
                       "schema: 9\n---\n\nBroken.\n")
        r = self.led.compile()
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_("Journal: DEGRADED - run: zamm-run.sh journal check",
                       self.led.digest())

    def test_episodes_never_reach_the_knowledge_content(self):
        self.assertCode(self.led.compile(), EXIT_OK)
        before = knowledge_view(self.led.digest())
        for i in range(30):
            self.led.add_episode(f"ep{i}", f"A distinctive episode {i}.",
                                 date="2026-07-10")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertEqual(before, knowledge_view(self.led.digest()))
        self.assertNotIn_("A distinctive episode", self.led.digest())

    @needs_permission_bits
    def test_an_unreadable_journal_tree_fails_the_digest(self):
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()
        self.led.add_episode("an-episode", "A statement.")
        locked = self.led.root / "zamm-memory/journal/2026"
        os.chmod(locked, 0o000)
        try:
            r = self.led.compile()
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(r, EXIT_UNREADABLE)
        self.assertEqual(before, self.led.digest(),
                         "previous digest left untouched")


class TestInstrumentation(ZammTest):
    """The sidecar aggregates: month x cue x axis, nearest rank, entries
    only, over created: dates."""

    def test_nearest_rank_quartiles_are_deterministic(self):
        for i, v in enumerate(("1", "2", "3", "4")):
            self.led.add_episode(f"s{i}", f"Sal {i}.", cue="side-quest",
                                 salience=v, date="2026-07-1%d" % i,
                                 axes={"mood": ("-2", "+0", "+1", "+3")[i]})
        self.led.add_elevation("monthly", "2026-07", "Not counted.",
                               extra={"axis-mood": "+5"}, date="2026-07-18")
        self.assertCode(self.led.journal("list"), EXIT_OK)
        state = self.led.journal_state()
        self.assertIn_("month\t2026-07\tside-quest\t4", state)
        self.assertIn_("axis\t2026-07\tside-quest\tsalience\tunipolar\t4\t1\t2\t3",
                       state)
        self.assertIn_("axis\t2026-07\tside-quest\tmood\tbipolar\t4\t-2\t+0\t+1",
                       state)
        self.assertNotIn_("+5", state, "elevations never enter the aggregates")


class TestJournalStatusAndCheck(ZammTest):
    """status watches the lens; check covers the tree exactly when it exists."""

    def setUp(self):
        super().setUp()
        self.led.add("a-fact", "A statement.")

    def test_status_is_silent_without_a_tree(self):
        self.led.compile()
        r = self.led.status()
        self.assertCode(r, EXIT_OK)
        self.assertNotIn_("Journal", r.out)

    def test_status_reports_the_journal(self):
        self.led.add_episode("an-episode", "A statement.", date="2026-07-18")
        self.led.add_watermark("2026-07-01", date="2026-07-01")
        self.assertCode(self.led.compile(), EXIT_OK)
        r = self.led.status()
        self.assertIn_("Journal   1 entries, 1 undigested (reviewed through "
                       "2026-07-01), 0 elevations", r.out)
        (self.led.root / "zamm-memory/.compiled/journal-state.tsv").unlink()
        r = self.led.status()
        self.assertCode(r, EXIT_OK)
        self.assertIn_("incoherent", r.out)
        self.assertIn_("Plans", r.out)

    def test_check_covers_the_journal_exactly_when_present(self):
        self.assertCode(self.led.check_all(), EXIT_OK)
        self.led.add_episode("rated", "An episode.", importance="guardrail")
        r = self.led.check_all()
        self.assertNotEqual(r.code, 0)
        self.assertIn_("guardrail importance is not allowed in the journal",
                       r.output)
