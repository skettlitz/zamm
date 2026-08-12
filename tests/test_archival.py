"""Archival is a rerunnable sequence, not a transaction — invariant G4.

The compiler reads the live and archived trees both, so a half-archived
ledger is a valid ledger and a rerun finishes the job. Moves never clobber
archived history, and what is still undone on failure is only what no rerun
would repair: a batch our own inert or plan rules should not have admitted.

See references/invariants.md for the guarantees these suites protect.
"""

import os
import shutil
import signal

from harness import (
    EXIT_CONTRACT, EXIT_DEGRADED, EXIT_OK, SCRIPTS, ShimTest, ZammTest,
    needs_permission_bits,
)

class TestArchiveTransactional(ZammTest):
    """The pre-fix archiver rolled back only when the post-move digest diff
    fired. Under `set -e` a failed move or a failed recompile aborted before
    that branch, and the EXIT trap then DELETED the move log — so a failure
    anywhere else left the ledger half-archived with no recovery map. It also
    used a bare `mv` fallback with no destination preflight, so it could
    overwrite an existing archived record."""

    def _retired_chain(self, slug, date="2026-01-05"):
        rec = self.led.add(slug, f"Retired knowledge: {slug}.", date=date)
        self.led.add(f"retire-{slug}", "No longer applies.",
                     date="2026-01-06", type="tombstone", supersedes=rec)
        return rec

    def _knowledge_snapshot(self):
        """Every record file under knowledge/ and archive/knowledge/, by
        relative path and content — the transactional invariant."""
        snap = {}
        for sub in ("zamm-memory/knowledge", "zamm-memory/archive/knowledge"):
            base = self.led.root / sub
            for p in base.rglob("*.md"):
                snap[str(p.relative_to(self.led.root))] = p.read_bytes()
        return snap

    def _shim_dir(self):
        d = self.led.root / ".shims"
        d.mkdir(exist_ok=True)
        return d

    def _write_exec(self, path, body):
        path.write_text(body)
        path.chmod(0o755)
        return path

    # -- (a) destination collision is refused in preflight, zero moves --
    def test_destination_collision_is_refused_before_any_move(self):
        self.led.add("live-rule", "Still true.")
        rec = self._retired_chain("obsolete")
        self.led.compile()
        before = self._knowledge_snapshot()
        # plant a file where the record would be archived
        dest = self.led.root / "zamm-memory/archive/knowledge/2026" / f"{rec}.md"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text("pre-existing archived record; must not be overwritten\n")
        planted = dest.read_bytes()

        r = self.led.memory_archive()

        self.assertNotEqual(r.code, 0)
        self.assertIn_("already exists", r.err)
        self.assertEqual(planted, dest.read_bytes(),
                         "the pre-existing archived record must be untouched")
        self.assertTrue(self.led.exists(f"zamm-memory/knowledge/2026/{rec}.md"),
                        "no source may move when a collision is detected")
        # only the planted file is new; nothing else changed
        after = self._knowledge_snapshot()
        self.assertEqual(set(after) - set(before),
                         {str(dest.relative_to(self.led.root))})

    # -- (b) a move failure mid-loop rolls everything back --
    def test_a_move_failure_mid_loop_rolls_back(self):
        self.led.add("live-rule", "Still true.")
        self._retired_chain("obsolete")   # two inert records => two moves
        self.led.compile()
        before = self._knowledge_snapshot()

        shim = self._shim_dir()
        # a `mv` that fails on the 2nd move INTO archive/knowledge, so the
        # first record commits and the second aborts the run — a genuine
        # partial state to roll back. Moves not into archive/knowledge (the
        # compiler publishing its own digest, and the rollback moving records
        # back) pass through, so the counter is not polluted and rollback
        # itself still works.
        self._write_exec(shim / "mv", (
            "#!/bin/sh\n"
            'case " $* " in\n'
            '  *archive/knowledge*)\n'
            '    d=$(dirname "$0")\n'
            '    n=$(cat "$d/.count" 2>/dev/null || echo 0)\n'
            "    n=$((n + 1))\n"
            '    printf "%s\\n" "$n" > "$d/.count"\n'
            '    if [ "$n" = "2" ]; then echo "shim mv: forced failure" >&2; exit 1; fi\n'
            '    ;;\n'
            'esac\n'
            'for c in /bin/mv /usr/bin/mv; do [ -x "$c" ] && exec "$c" "$@"; done\n'
            "exit 127\n"
        ))
        env = {"PATH": f"{shim}:{os.environ['PATH']}"}

        r = self.led.memory_archive(env=env)

        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._knowledge_snapshot(),
                         "a failed move must roll every record back")
        self.assertCode(self.led.check(), EXIT_OK, "ledger still valid after rollback")

    # -- (c) a failed post-move recompile rolls back --
    def _compile_wrapper(self, **extra_env):
        """A ZAMM_COMPILE shim that passes through to the real compiler but can
        be told to fail the post-move recompile or leak a live record into
        --list-inert. Returns the env dict to pass to memory_archive."""
        real = SCRIPTS / "internal" / "zamm-compile.sh"
        wrap = self._shim_dir() / "compile-wrapper.sh"
        self._write_exec(wrap, (
            "#!/bin/sh\n"
            f'REAL="{real}"\n'
            'state="$(dirname "$0")/.cstate"\n'
            'case " $* " in\n'
            '  *" --list-inert "*)\n'
            '    "$REAL" "$@"; rc=$?\n'
            '    echo primed > "$state"\n'
            '    [ -n "$LEAK_PATH" ] && printf "%s\\n" "$LEAK_PATH"\n'
            '    exit $rc ;;\n'
            '  *" --check "*|*" --list-live "*) exec "$REAL" "$@" ;;\n'
            '  *)\n'
            '    if [ -n "$FAIL_AFTER_INERT" ] && [ -f "$state" ] && '
            '[ "$(cat "$state")" = primed ]; then\n'
            '      echo disarmed > "$state"\n'
            '      echo "wrapper: forced recompile failure" >&2\n'
            '      exit 1\n'
            '    fi\n'
            '    exec "$REAL" "$@" ;;\n'
            'esac\n'
        ))
        env = {"ZAMM_COMPILE": str(wrap)}
        env.update(extra_env)
        return env

    def test_a_failed_recompile_rolls_back(self):
        self.led.add("live-rule", "Still true.")
        self._retired_chain("obsolete")
        self.led.compile()
        before = self._knowledge_snapshot()

        env = self._compile_wrapper(FAIL_AFTER_INERT="1")
        r = self.led.memory_archive(env=env)

        self.assertNotEqual(r.code, 0)
        self.assertIn_("did not recompile", r.err)
        self.assertEqual(before, self._knowledge_snapshot(),
                         "a failed recompile must roll every record back")

    # -- (d) the digest-change sabotage: an inert list that leaks a live
    #        record must be caught and rolled back (was a manual test in v2) --
    def test_a_digest_changing_move_is_caught_and_rolled_back(self):
        live = self.led.add("live-rule", "Still true and must stay live.")
        self._retired_chain("obsolete")
        self.led.compile()
        before = self._knowledge_snapshot()

        live_path = str(self.led.root / f"zamm-memory/knowledge/2026/{live}.md")
        env = self._compile_wrapper(LEAK_PATH=live_path)
        r = self.led.memory_archive(env=env)

        self.assertNotEqual(r.code, 0)
        self.assertIn_("digest changed", r.err)
        self.assertEqual(before, self._knowledge_snapshot(),
                         "moving a live record must be detected and rolled back")
        self.assertTrue(
            self.led.exists(f"zamm-memory/knowledge/2026/{live}.md"),
            "the leaked live record must be restored",
        )


