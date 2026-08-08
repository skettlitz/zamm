"""Regression locks for defects that were reproduced before they were fixed.

Every test here corresponds to a failure demonstrated on 2026-07-19 against
the pre-hardening toolchain. The full repro transcript is archived at
zamm-memory/archive/plans/2026-07-19-v3-hardening-external-review/workdir/
2026-07-19-verification-notes.md

These were written AFTER the fixes shipped, which is a weaker guarantee than
red-first: a test written after the fact can accidentally encode the bug as
expected behaviour. Each docstring therefore states the observed pre-fix
symptom, and each assertion is written against that symptom rather than
against whatever the code happens to do now.
"""

import concurrent.futures
import re

from harness import (
    EXIT_CONTRACT,
    EXIT_DEGRADED,
    EXIT_OK,
    EXIT_REFUSED_PUBLISH,
    ZammTest,
)


class TestCompilerIntegrity(ZammTest):
    def test_concurrent_compiles_leave_a_complete_digest(self):
        """PRE-FIX: 12 parallel compiles shared one memory.md.tmp path.
        5 failed with `mv: ... No such file or directory` and the surviving
        digest was 56 bytes: a '## Plans' section, zero records.
        """
        self.led.add_many(40)

        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            results = list(pool.map(lambda _: self.led.compile(), range(12)))

        failures = [r for r in results if r.code != EXIT_OK]
        self.assertEqual(failures, [], f"{len(failures)}/12 compiles failed")

        digest = self.led.digest()
        self.assertIn_("## Digest", digest)
        self.assertIn_("## Plans", digest)
        self.assertIn_("files=40 parsed=40 live=40 quarantined=0", self.header())
        self.assertEqual(len(self.led.entries()), 40)

        # no shared temp file may survive a run; memory.md and the state.tsv
        # sidecar are the two published artifacts, everything else is a stray.
        compiled = self.led.root / "zamm-memory/.compiled"
        published = {"memory.md", "state.tsv"}
        strays = [p.name for p in compiled.iterdir() if p.name not in published]
        self.assertEqual(strays, [], "temp files left behind")

    def test_invalid_record_cannot_suppress_a_valid_guardrail(self):
        """PRE-FIX: a successor missing `schema:` still had its supersedes
        edge applied. The valid guardrail vanished from the digest, the
        malformed record was published in its place, and the compile exited 0.
        """
        self.led.add(
            "guard",
            "Never run migrations against prod without a snapshot.",
            importance="guardrail",
            durability="permanent",
        )
        # invalid: no schema:, and it claims to supersede the guardrail
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-33333.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\nsupersedes: 2026-01-05-guard-22222\n"
            "created: 2026-01-06\n---\nHalf-written successor.\n",
        )

        r = self.led.compile()

        self.assertCode(r, EXIT_DEGRADED, "a quarantined record publishes (degraded), not fails")
        digest = self.led.digest()
        self.assertIn_(
            "Never run migrations against prod without a snapshot.",
            digest,
            "the guardrail must survive its invalid successor",
        )
        self.assertNotIn_("Half-written successor.", self.led.digest_section("Digest"))
        self.assertIn_("2026-01-06-broken-33333.md", self.led.digest_section("Degraded"))
        self.assertIn_("quarantined=1", self.header())
        self.assertCode(self.led.check(), EXIT_CONTRACT)

    def test_refuses_to_publish_when_nothing_survives(self):
        """PRE-FIX (no guard existed): a ledger whose records all failed
        validation published an empty digest, which reads as 'memory not
        initialized' and invites re-seeding over an intact ledger.
        """
        self.led.add("good", "A valid statement.")
        self.assertCode(self.led.compile(), EXIT_OK)
        before = self.led.digest()

        # break the only record
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-05-good-22222.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\n---\nNow missing schema.\n",
        )

        r = self.led.compile()

        self.assertCode(r, EXIT_REFUSED_PUBLISH)
        self.assertIn_("refusing to publish", r.err)
        self.assertEqual(before, self.led.digest(), "previous digest must survive")

    def test_genuinely_empty_ledger_still_reaches_initialization(self):
        """Guard on the guard: refusing to publish must not block the real
        empty-ledger path, or a new project can never be initialized.
        """
        r = self.led.compile()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("not been initialized", self.led.digest())
        self.assertIn_("live=0 quarantined=0", self.header())


