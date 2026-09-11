"""The bounded-attention claim.

README leads with it and the protocol documents exact numbers, but until
this file nothing pushed the caps: the largest fixture in the suite was 40
records against a 75/150 budget, so the limits never engaged.

These are ordinary tests, not regression locks — the budgets never broke, so
there is no pre-fix version to falsify them against.
"""

from harness import ZammTest

DIGEST_MAX = 75
HEADLINE_MAX = 150


def _count_entries(text):
    return sum(1 for ln in text.splitlines() if ln.startswith("- "))


# The accounting footers (Budget, OVER BUDGET, Unlisted, Dormant) trail the
# last record section rather than opening one of their own, so a section slice
# picks them up. They are not entries and never were. `Budget:` is always the
# first of them, which makes it the reliable cut point regardless of wording.


class TestDigestBudget(ZammTest):
    def test_layers_cap_at_their_documented_limits(self):
        """250 live records against a 75 + 150 budget: the ranked layers fill
        exactly, and everything past them is counted rather than listed."""
        self.led.add_many(250)

        self.led.compile()

        self.assertIn_("live=250", self.header())
        self.assertEqual(
            _count_entries(self.led.digest_section("Digest")), DIGEST_MAX
        )
        self.assertEqual(
            _count_entries(self.led.digest_section("Headlines")), HEADLINE_MAX
        )
        self.assertIn_(
            f"Unlisted live (below Digests+Headlines entry caps; ledger stays greppable): "
            f"{250 - DIGEST_MAX - HEADLINE_MAX}",
            self.led.digest(),
        )

    def test_every_live_record_is_accounted_for(self):
        """Listed + unlisted + dormant must equal the live count: a record
        that is silently dropped rather than counted is memory loss."""
        self.led.add_many(200)

        self.led.compile()
        digest = self.led.digest()

        listed = _count_entries(self.led.digest_section("Digest")) + _count_entries(
            self.led.digest_section("Headlines")
        )
        unlisted = 0
        for ln in digest.splitlines():
            if ln.startswith("Unlisted live"):
                unlisted = int(ln.rsplit(":", 1)[1])
        self.assertEqual(listed + unlisted, 200)

    def test_a_ledger_under_budget_lists_everything(self):
        """The caps must not truncate a small ledger."""
        self.led.add_many(30)

        self.led.compile()

        self.assertEqual(_count_entries(self.led.digest_section("Digest")), 30)
        self.assertNotIn_("Unlisted live", self.led.digest())

    def test_headlines_carry_no_elaboration(self):
        """The second layer is one line per record by definition — if
        elaboration leaked in, the space budget would be meaningless."""
        for i in range(120):
            self.led.add(
                f"rec-{i}",
                f"Headline number {i}.\n\nElaboration {i} that belongs only to full blocks.",
            )

        self.led.compile()
        headlines = self.led.digest_section("Headlines")

        self.assertGreater(_count_entries(headlines), 0)
        self.assertNotIn_("that belongs only to full blocks", headlines)
        for ln in headlines.splitlines():
            if ln.startswith("Budget: "):
                break
            if not ln.strip() or ln.startswith("### "):
                continue
            self.assertTrue(
                ln.startswith("- "),
                f"headline section must be flat, got: {ln!r}",
            )

    def test_guardrails_are_admitted_before_the_budget(self):
        """Documented as bounded in its ranked layers, NOT in total size:
        guardrails enter before the cap and may exceed it.

        NOT falsifiable: the plan claimed this changed in the hardening work,
        but the guardrail-first selection loop predates it — verified by
        running this test against the pre-hardening compiler, where it also
        passes. What 1.4 changed was the reconciliation interaction, not
        guardrail admission. Ordinary coverage of previously untested
        behaviour.
        """
        over = DIGEST_MAX + 5
        for i in range(over):
            self.led.add(
                f"guard-{i}", f"Guardrail number {i}.",
                importance="guardrail", durability="permanent",
            )

        r = self.led.compile()

        self.assertCode(r, 0)
        blocks = _count_entries(self.led.digest_section("Digest"))
        self.assertEqual(
            blocks, over,
            "every live guardrail must render, even past DIGEST_MAX",
        )
        self.assertGreater(blocks, DIGEST_MAX)

    def test_guardrails_do_not_starve_the_rest_of_the_digest(self):
        """A handful of guardrails plus ordinary records: guardrails go
        first, but the remaining seats still fill to the cap."""
        for i in range(5):
            self.led.add(
                f"guard-{i}", f"Guardrail {i}.",
                importance="guardrail", durability="permanent",
            )
        self.led.add_many(200)

        self.led.compile()
        section = self.led.digest_section("Digest")

        self.assertEqual(_count_entries(section), DIGEST_MAX)
        self.assertEqual(
            sum(1 for ln in section.splitlines() if ln.startswith("- ! ")), 5
        )