class TestArchiveSignalRollback(ZammTest):
    def _retired_chain(self, slug):
        rec = self.led.add(slug, f"Retired: {slug}.")
        self.led.add(f"retire-{slug}", "Gone.", date="2026-01-06",
                     type="tombstone", supersedes=rec)
        return rec

    def _knowledge_snapshot(self):
        snap = {}
        for sub in ("zamm-memory/knowledge", "zamm-memory/archive/knowledge"):
            for p in (self.led.root / sub).rglob("*.md"):
                snap[str(p.relative_to(self.led.root))] = p.read_bytes()
        return snap

    def _run_signal_case(self, signal):
        self.led.add("live-rule", "Still true.")
        self._retired_chain("obsolete")   # two inert records -> two moves
        self.led.compile()
        before = self._knowledge_snapshot()

        shim = self.led.root / ".shims"
        shim.mkdir(exist_ok=True)
        # a `mv` that, after completing the 2nd move into archive/knowledge,
        # sends the signal to the archive script — the exact "killed mid-loop"
        # window. Correct handling terminates and rolls back; the buggy version
        # resumed after cleanup deleted the work dir.
        mv = shim / "mv"
        mv.write_text(
            "#!/bin/sh\n"
            'case " $* " in\n'
            '  *archive/knowledge*)\n'
            '    d=$(dirname "$0")\n'
            '    n=$(cat "$d/.count" 2>/dev/null || echo 0); n=$((n + 1))\n'
            '    printf "%s\\n" "$n" > "$d/.count"\n'
            '    for c in /bin/mv /usr/bin/mv; do [ -x "$c" ] && { "$c" "$@"; rc=$?; break; }; done\n'
            f'    if [ "$n" = "2" ]; then kill -{signal} "$PPID" 2>/dev/null; sleep 2; fi\n'
            '    exit ${rc:-0} ;;\n'
            'esac\n'
            'for c in /bin/mv /usr/bin/mv; do [ -x "$c" ] && exec "$c" "$@"; done\n'
            "exit 127\n"
        )
        mv.chmod(0o755)
        env = {"PATH": f"{shim}:{os.environ['PATH']}"}

        r = self.led.memory_archive(env=env)

        self.assertNotEqual(r.code, 0, f"a {signal} must not produce a success exit")
        self.assertEqual(before, self._knowledge_snapshot(),
                         f"a caught {signal} must roll every record back")
        stranded = list(
            (self.led.root / "zamm-memory/archive/knowledge").rglob("*.md"))
        self.assertEqual(stranded, [], "no record may be stranded under archive/")

    def test_a_signal_mid_move_rolls_back_and_strands_nothing(self):
        # the plan claims HUP/INT/TERM fault-injection coverage — exercise all
        for signal in ("TERM", "INT", "HUP"):
            with self.subTest(signal=signal):
                self.setUp()   # fresh tree per signal
                self._run_signal_case(signal)