class TestVotesAndErasure(ZammTest):
    def test_tombstoned_votes_record_stops_counting(self):
        """PRE-FIX: vote aggregation ignored the dead set, so a tombstoned
        votes record still contributed. The target kept showing `+1`, and a
        mistaken vote had no correction path.
        """
        target = self.led.add("rule", "A statement that was voted on.")
        vote = self.led.add(
            "closure", type="votes", date="2026-01-06", plan="p", up=target
        )

        self.led.compile()
        self.assertIn_(f"[{target} +1]", self.led.digest())

        self.led.add(
            "kill-vote",
            "Vote was cast on the wrong record.",
            date="2026-01-07",
            type="tombstone",
            supersedes=vote,
        )
        self.led.compile()

        self.assertIn_(f"[{target}]", self.led.digest())
        self.assertNotIn_("+1", self.led.digest())

    def test_documented_erasure_leaves_the_ledger_valid(self):
        """PRE-FIX: the documented procedure (redact the id, delete the
        file) left every successor pointing at a missing target, so --check
        failed permanently with 'supersedes target not found'. (The
        mechanism became an erasure RECORD in place of shun.md; the
        invariant it guards is unchanged.)
        """
        leaky = self.led.add("leaky", "Record containing a secret.")
        self.led.add(
            "clean", "Successor with the secret removed.",
            date="2026-01-06", supersedes=leaky,
        )
        self.assertCode(self.led.check(), EXIT_OK)

        self.led.erase(leaky)
        self.led.delete(leaky)

        self.assertCode(self.led.check(), EXIT_OK, "erasure must not invalidate the ledger")
        self.led.compile()
        self.assertIn_("Successor with the secret removed.", self.led.digest())
        self.assertNotIn_("Record containing a secret.", self.led.digest())

    def test_vote_on_a_non_memory_record_is_rejected(self):
        """PRE-FIX: hardening item 2.6 specified that vote targets must be
        memory records, but only existence was implemented. A votes record
        upvoting a tombstone passed --check clean.
        """
        rec = self.led.add("rule", "A statement.")
        tomb = self.led.add(
            "retire", "No longer applies.", date="2026-01-06",
            type="tombstone", supersedes=rec,
        )
        self.led.add(
            "bad-vote", type="votes", date="2026-01-07", plan="p", up=tomb
        )

        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("only memory records can be voted on", r.err)

    def test_a_bad_vote_target_does_not_void_co_listed_valid_votes(self):
        """The type rule skips the offending target rather than quarantining
        the whole votes record, so valid signal is not lost to an unrelated
        authoring mistake.
        """
        good = self.led.add("good", "A statement worth voting on.")
        doomed = self.led.add("doomed", "Will be retired.")
        tomb = self.led.add(
            "retire", "Retired.", date="2026-01-06",
            type="tombstone", supersedes=doomed,
        )
        self.led.add(
            "mixed", type="votes", date="2026-01-07", plan="p",
            up=f"{good}, {tomb}",
        )

        self.led.compile()

        self.assertIn_(f"[{good} +1]", self.led.digest())


class TestDigestRendering(ZammTest):
    def test_contested_guardrails_keep_their_full_blocks(self):
        """PRE-FIX: the reconciliation index emitted heads through the same
        'printed' set the digest used, consuming their eligibility. Two
        competing guardrails rendered as one-line headlines and the whole
        '## Digest' section came out empty — losing the elaboration exactly
        when the knowledge was in conflict.
        """
        root = self.led.add(
            "root-guard", "Idempotency root.",
            importance="guardrail", durability="permanent",
        )
        for branch in ("a", "b"):
            self.led.add(
                f"head-{branch}",
                f"Idempotency rule, branch {branch}.\n\n"
                f"Elaboration for branch {branch} explaining what breaks.",
                date="2026-01-06", supersedes=root,
                importance="guardrail", durability="permanent",
            )

        self.led.compile()

        digest_section = self.led.digest_section("Digest")
        self.assertIn_("Elaboration for branch a explaining what breaks.", digest_section)
        self.assertIn_("Elaboration for branch b explaining what breaks.", digest_section)
        self.assertIn_("!~", digest_section, "contested heads must be marked")
        self.assertTrue(self.led.has_section("Needs reconciliation"))

    def test_conflict_grouping_follows_the_whole_dag(self):
        """PRE-FIX: only the FIRST supersedes target became the parent, and
        conflict grouping walked that single chain. A successor branching off
        the second lineage of a merge was never seen as competing with the
        merge head — no conflict was reported at all.
        """
        lin_a = self.led.add("lineage-a", "Lineage A root.")
        lin_b = self.led.add("lineage-b", "Lineage B root, unrelated.")
        self.led.add(
            "merge", "Merge head, first parent is lineage A.",
            date="2026-01-06", supersedes=[lin_a, lin_b],
        )
        self.led.add(
            "late", "Late successor branching off lineage B only.",
            date="2026-01-07", supersedes=lin_b,
        )

        self.led.compile()

        self.assertTrue(
            self.led.has_section("Needs reconciliation"),
            "merge head and the late successor both descend from lineage B",
        )
        group = self.led.digest_section("Needs reconciliation")
        self.assertIn_("Merge head", group)
        self.assertIn_("Late successor", group)


