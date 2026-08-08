"""Writing records and plans — invariants G1.

A record is composed in a private temporary file, validated there, and
claimed under its final name with a no-clobber hard link, so the bytes that
are validated are the bytes that land and a refusal writes nothing at all.
Plan creation publishes a fully rendered tree with one rename.

See references/invariants.md for the guarantees these suites protect.
"""

import os
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

from harness import (
    BROKEN_RECORD, EXIT_CONTRACT, EXIT_OK, EXIT_UNREADABLE, PINNED_TODAY,
    SCRIPTS, ShimTest, ZammTest, needs_permission_bits, suffix,
)

class TestWriterInputAuthority(ZammTest):
    def test_supersedes_newline_is_refused(self):
        inj = "%s\nseed-up: 50" % "2026-01-05-victim-22222"
        r = self.led.new_memory("--scope", "contracts/api", "--supersedes", inj, "forged")
        self.assertNotEqual(r.code, 0, "a newline in --supersedes must be refused")
        # nothing forged on disk
        for p in (self.led.root / "zamm-memory/knowledge").rglob("*.md"):
            self.assertNotIn_("seed-up", p.read_text())

    def test_plan_newline_is_refused(self):
        inj = "someplan\nup: 2026-01-05-x-22222"
        r = self.led.new_memory("--type", "votes", "--plan", inj, "closure")
        self.assertNotEqual(r.code, 0, "a newline in --plan must be refused")

    def test_ordinary_multi_target_supersedes_still_works(self):
        a = self.led.add("head-a", "A.")
        b = self.led.add("head-b", "B.")
        r = self.led.new_memory("--scope", "contracts/api",
                                "--supersedes", f"{a}, {b}", "merged")
        self.assertCode(r, EXIT_OK, "comma+space separated ids must still be accepted")


class TestDateZeroMonth(ZammTest):
    def _count(self):
        return len(list((self.led.root / "zamm-memory/knowledge").rglob("*.md")))

    def test_zero_month_is_refused(self):
        before = self._count()
        r = self.led.new_memory("--scope", "contracts/api", "--date", "2026-00-01", "z")
        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._count(), "no file may be written")

    def test_zero_day_is_refused(self):
        before = self._count()
        r = self.led.new_memory("--scope", "contracts/api", "--date", "2026-01-00", "z")
        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._count())

    def test_all_zero_is_refused(self):
        before = self._count()
        r = self.led.new_memory("--scope", "contracts/api", "--date", "0000-00-00", "z")
        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._count())

    def test_a_real_backdate_still_works(self):
        r = self.led.new_memory("--scope", "contracts/api", "--date", "2025-08-09", "b")
        self.assertCode(r, EXIT_OK, "08/09 must not trip octal parsing")


class TestMemoryCreateHardening(ZammTest):
    def test_option_missing_its_value_is_a_controlled_error(self):
        # PRE-FIX: `$2` under set -u aborted with a raw "unbound variable".
        for opt in ("--scope", "--type", "--durability", "--importance"):
            r = self.led.zamm("memory", "create", "topic", opt)
            self.assertCode(r, EXIT_CONTRACT, opt)
            self.assertIn_("requires a value", r.err)
            self.assertNotIn_("unbound variable", r.err)

    def test_generator_rejects_a_scope_the_checker_would_reject(self):
        # PRE-FIX: the shell split dropped the empty component, so the generator
        # wrote a record the compiler then quarantined.
        r = self.led.new_memory("--scope", "domain,,quality", "bad")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("empty component", r.err)

    def test_draft_is_invisible_to_the_compiler(self):
        """A hand-composed <id>.md.draft is not a ledger record until it is
        published; `memory create` never leaves one behind."""
        self.led.draft("myrule", "A body still being written.")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertIn_("not been initialized", self.led.digest())

    def test_publish_lands_a_filled_draft(self):
        draft = self.led.draft("myrule", "The actual rule body.")
        rid = os.path.basename(draft)[: -len(".md.draft")]
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)
        self.assertFalse(os.path.exists(draft), "the draft is consumed")
        self.led.compile()
        self.assertIn_("The actual rule body.", self.led.digest())

    def test_publish_refuses_an_invalid_draft_and_touches_nothing(self):
        """Validation happens on a private copy, so a refusal leaves the
        draft exactly as it was and lands no record at all."""
        draft = self.led.draft("myrule", "")
        before = open(draft).read()
        rid = os.path.basename(draft)[: -len(".md.draft")]
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertTrue(os.path.exists(draft), "invalid draft must stay a draft")
        self.assertEqual(before, open(draft).read(), "the draft is untouched")
        self.assertFalse(os.path.exists(draft[: -len(".draft")]),
                         "no live .md must be left behind")


