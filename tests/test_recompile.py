"""Compiling only what has moved.

Session start used to recompile unconditionally, so the common case — open a
session, change nothing, read memory — paid for the whole ledger to be reranked
and rewritten byte for byte. The compiler now fingerprints its inputs and skips
the work when the answer cannot have changed.

The fingerprint is CONTENT, not mtime: two edits inside one filesystem
timestamp tick, a restored backup, a `git checkout` that rewrites a file to the
same size — all of them leave a stale digest under a mtime rule, and memory
that is confidently stale is worse than memory that is slow.
"""

import os
import pathlib
import shutil
import subprocess
import unittest

from harness import EXIT_DEGRADED, EXIT_OK, SCRIPTS, ZammTest

DIGEST = "zamm-memory/.compiled/zamm-digest.md"
FULL = "zamm-memory/.compiled/zamm-digest-full.md"
STATE = "zamm-memory/.compiled/state.tsv"


class TestRecompileOnlyWhenInputsMove(ZammTest):
    def _stamp(self, rel=DIGEST):
        """The INODE, not the mtime: a real publish renames a new file into
        place (new inode), while a skip touches the existing files so that
        mtime-based observers — `status` and its `find -newer` — see them as
        current. mtime therefore cannot tell the two apart; the inode can."""
        return os.stat(self.led.root / rel).st_ino

    def _path(self, rid):
        return self.led.root / f"zamm-memory/knowledge/{rid[:4]}/{rid}.md"

    def test_a_second_startup_rebuilds_nothing(self):
        self.led.add("rule", "A statement.")
        self.led.compile()
        before = self._stamp()

        r = self.led.compile()

        self.assertCode(r, EXIT_OK)
        self.assertEqual(before, self._stamp(), "nothing moved, so nothing should be rewritten")

    def test_without_git_the_tree_is_read(self):
        self.led.add("rule", "A statement.")

        self.led.compile()

        self.assertIn_("fingerprint\ttree", self.led.read(STATE))

    def test_the_companion_is_skipped_with_it(self):
        """One fingerprint covers every artifact the compile publishes."""
        self.led.add("rule", "A statement.")
        self.led.compile()
        before = self._stamp(FULL)

        self.led.compile()

        self.assertEqual(before, self._stamp(FULL))

    def test_a_touch_is_not_a_change(self):
        """mtime moves for reasons that have nothing to do with content — a
        checkout, a sync, a backup restore. The digest depends on the bytes."""
        rid = self.led.add("rule", "A statement.")
        self.led.compile()
        before = self._stamp()

        os.utime(self._path(rid), None)
        self.led.compile()

        self.assertEqual(before, self._stamp())

    def test_an_in_place_edit_of_the_same_length_rebuilds(self):
        """The case a mtime+size rule gets wrong, and the reason this hashes
        content: same byte count, same second, different memory."""
        rid = self.led.add("rule", "Statement number one.")
        self.led.compile()
        before = self._stamp()

        rec = self._path(rid)
        rec.write_text(rec.read_text().replace("Statement number one.",
                                               "Statement number two."))
        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("Statement number two.", self.led.digest())

    def test_a_new_record_rebuilds(self):
        self.led.add("rule", "A statement.")
        self.led.compile()
        before = self._stamp()

        self.led.add("second", "Another statement.", date="2026-01-06")
        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("Another statement.", self.led.digest())

    def test_a_deleted_record_rebuilds(self):
        """Deletion is the change a content hash of what remains cannot see on
        its own, so the path list is in the fingerprint too."""
        self.led.add("rule", "A statement.")
        rid = self.led.add("second", "Another statement.", date="2026-01-06")
        self.led.compile()
        before = self._stamp()

        self._path(rid).unlink()
        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertNotIn_("Another statement.", self.led.digest())

    def test_a_plan_edit_rebuilds(self):
        """Plans are in the digest, so they are inputs like any record."""
        self.led.add("rule", "A statement.")
        self.led.add_plan("2026-01-05-work", status="Draft")
        self.led.compile()
        before = self._stamp()

        plan = self.led.root / "zamm-memory/active/plans/2026-01-05-work/2026-01-05-work.plan.md"
        plan.write_text(plan.read_text().replace("Status: Draft", "Status: Implementing"))
        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("Implementing", self.led.digest())

    def test_a_different_budget_rebuilds(self):
        """--softmax changes what the same ledger renders, so it is an input."""
        for i in range(40):
            self.led.add(f"rec-{i}", f"Headline {i}.\n\n" + ("Elaboration. " * 30))
        self.led.compile()
        before = self._stamp()

        self.led.compile("--softmax", "4000")

        self.assertNotEqual(before, self._stamp())

    def test_a_new_day_rebuilds(self):
        """Scores decay by date: a ledger nobody touched ranks differently
        tomorrow, and a digest that silently lags its own dormancy rule is the
        same stale-memory failure by another route."""
        self.led.add("rule", "A statement.")
        self.led.compile(today="2026-07-19")
        before = self._stamp()

        self.led.compile(today="2026-07-20")

        self.assertNotEqual(before, self._stamp())

    def test_force_rebuilds_anyway(self):
        self.led.add("rule", "A statement.")
        self.led.compile()
        before = self._stamp()

        r = self.led.compile("--force")

        self.assertCode(r, EXIT_OK)
        self.assertNotEqual(before, self._stamp())

    def test_a_missing_artifact_rebuilds_even_on_a_match(self):
        """The fingerprint answers "the inputs have not moved", never "the
        outputs are there". Both have to hold."""
        self.led.add("rule", "A statement.")
        self.led.compile()
        (self.led.root / FULL).unlink()

        self.led.compile()

        self.assertTrue(self.led.exists(FULL), "the missing companion must be rebuilt")

    def test_a_symlinked_copy_of_a_record_is_the_documented_blind_spot(self):
        """The one change this fingerprint cannot see, kept as a test so the
        trade stays visible: find does not follow symlinks but the content pass
        does, so a record replaced by a symlink to a byte-identical copy reads
        as no change at all. The ledger refuses a symlinked record at every
        compile it actually runs and `check` never skips, so the diagnosis is
        delayed rather than lost, and nothing from the symlink can reach a
        digest this run does not produce. Three traversals would have caught
        it; nobody does it by accident. See DELTAS, "the fingerprint is not a
        validator"."""
        rid = self.led.add("rule", "A statement.")
        self.led.compile()
        before = self._stamp()

        rec = self._path(rid)
        real = self.led.root / "copy-outside-the-ledger.md"
        rec.rename(real)
        os.symlink(real, rec)
        skipped = self.led.compile()

        self.assertEqual(before, self._stamp(), "the blind spot: nothing looked changed")
        self.assertCode(skipped, EXIT_OK)
        # and the moment anything else moves, or anyone asks directly:
        self.assertNotEqual(0, self.led.compile("--force").code)
        self.assertNotEqual(0, self.led.check().code)

    def test_startup_reads_the_manifest_the_compile_left(self):
        """The plan tally is the other derived answer session start reuses: the
        compile enumerated the tree, so startup reads that file instead of
        walking it again. Injecting two MISSING rows into it also pins the
        separator — `$(printf '\\n')` is the empty string, and with it two
        missing plan roots ran together into one unreadable path."""
        self.led.add("rule", "A statement.")
        self.led.compile()
        manifest = self.led.root / "zamm-memory/.compiled/plan-manifest.tsv"
        self.assertTrue(manifest.exists(), "the compile must leave its manifest")

        manifest.write_text(
            f"MISSING\t{self.led.root}/zamm-memory/active/plans\n"
            f"MISSING\t{self.led.root}/zamm-memory/archive/plans\n")
        r = self.led.compile()

        self.assertIn_("2 missing plan roots", r.out)
        defects = self.led.read("zamm-memory/.compiled/zamm-defects.md")
        self.assertIn_("  zamm-memory/active/plans\n", defects)
        self.assertIn_("  zamm-memory/archive/plans\n", defects)

    def test_a_missing_sub_tree_sidecar_rebuilds(self):
        """The skip promises every artifact is current, sidecars included. A
        deleted backlog-state.tsv left session start silently dropping the idea
        counts while `status` reported the lens/state pair incoherent and told
        you to run the one command that would skip forever."""
        self.led.add("rule", "A statement.")
        self.led.add_idea("idea", "An idea worth keeping.")
        self.led.compile()
        (self.led.root / "zamm-memory/.compiled/backlog-state.tsv").unlink()

        r = self.led.compile()

        self.assertTrue(self.led.exists("zamm-memory/.compiled/backlog-state.tsv"),
                        "the missing sidecar must be rebuilt")
        self.assertIn_("idea", r.out.splitlines()[0])

    def test_a_skipped_compile_keeps_the_degraded_exit_code(self):
        """A run that re-derived nothing must not read as a repair."""
        self.led.add("good", "A fine record.")
        self.led.write("zamm-memory/knowledge/2026/2026-01-05-broken-99999.md",
                       "no frontmatter\n")
        self.assertCode(self.led.compile(), EXIT_DEGRADED)
        before = self._stamp()

        r = self.led.compile()

        self.assertEqual(before, self._stamp(), "the fixture must actually skip")
        self.assertCode(r, EXIT_DEGRADED)
        self.assertIn_("quarantined record", r.out)

    def test_an_interrupted_read_stores_no_fingerprint(self):
        """Nothing is remembered until the inputs have been read twice with the
        same answer. The companion pass runs between those two reads, so a
        companion that WRITES A RECORD is a write that landed mid-compile: the
        fingerprint taken before does not describe the ledger after, and
        storing it would skip the recompile that fixes it."""
        self.led.add("rule", "A statement.")
        self.led.compile()
        self.assertIn_("inputs\t", self.led.read(STATE))

        writer = self.led.root / "writer.sh"
        writer.write_text(
            "#!/bin/sh\n"
            f"cat > '{self.led.root}/zamm-memory/knowledge/2026/2026-01-06-late-33333.md' <<'EOF'\n"
            "---\ntype: memory\nscope: internals\nimportance: useful\n"
            "durability: months\ncreated: 2026-01-06\nschema: 3\n---\n"
            "A record that landed while the compiler was running.\n"
            "EOF\n"
            "exit 0\n")
        self.led.add("second", "A second statement.", date="2026-01-07")   # forces a real compile
        self.led.compile(env={"ZAMM_COMPANION": str(writer)})

        self.assertNotIn_("inputs\t", self.led.read(STATE),
                          "a fingerprint taken before a mid-compile write must not be stored")
        self.led.compile()
        self.assertIn_("landed while the compiler was running", self.led.digest(),
                       "the next run must pick the late record up")

    def test_a_skip_leaves_status_with_nothing_to_nag_about(self):
        """`status` decides staleness by mtime; startup skips by content. A
        record touched without a content change used to leave status saying
        "run startup" and startup skipping, forever. A skip now touches the
        published files: they ARE current, and every mtime-based reader should
        see that."""
        rid = self.led.add("rule", "A statement.")
        self.led.compile()

        os.utime(self._path(rid), None)
        self.led.compile()
        out = self.led.status().out

        self.assertNotIn_("STALE", out)
        self.assertNotIn_("run: zamm-run.sh startup", out)

    def test_a_moved_project_rebuilds(self):
        """plan-manifest.tsv holds absolute paths, so the project path is an
        input: the same ledger at a new location must compile once."""
        import shutil, tempfile
        from harness import Ledger
        self.led.add("rule", "A statement.")
        self.led.add_plan("2026-01-05-work", status="Draft")
        self.led.compile()
        before = self._stamp()

        dest = pathlib.Path(tempfile.mkdtemp()) / "moved"
        shutil.move(str(self.led.root), str(dest))
        self.addCleanup(shutil.rmtree, dest.parent, ignore_errors=True)
        moved = Ledger(str(dest))
        r = moved.compile()

        self.assertCode(r, EXIT_OK)
        self.assertNotEqual(before, os.stat(dest / DIGEST).st_ino)
        self.assertIn_("1 plan", r.out.splitlines()[0])
        # the fixture's own cleanup expects the original path
        dest.rename(self.led.root)


