"""Regression locks for the 2026-07-20 command-surface review findings.

Every test here reproduces a finding that shipped with
2026-07-20-command-surface-v2 and is closed by
2026-07-20-command-surface-review-remediation. Each is written to FAIL
against the pre-fix scripts (prove it with ZAMM_SCRIPTS_DIR pointed at a
pristine checkout), so the suite guards the behaviour rather than encoding
the bug as expected.

Grouped by finding number from the review:
  1  compiler still applied a quarantined record's supersede edges
  2  `help <verb>` mutated the project
  3  `plan check` certified structurally invalid plans
  4  `plan create` was neither safely escaped nor atomic
  5  `memory archive` was not transactional on all failures
  6  plan lookup violated exact-match precedence
  7  secondary scopes were not searchable
  8  drift: stamp / staleness / legacy flag / docs
"""

import os
import stat
import subprocess

from harness import (
    EXIT_CONTRACT,
    EXIT_DEGRADED,
    EXIT_OK,
    SCRIPTS,
    ZammTest,
)


# ----------------------------------------------------------------------
# Finding 1 — a quarantined record must not suppress a valid neighbour
# ----------------------------------------------------------------------
class TestCompilerAuthority(ZammTest):
    """The invariant: invalid input degrades itself, never its neighbours.

    A record that fails the contract is quarantined; every supersede edge it
    carries must be dropped, INCLUDING edges the compiler only rejects while
    walking the edge list (type mismatch, duplicate target, cycle). The
    pre-fix compiler applied `dead[tgt]` before rejecting, so the target
    vanished from the digest with exit 0 — silent data loss.
    """

    def _survives(self, victim):
        entries = self.led.entries()
        self.assertIn_(
            victim, "\n".join(entries),
            "the valid supersede target must stay live in the digest",
        )

    def test_votes_superseding_a_memory_record_keeps_the_target(self):
        victim = self.led.add("victim", "Valid knowledge that must survive.")
        survivor = self.led.add("survivor", "A live sibling so the ledger is not empty.")
        # a parse-valid votes record (has plan:, up:) whose supersedes: points
        # at a memory record — rejected by the type-compat rule mid-loop
        self.led.add(
            "badvote", type="votes", date="2026-01-06", plan="2026-01-06-p",
            up=survivor, supersedes=victim,
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(victim)
        self.assertIn_("live=2", self.header(),
                       "both memory records must be live")

    def test_memory_superseding_a_votes_record_keeps_the_votes_alive(self):
        # a votes record is a valid target for nothing but another votes
        # record; a memory record trying to retire it is rejected mid-loop.
        # The harm the pre-fix compiler did was subtler than a vanished entry:
        # it applied dead[votes-record], silently DISABLING the vote. So the
        # assertion is that the vote still counts, not just that the target
        # is listed.
        target = self.led.add("voted", "A statement carrying a vote.")
        closer = self.led.add("closer", type="votes", date="2026-01-06",
                              plan="2026-01-06-p", up=target)
        # this memory record illegally supersedes the votes record
        self.led.add("bad-memory", "Tries to retire a votes record.",
                     date="2026-01-07", supersedes=closer)

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_(target, "\n".join(self.led.entries()))
        self.assertIn_("+1]", self.led.digest(),
                       "the vote must survive: the illegal superseder is "
                       "quarantined, so the votes record is never marked dead")

    def test_duplicate_target_after_a_valid_one_voids_the_whole_record(self):
        """A record whose edge list is `A, A` is malformed. The first edge
        is valid in isolation, but the record is quarantined, so NEITHER
        edge may apply — the target must survive."""
        target = self.led.add("dup-target", "Must not be retired by a bad record.")
        self.led.add("other", "A live sibling.")
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-08-dupsup-33333.md",
            "---\ntype: tombstone\n"
            f"supersedes: {target}, {target}\n"
            "created: 2026-01-08\nschema: 3\n---\nRetires it twice.\n",
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(target)

    def test_self_supersede_alongside_a_valid_target_voids_the_record(self):
        target = self.led.add("real-target", "Must survive a self-referential record.")
        self.led.add("other", "A live sibling.")
        rid = "2026-01-08-selfsup-44444"
        self.led.write(
            f"zamm-memory/knowledge/2026/{rid}.md",
            "---\ntype: tombstone\n"
            f"supersedes: {target}, {rid}\n"
            "created: 2026-01-08\nschema: 3\n---\nRetires target and itself.\n",
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(target)

    def test_cycle_member_pointing_at_an_external_target_spares_it(self):
        """Two records supersede each other (a cycle) and one also points at
        an innocent external memory record. The cycle members are
        quarantined; the external target must not be dragged down with them."""
        external = self.led.add("bystander", "Innocent record outside the cycle.")
        self.led.add("live", "Keeps the ledger non-empty.")
        # a <-> b cycle, and a also supersedes the bystander
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-08-cyc-a-55555.md",
            "---\ntype: tombstone\n"
            f"supersedes: 2026-01-08-cyc-b-66666, {external}\n"
            "created: 2026-01-08\nschema: 3\n---\nA.\n",
        )
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-08-cyc-b-66666.md",
            "---\ntype: tombstone\n"
            "supersedes: 2026-01-08-cyc-a-55555\n"
            "created: 2026-01-08\nschema: 3\n---\nB.\n",
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(external)

    def test_parse_time_quarantine_still_drops_edges(self):
        """The pre-fix compiler already handled this case correctly (a record
        rejected before the edge loop contributes nothing); lock it so the
        rewrite does not regress it."""
        victim = self.led.add("guarded", "Must survive an unreadable superseder.")
        self.led.add("live", "A live sibling.")
        # missing schema: -> quarantined at parse time, before edges walk
        self.led.write(
            "zamm-memory/knowledge/2026/2026-01-09-noschema-77777.md",
            "---\ntype: tombstone\n"
            f"supersedes: {victim}\n"
            "created: 2026-01-09\n---\nNo schema, retires the victim.\n",
        )

        r = self.led.compile()

        # quarantine publishes (with a ## Degraded section) but signals it via
        # exit 2; the point of each case is that the valid neighbour survives.
        self.assertCode(r, EXIT_DEGRADED)
        self._survives(victim)

    def test_check_still_reports_the_violation(self):
        """Quarantine-then-drop must not silence --check: the record is still
        invalid and the ledger must fail validation."""
        victim = self.led.add("victim", "Valid knowledge.")
        self.led.add("badvote", type="votes", date="2026-01-06",
                     plan="2026-01-06-p", up=victim, supersedes=victim)

        r = self.led.check()

        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("votes record", r.err)


# ----------------------------------------------------------------------
# Finding 2 — no help path may mutate the project
# ----------------------------------------------------------------------
# The forms `help <verb>` and `<verb> --help` for every documented command.
HELP_PATHS = [
    ["help"], ["--help"], ["-h"],
    ["help", "scaffold"], ["help", "status"], ["help", "check"],
    ["help", "memory"],
    ["help", "memory", "digest"], ["help", "memory", "list"],
    ["help", "memory", "show"], ["help", "memory", "check"],
    ["help", "memory", "create"], ["help", "memory", "archive"],
    ["help", "plan"],
    ["help", "plan", "list"], ["help", "plan", "show"],
    ["help", "plan", "check"], ["help", "plan", "create"],
    ["help", "plan", "archive"],
    ["scaffold", "--help"], ["status", "--help"], ["check", "--help"],
    ["memory", "--help"],
    ["memory", "digest", "--help"], ["memory", "list", "--help"],
    ["memory", "show", "--help"], ["memory", "check", "--help"],
    ["memory", "create", "--help"], ["memory", "archive", "--help"],
    ["plan", "--help"],
    ["plan", "list", "--help"], ["plan", "show", "--help"],
    ["plan", "check", "--help"], ["plan", "create", "--help"],
    ["plan", "archive", "--help"],
    ["memory", "show", "-h"], ["plan", "create", "-h"],
]


class TestHelpIsReadOnly(ZammTest):
    """The reproduction: `zamm help plan create` created a plan directory
    named `<date>-help/` and exited 0, because the built-in plan_create read
    --help as a title. Help must be observably read-only for EVERY command."""

    def _snapshot(self):
        return {
            str(p.relative_to(self.led.root)): p.read_bytes()
            for p in sorted(self.led.root.rglob("*")) if p.is_file()
        }

    def _fixture(self):
        # a realistic tree: one record, one plan, a compiled digest
        self.led.add("a-rule", "A statement so the ledger is not empty.")
        self.led.add_plan("2026-01-05-open", status="Implementing")
        self.led.compile()

    def test_every_help_path_is_read_only_and_prints_usage(self):
        self._fixture()
        for args in HELP_PATHS:
            with self.subTest(args=" ".join(args)):
                before = self._snapshot()
                r = self.led.zamm(*args)
                after = self._snapshot()
                self.assertCode(r, EXIT_OK, f"help path must exit 0: {args}")
                self.assertTrue(
                    r.output.strip(),
                    f"help path must print something: {args}",
                )
                self.assertEqual(
                    before, after,
                    f"help path mutated the project tree: {args}\n"
                    f"added/changed: "
                    f"{set(after) ^ set(before) or 'content of an existing file'}",
                )

    def test_help_plan_create_does_not_create_a_plan(self):
        """The exact reproduction, pinned on its own."""
        before = self._snapshot()
        r = self.led.zamm("help", "plan", "create")
        self.assertCode(r, EXIT_OK)
        self.assertFalse(
            any("-help" in name for name in self._snapshot()),
            "help must not create a plan directory named for --help",
        )
        self.assertEqual(before, self._snapshot())


# ----------------------------------------------------------------------
# Finding 4 — plan create must treat the title as data and be atomic
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# Finding 5 — memory archive must be transactional on ALL failures
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# Finding 3 — plan check must enforce the status contracts, not just shapes
# ----------------------------------------------------------------------
class TestPlanCheckHardening(ZammTest):
    """The pre-fix check validated only the SHAPE of `Last updated:` and the
    presence of a few fields, so an Implementing plan with no `Scope:` and
    `Last updated: 2026-99-99` passed with exit 0 — and `plan archive` trusts
    this check as its gate."""

    def _write_plan(self, slug, body):
        self.led.write(
            f"zamm-memory/active/plans/{slug}/{slug}.plan.md", body,
        )

    def test_the_exact_reproduction_is_now_rejected(self):
        """Implementing, no Scope, impossible Last updated."""
        self._write_plan(
            "2026-01-05-x",
            "# X\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: octopus\n"
            "Last updated: 2026-99-99\n\n## Done-when\n\n- [ ] thing\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("not a real", r.err)     # the fake date
        self.assertIn_("Scope", r.err)          # the missing scope

    def test_impossible_last_updated_is_rejected(self):
        self.led.add_plan("2026-01-05-p", status="Implementing")
        # overwrite just the date with a real-shaped but impossible one
        p = "zamm-memory/active/plans/2026-01-05-p/2026-01-05-p.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Last updated: 2026-01-05", "Last updated: 2026-02-30"))
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("not a real", r.err)

    def test_a_real_leap_day_last_updated_is_accepted(self):
        """The date check must not be over-broad."""
        self.led.add_plan("2024-02-29-leap", status="Implementing")
        p = "zamm-memory/active/plans/2024-02-29-leap/2024-02-29-leap.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Last updated: 2026-01-05", "Last updated: 2024-02-29"))
        self.assertCode(self.led.plan_check(), EXIT_OK)

    def test_missing_scope_is_rejected_once_implementing(self):
        self._write_plan(
            "2026-01-05-noscope",
            "# N\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: gecko\n"
            "Last updated: 2026-01-05\n\n## Done-when\n\n- [ ] thing\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Scope", r.err)

    def test_empty_scope_scaffolding_is_rejected(self):
        """A `Scope:` with only the bare `* In:` / `* Out:` markers is empty."""
        self._write_plan(
            "2026-01-05-bare",
            "# B\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: gecko\n"
            "Last updated: 2026-01-05\n\nScope:\n* In:\n* Out:\n\n"
            "## Done-when\n\n- [ ] thing\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Scope", r.err)

    def test_no_done_when_items_is_rejected(self):
        self._write_plan(
            "2026-01-05-empty-dw",
            "# E\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: gecko\n"
            "Last updated: 2026-01-05\n\nScope:\n* In: real work.\n* Out: no.\n\n"
            "## Done-when\n\n(nothing yet)\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Done-when", r.err)

    def test_bogus_complexity_forecast_is_rejected(self):
        self._write_plan(
            "2026-01-05-animal",
            "# A\n\nStatus: Implementing\n"
            "Execution-context-before: y\nComplexity-forecast: velociraptor\n"
            "Last updated: 2026-01-05\n\nScope:\n* In: work.\n* Out: no.\n\n"
            "## Done-when\n\n- [ ] thing\n",
        )
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("animal scale", r.err)

    def test_bogus_complexity_delta_is_rejected(self):
        self.led.add_plan("2026-01-05-rev", status="Review")
        p = "zamm-memory/active/plans/2026-01-05-rev/2026-01-05-rev.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Complexity-delta: as-expected", "Complexity-delta: sideways"))
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Complexity-delta", r.err)

    def test_bogus_complexity_felt_is_rejected(self):
        self.led.add_plan("2026-01-05-rev2", status="Review")
        p = "zamm-memory/active/plans/2026-01-05-rev2/2026-01-05-rev2.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Complexity-felt: gecko", "Complexity-felt: dragon"))
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("animal scale", r.err)

    def test_impossible_done_approved_at_is_rejected(self):
        self.led.add_plan("2026-01-05-done", status="Done")
        p = "zamm-memory/active/plans/2026-01-05-done/2026-01-05-done.plan.md"
        self.led.write(p, self.led.read(p).replace(
            "Done-approved-at: 2026-01-05", "Done-approved-at: 2026-13-40"))
        r = self.led.plan_check()
        self.assertCode(r, EXIT_CONTRACT)
        self.assertIn_("Done-approved-at", r.err)

    def test_the_well_formed_fixture_still_passes_and_archives(self):
        """Item 12: the strengthened fixture must remain valid end to end."""
        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-good", status="Done")
        self.assertCode(self.led.plan_check(), EXIT_OK)
        self.assertCode(self.led.archive(), EXIT_OK)
        self.assertTrue(self.led.exists(
            "zamm-memory/archive/plans/2026-01-05-good"))