class Rev2ScopeNormalized(ZammTest):
    """F7: the generator validated a trimmed scope tag but wrote the raw
    argument, so a leading newline survived into an invalid record."""

    def test_newline_scope_is_normalized_or_rejected(self):
        r = self.led.zamm("memory", "create", "--immediate",
                          "--scope", "\ncontracts/api", "topic",
                          env={"ZAMM_INTERNAL_IMMEDIATE": "1"})
        # either rejected outright, or written normalized so check finds no
        # scope problem (an empty skeleton body is the only allowed complaint)
        if r.code == 0:
            path = r.out.strip()
            with open(path) as fh:
                body = fh.read()
            self.assertIn_("scope: contracts/api\n", body)
            self.assertNotIn_("scope: \n", body)
            chk = self.led.check()
            self.assertNotIn_("scope", chk.err)
        else:
            self.assertCode(r, EXIT_CONTRACT)


class Rev2PublishOnDegradedLedger(ZammTest):
    """F1/F5 sibling: publishing a valid draft into a ledger already degraded
    by UNRELATED records must succeed (the recompile returns exit 2, which is a
    successful publish), not abort."""

    def test_publish_succeeds_despite_unrelated_degradation(self):
        # an unrelated quarantined record makes every compile exit 2
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-bbbbb.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-06\n---\nNo schema.\n",
        )
        # via publish
        draft = self.led.draft("good", "A valid body.")
        rid = os.path.basename(draft)[: -len(".md.draft")]
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)
        self.assertTrue(self.led.exists(
            "zamm-memory/knowledge/2026/" + rid + ".md"))

        # and via one-shot create, which runs the same ERROR-diff gate
        c = self.led.new_memory("--scope", "contracts/api", "alsogood",
                                body="Another valid body.\n", validate=True)
        self.assertCode(c, EXIT_OK)


class Rev3PublishBlame(ZammTest):
    """PRE-FIX: `grep -Fq "$rid" errfile` decided the candidate's fate. That
    rejected a valid draft when an unrelated error mentioned a longer id
    embedding the draft id, and PUBLISHED a bad draft whenever the new error
    named some other record (duplicate votes blame the canonical id) or none
    at all ("other holds 6 live records")."""

    def _draft(self, slug="short", scope="contracts/api"):
        draft = self.led.draft(slug, "A valid body.", scope=scope)
        rid = os.path.basename(draft)[: -len(".md.draft")]
        return draft, rid

    def test_embedded_id_in_an_unrelated_error_does_not_reject(self):
        self.led.add("live", "A live record.")
        draft, rid = self._draft()
        # unrelated invalid record whose FILENAME embeds the draft id: its
        # --check error line contains rid as a substring, in both the baseline
        # and the after run
        self.led.write(
            f"zamm-memory/knowledge/2026/2026-01-07-x-{rid}-e-33333.md",
            BROKEN_RECORD,
        )
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{rid}.md"),
            "valid draft must land despite an unrelated error embedding its id")

    def test_capacity_violation_names_no_record_but_still_rejects(self):
        # five live `other` records pass --check; the candidate makes six.
        # The diagnostic ("other holds 6 live records") names no record id.
        for i in range(5):
            self.led.add(f"otherrec{i}", f"Other {i}.", scope="other")
        draft, rid = self._draft(slug="sixth", scope="other")
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("other holds", p.err)
        self.assertTrue(os.path.exists(draft), "rejected draft is untouched")
        self.assertFalse(
            self.led.exists(f"zamm-memory/knowledge/2026/{rid}.md"),
            "a capacity-violating record must not stay live")

    def test_second_votes_record_blaming_the_canonical_still_rejects(self):
        m = self.led.add("real", "R.")
        # existing canonical votes record (newest id wins)
        self.led.add("votes", type="votes", plan="someplan", up=m,
                     date="2026-01-06", sfx="vvvvv")
        # the candidate sorts OLDER, so the duplicate-votes diagnostic names
        # only the plan and the CANONICAL record - never the candidate
        did = "2026-01-05-morevotes-22222"
        self.led.write(
            f"zamm-memory/knowledge/2026/{did}.md.draft",
            f"---\ntype: votes\nplan: someplan\nup: {m}\ndown:\n"
            "created: 2026-01-05\nschema: 3\n---\n",
        )
        p = self.led.memory_publish(did)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("active votes records for one plan", p.err)
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{did}.md.draft"))
        self.assertFalse(
            self.led.exists(f"zamm-memory/knowledge/2026/{did}.md"))

    def test_preexisting_unrelated_errors_still_do_not_block(self):
        self.led.add("live", "A live record.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-bbbbb.md",
            BROKEN_RECORD,
        )
        draft, rid = self._draft()
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)

    def test_validation_failure_does_not_claim_interruption(self):
        draft = self.led.draft("e", "")   # empty body -> invalid
        rid = os.path.basename(draft)[: -len(".md.draft")]
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("did not validate", p.err)
        self.assertNotIn_("interrupted", p.err)

    @needs_permission_bits
    def test_unvalidatable_ledger_fails_closed(self):
        # Since the round-8 draft-manifest fix, an unreadable year directory
        # stops publish at draft ENUMERATION (exit 4, unreadable-not-empty),
        # before the draft is ever staged — strictly earlier and stricter
        # than the original "could not validate (rc=4)" exit-1 path this test
        # first locked. The invariant under test is unchanged: fail closed,
        # draft untouched.
        self.led.add("alpha", "A.")
        self.led.add("hidden", "H.", date="2025-03-05")
        draft, rid = self._draft()
        locked = self.led.root / "zamm-memory/knowledge/2025"
        os.chmod(locked, 0o000)
        try:
            p = self.led.memory_publish(rid)
        finally:
            os.chmod(locked, 0o755)
        self.assertCode(p, EXIT_UNREADABLE)
        self.assertIn_("unreadable, not empty", p.err)
        self.assertTrue(os.path.exists(draft), "draft is untouched")


