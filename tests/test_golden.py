"""Golden digest: one authored ledger, compared byte-for-byte.

Per-mechanic tests cannot catch interaction effects — diversity penalty
against parsimony cost against guardrail admission against the headline
budget is emergent behaviour. This locks the whole rendered surface.

The fixture is built in code rather than committed as 20+ files: the builder
below IS the fixture spec, and each record says why it exists. Only the
output is committed.

Regenerate after an INTENDED rendering change:
    ZAMM_UPDATE_GOLDEN=1 python3 -m unittest test_golden
and read the resulting diff carefully — an unexplained change here means the
selector moved.
"""

import os
from pathlib import Path

from harness import PINNED_TODAY, ZammTest

GOLDEN = Path(__file__).resolve().parent / "fixtures" / "golden_digest.md"


def build(led):
    """A ledger shaped to exercise the selector, not to look realistic."""

    # --- guardrails: admitted before the digest budget, never decay ---
    led.add(
        "guard-snapshot",
        "Never run a migration against production without a snapshot first.\n\n"
        "Recovery without one has cost a full day twice.",
        date="2026-07-10", scope="ops/migrations",
        importance="guardrail", durability="permanent",
    )
    led.add(
        "guard-idempotency",
        "Always send an idempotency key with payment calls.",
        date="2026-07-10", scope="contracts/payments",
        importance="guardrail", durability="permanent",
    )

    # --- a crowded area: these compete with each other for seats, so the
    #     per-area diversity penalty has something to push against ---
    for i, topic in enumerate(
        ["retries", "timeouts", "pagination", "batching", "errors", "versioning"]
    ):
        led.add(
            f"contracts-{topic}",
            f"Contract rule about {topic} that exists to crowd the contracts area.",
            date="2026-07-12", scope=f"contracts/{topic}",
            importance="useful", durability="years",
        )

    # --- a sparse area: one record here should win a seat early despite a
    #     lower raw score, because its area is uncrowded ---
    led.add(
        "sparse-domain",
        "Domain rule in an otherwise empty area; it should enter early on diversity.",
        date="2026-07-12", scope="domain/audience",
        importance="minor", durability="years",
    )

    # --- multi-tag: enters through its least-crowded door but pays the
    #     per-extra-tag parsimony cost ---
    led.add(
        "multi-tag-record",
        "Two-tag record: enters via the least crowded of its areas and pays for the extra tag.",
        date="2026-07-12", scope="contracts/cli-flags, conventions",
        importance="useful", durability="years",
    )
    led.add(
        "three-tag-record",
        "Three-tag record: more selection doors, larger parsimony cost.",
        date="2026-07-12", scope="quality/checks, tooling, meta",
        importance="useful", durability="years",
    )

    # --- background marker ---
    led.add(
        "with-background",
        "Record carrying a Background section, so it must show the +bg pointer.\n\n"
        "## Background\nDetail that must never be inlined into the digest.",
        date="2026-07-13", scope="internals/digest",
        importance="useful", durability="months",
    )

    # --- votes shift ranking ---
    voted = led.add(
        "voted-record",
        "Record with an upvote, which should lift it above its unvoted peers.",
        date="2026-07-13", scope="conventions/naming",
        importance="useful", durability="months",
    )
    led.add("plan-closure", type="votes", date="2026-07-14", plan="a-plan", up=voted)

    # --- dormant: decayed below the floor, counted but never listed ---
    led.add(
        "dormant-note",
        "Short-lived note from long ago; it must be counted as dormant, not listed.",
        date="2026-01-05", scope="meta/process",
        importance="minor", durability="days",
    )

    # --- a supersede chain: only the head is live ---
    old = led.add(
        "chained-rule", "First version of a rule that gets revised.",
        date="2026-07-11", scope="internals/ranking",
        importance="useful", durability="months",
    )
    led.add(
        "chained-rule", "Current version of the revised rule.",
        date="2026-07-15", scope="internals/ranking", supersedes=old,
        importance="useful", durability="months",
    )

    # --- an unresolved conflict group: both heads keep full blocks, marked ~ ---
    root = led.add(
        "contested-root", "Original statement that got forked.",
        date="2026-07-11", scope="tooling/build",
        importance="useful", durability="months",
    )
    for branch in ("alpha", "beta"):
        led.add(
            f"contested-{branch}",
            f"Branch {branch} of the contested statement.\n\n"
            f"Elaboration explaining what branch {branch} assumes.",
            date="2026-07-16", scope="tooling/build", supersedes=root,
            importance="useful", durability="months",
        )

    # --- a retired record: tombstoned, must not appear ---
    doomed = led.add(
        "retired-rule", "This rule was retired and must not be listed.",
        date="2026-07-11", scope="quality/legacy",
        importance="useful", durability="months",
    )
    led.add(
        "retire-it", "Superseded by the platform rewrite.",
        date="2026-07-17", type="tombstone", supersedes=doomed,
    )