class TestPlanArchiverTransactional(ZammTest):
    def _plan_dirs(self, area):
        base = self.led.root / f"zamm-memory/{area}/plans"
        return sorted(p.name for p in base.iterdir() if p.is_dir()) \
            if base.exists() else []

    def test_a_collision_refuses_the_whole_batch(self):
        """A pre-existing archive destination refuses the batch before any
        move, rather than SKIP-ing it and archiving the rest (a partial
        archive). The refusal now fires at the plan-check gate (the manifest
        reports the cross-tree duplicate id) before the archiver's own
        preflight ever runs."""
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-one", status="Done")
        self.led.add_plan("2026-01-06-two", status="Done")
        # plant a colliding archive destination for the second plan
        (self.led.root / "zamm-memory/archive/plans/2026-01-06-two").mkdir(parents=True)

        r = self.led.archive()

        self.assertNotEqual(r.code, 0)
        self.assertIn_("exists in both active and archive", r.err)
        # NOTHING moved — the first plan must still be active (all-or-nothing)
        self.assertIn_("2026-01-05-one", self._plan_dirs("active"))
        self.assertIn_("2026-01-06-two", self._plan_dirs("active"))

    def test_a_clean_batch_archives_every_plan(self):
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-one", status="Done")
        self.led.add_plan("2026-01-06-two", status="Abandoned")

        r = self.led.archive()

        self.assertCode(r, EXIT_OK, r.err)
        self.assertEqual(self._plan_dirs("active"), [])
        self.assertEqual(self._plan_dirs("archive"),
                         ["2026-01-05-one", "2026-01-06-two"])

    def test_a_mid_batch_failure_rolls_back(self):
        """A move failure partway through the batch restores every plan that
        already moved (no partial archive)."""
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-one", status="Done")
        self.led.add_plan("2026-01-06-two", status="Done")
        before = self._plan_dirs("active")

        shim = self.led.root / ".shims"
        shim.mkdir(exist_ok=True)
        # a `mv` that fails on the 2nd move into archive/plans; the first plan
        # commits, the second aborts, rollback must restore the first
        (shim / "mv").write_text(
            "#!/bin/sh\n"
            'case " $* " in\n'
            '  *archive/plans*)\n'
            '    d=$(dirname "$0")\n'
            '    n=$(cat "$d/.c" 2>/dev/null || echo 0); n=$((n + 1))\n'
            '    printf "%s\\n" "$n" > "$d/.c"\n'
            '    if [ "$n" = "2" ]; then echo "shim mv: forced failure" >&2; exit 1; fi\n'
            '    ;;\n'
            'esac\n'
            'for c in /bin/mv /usr/bin/mv; do [ -x "$c" ] && exec "$c" "$@"; done\n'
            "exit 127\n"
        )
        (shim / "mv").chmod(0o755)
        # git mv would bypass the shim; force the mv fallback by disabling git
        (shim / "git").write_text("#!/bin/sh\nexit 1\n")
        (shim / "git").chmod(0o755)
        env = {"PATH": f"{shim}:{os.environ['PATH']}"}

        r = self.led.archive(env=env)

        self.assertNotEqual(r.code, 0)
        self.assertEqual(before, self._plan_dirs("active"),
                         "a failed batch move must roll every plan back")
        self.assertEqual(self._plan_dirs("archive"), [],
                         "nothing may remain in archive after rollback")