class Rev3PublishInterrupt(ZammTest):
    """A faithful Ctrl-C is a process-group SIGINT. Publish validates a
    private copy and only then claims the final name, so an interrupt during
    the (long) validation can only ever leave the draft exactly as it was:
    there is no half-published state to roll back from."""

    def test_sigint_mid_validation_leaves_the_draft_alone(self):
        # enough records that validation leaves a wide window
        self.led.add_many(60)
        draft = self.led.draft("victim", "A valid body.")
        rid = os.path.basename(draft)[: -len(".md.draft")]
        final = draft[: -len(".draft")]
        before = open(draft).read()
        year = os.path.dirname(draft)

        def pending():
            return [f for f in os.listdir(year) if ".md.pending." in f]

        env = dict(os.environ)
        env["ZAMM_TODAY"] = PINNED_TODAY
        proc = subprocess.Popen(
            ["sh", str(SCRIPTS / "zamm-run.sh"), "--project-root",
             str(self.led.root), "memory", "publish", rid],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env=env, cwd=str(self.led.root), preexec_fn=os.setsid,
        )
        try:
            # the private copy precedes validation; once it exists the
            # publish is inside its validation window
            deadline = time.time() + 20
            while not pending() and time.time() < deadline:
                if proc.poll() is not None:
                    break
                time.sleep(0.005)
            self.assertTrue(proc.poll() is None and pending(),
                            "publish finished before it could be interrupted")
            os.killpg(os.getpgid(proc.pid), signal.SIGINT)
            out, err = proc.communicate(timeout=30)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()

        self.assertEqual(proc.returncode, 130, err)
        self.assertTrue(os.path.exists(draft), "the draft must survive intact")
        self.assertEqual(before, open(draft).read(), "the draft is untouched")
        self.assertFalse(os.path.exists(final),
                         "an interrupted publish must not leave a live record")
        self.assertEqual(pending(), [],
                         "the private copy must be cleaned up on the way out")