class TestGoldenDigest(ZammTest):
    def test_digest_matches_the_committed_golden(self):
        build(self.led)
        r = self.led.compile(today=PINNED_TODAY)
        self.assertCode(r, 0)
        actual = self.led.digest()

        if os.environ.get("ZAMM_UPDATE_GOLDEN"):
            GOLDEN.parent.mkdir(parents=True, exist_ok=True)
            GOLDEN.write_text(actual)
            self.skipTest(f"golden regenerated at {GOLDEN}")

        self.assertTrue(
            GOLDEN.exists(),
            f"missing golden file; regenerate with ZAMM_UPDATE_GOLDEN=1",
        )
        expected = GOLDEN.read_text()
        if actual != expected:
            import difflib

            diff = "\n".join(
                difflib.unified_diff(
                    expected.splitlines(), actual.splitlines(),
                    fromfile="golden", tofile="actual", lineterm="",
                )
            )
            self.fail(f"digest differs from the committed golden:\n{diff}")

    def test_golden_fixture_is_machine_independent(self):
        """The golden only works if nothing machine-specific leaks in:
        absolute paths, the real clock, or host-dependent ordering."""
        build(self.led)
        self.led.compile(today=PINNED_TODAY)
        digest = self.led.digest()

        self.assertNotIn_(str(self.led.root), digest, "absolute paths must not leak")
        self.assertNotIn_("/tmp", digest)
        self.assertNotIn_("/var", digest)
        self.assertIn_(PINNED_TODAY, digest.splitlines()[0])

    def test_selector_invariants_hold_in_the_golden_ledger(self):
        """Readable assertions alongside the byte comparison: when the golden
        diff is noisy, these say which property actually broke."""
        build(self.led)
        self.led.compile(today=PINNED_TODAY)
        digest = self.led.digest()
        digest_section = self.led.digest_section("Digest")

        # guardrails are always in the actionable layer
        self.assertIn_("Never run a migration against production", digest_section)
        self.assertIn_("Always send an idempotency key", digest_section)

        # background stays out, marker stays in
        self.assertIn_("+bg]", digest)
        self.assertNotIn_("Detail that must never be inlined", digest)

        # retired and superseded records are gone
        self.assertNotIn_("This rule was retired", digest)
        self.assertNotIn_("First version of a rule", digest)
        self.assertIn_("Current version of the revised rule.", digest)

        # dormant is counted, not listed
        self.assertNotIn_("Short-lived note from long ago", digest)
        self.assertIn_("Dormant", digest)

        # both contested heads keep full blocks and the ~ marker
        self.assertIn_("Elaboration explaining what branch alpha assumes.", digest_section)
        self.assertIn_("Elaboration explaining what branch beta assumes.", digest_section)
        self.assertIn_("~ ", digest_section)

        # the vote landed
        self.assertIn_("+1]", digest)
