"""Record-contract validation: one representative case per family.

Deliberately NOT exhaustive (see tests/README.md). The goal is that each
validation family has a live test, not that every rule has its own case.
Assertions check the exit code and that the message names the offending
file — never the exact wording, which is free to improve.
"""

from harness import EXIT_CONTRACT, EXIT_OK, ZammTest

FM = "---\ntype: memory\nscope: contracts/api\nimportance: useful\ndurability: years\n"


class TestRecordContract(ZammTest):
    def assertRejected(self, filename, content, because):
        self.led.write(f"zamm-memory/knowledge/2026/{filename}", content)
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT, f"should reject: {because}")
        self.assertIn_(
            filename, r.err, f"the error must name the offending file ({because})"
        )

    # ---- dates ----

    def test_impossible_calendar_date(self):
        self.assertRejected(
            "2026-99-99-bad-date-22222.md",
            FM + "created: 2026-99-99\nschema: 3\n---\nImpossible date.\n",
            "month 99 / day 99",
        )

    def test_day_that_does_not_exist_in_that_month(self):
        self.assertRejected(
            "2026-02-30-feb30-22222.md",
            FM + "created: 2026-02-30\nschema: 3\n---\nFebruary 30th.\n",
            "Feb 30 never exists",
        )

    def test_feb_29_in_a_non_leap_year(self):
        self.assertRejected(
            "2026-02-29-noleap-22222.md",
            FM + "created: 2026-02-29\nschema: 3\n---\n2026 is not a leap year.\n",
            "leap-year arithmetic",
        )

    def test_real_leap_day_is_accepted(self):
        """The negative cases above must not be over-broad."""
        self.led.write(
            "zamm-memory/knowledge/2024/2024-02-29-leap-22222.md",
            FM + "created: 2024-02-29\nschema: 3\n---\nA real leap day.\n",
        )
        self.assertCode(self.led.check(), EXIT_OK)

    # ---- filename ----

    def test_suffix_outside_the_uniqueness_alphabet(self):
        self.assertRejected(
            "2026-01-05-bad-suffix-00001.md",
            FM + "created: 2026-01-05\nschema: 3\n---\nSuffix uses 0 and 1.\n",
            "0 and 1 are excluded from the 30-symbol alphabet",
        )

    def test_slug_longer_than_the_limit(self):
        slug = "this-slug-is-far-too-long-and-keeps-going-well-past-forty"
        self.assertRejected(
            f"2026-01-05-{slug}-22222.md",
            FM + "created: 2026-01-05\nschema: 3\n---\nOverlong slug.\n",
            "slug exceeds 40 chars",
        )

    # ---- scope ----

    def test_scope_that_yields_no_tags(self):
        self.assertRejected(
            "2026-01-05-empty-scope-22222.md",
            "---\ntype: memory\nscope: ,\nimportance: useful\ndurability: years\n"
            "created: 2026-01-05\nschema: 3\n---\nBare comma scope.\n",
            "a bare comma parses to zero tags",
        )

    def test_unknown_scope_area(self):
        self.assertRejected(
            "2026-01-05-bad-area-22222.md",
            "---\ntype: memory\nscope: teamstuff\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\nschema: 3\n---\nInvented area.\n",
            "areas come from a fixed set",
        )

    # ---- frontmatter ----

    def test_duplicate_known_key(self):
        self.assertRejected(
            "2026-01-05-dupe-key-22222.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "importance: guardrail\ndurability: years\ncreated: 2026-01-05\n"
            "schema: 3\n---\nTwo importance lines.\n",
            "last-wins would silently pick one ranking",
        )

    def test_missing_schema(self):
        self.assertRejected(
            "2026-01-05-no-schema-22222.md",
            FM + "created: 2026-01-05\n---\nNo schema line.\n",
            "schema is required",
        )

    # ---- graph ----

    def test_self_supersession(self):
        self.assertRejected(
            "2026-01-05-self-loop-22222.md",
            FM + "supersedes: 2026-01-05-self-loop-22222\ncreated: 2026-01-05\n"
            "schema: 3\n---\nI supersede myself.\n",
            "a record cannot replace itself",
        )

    def test_supersede_cycle(self):
        a = "2026-01-05-node-a-22222"
        b = "2026-01-06-node-b-33333"
        self.led.write(
            f"zamm-memory/knowledge/2026/{a}.md",
            FM + f"supersedes: {b}\ncreated: 2026-01-05\nschema: 3\n---\nNode A.\n",
        )
        self.assertRejected(
            f"{b}.md",
            FM + f"supersedes: {a}\ncreated: 2026-01-06\nschema: 3\n---\nNode B.\n",
            "A -> B -> A makes liveness undefined",
        )

    def test_memory_cannot_supersede_a_votes_record(self):
        vote = self.led.add(
            "closure", type="votes", plan="p", up="2026-01-05-x-22222"
        )
        self.assertRejected(
            "2026-01-07-wrong-type-44444.md",
            FM + f"supersedes: {vote}\ncreated: 2026-01-07\nschema: 3\n---\n"
            "Memory superseding a vote.\n",
            "only tombstones may retire anything",
        )

    # ---- type-specific bodies ----

    def test_tombstone_without_a_reason(self):
        target = self.led.add("target", "Something to retire.")
        self.assertRejected(
            "2026-01-06-silent-tomb-33333.md",
            f"---\ntype: tombstone\nsupersedes: {target}\ncreated: 2026-01-06\n"
            "schema: 3\n---\n",
            "a retirement with no reason is unauditable",
        )

    def test_votes_record_with_a_body(self):
        target = self.led.add("target", "Something to vote on.")
        self.assertRejected(
            "2026-01-06-chatty-vote-33333.md",
            f"---\ntype: votes\nplan: p\nup: {target}\ndown:\ncreated: 2026-01-06\n"
            "schema: 3\n---\nThis prose does not belong here.\n",
            "the up/down lists are the whole payload",
        )

    def test_votes_record_with_neither_up_nor_down(self):
        self.assertRejected(
            "2026-01-06-empty-vote-33333.md",
            "---\ntype: votes\nplan: p\nup:\ndown:\ncreated: 2026-01-06\n"
            "schema: 3\n---\n",
            "an empty skeleton must be filled before committing",
        )


class TestGeneratorAgreement(ZammTest):
    """zamm-new-memory.sh must not be able to emit a record the compiler
    would quarantine — the two must implement one contract."""

    def test_generator_rejects_an_impossible_backdate(self):
        r = self.led.new_memory("--scope", "contracts/api", "--date", "2026-02-30", "topic")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("calendar date", r.err)

    def test_generator_rejects_a_malformed_slug(self):
        for slug in ("trailing-hyphen-", "doubled--hyphen", "Upper-Case"):
            with self.subTest(slug=slug):
                r = self.led.new_memory("--scope", "contracts/api", slug)
                self.assertNotEqual(r.code, 0, f"{slug!r} should be rejected")

    def test_generator_requires_scope_for_memory_records(self):
        r = self.led.new_memory("no-scope-given")
        self.assertNotEqual(r.code, 0)
        self.assertIn_("scope", r.err)

    def test_generator_rejects_bad_enums(self):
        r = self.led.new_memory("--scope", "contracts/api", "--importance", "urgent", "topic")
        self.assertNotEqual(r.code, 0)
