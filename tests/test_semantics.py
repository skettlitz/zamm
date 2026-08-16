"""Exit codes and warning semantics.

Cheap to lock and easy to conflate. Exit 1 (a contract violation somewhere)
and exit 3 (nothing survived, refusing to publish) mean different things and
call for different responses; a warning must never masquerade as either.
"""

from harness import (
    EXIT_CONTRACT,
    EXIT_DEGRADED,
    EXIT_OK,
    EXIT_REFUSED_PUBLISH,
    ZammTest,
)


class TestExitCodes(ZammTest):
    def test_check_exits_zero_when_clean(self):
        self.led.add("fine", "A valid statement.")
        self.assertCode(self.led.check(), EXIT_OK)

    def test_check_exits_one_on_a_contract_violation(self):
        self.led.add("fine", "A valid statement.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-33333.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-06\n---\nNo schema line.\n",
        )
        self.assertCode(self.led.check(), EXIT_CONTRACT)

    def test_normal_compile_survives_a_quarantined_record(self):
        """A broken file must not take the whole digest down: the valid
        records still publish, and the compile still succeeds."""
        self.led.add("fine", "A valid statement.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-33333.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-06\n---\nNo schema line.\n",
        )

        r = self.led.compile()

        # A quarantined record among valid ones publishes, but now signals the
        # degradation with exit 2 rather than a healthy-looking exit 0.
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_("A valid statement.", self.led.digest())
        self.assertIn_("quarantined=1", self.header())

    def test_exit_three_is_reserved_for_the_publish_guard(self):
        """Each exit code means exactly one thing, so a caller can tell
        'some records are broken' (2, degraded) from 'nothing survived' (3)."""
        # one broken record among valid ones: degraded, not a refusal
        self.led.add("fine", "A valid statement.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-33333.md",
            "---\ntype: memory\nscope: contracts/api\ncreated: 2026-01-06\n---\nBad.\n",
        )
        self.assertCode(self.led.compile(), EXIT_DEGRADED)

        # now break the only valid one too: nothing survives
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-05-fine-22222.md",
            "---\ntype: memory\nscope: contracts/api\ncreated: 2026-01-05\n---\nBad.\n",
        )
        self.assertCode(self.led.compile(), EXIT_REFUSED_PUBLISH)


class TestWarnings(ZammTest):
    def test_unknown_key_warns_without_failing_or_quarantining(self):
        """A typo'd key is a warning, not an error: guessing wrong must not
        cost the whole record."""
        self.led.add(
            "typo-key",
            "A statement with a misspelled field.",
            extra={"durabilty": "years", "x-team": "payments"},
        )

        c = self.led.check()
        self.assertCode(c, EXIT_OK, "warnings must not fail --check")
        self.assertIn_("durabilty", c.err)
        self.assertIn_("WARNING", c.err)

        self.led.compile()
        self.assertIn_("A statement with a misspelled field.", self.led.digest())
        self.assertIn_("quarantined=0", self.header())

    def test_extension_namespace_is_silent(self):
        """x- prefixed keys are a deliberate extension point, not typos."""
        self.led.add("ext", "A statement.", extra={"x-owner": "platform"})
        c = self.led.check()
        self.assertCode(c, EXIT_OK)
        self.assertNotIn_("x-owner", c.err)

    def test_guardrail_inflation_warns_without_failing(self):
        """Guardrails bypass the digest budget and never decay, so growth is
        invisible; the ceiling is advisory because the call is a judgement."""
        for i in range(17):
            self.led.add(
                f"guard-{i}", f"Guardrail number {i}.",
                importance="guardrail", durability="permanent",
            )

        c = self.led.check()

        self.assertCode(c, EXIT_OK, "a soft ceiling must not block the compile")
        self.assertIn_("17 live guardrails", c.err)

    def test_no_warnings_on_a_clean_ledger(self):
        """Guard against noisy output: a valid ledger must be silent."""
        self.led.add("a", "First.")
        self.led.add("b", "Second.")
        c = self.led.check()
        self.assertNotIn_("WARNING", c.err)
        self.assertNotIn_("ERROR", c.err)


class TestDeterminism(ZammTest):
    def test_pinned_clock_makes_the_digest_reproducible(self):
        """Ranking decays over real dates, so golden comparisons depend on
        ZAMM_TODAY actually being honoured."""
        self.led.add("a", "First statement.")
        self.led.add("b", "Second statement.", durability="days")

        self.led.compile(today="2026-07-19")
        first = self.led.digest()
        self.led.compile(today="2026-07-19")
        self.assertEqual(first, self.led.digest())

        self.led.compile(today="2027-01-01")
        self.assertNotEqual(
            first, self.led.digest(), "a later clock must change decayed ranking"
        )

    def test_scaffold_clock_is_pinnable(self):
        """The managed-block markers embed the date, so rendered surfaces
        are only comparable when the scaffold honours ZAMM_TODAY too."""
        import shutil

        shutil.rmtree(self.led.root / "zamm-memory")
        self.led.scaffold(today="2026-01-01")
        self.assertIn_("date=2026-01-01", self.led.read("AGENTS.md"))
        self.assertIn_("date=2026-01-01", self.led.read(".cursorignore"))
        self.assertIn_("date=2026-01-01", self.led.read(".cursorindexingignore"))