class PublishCommitsTheValidatedBytes(ShimTest):
    """The original P0: publish validated an overlay COPY of the draft but
    committed the ORIGINAL draft path, so a write landing between the two
    published bytes nothing had checked.

    That whole class of defect is now structural rather than guarded. Both
    writers copy the record to a private, freshly created file, validate THAT,
    and hard-link the same inode into place — so the validated bytes are the
    committed bytes by construction, and there is no freeze, no lock and no
    rollback anywhere in the path. These tests pin the property, not the
    machinery that used to enforce it."""

    # rewrite the draft while validation is running: the shim fires on the
    # compiler's own awk in --check mode (the overlay validation pass)
    SHIM = """#!/bin/sh
for a in "$@"; do
  case "$a" in
    check=1)
      if mkdir "$ZAMM_TEST_BARRIER/once" 2>/dev/null; then
        printf '%s' "$ZAMM_TEST_REPLACEMENT" > "$ZAMM_TEST_DRAFT"
        : > "$ZAMM_TEST_BARRIER/fired"
      fi
      ;;
  esac
done
exec {REAL_AWK} "$@"
"""

    def test_a_write_during_validation_cannot_reach_the_published_record(self):
        import shutil
        import tempfile

        self.led.add("alive", "A living record.")
        draft, rid = self._draft(body="The validated body.\n")
        final = draft[: -len(".draft")]

        real_awk = shutil.which("awk")
        self.assertTrue(real_awk, "no awk on PATH")
        shim = self._write_exec(self._shim_dir() / "awk",
                                self.SHIM.replace("{REAL_AWK}", f'"{real_awk}"'))
        self.assertTrue(shim.exists())

        replacement = (
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-05\nschema: 3\n---\n"
            "SNEAKED IN AFTER VALIDATION.\n"
        )
        with tempfile.TemporaryDirectory() as td:
            barrier = os.path.join(td, "barrier")
            os.mkdir(barrier)
            p = self.led.memory_publish(rid, env=self._shim_env({
                "ZAMM_TEST_BARRIER": barrier,
                "ZAMM_TEST_DRAFT": draft,
                "ZAMM_TEST_REPLACEMENT": replacement,
            }))

            fired = os.path.exists(os.path.join(barrier, "fired"))

        self.assertTrue(fired, "the shim never rewrote the draft; test is vacuous")
        self.assertCode(p, EXIT_OK)
        landed = open(final).read()
        self.assertIn("The validated body.", landed)
        self.assertNotIn("SNEAKED IN AFTER VALIDATION.", landed,
                         "the published record must be the validated bytes")

    def test_a_refused_publish_writes_nothing_and_keeps_the_draft(self):
        draft, rid = self._draft(slug="bad", body="")
        before = open(draft).read()
        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_CONTRACT)
        self.assertEqual(before, open(draft).read())
        self.assertFalse(os.path.exists(draft[: -len(".draft")]))
        year = os.path.dirname(draft)
        self.assertEqual(
            [f for f in os.listdir(year) if ".md.pending." in f], [],
            "the private copy must not survive a refusal")

    def test_an_existing_record_is_never_overwritten_by_publish(self):
        """The final name is claimed with a no-clobber hard link, so a record
        that appeared meanwhile is reported rather than replaced."""
        draft, rid = self._draft(body="Draft body.\n")
        final = draft[: -len(".draft")]
        with open(final, "w") as fh:
            fh.write("---\ntype: memory\nscope: contracts/api\n"
                     "importance: useful\ndurability: years\n"
                     "created: 2026-01-05\nschema: 3\n---\nAlready here.\n")
        p = self.led.memory_publish(rid)
        self.assertNotEqual(p.code, 0)
        self.assertIn("Already here.", open(final).read())


class Rev7PublishDegradedSurfaced(ShimTest):
    """PRE-FIX: publish accepted the recompile's exit 2 silently, so the
    caller never learned the digest it just refreshed is degraded."""

    def test_unrelated_degradation_publishes_with_a_warning(self):
        self.led.add("alive", "A living record.")
        # unrelated pre-existing damage: a live record whose supersedes
        # target does not exist (dangling reference -> digest exit 2)
        self.led.add("dangler", "Points nowhere.", date="2026-01-06",
                     supersedes="2025-01-01-ghost-77777")
        draft, rid = self._draft(slug="clean")

        p = self.led.memory_publish(rid)
        self.assertCode(p, EXIT_OK)
        self.assertIn_("Published:", p.out)
        self.assertIn_("degraded by unrelated pre-existing problems", p.err)
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{rid}.md"))


class Rev7CreateNoClobber(ShimTest):
    """PRE-FIX: the id reservation probed the destination and then renamed
    with a clobbering mv, so a second create that drew the same suffix
    silently REPLACED the first creator's record. The name is now claimed
    with an atomic no-clobber hard link."""

    def _pin_suffix(self, suffix="22222"):
        # memory create draws its suffix through `... | dd bs=1 count=5`;
        # pinning dd makes the collision deterministic
        self._write_exec(
            self._shim_dir() / "dd",
            "#!/bin/sh\n"
            f"printf '{suffix}'\n")

    def test_existing_live_record_is_never_replaced(self):
        self._pin_suffix()
        r1 = self.led.new_memory("--scope", "contracts/api", "clobber",
                                 body="LIVE CONTENT\n", env=self._shim_env())
        self.assertCode(r1, EXIT_OK)
        live = r1.out.strip()
        original = Path(live).read_text()

        r2 = self.led.new_memory("--scope", "contracts/api", "clobber",
                                 body="SECOND CONTENT\n", env=self._shim_env())
        self.assertNotEqual(r2.code, 0,
                            "a create that cannot claim a free id must fail")
        self.assertIn_("could not claim a free record id", r2.err)
        self.assertEqual(original, Path(live).read_text(),
                         "the live record must never be replaced")

    def test_a_failed_claim_leaves_no_temporary_behind(self):
        self._pin_suffix()
        self.assertCode(
            self.led.new_memory("--scope", "contracts/api", "clobber",
                                body="First.\n", env=self._shim_env()), EXIT_OK)
        self.led.new_memory("--scope", "contracts/api", "clobber",
                            body="Second.\n", env=self._shim_env())
        year = self.led.root / "zamm-memory/knowledge/2026"
        self.assertEqual(
            [f.name for f in year.iterdir() if ".md.pending." in f.name], [])