# ----------------------------------------------------------------------
# Finding 6 — plan lookup must honour exact-match precedence
# ----------------------------------------------------------------------
class TestPlanLookupPrecedence(ZammTest):
    """`plan show alpha` used to report an ambiguous match against `alpha` and
    `alpha-beta` because it matched by substring only. Exact id wins, then
    exact slug, and only then substring."""

    def _plan(self, slug):
        self.led.add_plan(slug, status="Implementing")

    def test_exact_slug_beats_a_longer_prefix(self):
        self._plan("2026-01-02-alpha")
        self._plan("2026-01-03-alpha-beta")

        r = self.led.plan_show("alpha")

        self.assertCode(r, EXIT_OK, r.err)
        self.assertIn_("2026-01-02-alpha", r.out)
        self.assertNotIn_("alpha-beta", r.out)

    def test_exact_id_resolves(self):
        self._plan("2026-01-02-alpha")
        self._plan("2026-01-03-alpha-beta")

        r = self.led.plan_show("2026-01-03-alpha-beta")

        self.assertCode(r, EXIT_OK, r.err)
        self.assertIn_("2026-01-03-alpha-beta", r.out)

    def test_a_genuinely_ambiguous_substring_still_lists_candidates(self):
        self._plan("2026-01-02-alpha")
        self._plan("2026-01-03-alpha-beta")
        # "al" is a substring of both and an exact id/slug of neither
        r = self.led.plan_show("al")

        self.assertNotEqual(r.code, 0)
        self.assertIn_("matches 2 plans", r.err)
        self.assertIn_("2026-01-02-alpha", r.err)
        self.assertIn_("2026-01-03-alpha-beta", r.err)

    def test_substring_still_works_when_unambiguous(self):
        """The convenience the substring tier preserves."""
        self._plan("2026-07-20-command-surface-v2")
        r = self.led.plan_show("surface")
        self.assertCode(r, EXIT_OK, r.err)
        self.assertIn_("command-surface-v2", r.out)