class TestScaffoldSafety(ZammTest):
    def _bare_project(self):
        """A project tree with no zamm-memory/ at all."""
        import shutil

        shutil.rmtree(self.led.root / "zamm-memory")

    def test_append_preserves_a_file_without_a_trailing_newline(self):
        """PRE-FIX: ensure_line appended directly. A .gitignore ending
        'dist/' with no final newline became 'dist/zamm-memory/.compiled/' —
        one invalid rule, destroying both the user's rule and ours.
        """
        self._bare_project()
        self.led.write(".gitignore", "dist/")          # no trailing newline
        self.led.write(".gitattributes", "*.bin")      # no trailing newline

        self.assertCode(self.led.scaffold(), 0)

        gitignore = self.led.read(".gitignore").splitlines()
        self.assertIn_("dist/", gitignore)
        self.assertIn_("zamm-memory/.compiled/", gitignore)
        self.assertNotIn_("dist/zamm-memory/.compiled/", self.led.read(".gitignore"))

        attrs = self.led.read(".gitattributes").splitlines()
        self.assertIn_("*.bin", attrs)
        self.assertIn_("zamm-memory/**/*.md text eol=lf", attrs)

    def test_refuses_to_relabel_a_non_v3_project(self):
        """PRE-FIX: the guard keyed on leftover tier files, not VERSION. A
        project with VERSION=2 and no tier files scaffolded successfully and
        had its VERSION rewritten to 3 — a silent protocol upgrade with no
        migration and no approval.
        """
        self.led.version("2")
        self.led.add("legacy", "A v2-era record.")

        r = self.led.scaffold()

        self.assertNotEqual(r.code, 0, "must refuse")
        self.assertIn_("VERSION", r.output)
        self.assertEqual(
            self.led.read("zamm-memory/VERSION").strip(), "2",
            "VERSION must be left untouched",
        )

    def test_refuses_a_versionless_tree_that_already_holds_content(self):
        """Unknown state must not be stamped as v3."""
        # The default fixture ships a VERSION; this case is specifically a
        # versionless tree that nonetheless holds content, so remove it first.
        (self.led.root / "zamm-memory/VERSION").unlink()
        self.led.add("orphan", "A record with no VERSION file.")

        r = self.led.scaffold()

        self.assertNotEqual(r.code, 0)
        self.assertFalse(self.led.exists("zamm-memory/VERSION"))

    def test_malformed_managed_block_refuses_without_truncating(self):
        """PRE-FIX: the block remover suppressed everything from the begin
        marker to EOF when no end marker was found, silently deleting user
        content written after the block.
        """
        self._bare_project()
        self.led.write(
            "AGENTS.md",
            "# Team instructions\n\n"
            "<!-- SKILL-BLOCK:zamm:BEGIN version=git:old date=2026-01-01 -->\n"
            "stale zamm content\n\n"
            "## CRITICAL PROJECT RULES\n"
            "Never deploy on Fridays.\n",
        )
        before = self.led.read("AGENTS.md")

        r = self.led.scaffold()

        self.assertNotEqual(r.code, 0, "must refuse a malformed block")
        self.assertEqual(before, self.led.read("AGENTS.md"), "file must be untouched")
        self.assertIn_("Never deploy on Fridays.", self.led.read("AGENTS.md"))

    def test_cursorignore_keeps_user_rules_and_gains_zamm_rules(self):
        """PRE-FIX: whole-file ownership forced a choice between 'no ZAMM
        rules' (normal run left the file alone) and 'user rules deleted'
        (--overwrite-templates replaced the file).
        """
        self._bare_project()
        self.led.write(".cursorignore", "node_modules/**\n")

        self.assertCode(self.led.scaffold(), 0)

        content = self.led.read(".cursorignore")
        self.assertIn_("node_modules/**", content)
        self.assertIn_("zamm-memory/archive/**", content)

    def test_scaffold_is_idempotent(self):
        """Re-running must not duplicate managed blocks or ignore rules."""
        self._bare_project()
        self.assertCode(self.led.scaffold(), 0)
        self.assertCode(self.led.scaffold(), 0)

        agents = self.led.read("AGENTS.md")
        self.assertEqual(agents.count("SKILL-BLOCK:zamm:BEGIN"), 1)
        self.assertEqual(agents.count("SKILL-BLOCK:zamm:END"), 1)
        self.assertEqual(
            self.led.read(".gitignore").count("zamm-memory/.compiled/"), 1
        )

    def test_drift_stamp_is_content_derived_without_git(self):
        """PRE-FIX: a non-git skill install stamped the literal 'local', so
        two entirely different local versions produced the same stamp and the
        documented drift check could never fire.
        """
        self._bare_project()
        self.assertCode(self.led.scaffold(), 0)

        stamp = re.search(r"version=(\S+)", self.led.read("AGENTS.md")).group(1)
        self.assertNotEqual(stamp, "local")
        self.assertTrue(
            stamp.startswith("git:") or stamp.startswith("sha:"), stamp
        )