class BulkCreateSkipsValidation(ZammTest):
    """`--immediate` used to be the scripted-creation escape hatch, and it
    landed a frontmatter-only record that failed the contract until someone
    filled it in — so it was gated behind an environment variable.

    With the body supplied at creation, the only thing bulk callers actually
    need is to skip the per-record compile, which costs O(n^2) for a
    migration. `--no-validate` does exactly that and nothing else: the record
    it writes is complete, and `check` is the backstop."""

    def test_no_validate_writes_a_complete_record(self):
        r = self.led.new_memory("--scope", "contracts/api", "bulk",
                                body="A migrated statement.\n")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("A migrated statement.", Path(r.out.strip()).read_text())
        self.assertCode(self.led.check(), EXIT_OK)

    def test_no_validate_defers_the_error_to_check(self):
        """A record the compiler would refuse still lands — that is the whole
        point of the flag — but check reports it, so the migration is not
        silently broken."""
        r = self.led.new_memory("--scope", "contracts/api",
                                "--supersedes", "2020-01-01-ghost-aaaaa",
                                "bulk", body="Points nowhere.\n")
        self.assertCode(r, EXIT_OK)
        self.assertNotEqual(self.led.check().code, 0)

    def test_validation_is_on_when_asked(self):
        r = self.led.new_memory("--scope", "contracts/api",
                                "--supersedes", "2020-01-01-ghost-aaaaa",
                                "bulk", body="Points nowhere.\n", validate=True)
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("did not validate", r.err)
        files = [p for p in (self.led.root / "zamm-memory/knowledge").rglob("*")
                 if p.is_file()]
        self.assertEqual(files, [], "a refused create writes nothing")


class Rev6PublishAtomic(ZammTest):
    """PRE-FIX: publish renamed the draft into the live namespace BEFORE
    validating, and a rejection renamed it back without recompiling — so a
    concurrent compile in that window published a digest and sidecar naming
    a quarantined record whose file was a draft again, and nothing ever
    reported the divergence."""

    def test_rejected_candidate_is_never_visible_live(self):
        """Deterministic probe of the pre-fix window: the verdict pipeline
        calls `comm`, which pre-fix ran while the candidate had already been
        renamed into the live namespace — exactly when a concurrent compile
        could publish a digest naming it. A PATH shim on comm records
        whether the candidate is a live .md at that instant."""
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)
        digest_before = self.led.digest()
        state_before = self.led.read("zamm-memory/.compiled/state.tsv")

        bad = "2026-01-06-badrec-33333"
        self.led.write(
            f"zamm-memory/knowledge/2026/{bad}.md.draft",
            "---\ntype: memory\nscope: internals\nimportance: not-an-enum\n"
            "durability: months\ncreated: 2026-01-06\nschema: 3\n---\nBody.\n")

        live = self.led.root / f"zamm-memory/knowledge/2026/{bad}.md"
        marker = self.led.root / "candidate-was-live"
        shim = self.led.root / "shim"
        shim.mkdir()
        real_comm = shutil.which("comm")
        (shim / "comm").write_text(
            "#!/bin/sh\n"
            f'[ -e "{live}" ] && touch "{marker}"\n'
            f'exec "{real_comm}" "$@"\n')
        os.chmod(shim / "comm", 0o755)

        p = self.led.memory_publish(
            bad, env={"PATH": f"{shim}:{os.environ['PATH']}"})
        self.assertCode(p, EXIT_CONTRACT)
        self.assertIn_("did not validate", p.err)
        self.assertFalse(
            marker.exists(),
            "an unvalidated candidate must never be visible in the live "
            "namespace, not even transiently")
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{bad}.md.draft"),
            "the rejected candidate must still be a draft")
        self.assertFalse(
            self.led.exists(f"zamm-memory/knowledge/2026/{bad}.md"),
            "the rejected candidate must never appear in the live namespace")
        self.assertEqual(digest_before, self.led.digest(),
                         "a rejected publish must not change the digest")
        self.assertEqual(state_before,
                         self.led.read("zamm-memory/.compiled/state.tsv"),
                         "a rejected publish must not change the sidecar")
        self.assertNotIn_(bad, self.led.status().out,
                          "status must not report a record that never landed")

    def test_status_reports_divergence_when_a_record_vanishes(self):
        self.led.add("alive", "A living record.")
        gone = self.led.add("vanish", "A record that will vanish.",
                            date="2026-01-06", sfx="77777")
        self.assertCode(self.led.compile(), EXIT_OK)
        # simulate the reviewer scenario OUTSIDE any publish path: the live
        # file is hand-moved back to a draft, so nothing is newer than the
        # digest and only the count comparison can notice
        src = self.led.root / f"zamm-memory/knowledge/2026/{gone}.md"
        src.rename(str(src) + ".draft")

        st = self.led.status()
        self.assertIn_("on disk but the last compile saw", st.out,
                       "status must report sidecar-vs-disk divergence")


