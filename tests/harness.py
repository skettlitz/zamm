"""Test harness for the ZAMM toolchain.

Every fixture is synthetic and built per test in a temporary directory. No
test reads or writes this repository's own ledger, and no fixture is derived
from real project data (see tests/README.md).

The scripts under test stay POSIX sh / bash; only this harness is Python, and
it uses the standard library alone so `python3 -m unittest` works on a fresh
clone and in CI with no setup step.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
# ZAMM_SCRIPTS_DIR points the suite at a different copy of the scripts. Used
# to prove the regression locks actually fail against the pre-fix toolchain —
# a test written after its fix can otherwise encode the bug as expected
# behaviour and pass forever without guarding anything.
SCRIPTS = Path(os.environ.get("ZAMM_SCRIPTS_DIR") or (SKILL_DIR / "scripts"))

# The uniqueness alphabet the compiler enforces: Crockford base32 minus the
# visually ambiguous 0 1 i l o u. Counter-style suffixes ("00000") are
# rejected, so fixtures must draw from this.
ALPHABET = "23456789abcdefghjkmnpqrstvwxyz"

# Ranking decays over real dates, so every run pins the clock. Both
# zamm-compile.sh and zamm-scaffold.sh honour ZAMM_TODAY (test-only).
PINNED_TODAY = "2026-07-19"

BASH_SCRIPTS = {"zamm-scaffold.sh", "zamm-archive.sh", "zamm-status.sh"}

# chmod 000 does not deny access to root: with geteuid()==0 the kernel grants
# read/traverse regardless of permission bits, so permission-based fault
# injection never fires and the "unreadable" branch under test is unreachable.
# Decorate such tests with this so a root container (common in CI images)
# skips them with the mechanism named instead of failing confusingly.
needs_permission_bits = unittest.skipIf(
    hasattr(os, "geteuid") and os.geteuid() == 0,
    "permission-bit fault injection cannot deny access to root "
    "(geteuid()==0 bypasses chmod 000)",
)

# memory digest prints the digest, so tests that assert on stdout use
# Ledger.digest() (the file) rather than the command output.

# Exit codes carry three distinct meanings; conflating 1 and 3 would hide the
# difference between "invalid records" and "refused to publish".
EXIT_OK = 0
EXIT_CONTRACT = 1
EXIT_DEGRADED = 2       # digest published, but a Degraded section is present
EXIT_REFUSED_PUBLISH = 3
EXIT_UNREADABLE = 4     # ledger enumeration failed; previous digest untouched
EXIT_VERSION = 5        # dispatcher refused: project protocol version mismatch


def suffix(n: int) -> str:
    """A deterministic valid 5-char suffix, so record ids are stable."""
    s = ""
    for _ in range(5):
        s = ALPHABET[n % len(ALPHABET)] + s
        n //= len(ALPHABET)
    return s


class Result:
    def __init__(self, cp: subprocess.CompletedProcess):
        self.code = cp.returncode
        self.out = cp.stdout
        self.err = cp.stderr

    @property
    def output(self) -> str:
        """stdout + stderr, for assertions that do not care which stream."""
        return self.out + self.err

    def __repr__(self) -> str:  # shows up in assertion failures
        return (
            f"<Result code={self.code}\n"
            f"  stdout: {self.out.strip()!r}\n"
            f"  stderr: {self.err.strip()!r}>"
        )


class Ledger:
    """A throwaway ZAMM project tree."""

    def __init__(self, root):
        self.root = Path(root)
        self._n = 0
        for d in (
            "zamm-memory/knowledge",
            "zamm-memory/active/plans",
            "zamm-memory/archive/plans",
        ):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        # A scaffolded project always carries a VERSION; the dispatcher's
        # version gate refuses operational commands without it. Tests that
        # exercise a missing/mismatched version override this with .version()
        # or by deleting the file.
        (self.root / "zamm-memory/VERSION").write_text("3\n")

    # ---------------- authoring ----------------

    def add(
        self,
        slug,
        body="A synthetic statement for testing.",
        *,
        date="2026-01-05",
        type="memory",
        scope="contracts/api",
        importance="useful",
        durability="years",
        supersedes=None,
        erases=None,
        plan=None,
        up=None,
        down=None,
        extra=None,
        sfx=None,
        tree="knowledge",
    ) -> str:
        """Write a well-formed record; returns its id."""
        if sfx is None:
            sfx = suffix(self._n)
            self._n += 1
        rid = f"{date}-{slug}-{sfx}"

        fm = [f"type: {type}"]
        if type in ("memory", "digest"):
            if scope:
                fm.append(f"scope: {scope}")
        if supersedes:
            if isinstance(supersedes, (list, tuple)):
                supersedes = ", ".join(supersedes)
            fm.append(f"supersedes: {supersedes}")
        if erases:
            if isinstance(erases, (list, tuple)):
                erases = ", ".join(erases)
            fm.append(f"erases: {erases}")
        if type in ("memory", "digest"):
            if importance:
                fm.append(f"importance: {importance}")
            if durability:
                fm.append(f"durability: {durability}")
        if plan:
            fm.append(f"plan: {plan}")
        if type == "votes":
            fm.append(f"up: {up or ''}")
            fm.append(f"down: {down or ''}")
        for k, v in (extra or {}).items():
            fm.append(f"{k}: {v}")
        fm.append(f"created: {date}")
        fm.append("schema: 3")

        text = "---\n" + "\n".join(fm) + "\n---\n"
        if type != "votes":
            text += body.rstrip("\n") + "\n"
        self.write(f"zamm-memory/{tree}/{date[:4]}/{rid}.md", text)
        return rid

    def add_idea(self, slug, body="A synthetic idea for testing.", *,
                 scope="tooling", durability="months", marked=None, **kw) -> str:
        """Write a well-formed backlog record; returns its id.

        Ideas are ordinary records in the backlog tree — same writer, other
        root. `marked` lands as the marked: frontmatter key (a date or "no").
        """
        extra = dict(kw.pop("extra", None) or {})
        if marked is not None:
            extra["marked"] = marked
        return self.add(slug, body, tree="backlog", scope=scope,
                        durability=durability, extra=extra, **kw)

    def add_episode(self, slug, body="A synthetic episode for testing.", *,
                    scope="other", durability="weeks", cue=None, salience=None,
                    axes=None, time=None, agent=None, user=None, **kw) -> str:
        """Write a well-formed journal ENTRY; returns its id.

        Episodes are ordinary records in the journal tree. The journal-only
        keys land as frontmatter (axes is a {name: value} dict, values as
        strings so a bipolar sign survives).
        """
        extra = dict(kw.pop("extra", None) or {})
        if cue is not None:
            extra["cue"] = cue
        if salience is not None:
            extra["salience"] = salience
        if time is not None:
            extra["time"] = time
        if agent is not None:
            extra["agent"] = agent
        if user is not None:
            extra["user"] = user
        for name, value in (axes or {}).items():
            extra[f"axis-{name}"] = value
        return self.add(slug, body, tree="journal", scope=scope,
                        durability=durability, extra=extra, **kw)

    def add_elevation(self, kind, covers, body="A synthetic elevation.", *,
                      slug=None, scope="other", durability="years", **kw) -> str:
        """Write a journal ELEVATION (type: digest); returns its id."""
        extra = dict(kw.pop("extra", None) or {})
        extra["digest"] = kind
        extra["covers"] = covers
        return self.add(slug or f"{kind}-{covers}", body, tree="journal",
                        type="digest", scope=scope, durability=durability,
                        extra=extra, **kw)

    def add_watermark(self, through, body=None, *, pass_=None, date=None,
                      durability="weeks", **kw) -> str:
        """Write a journal WATERMARK (reviewed-through claim); returns its id."""
        extra = dict(kw.pop("extra", None) or {})
        extra["reviewed-through"] = through
        if pass_ is not None:
            extra["pass"] = pass_
        return self.add(f"reviewed-through-{through}",
                        body or f"Reviewed through {through}.",
                        tree="journal", scope="other", durability=durability,
                        date=date or through, extra=extra, **kw)

    def draft(self, slug, body="A synthetic statement for testing.", **kw) -> str:
        """Write an <id>.md.draft — a record someone chose to compose over
        several edits rather than pass to `memory create` in one go. Returns
        the absolute draft path. `memory create` never produces one."""
        rid = self.add(slug, body, **kw)
        date = rid[:10]
        live = self.root / f"zamm-memory/knowledge/{date[:4]}/{rid}.md"
        draft = live.with_suffix(".md.draft")
        live.rename(draft)
        return str(draft)

    def add_many(self, count, *, slug="rec", **kw) -> list:
        return [self.add(slug, f"Record number {i}.", **kw) for i in range(count)]

    def write(self, relpath, content):
        """Write any file verbatim — the escape hatch for malformed fixtures."""
        p = self.root / relpath
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        return p

    def read(self, relpath) -> str:
        return (self.root / relpath).read_text()

    def exists(self, relpath) -> bool:
        return (self.root / relpath).exists()

    def erase(self, *ids, slug="redacted", date="2026-01-07",
              reason="Synthetic erasure for testing.", sfx=None) -> str:
        """Redact ids the v3 way: an erasure RECORD naming them.

        Replaces the old shun.md list — erasure now rides the same
        enumeration, validation and symlink handling as every other record,
        and carries its reason.
        """
        return self.add(slug, reason, date=date, type="erasure",
                        scope=None, importance=None, durability=None,
                        erases=list(ids), sfx=sfx)

    def delete(self, rid, year="2026"):
        (self.root / f"zamm-memory/knowledge/{year}/{rid}.md").unlink()

    def add_plan(self, slug, status="Implementing", title=None, valid=True):
        """Write a plan fixture.

        valid=True fills whatever the status requires, so terminal plans are
        archivable — `plan archive` refuses plans that fail `plan check`.
        Pass valid=False to build a deliberately malformed fixture.
        """
        head = [f"# {title or slug}", "", f"Status: {status}"]
        # Abandoned included: a terminal plan the suite archives represents work
        # that was done and then abandoned, so it carries execution context (and
        # the retrospective below). The checker's work-happened heuristic then
        # requires that retrospective, which this fixture supplies.
        if valid and status in ("Implementing", "Review", "Done", "Abandoned"):
            head += ["Execution-context-before: synthetic fixture",
                     "Complexity-forecast: gecko"]
        head += ["Last updated: 2026-01-05", ""]
        # A well-formed plan carries scope; the check requires non-empty scope
        # once a plan leaves Draft. Omitting it here used to teach the suite
        # that a scope-less Implementing plan was valid (review finding 3).
        if valid:
            head += ["Scope:", "* In: synthetic in-scope note.",
                     "* Out: nothing.", ""]
        head += ["## Done-when", ""]
        head += ["- [x] something" if (valid and status in ("Review", "Done"))
                 else "- [ ] something", ""]
        if valid and status in ("Review", "Done", "Abandoned"):
            head += ["## Learnings", "", "- Synthetic fixture learning.", ""]
            if status == "Abandoned":
                # a worked-on abandon needs a Loose-ends rationale/cleanup note
                head += ["## Loose ends", "",
                         "- Synthetic abandonment rationale.", ""]
            head += ["Execution-friction-after: none",
                     "Complexity-felt: gecko",
                     "Complexity-delta: as-expected"]
        if valid and status == "Done":
            head += ["Done-approved-by: fixture",
                     "Done-approved-at: 2026-01-05",
                     "Done-approval-evidence: synthetic"]
        self.write(
            f"zamm-memory/active/plans/{slug}/{slug}.plan.md",
            "\n".join(head) + "\n",
        )

    def version(self, value):
        self.write("zamm-memory/VERSION", f"{value}\n")

    # ---------------- running ----------------

    def run(self, script, *args, today=PINNED_TODAY, env=None, cwd=None,
            stdin=None) -> Result:
        """Invoke one underlying script directly.

        The escape hatch: use it to address a script the dispatcher wraps
        (asserting its own --help, for instance). Everything that models
        normal use should go through zamm() instead, so the suite exercises
        the documented surface. Internal scripts live in scripts/internal/;
        only zamm-run.sh sits at the top of scripts/.
        """
        interp = "bash" if script in BASH_SCRIPTS else "sh"
        base = SCRIPTS if script == "zamm-run.sh" else SCRIPTS / "internal"
        return self._exec(
            [interp, str(base / script), "--project-root", str(self.root), *args],
            today, env, cwd, stdin,
        )

    def zamm(self, *args, today=PINNED_TODAY, env=None, cwd=None,
             stdin=None) -> Result:
        """Invoke the dispatcher — the documented entrypoint."""
        return self._exec(
            ["sh", str(SCRIPTS / "zamm-run.sh"), "--project-root", str(self.root), *args],
            today, env, cwd, stdin,
        )

    def _exec(self, argv, today, env, cwd, stdin=None) -> Result:
        e = dict(os.environ)
        if today is not None:
            e["ZAMM_TODAY"] = today
        else:
            e.pop("ZAMM_TODAY", None)
        e.update(env or {})
        cp = subprocess.run(
            argv, capture_output=True, text=True, env=e,
            cwd=str(cwd) if cwd else str(self.root),
            # "" not None: with no stdin the generator sees a pipe at EOF and
            # reports an empty body, which is the honest behaviour but makes
            # every caller pass a body explicitly. Callers that want the
            # no-stdin case pass stdin=None through run()/zamm() directly.
            input=stdin if stdin is not None else "",
        )
        return Result(cp)

    # --- the documented surface, one helper per command ---

    def compile(self, *args, **kw) -> Result:
        """memory digest — kept as compile() because most tests only care
        that the digest was rebuilt, not that it was printed."""
        r = self.zamm("memory", "digest", *args, **kw)
        return r

    def check(self, **kw) -> Result:
        return self.zamm("memory", "check", **kw)

    def scaffold(self, *args, **kw) -> Result:
        return self.zamm("scaffold", *args, **kw)

    def new_memory(self, *args, body=None, validate=False, **kw) -> Result:
        """memory create — one atomic step, body on stdin.

        Validation is OFF by default: most fixtures build a deliberately
        broken ledger, where a validating create would (correctly) refuse.
        Tests that exercise the validation gate pass validate=True.
        """
        a = list(args)
        if not validate:
            a.append("--no-validate")
        if body is None:
            body = "Synthetic record body for testing.\n"
        return self.zamm("memory", "create", *a, stdin=body, **kw)

    def memory_publish(self, *args, **kw) -> Result:
        return self.zamm("memory", "publish", *args, **kw)

    def memory_list(self, *args, **kw) -> Result:
        return self.zamm("memory", "list", *args, **kw)

    def memory_show(self, *args, **kw) -> Result:
        return self.zamm("memory", "show", *args, **kw)

    def memory_archive(self, *args, **kw) -> Result:
        return self.zamm("memory", "archive", *args, **kw)

    def archive(self, *args, **kw) -> Result:
        return self.zamm("plan", "archive", *args, **kw)

    def plan_list(self, *args, **kw) -> Result:
        return self.zamm("plan", "list", *args, **kw)

    def plan_show(self, *args, **kw) -> Result:
        return self.zamm("plan", "show", *args, **kw)

    def plan_check(self, *args, **kw) -> Result:
        return self.zamm("plan", "check", *args, **kw)

    def plan_create(self, *args, **kw) -> Result:
        return self.zamm("plan", "create", *args, **kw)

    def status(self, *args, **kw) -> Result:
        return self.zamm("status", *args, **kw)

    def backlog(self, *args, **kw) -> Result:
        return self.zamm("backlog", *args, **kw)

    def backlog_lens(self) -> str:
        return self.read("zamm-memory/.compiled/backlog.md")

    def journal(self, *args, **kw) -> Result:
        return self.zamm("journal", *args, **kw)

    def journal_lens(self) -> str:
        return self.read("zamm-memory/.compiled/journal.md")

    def journal_state(self) -> str:
        return self.read("zamm-memory/.compiled/journal-state.tsv")

    def check_all(self, *args, **kw) -> Result:
        return self.zamm("check", *args, **kw)

    def digest(self) -> str:
        return self.read("zamm-memory/.compiled/memory.md")

    def digest_section(self, name) -> str:
        """Text of one '## <name>' section, up to the next '## '."""
        lines = self.digest().splitlines()
        out, inside = [], False
        for ln in lines:
            if ln.startswith("## "):
                if inside:
                    break
                inside = ln.startswith(f"## {name}")
                continue
            if inside:
                out.append(ln)
        return "\n".join(out)

    def has_section(self, name) -> bool:
        """True when the digest has a '## <name>' heading.

        Substring checks are unsafe here: the digest legend names sections
        it is explaining ("~ = contested head, also listed under Needs
        reconciliation"), so a bare `in` match hits boilerplate.
        """
        return any(
            ln.startswith(f"## {name}") for ln in self.digest().splitlines()
        )

    def entries(self) -> list:
        """Record ids the digest actually lists, in order."""
        import re

        return re.findall(r"\[([0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+)", self.digest())


class ZammTest(unittest.TestCase):
    """Base case: a fresh synthetic project tree per test."""

    def require_case_sensitive(self):
        """Skip unless the fixture filesystem can hold two names differing
        only by case — and refuse to skip silently.

        A test that skips everywhere guards nothing, so CI sets
        ZAMM_REQUIRE_CASE_SENSITIVE=1 on the Linux leg, which turns the skip
        into a failure. Locally on APFS, run against a case-sensitive volume:

            hdiutil create -size 300m -fs "Case-sensitive APFS" \\
                -volname ZammCS /tmp/zammcs.dmg
            hdiutil attach /tmp/zammcs.dmg
            TMPDIR=/Volumes/ZammCS python3 -m unittest discover -s . -t .
        """
        probe = self.led.root / "CaseProbe"
        probe.write_text("x")
        case_sensitive = not (self.led.root / "caseprobe").exists()
        probe.unlink()
        if case_sensitive:
            return
        if os.environ.get("ZAMM_REQUIRE_CASE_SENSITIVE"):
            self.fail(
                "ZAMM_REQUIRE_CASE_SENSITIVE is set but TMPDIR is on a "
                "case-insensitive filesystem, so this check cannot run"
            )
        self.skipTest("filesystem is case-insensitive; cannot stage the collision")

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.led = Ledger(tmp.name)

    # -------- assertions with useful failure output --------

    def assertCode(self, result, expected, msg=""):
        self.assertEqual(
            result.code,
            expected,
            f"{msg}\nexpected exit {expected}, got {result.code}\n{result!r}",
        )

    def assertIn_(self, needle, haystack, msg=""):
        self.assertIn(needle, haystack, f"{msg}\nmissing {needle!r} in:\n{haystack}")

    def assertNotIn_(self, needle, haystack, msg=""):
        self.assertNotIn(
            needle, haystack, f"{msg}\nunexpected {needle!r} in:\n{haystack}"
        )

    def header(self) -> str:
        return self.led.digest().splitlines()[0]


# ---------------------------------------------------------------------
# Shared fixtures for the behaviour suites
#
# These lived as duplicated module-level helpers across the old
# test_remediation*.py files. They are inputs, not assertions, so they belong
# with the rest of the fixture builders.
# ---------------------------------------------------------------------

def ignore_rules(text):
    """The ACTIVE rules of a gitignore-syntax file: comments and blank lines
    dropped.

    Assertions about ignore files have to parse, not substring-match: the
    scaffold blocks are mostly prose now (".cursorignore" carries a note
    explaining why ZAMM writes no rules there), so a raw `in` check passes on
    a rule that is only mentioned in a comment — and a raw `not in` check
    fails on the explanation itself.
    """
    return [ln.strip() for ln in text.splitlines()
            if ln.strip() and not ln.strip().startswith("#")]


RUN = str(SCRIPTS / "zamm-run.sh")

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
    ["help", "journal"], ["journal", "--help"], ["journal", "add", "--help"],
    ["journal", "digest", "--help"], ["journal", "settle", "-h"],
]


BROKEN_RECORD = (
    "---\ntype: memory\nscope: contracts/api\nimportance: useful\n"
    "durability: years\ncreated: 2026-01-06\n---\nNo schema line.\n"
)


def review_plan(upvotes, status="Review", extra_head=""):
    """A plan file text that passes plan check at the given status."""
    head = f"# P\nStatus: {status}\n{extra_head}"
    head += ("Execution-context-before: x\nComplexity-forecast: gecko\n"
             f"Memory-upvotes: {upvotes}\nLast updated: 2026-07-19\n\n"
             "Scope:\n* In: x\n* Out: nothing.\n\n"
             "## Done-when\n- [x] d\n\n## Learnings\n- L.\n\n")
    if status == "Abandoned":
        head += "## Loose ends\n\n- Abandoned for a synthetic reason.\n\n"
    head += ("Execution-friction-after: n\nComplexity-felt: gecko\n"
             "Complexity-delta: as-expected\n")
    if status == "Done":
        head += ("Done-approved-by: fixture\nDone-approved-at: 2026-07-19\n"
                 "Done-approval-evidence: synthetic\n")
    return head


ARCHIVED_MEMORY = (
    "---\ntype: memory\nscope: internals\nimportance: useful\n"
    "durability: months\ncreated: {date}\nschema: 3\n{extra}---\n{body}\n"
)


def archived_record(date, body, supersedes=""):
    extra = f"supersedes: {supersedes}\n" if supersedes else ""
    return ARCHIVED_MEMORY.format(date=date, extra=extra, body=body)


class ShimTest(ZammTest):
    def _shim_dir(self):
        d = self.led.root / ".shims"
        d.mkdir(exist_ok=True)
        return d

    def _write_exec(self, path, body):
        path.write_text(body)
        path.chmod(0o755)
        return path

    def _shim_env(self, extra=None):
        e = {"PATH": f"{self._shim_dir()}:{os.environ['PATH']}"}
        e.update(extra or {})
        return e

    def _draft(self, slug="fresh", body="A fresh synthetic statement.\n"):
        draft = self.led.draft(slug, body)
        rid = os.path.basename(draft)[: -len(".md.draft")]
        return draft, rid