class TestDormantAndUnlisted(ZammTest):
    def test_dormant_and_unlisted_are_counted_separately(self):
        """Two different reasons a record is absent from the digest, two
        different lines. Conflating them would hide decay behind budget
        pressure."""
        self.led.add_many(230)
        for i in range(10):
            self.led.add(
                f"stale-{i}", f"Long-decayed note {i}.",
                date="2026-01-05", importance="minor", durability="days",
                scope="meta/process",
            )

        self.led.compile()
        digest = self.led.digest()

        self.assertIn_("live=240", self.header())
        self.assertIn_(
            f"Unlisted live (below Digests+Headlines entry caps; ledger stays greppable): "
            f"{230 - DIGEST_MAX - HEADLINE_MAX}",
            digest,
        )
        self.assertIn_(
            "Dormant (decayed below digest floor; ledger stays greppable): 10 meta",
            digest,
        )
        self.assertNotIn_("Long-decayed note", digest)

    def test_a_dormant_guardrail_never_decays_out(self):
        """`!` is a safety contract: a guardrail leaves the digest only
        through supersession or a tombstone, never through decay."""
        self.led.add(
            "old-guard",
            "Ancient but still binding safety rule.",
            date="2026-01-05", importance="guardrail", durability="days",
        )

        self.led.compile()

        self.assertIn_("Ancient but still binding safety rule.", self.led.digest())
        self.assertNotIn_("Dormant", self.led.digest())


def _fat(i, sentences=6):
    """A record whose headline is short and whose elaboration is not: the
    only shape where expanding or collapsing makes a measurable difference."""
    body = f"Headline number {i}."
    body += "\n\n"
    body += " ".join(f"Elaboration sentence {j} for record {i}." for j in range(sentences))
    return body


def _collapsed(digest):
    """Entry lines the budget collapsed. Matched on entries only: the header
    legend spells out the +el marker, and matching the whole digest would find
    the explanation instead of a single real occurrence of it."""
    return [ln for ln in digest.splitlines() if ln.startswith("- ") and "+el]" in ln]


def _budget_line(digest):
    for ln in digest.splitlines():
        if ln.startswith("Budget: "):
            return ln
    raise AssertionError(f"no Budget line in digest:\n{digest[:400]}")