class TestArchiveHelperGate(ZammTest):
    def test_raw_helper_refuses_an_invalid_done_plan(self):
        """`zamm-archive.sh --archive` invoked directly must not move a plan
        that fails plan check (the dispatcher already gates; the helper did
        not, so direct invocation bypassed the safety story)."""
        self.led.add("a-rule", "A statement.")
        # a Done plan with empty approval fields: fails plan check hard
        self.led.add_plan("2026-01-05-sloppy", status="Done", valid=False)

        r = self.led.run("zamm-archive.sh", "--archive")

        self.assertNotEqual(r.code, 0, "the helper must refuse an invalid ledger")
        self.assertTrue(
            self.led.exists("zamm-memory/active/plans/2026-01-05-sloppy"),
            "the invalid plan must stay in active/",
        )
        self.assertFalse(
            self.led.exists("zamm-memory/archive/plans/2026-01-05-sloppy"),
            "the invalid plan must not reach archive/",
        )

    def test_raw_helper_still_archives_a_valid_plan(self):
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-proper", status="Done")

        r = self.led.run("zamm-archive.sh", "--archive")

        self.assertCode(r, EXIT_OK)
        self.assertTrue(self.led.exists("zamm-memory/archive/plans/2026-01-05-proper"))


class TestPlanArchiveNoActivePlans(ZammTest):
    """Falsified on CI, not locally: pre-fix, GitHub's ubuntu runner bash
    dies with `READY_SLUGS: unbound variable` (zamm-archive.sh line 112,
    run of 2026-07-28 on main), while macOS bash 3.2 tolerates the unset
    array — so this lock guards a failure only CI can reproduce."""

    def test_no_plans_at_all(self):
        r = self.led.zamm("plan", "archive")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("No archive-ready plan directories", r.out)

    def test_active_plans_but_none_terminal(self):
        self.led.add_plan("2026-01-05-busy", status="Implementing")
        r = self.led.zamm("plan", "archive")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("No archive-ready plan directories", r.out)


class TestPlanArchiveListPreview(ZammTest):
    def test_list_previews_without_moving(self):
        self.led.add_plan("2026-01-05-done", status="Done")
        r = self.led.zamm("plan", "archive", "--list")
        self.assertCode(r, EXIT_OK)
        self.assertIn_("2026-01-05-done", r.out)
        self.assertIn_("Dry run", r.out)
        # nothing moved
        self.assertTrue(self.led.exists(
            "zamm-memory/active/plans/2026-01-05-done"))
        self.assertFalse(self.led.exists(
            "zamm-memory/archive/plans/2026-01-05-done"))


