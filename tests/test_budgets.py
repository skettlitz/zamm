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
            f"Unlisted live (below Digests+Headlines budget; ledger stays greppable): "
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
            if ln.strip():
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
            f"Unlisted live (below Digests+Headlines budget; ledger stays greppable): "
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