class TestSpaceBudget(ZammTest):
    """The soft character ceiling (SOFTMAX, default 28000).

    It exists because a digest that overruns the reader's inline-output limit
    is not a long digest, it is an absent one: Claude Code replaces a Bash
    result over 30000 chars with a 2000-char preview, so a session reads the
    header and one entry while believing it read the whole ledger.

    The budget buys EXPANSION, never membership.
    """

    def _entries(self):
        return _count_entries(
            self.led.digest_section("Digest")
        ) + _count_entries(self.led.digest_section("Headlines"))

    def test_a_bound_budget_collapses_blocks_and_keeps_every_entry(self):
        """The load-bearing claim: under pressure the digest says less about
        each record, never less about which records exist."""
        for i in range(40):
            self.led.add(f"fat-{i}", _fat(i))

        self.led.compile()
        roomy = (self._entries(), len(self.led.digest()))
        self.led.compile("--softmax", "9000")
        tight = (self._entries(), len(self.led.digest()))

        self.assertEqual(roomy[0], tight[0], "the budget must not shed entries")
        self.assertLess(tight[1], roomy[1], "a bound budget must actually shrink the surface")
        self.assertLessEqual(tight[1], 9000)
        self.assertGreater(len(_collapsed(self.led.digest())), 0)

    def test_a_collapsed_entry_keeps_its_headline_and_says_what_it_withheld(self):
        """+el is the whole reason collapsing is safe: it distinguishes a
        record with nothing more to say from one whose elaboration was cut."""
        for i in range(40):
            self.led.add(f"fat-{i}", _fat(i))

        self.led.compile("--softmax", "9000")
        digest = self.led.digest()

        collapsed = _collapsed(digest)
        self.assertGreater(len(collapsed), 0)
        for ln in collapsed:
            self.assertRegex(ln, r"^- (?:[a-z0-9-]+: )?Headline number \d+\. \[")
        idx = collapsed[0].split("number ")[1].split(".")[0]
        self.assertNotIn_(f"Elaboration sentence 0 for record {idx}.", digest)

    def test_a_block_with_no_elaboration_is_never_marked(self):
        """+el claims something was withheld. On a one-paragraph record
        nothing was, and a marker that cries wolf costs the reader an open."""
        self.led.add_many(40)

        self.led.compile("--softmax", "5000")

        self.assertEqual(_collapsed(self.led.digest()), [])

    def test_guardrails_are_never_collapsed(self):
        """`!` is a safety contract, and half of one is not one. Guardrails
        expand unconditionally — that overrun is what makes this a SOFT max."""
        self.led.add(
            "guard",
            "Never do the dangerous thing.\n\nBecause the dangerous thing destroys the ledger.",
            importance="guardrail",
        )
        for i in range(60):
            self.led.add(f"fat-{i}", _fat(i))

        self.led.compile("--softmax", "4000")
        digest = self.led.digest()

        self.assertIn_("Because the dangerous thing destroys the ledger.", digest)
        guard = [ln for ln in digest.splitlines() if ln.startswith("- ! ")]
        self.assertEqual(len(guard), 1)
        self.assertNotIn("+el]", guard[0])

    def test_an_impossible_budget_bursts_rather_than_shedding_entries(self):
        """When even the all-collapsed floor does not fit, the digest goes
        over and says so. Hitting the number by dropping records would make
        the digest lie about the ledger; overrunning only makes it large."""
        for i in range(60):
            self.led.add(f"fat-{i}", _fat(i))

        self.led.compile()
        roomy = self._entries()
        self.led.compile("--softmax", "4000")
        digest = self.led.digest()

        self.assertEqual(self._entries(), roomy)
        self.assertGreater(len(digest), 4000)
        self.assertIn_("OVER BUDGET by ", digest)

    def test_the_burst_is_reported_on_stderr_too(self):
        """The digest itself is the thing being truncated, so the warning
        cannot only live inside it."""
        for i in range(60):
            self.led.add(f"fat-{i}", _fat(i))

        r = self.led.compile("--softmax", "4000")

        self.assertIn_("over the 4000-char soft budget", r.err)

    def test_the_budget_line_reports_what_it_spent(self):
        """Pressure has to be legible before it becomes an outage."""
        for i in range(40):
            self.led.add(f"fat-{i}", _fat(i))

        self.led.compile("--softmax", "9000")

        line = _budget_line(self.led.digest())
        self.assertRegex(
            line, r"^Budget: \d+/9000 chars, ~\d+k tokens \(soft\)\. \d+ of \d+ digest entries"
        )

    def test_an_unbound_budget_changes_nothing(self):
        """The budget is a ceiling, not a shaper: a ledger that fits must
        compile exactly as it did before the budget existed."""
        for i in range(40):
            self.led.add(f"fat-{i}", _fat(i))

        self.led.compile("--softmax", "400000")
        digest = self.led.digest()

        self.assertEqual(_collapsed(digest), [])
        self.assertNotIn_("OVER BUDGET", digest)
        for i in range(40):
            self.assertIn_(f"Elaboration sentence 0 for record {i}.", digest)


class TestAreaGrouping(ZammTest):
    """Both record sections group under `### <area>` headings.

    The compiler used to group the Digest layer by FULL scope. In a mature
    ledger the subpaths are nearly unique per record — the ledger this was
    measured on produced 66 groups for 75 entries, 58 of them singletons — so
    the grouping produced headings rather than groups, and paid for them.

    The area is also the domain the SELECTOR balances across (GROUP_PENALTY x
    mintaken), so grouping by it shows the diversity the ranking already
    bought instead of burying it under a heading per record.
    """

    def _headings(self, section):
        return [ln[4:] for ln in self.led.digest_section(section).splitlines()
                if ln.startswith("### ")]

    def test_headings_are_areas_not_full_scopes(self):
        for i, sub in enumerate(("alpha", "beta", "gamma", "delta")):
            self.led.add(f"rec-{i}", f"Statement {i}.", scope=f"internals/{sub}")

        self.led.compile()

        self.assertEqual(self._headings("Digest"), ["internals"])

    def test_the_subpath_moves_onto_the_entry_as_its_label(self):
        """The area is context the heading already gave; what earns a place on
        the line is the subpath, which names the one record."""
        self.led.add("rec", "A statement.", scope="internals/bot-navigation")

        self.led.compile()
        digest = self.led.digest()

        self.assertIn_("### internals", digest)
        self.assertIn_("- bot-navigation: A statement.", digest)
        self.assertNotIn_("internals/bot-navigation:", digest)

    def test_a_bare_area_carries_no_label(self):
        """Nothing to name inside the area, so nothing is printed — an empty
        `: ` would be chrome that says nothing."""
        self.led.add("rec", "A statement with no subpath.", scope="tooling")

        self.led.compile()

        self.assertIn_("- A statement with no subpath.", self.led.digest())

    def test_both_layers_group(self):
        """The Headlines layer is a topical lookup — "open the record when the
        topic matches" — and a flat ranked list is the one shape that cannot
        serve one."""
        for i in range(120):
            area = ("internals", "contracts", "domain")[i % 3]
            self.led.add(f"rec-{i}", f"Statement {i}.", scope=f"{area}/sub-{i}")

        self.led.compile()

        for section in ("Digest", "Headlines"):
            heads = self._headings(section)
            self.assertGreater(len(heads), 0, f"{section} must group")
            self.assertEqual(len(heads), len(set(heads)), f"{section} repeats a heading")
            for h in heads:
                self.assertNotIn("/", h, f"{section} heading {h!r} is not an area")

    def test_grouping_does_not_change_which_records_are_listed(self):
        """Presentation only: rank still decides membership."""
        for i in range(120):
            self.led.add(f"rec-{i}", f"Statement {i}.", scope=f"internals/sub-{i}")

        self.led.compile()
        digest = self.led.digest()

        listed = sum(1 for ln in digest.splitlines() if ln.startswith("- "))
        self.assertEqual(listed, 120)


