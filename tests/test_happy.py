"""Happy paths: the normal case must work before failure cases mean anything.

A suite made only of failure tests can pass while the tool does nothing
useful, so these come first.
"""

from harness import EXIT_OK, ZammTest


class TestCompileHappy(ZammTest):
    def test_valid_ledger_compiles_clean(self):
        self.led.add("first-rule", "Always run the migration before deploying.")
        self.led.add("second-rule", "Prefer the batch endpoint over per-item calls.")
        self.led.add("third-rule", "Cache invalidation keys are namespaced by tenant.")

        r = self.led.compile()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("files=3 parsed=3 live=3 quarantined=0", self.header())
        self.assertEqual(len(self.led.entries()), 3)

    def test_check_passes_on_valid_ledger(self):
        self.led.add("a-rule")
        r = self.led.check()
        self.assertCode(r, EXIT_OK)
        self.assertIn_("check passed", r.output)

    def test_headline_and_elaboration_render(self):
        self.led.add(
            "two-part",
            "Headline statement that triggers action.\n\n"
            "Elaboration explaining the load-bearing why.",
        )
        self.led.compile()
        digest = self.led.digest()
        self.assertIn_("Headline statement that triggers action.", digest)
        self.assertIn_("Elaboration explaining the load-bearing why.", digest)

    def test_background_earns_bg_marker_and_stays_out_of_digest(self):
        self.led.add(
            "with-bg",
            "Short headline.\n\n## Background\nDeep detail that must not be inlined.",
        )
        self.led.compile()
        digest = self.led.digest()
        self.assertIn_("+bg]", digest)
        self.assertNotIn_("Deep detail that must not be inlined", digest)

    def test_guardrail_is_marked(self):
        self.led.add(
            "guard", "Never delete the audit log.", importance="guardrail",
            durability="permanent",
        )
        self.led.compile()
        self.assertIn_("- ! Never delete the audit log.", self.led.digest())


class TestSupersessionHappy(ZammTest):
    def test_linear_chain_shows_only_the_head(self):
        old = self.led.add("rule", "Original statement.")
        mid = self.led.add("rule", "Revised statement.", date="2026-01-06", supersedes=old)
        head = self.led.add(
            "rule", "Current statement.", date="2026-01-07", supersedes=mid
        )

        self.led.compile()

        self.assertEqual(self.led.entries(), [head])
        self.assertIn_("live=1", self.header())
        self.assertNotIn_("Original statement.", self.led.digest())

    def test_tombstone_retires_its_target(self):
        doomed = self.led.add("doomed", "This rule no longer applies.")
        self.led.add(
            "retire", "No longer relevant after the rewrite.",
            date="2026-01-06", type="tombstone", supersedes=doomed,
        )

        self.led.compile()

        self.assertEqual(self.led.entries(), [])
        self.assertIn_("live=0", self.header())

    def test_merge_of_two_heads_resolves_the_conflict(self):
        root = self.led.add("root", "Original.")
        a = self.led.add("head-a", "Branch A.", date="2026-01-06", supersedes=root)
        b = self.led.add("head-b", "Branch B.", date="2026-01-06", supersedes=root)

        self.led.compile()
        self.assertTrue(
            self.led.has_section("Needs reconciliation"), "fork should be flagged"
        )

        merged = self.led.add(
            "merged", "Unified statement.", date="2026-01-07", supersedes=[a, b]
        )
        self.led.compile()

        self.assertFalse(
            self.led.has_section("Needs reconciliation"),
            "merge should clear the conflict group",
        )
        self.assertEqual(self.led.entries(), [merged])

    def test_votes_record_raises_the_score_of_its_target(self):
        target = self.led.add("voted", "A statement others found useful.")
        self.led.add(
            "closure", type="votes", date="2026-01-06", plan="some-plan", up=target
        )

        self.led.compile()

        self.assertIn_(f"[{target} +1]", self.led.digest())
        self.assertCode(self.led.check(), EXIT_OK)


class TestToolchainHappy(ZammTest):
    def test_generated_record_passes_check_once_filled(self):
        r = self.led.new_memory("--scope", "contracts/api", "generated-rule")
        self.assertCode(r, 0)
        path = r.out.strip()
        self.assertTrue(path.endswith(".md"), r)

        # a skeleton has no body yet: quarantined by design until filled
        self.assertCode(self.led.check(), 1, "empty skeleton should not pass")

        with open(path, "a") as fh:
            fh.write("A statement written by the caller after generation.\n")

        self.assertCode(self.led.check(), EXIT_OK)
        self.led.compile()
        self.assertIn_("A statement written by the caller", self.led.digest())

    def test_fresh_scaffold_produces_a_tree_that_compiles(self):
        import tempfile

        with tempfile.TemporaryDirectory() as fresh:
            from harness import Ledger

            led = Ledger(fresh)
            # start genuinely empty
            import shutil

            shutil.rmtree(led.root / "zamm-memory")

            r = led.scaffold()
            self.assertCode(r, 0)
            self.assertEqual(led.read("zamm-memory/VERSION").strip(), "3")
            self.assertTrue(led.exists("AGENTS.md"))
            self.assertTrue(led.exists(".cursor/rules/zamm.mdc"))

            c = led.compile()
            self.assertCode(c, 0)
            self.assertIn("not been initialized", led.digest())

    def test_archive_moves_a_done_plan(self):
        self.led.add("a-rule")
        self.led.add_plan("2026-01-05-finished-work", status="Done")

        r = self.led.archive()

        self.assertCode(r, 0)
        self.assertFalse(
            self.led.exists("zamm-memory/active/plans/2026-01-05-finished-work")
        )
        self.assertTrue(
            self.led.exists("zamm-memory/archive/plans/2026-01-05-finished-work")
        )

    def test_active_plan_appears_in_the_digest_tail(self):
        self.led.add("a-rule")
        self.led.add_plan("2026-01-05-open-work", status="Implementing")

        self.led.compile()

        plans = self.led.digest_section("Plans")
        self.assertIn_("2026-01-05-open-work", plans)
        self.assertIn_("Implementing", plans)