class Rev2PlanArchiveDegraded(ZammTest):
    """F5: plan archive rejected a successful (exit 2) recompile, so unrelated
    ledger degradation blocked archiving a valid terminal plan."""

    def test_archive_succeeds_despite_unrelated_degradation(self):
        self.led.add("live", "A live record so the digest is not empty.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-06-broken-bbbbb.md",
            "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
            "durability: years\ncreated: 2026-01-06\n---\nNo schema.\n",
        )
        self.led.add_plan("2026-01-05-done", status="Done")
        self.assertCode(self.led.compile(), EXIT_DEGRADED)
        r = self.led.archive()
        self.assertCode(r, EXIT_OK)
        self.assertTrue(self.led.exists(
            "zamm-memory/archive/plans/2026-01-05-done"))
        self.assertFalse(self.led.exists(
            "zamm-memory/active/plans/2026-01-05-done"))


class Rev6ArchiveGate(ZammTest):
    """PRE-FIX: the archive gate ran only plan check, so a plan whose votes
    record disagreed with its declared Memory-upvotes moved into history with
    the mismatch unresolved (see also Rev3VoteLaundering, which locks the
    missing-votes-record variant)."""

    def test_archive_refuses_a_disagreeing_votes_record(self):
        a = self.led.add("recorda", "A.")
        b = self.led.add("recordb", "B.", date="2026-01-06", sfx="66666")
        self.led.add_plan("2026-01-05-closing", status="Done")
        pf = "zamm-memory/active/plans/2026-01-05-closing/2026-01-05-closing.plan.md"
        self.led.write(pf, self.led.read(pf).replace(
            "Status: Done", f"Status: Done\nMemory-upvotes: {a}"))
        # the votes record upvotes B, the plan declares A
        self.led.add("votes", type="votes", plan="2026-01-05-closing", up=b,
                     date="2026-01-07", sfx="vvvvv")

        arch = self.led.archive()
        self.assertNotEqual(arch.code, 0, "archive must refuse the mismatch")
        self.assertIn_("disagree", arch.err)
        self.assertTrue(
            self.led.exists("zamm-memory/active/plans/2026-01-05-closing"),
            "the mismatched plan must stay in active/")