class Rev6DraftVisibility(ZammTest):
    """PRE-FIX: an unpublished .md.draft was invisible to every read surface
    (check, digest, status, list), so a draft nobody published rotted silently
    forever. `memory create` no longer makes drafts, but a draft composed by
    hand still must not become invisible."""

    def _draft(self, slug="pending"):
        return self.led.draft(slug, "A body.", scope="internals")

    def test_drafts_are_listed_and_counted_in_status(self):
        self.led.add("alive", "A living record.")
        draft = self._draft()
        rid = os.path.basename(draft)[: -len(".md.draft")]

        d = self.led.zamm("memory", "drafts")
        self.assertCode(d, EXIT_OK)
        self.assertIn_(rid, d.out)

        st = self.led.status()
        self.assertIn_("drafts: 1 unpublished", st.out)

    def test_discard_removes_a_draft_and_only_a_draft(self):
        self.led.add("alive", "A living record.")
        draft = self._draft()

        r = self.led.zamm("memory", "discard", "pending")
        self.assertCode(r, EXIT_OK)
        self.assertFalse(os.path.exists(draft))

        # a published record is out of discard's reach: no draft matches
        live = self.led.add("keepme", "A published record.",
                            date="2026-01-06", sfx="66666")
        r2 = self.led.zamm("memory", "discard", "keepme")
        self.assertCode(r2, EXIT_CONTRACT)
        self.assertIn_("no draft matches", r2.err)
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{live}.md"))


class TestPlanCreateSafety(ZammTest):
    """`plan create 'R&D | Ops'` used to interpolate the title into a sed
    program: `&` and `|` corrupted the command, sed exited non-zero AFTER the
    directory was made, and a broken plan dir with an empty .plan.md was left
    behind (which then failed `plan check` project-wide)."""

    HAZARD_TITLES = [
        "R&D | Ops",              # the reproduction: sed delimiter + &
        "back\\slash and /slash", # backslashes and forward slashes
        "quote's and \"quotes\"", # single and double quotes
        "Ünïcode Ω plan",         # non-ASCII
        "a & b | c ; d $e `f`",   # a spread of shell metacharacters
        "x" * 120,                # longer than the 60-char slug cap
    ]

    def _plans(self):
        return sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*")
        )

    def test_hazardous_titles_render_a_valid_plan_verbatim(self):
        for title in self.HAZARD_TITLES:
            with self.subTest(title=title):
                r = self.led.plan_create(title)
                self.assertCode(r, EXIT_OK, f"title should be accepted: {title!r}")
                path = r.out.strip()
                self.assertTrue(self.led.exists(path), f"plan file missing for {title!r}")
                body = self.led.read(path)
                # the title is preserved verbatim on the heading line
                self.assertIn_(f"# {title}", body)
                self.assertIn_("Status: Draft", body)
                # and the plan it produced passes validation
                self.assertCode(self.led.plan_check(), EXIT_OK,
                                f"created plan must pass plan check: {title!r}")

    def test_an_unsluggable_title_leaves_no_debris(self):
        """A title that reduces to an empty slug is refused, and active/plans/
        is left exactly as it was — no partial directory, no empty .plan.md,
        no Status-less debris that would fail `plan check` project-wide."""
        before = self._plans()

        r = self.led.plan_create("!!!  @@@  ###")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("empty slug", r.err)
        self.assertEqual(before, self._plans(),
                         "a failed create must leave active/plans/ untouched")
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_duplicate_is_refused_and_cleans_up_its_temp_dir(self):
        """The duplicate-collision path runs AFTER the temp directory is built
        and rendered, so it exercises the cleanup trap: the refusal must leave
        neither the existing plan altered nor a `.tmp-plan-*` directory."""
        first = self.led.plan_create("Same Title")
        self.assertCode(first, EXIT_OK)
        original = self.led.read(first.out.strip())

        second = self.led.plan_create("Same Title")

        self.assertNotEqual(second.code, 0)
        self.assertIn_("already exists", second.err)
        self.assertEqual(original, self.led.read(first.out.strip()),
                         "the existing plan must be untouched")
        self.assertFalse(
            any(".tmp-plan-" in name for name in self._plans()),
            "the temp directory must be cleaned up on refusal",
        )