# ----------------------------------------------------------------------
# Finding 7 — secondary scopes must be searchable
# ----------------------------------------------------------------------
class TestSecondaryScopeSearch(ZammTest):
    """`memory list --scope X` filtered on the primary scope only, so a record
    tagged `contracts/api, conventions` was invisible to `--scope conventions`
    even though the data model calls secondary tags selection doors."""

    def test_finds_a_record_by_its_secondary_scope(self):
        self.led.add("multi", "A record with a secondary tag.",
                     scope="contracts/api, conventions")
        self.led.add("other", "An unrelated record.", scope="ops/migrations")
        self.led.compile()

        r = self.led.memory_list("--scope", "conventions")

        self.assertCode(r, EXIT_OK)
        self.assertIn_("multi", r.out)
        self.assertNotIn_("other", r.out)

    def test_primary_scope_still_matches(self):
        self.led.add("multi", "A record with a secondary tag.",
                     scope="contracts/api, conventions")
        self.led.compile()

        r = self.led.memory_list("--scope", "contracts")

        self.assertCode(r, EXIT_OK)
        self.assertIn_("multi", r.out)
        # the listing still displays the primary scope as the home
        self.assertIn_("contracts/api", r.out)

    def test_a_non_matching_area_excludes_the_record(self):
        self.led.add("multi", "A record with a secondary tag.",
                     scope="contracts/api, conventions")
        self.led.compile()

        r = self.led.memory_list("--scope", "ops")

        self.assertEqual(r.out.strip(), "", "no record has an ops tag")