class Rev7PlanArchiveIntegrity(ShimTest):
    """PRE-FIX: the archive helper validated the plans, then moved them with
    no lock and no content re-verification — a plan modified after the gates
    (approval evidence emptied, say) was archived successfully, and archived
    plans were never structurally validated again, so every later check
    stayed green over invalid permanent history."""

    def test_plan_holding_a_symlink_is_refused_up_front(self):
        """Archived history must be self-contained: a symlink anywhere in
        the plan (nested ones are invisible to plan check) would archive a
        pointer to content the repository does not hold."""
        self.led.add("alive", "A living record.")
        self.led.add_plan("2026-01-05-linked", status="Done")
        outside = self.led.root / "outside-target.txt"
        outside.write_text("EXTERNAL CONTENT\n")
        workdir = (self.led.root /
                   "zamm-memory/active/plans/2026-01-05-linked/workdir")
        workdir.mkdir(parents=True, exist_ok=True)
        os.symlink(outside, workdir / "ref")
        self.assertCode(self.led.compile(), EXIT_OK)

        r = self.led.archive("--archive")
        self.assertNotEqual(r.code, 0, r)
        self.assertIn_("symlink", r.err)
        self.assertEqual("EXTERNAL CONTENT\n", outside.read_text())
        self.assertTrue(self.led.exists(
            "zamm-memory/active/plans/2026-01-05-linked/"
            "2026-01-05-linked.plan.md"))

    def _archived_v3_plan(self, slug, status="Done", approved_by="fixture"):
        body = [f"# {slug}", "", f"Status: {status}",
                "Execution-context-before: synthetic fixture",
                "Complexity-forecast: gecko",
                "Last updated: 2026-01-05", "",
                "Scope:", "* In: synthetic in-scope note.",
                "* Out: nothing.", "",
                "## Done-when", "", "- [x] something", "",
                "## Learnings", "", "- Synthetic fixture learning.", "",
                "Execution-friction-after: none",
                "Complexity-felt: gecko",
                "Complexity-delta: as-expected"]
        if status == "Done":
            body += [f"Done-approved-by: {approved_by}",
                     "Done-approved-at: 2026-01-05",
                     "Done-approval-evidence: synthetic"]
        self.led.write(
            f"zamm-memory/archive/plans/{slug}/{slug}.plan.md",
            "\n".join(body) + "\n")

    def test_invalid_archived_v3_plan_fails_the_checks(self):
        self.led.add("alive", "A living record.")
        self._archived_v3_plan("2026-01-05-badplan", approved_by="")
        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("badplan", pc.err)
        self.assertIn_("Done-approved-by", pc.err)
        self.assertNotEqual(self.led.check_all().code, 0,
                            "the top-level check must catch it too")

    def test_non_terminal_archived_v3_plan_fails_the_checks(self):
        self.led.add("alive", "A living record.")
        self._archived_v3_plan("2026-01-05-openplan", status="Implementing")
        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("archived plan is not terminal", pc.err)

    def test_legacy_archived_plan_is_left_alone(self):
        self.led.add("alive", "A living record.")
        # no stamp and no Execution-context-before: key -> pre-v3 schema;
        # its non-terminal status and missing fields must NOT become errors
        self.led.write(
            "zamm-memory/archive/plans/legacy-plan/legacy-plan.plan.md",
            "# Legacy\n\nStatus: Implementing\nLast updated: 2026-01-05\n")
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_archived_dir_without_main_file_always_fails(self):
        """PRE-FIX: an archived dir was silently skipped unless it held
        exactly one readable main file — moving the main file away disabled
        validation entirely instead of failing it."""
        self.led.add("alive", "A living record.")
        self._archived_v3_plan("2026-01-05-gutted")
        pd = self.led.root / "zamm-memory/archive/plans/2026-01-05-gutted"
        os.rename(pd / "2026-01-05-gutted.plan.md", pd / "notes.md")
        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("no main .plan.md", pc.err)
        self.assertIn_("gutted", pc.err)

    def test_archived_dir_with_two_main_files_always_fails(self):
        self.led.add("alive", "A living record.")
        self._archived_v3_plan("2026-01-05-twinned")
        pd = self.led.root / "zamm-memory/archive/plans/2026-01-05-twinned"
        shutil.copy(pd / "2026-01-05-twinned.plan.md", pd / "second.plan.md")
        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("2 main .plan.md files", pc.err)

    def test_stripped_marker_cannot_demote_a_stamped_v3_plan(self):
        """PRE-FIX: v3-ness was judged solely from the file being validated,
        so deleting the Execution-context-before: line demoted a damaged v3
        plan to 'legacy' and every check passed again."""
        self.led.add("alive", "A living record.")
        self._archived_v3_plan("2026-01-05-demoted", approved_by="")
        pd = self.led.root / "zamm-memory/archive/plans/2026-01-05-demoted"
        pf = pd / "2026-01-05-demoted.plan.md"
        body = pf.read_text().replace(
            "Execution-context-before: synthetic fixture\n", "")
        pf.write_text(body)
        # without the stamp, the stripped file would read as legacy...
        self.assertCode(self.led.plan_check(), EXIT_OK)
        # ...but the archiver's provenance stamp lives OUTSIDE the file
        (pd / ".zamm-archived").write_text("schema: 3\n")
        pc = self.led.plan_check()
        self.assertCode(pc, EXIT_CONTRACT)
        self.assertIn_("demoted", pc.err)

    def test_stamp_name_is_reserved_and_never_followed(self):
        """PRE-FIX: the archiver truncated .zamm-archived with a plain `>`
        redirection, which FOLLOWS a symlink — and hidden entries never
        reach the manifest, so a plan carrying a .zamm-archived symlink got
        archived successfully while its external target was overwritten with
        'schema: 3'."""
        self.led.add("alive", "A living record.")
        self.led.add_plan("2026-01-05-sneaky", status="Done")
        outside = self.led.root / "outside-secret.txt"
        outside.write_text("PRECIOUS EXTERNAL CONTENT\n")
        os.symlink(
            outside,
            self.led.root /
            "zamm-memory/active/plans/2026-01-05-sneaky/.zamm-archived")
        self.assertCode(self.led.compile(), EXIT_OK)

        r = self.led.archive("--archive")
        self.assertNotEqual(r.code, 0, r)
        self.assertIn_("reserved .zamm-archived", r.err)
        self.assertEqual("PRECIOUS EXTERNAL CONTENT\n", outside.read_text(),
                         "the symlink target must never be written through")
        self.assertTrue(self.led.exists(
            "zamm-memory/active/plans/2026-01-05-sneaky/"
            "2026-01-05-sneaky.plan.md"),
            "nothing may be archived when the reserved name is occupied")

    @needs_permission_bits
    def test_archiver_stamps_v3_provenance(self):
        """The archive flow must write the .zamm-archived stamp beside the
        plan file, so post-archive damage to the file's keys cannot opt it
        out of validation."""
        self.led.add("alive", "A living record.")
        self.led.add_plan("2026-01-05-stamped", status="Done")
        self.assertCode(self.led.compile(), EXIT_OK)
        r = self.led.archive("--archive")
        self.assertCode(r, EXIT_OK, r)
        self.assertTrue(self.led.exists(
            "zamm-memory/archive/plans/2026-01-05-stamped/.zamm-archived"),
            "the archiver must stamp v3 provenance outside the plan file")