class TestPlanCreateInjection(ZammTest):
    def _plan_files(self):
        return sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*")
        )

    def test_multiline_title_is_refused(self):
        title = "Innocent\nStatus: Done\nDone-approved-by: x"
        before = self._plan_files()
        r = self.led.plan_create(title)
        self.assertNotEqual(r.code, 0, "a multiline title must be refused")
        self.assertEqual(before, self._plan_files(), "no plan directory may be created")

    def test_help_in_any_position_does_not_create_a_plan(self):
        before = self._plan_files()
        r = self.led.plan_create("My Plan", "--help")
        self.assertCode(r, EXIT_OK)
        self.assertEqual(before, self._plan_files(),
                         "plan create <title> --help must not create a plan")
        self.assertIn_("Usage", r.output)


class TestPlanCreateRenderFailure(ZammTest):
    def test_a_template_that_renders_invalid_leaves_no_debris(self):
        # a template with neither placeholder nor a Status line: the render
        # "succeeds" but validation rejects it, exercising the cleanup path
        bad = self.led.root / "bad.template.md"
        bad.write_text("# not a real template\nno status here\n")
        before = sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*"))

        r = self.led.plan_create("Some Title",
                                 env={"ZAMM_PLAN_TEMPLATE": str(bad)})

        self.assertNotEqual(r.code, 0, "an invalid render must be refused")
        self.assertIn_("Status: Draft", r.err)
        after = sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*"))
        self.assertEqual(before, after, "no plan directory or .tmp-plan- debris")
        self.assertFalse(any(".tmp-plan-" in n for n in after))


class TestPlanCreateClockValidation(ZammTest):
    def _plan_files(self):
        return sorted(
            str(p.relative_to(self.led.root))
            for p in (self.led.root / "zamm-memory/active/plans").rglob("*"))

    def test_invalid_clock_is_refused_without_debris(self):
        before = self._plan_files()
        r = self.led.plan_create("Weird Day", today="2026-00-01")
        self.assertNotEqual(r.code, 0, "an impossible clock must be refused")
        self.assertEqual(before, self._plan_files(), "no plan directory may be created")


