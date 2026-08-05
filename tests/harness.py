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
        plan=None,
        up=None,
        down=None,
        extra=None,
        sfx=None,
    ) -> str:
        """Write a well-formed record; returns its id."""
        if sfx is None:
            sfx = suffix(self._n)
            self._n += 1
        rid = f"{date}-{slug}-{sfx}"

        fm = [f"type: {type}"]
        if type == "memory":
            if scope:
                fm.append(f"scope: {scope}")
        if supersedes:
            if isinstance(supersedes, (list, tuple)):
                supersedes = ", ".join(supersedes)
            fm.append(f"supersedes: {supersedes}")
        if type == "memory":
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
        self.write(f"zamm-memory/knowledge/{date[:4]}/{rid}.md", text)
        return rid

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

    def shun(self, *ids):
        self.write(
            "zamm-memory/knowledge/shun.md", "".join(f"{i}\n" for i in ids)
        )

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

    def run(self, script, *args, today=PINNED_TODAY, env=None, cwd=None) -> Result:
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
            today, env, cwd,
        )

    def zamm(self, *args, today=PINNED_TODAY, env=None, cwd=None) -> Result:
        """Invoke the dispatcher — the documented entrypoint."""
        return self._exec(
            ["sh", str(SCRIPTS / "zamm-run.sh"), "--project-root", str(self.root), *args],
            today, env, cwd,
        )

    def _exec(self, argv, today, env, cwd) -> Result:
        e = dict(os.environ)
        if today is not None:
            e["ZAMM_TODAY"] = today
        else:
            e.pop("ZAMM_TODAY", None)
        e.update(env or {})
        cp = subprocess.run(
            argv, capture_output=True, text=True, env=e,
            cwd=str(cwd) if cwd else str(self.root),
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

    def new_memory(self, *args, **kw) -> Result:
        # Programmatic creation wants the record on disk immediately; the
        # draft/publish flow is the interactive default and is tested directly.
        return self.zamm("memory", "create", "--immediate", *args, **kw)

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
