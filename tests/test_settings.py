"""Remaining tuning constants, generator flags, and known edge paths.

Everything here was enumerated by the 2026-07-20 coverage audit as reachable
in code but never exercised by a test.
"""

import os

from harness import EXIT_CONTRACT, EXIT_OK, ZammTest


def _read(path):
    with open(path) as fh:
        return fh.read()


class TestChainDepthCap(ZammTest):
    """CHAINDEPTH_MAX = 2. Falsifiable: the pre-hardening compiler gave
    uncapped credit and ranks the churning record first."""

    def _fixture(self):
        # six revisions of one statement = five single-target hops
        prev = None
        for i in range(6):
            prev = self.led.add(
                "churned", "Churned statement, revised five times.",
                date="2026-07-19", scope="contracts/api", supersedes=prev,
                durability="permanent",
            )
        stable = self.led.add(
            "stable", "Stable statement, right the first time.",
            date="2026-07-19", scope="conventions/style", durability="permanent",
        )
        # +2 via two DISTINCT plans that each found the record helpful — a
        # single record listing the same target twice is now rejected as a
        # forged vote, and two active votes records for ONE plan is flagged.
        self.led.add(
            "votes-a", type="votes", date="2026-07-19", plan="p-a", up=stable,
        )
        self.led.add(
            "votes-b", type="votes", date="2026-07-19", plan="p-b", up=stable,
        )
        return stable

    def test_churn_does_not_outrank_a_stable_upvoted_record(self):
        """Uncapped, lineage length compounds with inherited ancestor votes,
        so the statements revised most often — the least settled — rank
        highest. Capped at 2 hops: 1.0 + 0.8 vs 1.0 + votes.
        """
        stable = self._fixture()

        self.led.compile(today="2026-07-19")
        entries = self.led.entries()

        self.assertEqual(
            entries[0], stable,
            "the stable record must outrank the churned chain\n"
            + self.led.digest_section("Digest"),
        )


class TestOtherArea(ZammTest):
    """The `other` catch-all and OTHER_MAX = 5 — never exercised before."""

    def test_other_is_accepted_as_a_sole_tag(self):
        self.led.add("parked", "Temporarily parked record.", scope="other")
        self.assertCode(self.led.check(), EXIT_OK)

    def test_other_rejects_a_subpath(self):
        self.led.add("parked", "Parked.", scope="other/somewhere")
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("other must be the sole scope tag", r.err)

    def test_other_rejects_a_companion_tag(self):
        self.led.add("parked", "Parked.", scope="other, conventions")
        r = self.led.check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("other must be the sole scope tag", r.err)

    def test_check_fails_once_other_exceeds_its_limit(self):
        """`other` is temporary parking; past five live records --check
        fails so the backlog cannot quietly become permanent."""
        for i in range(5):
            self.led.add(f"parked-{i}", f"Parked record {i}.", scope="other")
        self.assertCode(self.led.check(), EXIT_OK, "five must still pass")

        self.led.add("parked-5", "One too many.", scope="other")
        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("other holds 6 live records", r.err)

    def test_refiling_by_supersession_drains_the_backlog(self):
        """The documented escape: supersede into a real area."""
        parked = [
            self.led.add(f"parked-{i}", f"Parked {i}.", scope="other")
            for i in range(6)
        ]
        self.assertCode(self.led.check(), EXIT_CONTRACT)

        self.led.add(
            "refiled", "Refiled into a real area.", date="2026-01-06",
            scope="conventions/naming", supersedes=parked[0],
        )
        self.assertCode(self.led.check(), EXIT_OK)