class ArchivalIsRerunnable(ShimTest):
    """PRE-FIX this class fingerprinted the whole ledger before and after the
    inert decision, re-hashed every record immediately before its move, and
    verified the landed bytes as its final act — all of it guarding against a
    writer racing the archiver.

    That is out of scope now (references/invariants.md), and the reason is
    that archival was never a transaction to begin with: the compiler reads
    the live tree and the archived tree both, so a half-archived ledger is a
    VALID ledger and a rerun simply finishes the job. What survives is the
    self-check on our own inert rule, which no rerun would repair."""

    def _retired_chain(self, slug, date="2026-01-05"):
        rec = self.led.add(slug, f"Old {slug}.", date=date)
        self.led.add(f"retire-{slug}", "No longer applies.", date="2026-01-06",
                     type="tombstone", supersedes=rec)
        return rec

    def test_a_half_archived_ledger_is_valid_and_a_rerun_finishes_it(self):
        self.led.add("alive", "A living record.")
        a = self._retired_chain("alpha")
        b = self._retired_chain("beta")
        self.assertCode(self.led.compile(), EXIT_OK)

        # simulate an archive killed after the first move: do that one move
        # by hand, exactly as the archiver would
        dest = self.led.root / "zamm-memory/archive/knowledge/2026"
        dest.mkdir(parents=True, exist_ok=True)
        os.rename(self.led.root / f"zamm-memory/knowledge/2026/{a}.md",
                  dest / f"{a}.md")

        # the ledger is not damaged: it is simply further along
        self.assertCode(self.led.check(), EXIT_OK)
        self.assertCode(self.led.compile(), EXIT_OK)

        # and a rerun completes the batch
        r = self.led.memory_archive()
        self.assertCode(r, EXIT_OK)
        self.assertTrue((dest / f"{b}.md").exists(),
                        "the rerun must archive what the first run did not")
        self.assertCode(self.led.check(), EXIT_OK)

    def test_archiving_never_overwrites_an_archived_record(self):
        """Bytes are never destroyed: a name collision in the archive stops
        the batch instead of replacing history."""
        self.led.add("alive", "A living record.")
        a = self._retired_chain("alpha")
        self.assertCode(self.led.compile(), EXIT_OK)
        dest = self.led.root / "zamm-memory/archive/knowledge/2026"
        dest.mkdir(parents=True, exist_ok=True)
        (dest / f"{a}.md").write_text("PRECIOUS ARCHIVED HISTORY\n")

        r = self.led.memory_archive()
        self.assertNotEqual(r.code, 0)
        self.assertIn_("already exists", r.err)
        self.assertEqual("PRECIOUS ARCHIVED HISTORY\n",
                         (dest / f"{a}.md").read_text())

    def test_a_load_bearing_record_that_changes_the_digest_rolls_back(self):
        """The one thing archival still undoes: if OUR inert rule admits a
        record whose absence changes the digest, no rerun would put it back,
        so the batch is rolled back and reported."""
        self.led.add("alive", "A living record.")
        rec = self._retired_chain("alpha")
        self.assertCode(self.led.compile(), EXIT_OK)

        # a compiler shim that lists a LIVE record as inert
        real_sh = shutil.which("sh")
        fake = self._shim_dir() / "fake-compile.sh"
        real_compile = SCRIPTS / "internal/zamm-compile.sh"
        live_path = self.led.root / "zamm-memory/knowledge/2026"
        live = sorted(p for p in live_path.glob("*alive*.md"))[0]
        self._write_exec(fake,
            "#!/bin/sh\n"
            'for a in "$@"; do\n'
            '  if [ "$a" = "--list-inert" ]; then\n'
            f'    printf \'%s\\n\' "{live}"\n'
            "    exit 0\n"
            "  fi\n"
            "done\n"
            f'exec "{real_sh}" "{real_compile}" "$@"\n')

        r = self.led.memory_archive(env={"ZAMM_COMPILE": str(fake)})
        self.assertNotEqual(r.code, 0)
        self.assertIn_("digest changed after archiving", r.err)
        self.assertTrue(live.exists(),
                        "the rollback must put the record back")
        self.assertFalse(
            (self.led.root / f"zamm-memory/archive/knowledge/2026/{live.name}").exists(),
            "nothing may remain archived after the rollback")
        self.assertCode(self.led.check(), EXIT_OK)
        _ = rec