class TestSoftmaxValidation(ZammTest):
    """`--softmax` refuses a non-integer and anything under 4000. The
    environment variable is the same setting through a different door and
    must refuse the same values: pre-fix it skipped validation entirely, so
    ZAMM_DIGEST_SOFTMAX=abc reached awk as 0, collapsed every entry to its
    headline, and exited 0 — a corrupt digest reporting success."""

    def setUp(self):
        super().setUp()
        self.led.add_many(3)

    def _env(self, value):
        return self.led.compile(env={"ZAMM_DIGEST_SOFTMAX": value})

    def test_a_non_integer_environment_value_is_refused(self):
        r = self._env("abc")
        self.assertNotEqual(0, r.code, "a bad ceiling must not compile")
        self.assertIn("ZAMM_DIGEST_SOFTMAX", r.err)

    def test_an_environment_value_below_the_floor_is_refused(self):
        r = self._env("100")
        self.assertNotEqual(0, r.code)
        self.assertIn("below 4000", r.err)

    def test_a_valid_environment_value_is_accepted(self):
        self.assertEqual(0, self._env("50000").code)

    def test_the_flag_still_refuses_the_same_values(self):
        """The refactor must not have loosened the original door."""
        self.assertNotEqual(0, self.led.compile("--softmax", "abc").code)
        self.assertNotEqual(0, self.led.compile("--softmax", "100").code)
        self.assertEqual(0, self.led.compile("--softmax", "50000").code)


class TestTailIsMeasuredNotEstimated(ZammTest):
    """Everything appended after the awk is rendered and measured before the
    budget runs. The backlog tail used to be charged a flat 256 bytes as "one
    or two fixed lines" — true until `## Marked backlog` arrived, which adds a
    line per marked idea. Nine marked ideas produced a 4142-char digest
    reporting `Budget: 1746/4000` and no OVER BUDGET notice."""

    # Bytes per idea, not ideas: every `backlog add`/`mark` pair recompiles
    # both the lens and the digest (~0.6s), while the length of the sentence
    # is free. Reaching the same tail size through longer sentences instead
    # of more of them cut this class from 18s to 8s and changed nothing it
    # asserts — the claim is about bytes the compiler must measure, and it
    # never cared where they came from.
    SENTENCE = ("Marked idea {} with a deliberately long sentence that spends a great "
                "many bytes in the marked lane, so the rendered tail is unmistakably "
                "larger than the flat estimate the compiler used to charge for it.")

    def _mark(self, n):
        for i in range(n):
            r = self.led.backlog("add", self.SENTENCE.format(i))
            mid = r.out.strip().splitlines()[-1].split("/")[-1].replace(".md", "")
            self.led.backlog("mark", mid)

    def _reported(self):
        line = [ln for ln in self.led.digest().splitlines()
                if ln.startswith("Budget:")][0]
        return int(line.split()[1].split("/")[0])

    def test_the_marked_section_is_inside_the_reported_total(self):
        self.led.add_many(3)
        self._mark(3)
        self.assertEqual(0, self.led.compile("--softmax", "4000").code)
        digest = self.led.digest()
        self.assertIn("## Marked backlog", digest)
        marked_bytes = sum(len(ln) + 1 for ln in digest.splitlines()
                           if ln.startswith("- ") and "(marked " in ln)
        self.assertGreater(marked_bytes, 256,
                           "the fixture must exceed the old flat estimate")
        self.assertGreaterEqual(
            self._reported(), len(digest) - 256,
            "the reported budget must account for the section it appends")

    def test_a_digest_over_the_ceiling_says_so(self):
        self.led.add_many(3)
        self._mark(10)
        self.assertEqual(0, self.led.compile("--softmax", "4000").code)
        digest = self.led.digest()
        self.assertGreater(len(digest), 4000)
        self.assertIn("OVER BUDGET", digest)