class TestGeneratorFlags(ZammTest):
    def test_type_votes_skeleton_shape(self):
        r = self.led.new_memory("--type", "votes", "--plan", "some-plan", "closure")
        self.assertCode(r, 0)
        content = _read(r.out.strip())

        self.assertIn_("type: votes", content)
        self.assertIn_("plan: some-plan", content)
        self.assertIn_("up:", content)
        self.assertIn_("down:", content)
        self.assertNotIn_("importance:", content)
        self.assertIn_("fill up:/down:", r.output)

    def test_type_tombstone_skeleton_shape(self):
        target = self.led.add("doomed", "To be retired.")
        r = self.led.new_memory(
            "--type", "tombstone", "--supersedes", target, "retire-it"
        )
        self.assertCode(r, 0)
        path = r.out.strip()
        content = _read(path)

        self.assertIn_("type: tombstone", content)
        self.assertIn_(f"supersedes: {target}", content)
        self.assertNotIn_("importance:", content)

        with open(path, "a") as fh:
            fh.write("Retired after the rewrite.\n")
        self.assertCode(self.led.check(), EXIT_OK)

    def test_supersedes_accepts_multiple_targets(self):
        a = self.led.add("head-a", "Branch A.")
        b = self.led.add("head-b", "Branch B.")
        r = self.led.new_memory(
            "--scope", "contracts/api", "--supersedes", f"{a},{b}", "merged"
        )
        self.assertCode(r, 0)
        path = r.out.strip()

        with open(path, "a") as fh:
            fh.write("Unified statement replacing both heads.\n")

        self.assertCode(self.led.check(), EXIT_OK)
        self.led.compile()
        self.assertEqual(len(self.led.entries()), 1)

    def test_importance_and_durability_reach_the_file(self):
        r = self.led.new_memory(
            "--scope", "ops/deploys", "--importance", "guardrail",
            "--durability", "permanent", "rated",
        )
        content = _read(r.out.strip())
        self.assertIn_("importance: guardrail", content)
        self.assertIn_("durability: permanent", content)


class TestLedgerEdgePaths(ZammTest):
    def test_shun_file_tolerates_comments_and_blank_lines(self):
        """shun.md is hand-edited during erasure, so its parser has to cope
        with the formatting a human would naturally use."""
        leaky = self.led.add("leaky", "Contains a secret.")
        self.led.add(
            "clean", "Secret removed.", date="2026-01-06", supersedes=leaky
        )
        self.led.write(
            "zamm-memory/knowledge/shun.md",
            "# erased 2026-01-06 after a credential leak\n"
            "\n"
            f"{leaky}   # the offending record\n"
            "\n",
        )
        self.led.delete(leaky)

        self.assertCode(self.led.check(), EXIT_OK)
        self.led.compile()
        self.assertIn_("Secret removed.", self.led.digest())

    def test_case_fold_collision_is_rejected(self):
        """Two names differing only by case collide when the ledger is
        checked out on a case-insensitive filesystem, so the compiler
        refuses them everywhere.

        The check can only be EXERCISED on a case-sensitive filesystem: on
        macOS the second file simply overwrites the first, so there is
        nothing for the compiler to see.

        A test that skips everywhere guards nothing, so the skip is not
        allowed to be silent forever: CI sets ZAMM_REQUIRE_CASE_SENSITIVE=1
        on the Linux leg, which turns the skip into a failure. Locally on
        APFS, run the suite against a case-sensitive volume:

            hdiutil create -size 300m -fs "Case-sensitive APFS" \\
                -volname ZammCS /tmp/zammcs.dmg
            hdiutil attach /tmp/zammcs.dmg
            TMPDIR=/Volumes/ZammCS python3 -m unittest discover -s . -t .
        """
        probe = self.led.root / "CaseProbe"
        probe.write_text("x")
        case_sensitive = not (self.led.root / "caseprobe").exists()
        probe.unlink()
        if not case_sensitive:
            if os.environ.get("ZAMM_REQUIRE_CASE_SENSITIVE"):
                self.fail(
                    "ZAMM_REQUIRE_CASE_SENSITIVE is set but TMPDIR is on a "
                    "case-insensitive filesystem, so this check cannot run"
                )
            self.skipTest("filesystem is case-insensitive; cannot stage the collision")

        body = (
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\nschema: 3\n---\nA record.\n"
        )
        self.led.write("zamm-memory/knowledge/2026/2026-01-05-samename-22222.md", body)
        self.led.write("zamm-memory/knowledge/2026/2026-01-05-SameName-22222.md", body)

        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("case-fold collision", r.err)

    def test_year_directory_must_match_the_filename_year(self):
        """Misfiled records still compile but break the by-year layout the
        archive story depends on."""
        self.led.write(
            "zamm-memory/knowledge/2025/2026-01-05-misfiled-22222.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\nschema: 3\n---\nMisfiled.\n",
        )

        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("year directory", r.err)

    def test_duplicate_record_id_is_reported_separately(self):
        """Two files claiming one id take the `ndup` path, which is counted
        with quarantine but reported on its own line."""
        body = (
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\nschema: 3\n---\nDuplicate id.\n"
        )
        self.led.write("zamm-memory/knowledge/2026/2026-01-05-twin-22222.md", body)
        self.led.write("zamm-memory/knowledge/2025/2026-01-05-twin-22222.md", body)

        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("duplicate record id", r.err)