class Rev7PlanCreateAtomic(ShimTest):
    """PRE-FIX: plan create re-probed the destination and then ran
    `mv "$tmp" "$dir"`; when the destination appeared between the probe and
    the mv, POSIX mv moved the tree INSIDE it — both creators reported
    success, one plan silently won, and the loser survived as a nested
    .tmp-plan-* directory invisible to every consumer.

    There is no lock any more (references/invariants.md): the race is allowed
    to happen and then detected, because losing it has an exact signature —
    our whole tree ends up nested under its own temp name inside the winner's
    directory. The loser cleans that up and says so."""

    def _paused_creator(self, barrier):
        """Start `plan create` with an mv shim that pauses the FIRST move of
        a rendered .tmp-plan-* tree — i.e. suspended inside the one rename
        that publishes the tree. Returns the Popen, paused."""
        real_mv = shutil.which("mv")
        self._write_exec(
            self._shim_dir() / "mv",
            "#!/bin/sh\n"
            'for a in "$@"; do\n'
            "  case \"$a\" in\n"
            "    *.tmp-plan-*)\n"
            '      if mkdir "$ZAMM_TEST_BARRIER/once" 2>/dev/null; then\n'
            '        : > "$ZAMM_TEST_BARRIER/paused"\n'
            '        while [ ! -e "$ZAMM_TEST_BARRIER/go" ]; do sleep 0.02; done\n'
            "      fi\n"
            "      break\n"
            "      ;;\n"
            "  esac\n"
            "done\n"
            f'exec "{real_mv}" "$@"\n')
        env = dict(os.environ)
        env["PATH"] = f"{self._shim_dir()}:{env['PATH']}"
        env["ZAMM_TEST_BARRIER"] = str(barrier)
        env["ZAMM_TODAY"] = PINNED_TODAY
        p = subprocess.Popen(
            ["sh", str(SCRIPTS / "zamm-run.sh"), "--project-root",
             str(self.led.root), "plan", "create", "Same Plan"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env=env, cwd=str(self.led.root))
        deadline = time.time() + 10
        while not (barrier / "paused").exists():
            self.assertLess(time.time(), deadline,
                            "the creator never reached its publish step")
            if p.poll() is not None:
                self.fail(f"the creator exited early: {p.communicate()}")
            time.sleep(0.02)
        return p, env

    def test_concurrent_create_has_exactly_one_winner_and_no_debris(self):
        barrier = self.led.root / ".barrier"
        barrier.mkdir()
        a, env = self._paused_creator(barrier)
        b = None
        try:
            b = subprocess.Popen(
                ["sh", str(SCRIPTS / "zamm-run.sh"), "--project-root",
                 str(self.led.root), "plan", "create", "Same Plan"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                env=env, cwd=str(self.led.root))
            # B is NOT excluded: it renders and publishes its own tree while
            # A is paused inside its move. Exactly one of them must end up
            # owning the directory.
            b.wait(timeout=30)
            (barrier / "go").touch()
            a_out, a_err = a.communicate(timeout=30)
            b_out, b_err = b.communicate(timeout=30)
        finally:
            for proc in (a, b):
                if proc is not None and proc.poll() is None:
                    proc.kill()

        codes = sorted([a.returncode, b.returncode])
        self.assertEqual(codes[0], 0,
                         f"one creator must win\nA: {a_err}\nB: {b_err}")
        self.assertNotEqual(codes[1], 0,
                            "the second creator must fail, not double-report "
                            f"success\nA: {a_err}\nB: {b_err}")
        loser_err = b_err if b.returncode != 0 else a_err
        self.assertIn_("already exists", loser_err)

        pd = self.led.root / f"zamm-memory/active/plans/{PINNED_TODAY}-same-plan"
        self.assertTrue(pd.is_dir())
        self.assertEqual([p for p in pd.rglob(".tmp-plan-*")], [],
                         "no raced temporary tree may hide inside the winner")
        self.assertEqual(
            sorted(p.name for p in pd.iterdir()),
            [f"{PINNED_TODAY}-same-plan.plan.md", "workdir"])
        self.assertCode(self.led.plan_check(), EXIT_OK)
        plans = self.led.root / "zamm-memory/active/plans"
        self.assertEqual([p.name for p in plans.glob(".tmp-plan-*")], [],
                         "no rendered tree may be abandoned in active/plans")

    def test_concurrent_compile_never_sees_a_half_built_plan(self):
        """PRE-FIX: the final directory was claimed with mkdir and populated
        afterwards, so a compile landing in that window published
        'Unknown: ... (no .plan.md file)'.

        One rename is what makes this safe, not exclusion: the compile is free
        to run right through the window, and it either sees no plan at all or
        the finished one."""
        self.led.add("alive", "A living record.")
        self.assertCode(self.led.compile(), EXIT_OK)
        barrier = self.led.root / ".barrier"
        barrier.mkdir()
        a, _env = self._paused_creator(barrier)
        c = None
        try:
            c = subprocess.Popen(
                ["sh", str(SCRIPTS / "zamm-run.sh"), "--project-root",
                 str(self.led.root), "memory", "digest"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                env={**os.environ, "ZAMM_TODAY": PINNED_TODAY},
                cwd=str(self.led.root))
            c.wait(timeout=60)
            (barrier / "go").touch()
            a_out, a_err = a.communicate(timeout=30)
            c_out, c_err = c.communicate(timeout=60)
        finally:
            for proc in (a, c):
                if proc is not None and proc.poll() is None:
                    proc.kill()

        self.assertEqual(a.returncode, 0, f"plan create failed: {a_err}")
        self.assertIn(c.returncode, (0, 2), f"compile failed: {c_err}")
        self.assertNotIn_("Unknown:", c_out + self.led.digest(),
                          "no digest may describe a half-built plan")
        self.assertNotIn_("no .plan.md file", c_out + self.led.digest())
        st = self.led.status()
        self.assertNotIn_("INVALID ENTRIES", st.out)

    def test_planted_nested_debris_is_reported(self):
        self.led.add_plan("2026-01-05-good", status="Implementing")
        debris = (self.led.root /
                  "zamm-memory/active/plans/2026-01-05-good/.tmp-plan-x")
        debris.mkdir()
        (debris / "2026-01-05-good.plan.md").write_text("Status: Done\n")
        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("stray temporary directory", pc.err)


class Rev6PlanIdUniqueness(ZammTest):
    """PRE-FIX: `plan create` checked only active/, so a slug still resolvable
    from the archive could be minted again, making every by-slug reference
    (votes records, archive moves) ambiguous."""

    def test_create_refuses_a_slug_that_is_archived(self):
        self.led.add("alive", "A living record.")
        # plan create stamps ZAMM_TODAY (pinned 2026-07-19) into the id
        taken = self.led.root / "zamm-memory/archive/plans/2026-07-19-taken-title"
        taken.mkdir(parents=True)
        r = self.led.plan_create("Taken Title")
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("already archived", r.err)
        self.assertFalse(
            self.led.exists("zamm-memory/active/plans/2026-07-19-taken-title"))

    def test_check_reports_a_handmade_collision(self):
        self.led.add("alive", "A living record.")
        self.led.add_plan("2026-01-05-doubled", status="Implementing")
        dup = self.led.root / "zamm-memory/archive/plans/2026-01-05-doubled"
        dup.mkdir(parents=True)
        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("exists in both active and archive", pc.err)


if __name__ == "__main__":
    unittest.main()