class TestTheBudgetIsRememberedNotReverted(ZammTest):
    """`--softmax` is a SETTING, so it has to outlive the run that named it.

    It did not. The digest is rebuilt implicitly by almost every write —
    `memory create`, `memory archive`, `plan block`, `plan unblock` — none of
    which can know what the published digest was built at, so each rebuilt it
    at the default 80000 and silently replaced a `--softmax`-built digest with
    a differently-budgeted one. The digest's own advice ("Raise with
    --softmax") therefore appeared to work and then undid itself at the next
    ledger write, and `memory archive` printed "Digest unchanged (verified)"
    over a file it had just re-budgeted.

    The value now rides in the state sidecar beside the digest it produced,
    and any run that does not name one adopts it.
    """

    CEILING = "6000"

    def _ceiling(self):
        """The denominator of the Budget line: what the digest was built at."""
        line = [ln for ln in self.led.digest().splitlines()
                if ln.startswith("Budget:")][0]
        return line.split()[1].split("/")[1]

    def setUp(self):
        super().setUp()
        self.led.add_many(12)
        self.assertEqual(0, self.led.compile("--softmax", self.CEILING).code)
        self.assertEqual(self.CEILING, self._ceiling())

    def test_a_plain_recompile_keeps_it(self):
        self.assertEqual(0, self.led.compile().code)
        self.assertEqual(self.CEILING, self._ceiling())

    def test_a_record_write_keeps_it(self):
        r = self.led.zamm("memory", "create", "--scope", "internals",
                          "later", stdin="A statement written afterwards.\n")
        self.assertCode(r, 0)
        self.assertEqual(self.CEILING, self._ceiling())

    def test_memory_archive_keeps_it(self):
        """The loudest symptom: archive compares BEFORE (the published digest)
        with AFTER (its own recompile) and calls the pair verified."""
        rec = self.led.add("doomed", "A statement about to be retired.")
        self.led.add("tomb", "Retired; nothing replaces it.",
                     type="tombstone", supersedes=rec)
        self.assertEqual(0, self.led.compile("--softmax", self.CEILING).code)
        r = self.led.memory_archive()
        self.assertCode(r, 0)
        self.assertEqual(self.CEILING, self._ceiling())

    def test_a_plan_block_keeps_it(self):
        self.led.add_plan("2026-01-05-p", status="Implementing")
        r = self.led.plan_block("--kind", "human", "2026-01-05-p",
                                "Waiting on an answer.", stdin="")
        self.assertCode(r, 0)
        self.assertEqual(self.CEILING, self._ceiling())

    def test_a_later_flag_overrides_it(self):
        """Sticky must not mean stuck: the flag is still the authority."""
        self.assertEqual(0, self.led.compile("--softmax", "9000").code)
        self.assertEqual("9000", self._ceiling())
        self.assertEqual(0, self.led.compile().code)
        self.assertEqual("9000", self._ceiling())

    def test_the_default_is_reachable_again(self):
        self.assertEqual(0, self.led.compile("--softmax", "80000").code)
        self.assertEqual("80000", self._ceiling())
        self.assertEqual(0, self.led.compile().code)
        self.assertEqual("80000", self._ceiling())

    def test_a_corrupt_remembered_value_falls_back_to_the_default(self):
        """A sidecar is a derived file anyone can clobber. It may fail to
        answer, but it must never be able to brick the digest — the floor and
        integer rules that guard the flag guard this door too."""
        state = "zamm-memory/.compiled/state.tsv"
        for bad in ("abc", "100", ""):
            with self.subTest(value=bad):
                text = self.led.read(state)
                self.led.write(state, "".join(
                    ln + "\n" for ln in text.splitlines()
                    if not ln.startswith("softmax\t")) + f"softmax\t{bad}\n")
                self.assertEqual(0, self.led.compile().code)
                self.assertEqual("80000", self._ceiling())
                self.assertEqual(0, self.led.compile(
                    "--softmax", self.CEILING).code)