# ----------------------------------------------------------------------
# Finding 8 — stamp / staleness / legacy flag / docs drift
# ----------------------------------------------------------------------
import re                                        # noqa: E402
import shutil                                    # noqa: E402


class TestDriftDetection(ZammTest):
    """The stamp was the git short SHA in a checkout, identical for a clean
    and a dirty tree, so `status` reported rendered surfaces current while the
    skill had actually changed. And staleness watched knowledge/ only, though
    the digest embeds active plans too."""

    def _scaffold_fresh(self):
        shutil.rmtree(self.led.root / "zamm-memory")
        self.assertCode(self.led.scaffold(), EXIT_OK)

    def test_stamp_is_content_derived_not_a_git_sha(self):
        self._scaffold_fresh()
        stamp = re.search(r"version=(\S+)", self.led.read("AGENTS.md")).group(1)
        # content hash, even though the skill dir is itself a git checkout
        self.assertTrue(stamp.startswith("sha:"), f"expected sha: stamp, got {stamp}")

    def test_status_is_current_right_after_scaffold(self):
        self._scaffold_fresh()
        self.led.add("a-rule", "A statement.")
        self.led.compile()

        r = self.led.status()

        self.assertCode(r, EXIT_OK)
        self.assertIn_("rendered surfaces:", r.out)
        self.assertNotIn_("STALE", r.out)

    def test_status_reports_surface_drift_when_the_stamp_differs(self):
        """A stamp that no longer matches the skill's content reads STALE —
        the case a dirty git checkout used to hide."""
        self._scaffold_fresh()
        self.led.add("a-rule", "A statement.")
        self.led.compile()
        agents = self.led.read("AGENTS.md")
        # simulate a project scaffolded from an older skill version
        agents = re.sub(r"version=\S+", "version=sha:000000000000", agents, count=1)
        self.led.write("AGENTS.md", agents)

        r = self.led.status()

        self.assertIn_("STALE", r.out)
        self.assertIn_("scaffold", r.out)

    def test_staleness_watches_active_plans_too(self):
        """A plan edited after the last compile makes the digest stale, since
        the digest embeds the active plans."""
        import time

        self.led.add("a-rule", "A statement.")
        self.led.add_plan("2026-01-05-open", status="Implementing")
        self.led.compile()
        time.sleep(1.1)
        # edit the plan file after the digest was built
        p = "zamm-memory/active/plans/2026-01-05-open/2026-01-05-open.plan.md"
        self.led.write(p, self.led.read(p) + "\nAn edit after compiling.\n")

        self.assertIn_("STALE", self.led.status().out)

    def test_overwrite_templates_flag_is_gone(self):
        """The legacy mode flag is removed from the scaffold script itself,
        not just hidden by the dispatcher."""
        r = self.led.run("zamm-scaffold.sh", "--overwrite-templates")
        self.assertNotEqual(r.code, 0, "the removed flag must be rejected")
        self.assertIn_("unknown argument", r.output)