if __name__ == "__main__":
    unittest.main()


class TestErasureRecordsAreNeverArchived(ZammTest):
    """An erasure record is load-bearing forever, so it is never inert.

    PRE-FIX the inert rule kept a component only for a live `memory` record
    or a non-dead `votes` record. An `erasure` record is neither, so
    `memory archive` classified it as fully retired and moved it — and the
    compiler reads archived records for their id, type and supersedes only,
    never their `erases:`. An archived erasure record therefore stopped
    erasing and the redacted content came back into the digest.

    The digest self-check caught the change and rolled the batch back, so
    nothing actually resurfaced through the supported command; the damage
    was that `memory archive` then failed forever in any project that had
    ever redacted anything, and that a post-hoc digest diff was the only
    thing standing between an erased secret and the digest.

    invariants.md makes erasure the one carve-out where rerun-fixes-it does
    not hold: a secret that reappears has already been exposed.
    """

    SECRET = "hunter2-staging-token"

    def _ledger_with_an_erasure(self):
        """A live record, plus a leaked record redacted by an erasure."""
        self.led.add("live-rule", "Still true and still live.")
        leaky = self.led.add("leaked", f"The token is {self.SECRET}.")
        eid = self.led.erase(leaky, date="2026-01-06")
        self.assertCode(self.led.compile(), EXIT_OK)
        self.assertNotIn_(self.SECRET, self.led.digest())
        return leaky, eid

    def test_an_erasure_record_is_not_inert(self):
        _, eid = self._ledger_with_an_erasure()

        inert = self.led.run("zamm-compile.sh", "--list-inert").out
        self.assertNotIn(
            eid, inert,
            "an erasure record must never be offered to memory archive")

    def test_memory_archive_succeeds_when_an_erasure_record_exists(self):
        """The whole command is all-or-nothing, so one erasure record used to
        brick archival for every other retired chain in the project."""
        self._ledger_with_an_erasure()
        rec = self.led.add("obsolete", "Retired knowledge.", date="2026-01-07")
        self.led.add("retire-obsolete", "No longer applies.",
                     date="2026-01-08", type="tombstone", supersedes=rec)
        self.assertCode(self.led.compile(), EXIT_OK)

        r = self.led.memory_archive()

        self.assertCode(r, EXIT_OK, "archival must not be blocked by erasure")
        self.assertTrue(
            self.led.exists(f"zamm-memory/archive/knowledge/2026/{rec}.md"),
            "the genuinely retired chain must still be archived")

    def test_an_archived_erasure_record_still_erases(self):
        """Defence in depth: however the file reached the archive — a manual
        tidy-up, an interrupted run, a merge — the redaction must hold.
        """
        leaky, eid = self._ledger_with_an_erasure()
        src = self.led.root / f"zamm-memory/knowledge/2026/{eid}.md"
        dst = self.led.root / f"zamm-memory/archive/knowledge/2026/{eid}.md"
        dst.parent.mkdir(parents=True, exist_ok=True)
        src.rename(dst)

        self.assertCode(self.led.compile(), EXIT_OK)

        self.assertNotIn_(
            self.SECRET, self.led.digest(),
            "an archived erasure record must keep redacting")
        self.assertNotIn_(leaky, self.led.digest())