def _git(root, *args):
    return subprocess.run(("git", "-C", str(root)) + args,
                          capture_output=True, text=True,
                          env={**os.environ, "GIT_AUTHOR_NAME": "t",
                               "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                               "GIT_COMMITTER_EMAIL": "t@t"})


@unittest.skipUnless(shutil.which("git"), "git is not installed")
class TestTheGitAnswer(ZammTest):
    """Under version control the fingerprint asks git instead of reading the
    ledger: the object ids of the committed ledger name its content, and
    `status` names everything not committed-and-clean. At four hundred records
    the two cost the same (~50ms); at four thousand it is 20ms against 140ms,
    and the gap is linear — the tree object does not care how large the ledger
    is. It is also the more precise instrument: git compares content, and a
    tracked record swapped for a symlink is a typechange it reports.
    """

    def setUp(self):
        super().setUp()
        _git(self.led.root, "init", "-q")
        self.led.add("rule", "A statement.")
        _git(self.led.root, "add", "-A")
        _git(self.led.root, "commit", "-qm", "records")
        self.led.compile()

    def _stamp(self):
        return os.stat(self.led.root / DIGEST).st_ino

    def test_a_clean_repository_skips(self):
        before = self._stamp()

        self.led.compile()

        self.assertEqual(before, self._stamp())

    def test_a_clean_repository_is_answered_by_git(self):
        """The one that would have caught it: with nothing dirty, the list of
        paths to check is empty, and an empty here-doc is one empty line — which
        resolved to the repository root, read as a directory, and bailed every
        clean repository out of the git tier into the tree read. The sidecar
        now says which tier answered, and a clean repository must say git."""
        self.assertIn_("fingerprint\tgit", self.led.read(STATE))

    def test_our_own_compiled_output_is_not_an_input(self):
        """.compiled is gitignored, and `--ignored` lists it file by file. Left
        in, the digest would be part of the fingerprint of the inputs that
        produce it, and no run could ever match the one before it."""
        state = self.led.read(STATE)

        self.assertIn_("inputs\t", state,
                       "a fingerprint that never settles is never stored")

    def test_a_commit_arriving_from_elsewhere_rebuilds(self):
        """The pull case: someone else wrote a record, and it arrives as a
        change to the committed tree."""
        before = self._stamp()
        self.led.add("pulled", "A record written on another machine.",
                     date="2026-01-06")
        _git(self.led.root, "add", "-A")
        _git(self.led.root, "commit", "-qm", "from elsewhere")

        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("written on another machine", self.led.digest())

    def test_an_uncommitted_edit_rebuilds(self):
        """Not everything arrives through a commit: a hand-edited record is
        dirty in the working tree, and its content is hashed on top of the tree
        object."""
        before = self._stamp()
        rec = self.led.root / "zamm-memory/knowledge/2026/2026-01-05-rule-22222.md"
        rec.write_text(rec.read_text().replace("A statement.", "An edited statement."))

        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("An edited statement.", self.led.digest())

    def test_a_second_edit_of_the_same_dirty_file_rebuilds(self):
        """The case the status TEXT alone cannot see: the file was already
        listed as modified, so only its content distinguishes the two edits."""
        rec = self.led.root / "zamm-memory/knowledge/2026/2026-01-05-rule-22222.md"
        rec.write_text(rec.read_text().replace("A statement.", "First edit."))
        self.led.compile()
        before = self._stamp()

        rec.write_text(rec.read_text().replace("First edit.", "Second edit."))
        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("Second edit.", self.led.digest())

    def test_an_empty_plan_directory_rebuilds(self):
        """git tracks no directories, but the plans tail renders an empty one
        as "Unknown: <slug> (no .plan.md file)" and the tally counts it. The
        fingerprint lists directories itself."""
        before = self._stamp()
        (self.led.root / "zamm-memory/active/plans/2026-01-06-ghost").mkdir(parents=True)

        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("2026-01-06-ghost", self.led.digest())

    def test_a_ledger_the_outer_repository_never_committed_reads_the_tree(self):
        """zamm-memory/ as its own repository, never added to the project's: to
        the outer git it is one untracked line, `?? zamm-memory/`, whatever
        happens inside. No committed tree means git has no answer, and the
        fingerprint reads the files instead."""
        import shutil
        shutil.rmtree(self.led.root / ".git")
        _git(self.led.root, "init", "-q")                      # outer: nothing committed
        _git(self.led.root / "zamm-memory", "init", "-q")      # inner: the ledger
        self.led.compile()
        before = self._stamp()
        rec = self.led.root / "zamm-memory/knowledge/2026/2026-01-05-rule-22222.md"
        rec.write_text(rec.read_text().replace("A statement.", "An edit inside the nested repository."))

        self.led.compile()

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("inside the nested repository", self.led.digest())

    def test_a_repository_nested_inside_a_committed_ledger_reads_the_tree(self):
        """The ledger is committed, and then a directory inside it becomes its
        own repository. To the outer git that directory is one line, `?? dir/`,
        and nothing inside it can move the line; the content pass would read a
        directory and hash nothing. A listed path that is a directory is the
        signal to read the tree.

        Honest note: this test passes without the guard too, on this platform,
        because reading the directory's path raises an I/O error that breaks
        the git tier and falls back by accident. The guard turns that accident
        into the rule; the test pins the behaviour, not the mechanism."""
        inner = self.led.root / "zamm-memory/knowledge/2027"
        inner.mkdir()
        _git(inner, "init", "-q")
        rec = inner / "2027-01-05-nested-44444.md"
        rec.write_text("---\ntype: memory\nscope: internals\nimportance: useful\n"
                       "durability: months\ncreated: 2027-01-05\nschema: 3\n---\n"
                       "A statement inside the nested repository.\n")
        self.led.compile(today="2027-02-01")
        before = self._stamp()
        rec.write_text(rec.read_text().replace("A statement inside", "An edit inside"))

        self.led.compile(today="2027-02-01")

        self.assertNotEqual(before, self._stamp())
        self.assertIn_("An edit inside the nested repository", self.led.digest())

    def test_an_unrelated_commit_does_not_rebuild(self):
        """The subtree object, not HEAD: committing code the ledger never saw
        must not cost a session the full compile."""
        before = self._stamp()
        (self.led.root / "src.py").write_text("print('hello')\n")
        _git(self.led.root, "add", "-A")
        _git(self.led.root, "commit", "-qm", "unrelated code")

        self.led.compile()

        self.assertEqual(before, self._stamp())


@unittest.skipUnless(shutil.which("git"), "git is not installed")
class TestAProjectBelowTheRepositoryTop(ZammTest):
    """A ZAMM project does not have to be the repository: it can be app/ inside
    a monorepo. Two git behaviours are relative to the working directory there
    and bit the first version: a pathspec prefixed with the repo-relative prefix
    named <prefix>/<prefix>/zamm-memory and matched nothing (the fast path was
    silently dead), and `ls-tree` filters its output by the working directory
    unless told --full-tree (a listing that could come back partial and be
    accepted as whole).
    """

    def setUp(self):
        super().setUp()
        self.repo = self.led.root
        # a prefix that is ALSO the name of a directory inside the ledger: the
        # case where an unfiltered ls-tree answered with the wrong subtree
        self.app = self.repo / "knowledge"
        self.app.mkdir()
        r = subprocess.run(("sh", str(SCRIPTS / "zamm-run.sh"), "--project-root",
                            str(self.app), "scaffold"),
                           capture_output=True, text=True, stdin=subprocess.DEVNULL)
        self.assertEqual(0, r.returncode, r.stderr)
        (self.app / "zamm-memory/knowledge/2026").mkdir(parents=True, exist_ok=True)
        _git(self.repo, "init", "-q")

    def _run(self, *args):
        return subprocess.run(
            ("sh", str(SCRIPTS / "internal/zamm-compile.sh"),
             "--project-root", str(self.app)) + args,
            capture_output=True, text=True)

    def test_an_uncommitted_edit_below_the_top_is_seen(self):
        rec = self.app / "zamm-memory/knowledge/2026/2026-01-05-rule-22222.md"
        rec.write_text(self._record_text("A statement."))
        _git(self.repo, "add", "-A")
        _git(self.repo, "commit", "-qm", "records")
        first = self._run()
        self.assertIn(first.returncode, (0, 2), first.stderr)
        self.assertIn_("(unchanged)", self._run().stdout,
                       "the git answer must engage below the top as well")

        rec.write_text(self._record_text("An edited statement."))
        r = self._run()

        self.assertNotIn_("(unchanged)", r.stdout)
        self.assertIn_("An edited statement.",
                       (self.app / "zamm-memory/.compiled/zamm-digest.md").read_text())

    @staticmethod
    def _record_text(headline):
        return ("---\ntype: memory\nscope: internals\nimportance: useful\n"
                "durability: months\ncreated: 2026-01-05\nschema: 3\n---\n"
                + headline + "\n")


class TestTheCompanionIsHeldToTheSameStandard(ZammTest):
    def test_a_degraded_sub_tree_reads_degraded_in_both_files(self):
        """The full rendering is the file a human is sent to. It read the
        backlog sidecar, which a degraded sub-pass still writes, and so rendered
        a healthy count line beside a session digest that said DEGRADED."""
        self.led.add("rule", "A statement.")
        self.led.add_idea("fine", "An idea.")
        self.led.write("zamm-memory/backlog/2026/2026-01-05-broke-abcde.md",
                       "---\ntype: memory\nscope: tooling\ncreated: 2026-01-05\n"
                       "schema: 9\n---\n\nBroken.\n")

        self.led.compile()

        self.assertIn_("Backlog: DEGRADED", self.led.digest())
        self.assertIn_("Backlog: DEGRADED", self.led.read(FULL))

    def test_a_failed_companion_is_not_certified_as_current(self):
        """The skip only checks that the companion EXISTS. If its rebuild failed
        and the fingerprint were stored anyway, every later run would call an
        old full rendering unchanged, forever."""
        self.led.add("rule", "A statement.")
        self.led.compile()

        self.led.add("second", "A statement the companion must learn about.",
                     date="2026-01-06")
        # A shell script that fails, not /usr/bin/false: the seam is run as
        # `sh <path>`, and what a shell does when handed a BINARY is not
        # portable — bash refuses with 126, dash on macOS exits 0, dash on
        # Linux reports a syntax error with 2, which reads as "published,
        # degraded". The first version of this test passed on exactly one of
        # the three.
        failing = self.led.root / "failing-companion.sh"
        failing.write_text("exit 7\n")
        r = self.led.compile(env={"ZAMM_COMPANION": str(failing)})

        self.assertIn_("could not be rebuilt", r.err + r.out)
        self.assertNotIn_("inputs\t", self.led.read(STATE),
                          "a run whose companion failed must not store a fingerprint")
        self.led.compile()
        self.assertIn_("the companion must learn about", self.led.read(FULL),
                       "the next run retries instead of skipping")

