"""Slow checks: skipped by default, run with ZAMM_SLOW=1.

Kept out of the default run so the fast suite stays usable in a tight edit
loop. CI sets ZAMM_SLOW=1.
"""

import os
import re
import time
import unittest
from pathlib import Path

from harness import SKILL_DIR, ZammTest

SLOW = os.environ.get("ZAMM_SLOW")

# Generous on purpose: this guards against a return to quadratic scaling, not
# against a few hundred milliseconds of drift. Measured 2026-07-20 on a dev
# laptop: ~1.1s after the Phase 4 work, ~9.9s before it. The ceiling is
# deliberately far above the isolated time (~1.7s): under full-suite load the
# same compile has been observed at 6.2s, and a load-flaky failure teaches the
# suite to be ignored. test_scaling_stays_roughly_linear is the real
# quadratic guard; this is only a catastrophic-regression backstop.
PERF_RECORDS = 4000
PERF_CEILING_SECONDS = 15.0


@unittest.skipUnless(SLOW, "set ZAMM_SLOW=1 to run")
class TestPerformance(ZammTest):
    def test_large_ledger_compiles_within_the_ceiling(self):
        """PRE-FIX: insertion sort plus a per-group rescan made compile time
        grow quadratically; 4000 records took ~10s and 10000 was unusable."""
        self.led.add_many(PERF_RECORDS)

        start = time.monotonic()
        r = self.led.compile()
        elapsed = time.monotonic() - start

        self.assertCode(r, 0)
        self.assertIn_(f"live={PERF_RECORDS}", self.header())
        self.assertLess(
            elapsed,
            PERF_CEILING_SECONDS,
            f"{PERF_RECORDS} records took {elapsed:.2f}s "
            f"(ceiling {PERF_CEILING_SECONDS}s) — check for a quadratic regression",
        )

    def test_scaling_stays_roughly_linear(self):
        """Doubling the ledger must not quadruple the time."""

        def timed(n):
            import tempfile

            from harness import Ledger

            with tempfile.TemporaryDirectory() as d:
                led = Ledger(d)
                led.add_many(n)
                start = time.monotonic()
                led.compile()
                return time.monotonic() - start

        small = timed(1000)
        large = timed(2000)
        # linear would be ~2x; allow generous headroom for noise, but 4x+
        # means the quadratic is back
        self.assertLess(
            large,
            small * 3.5 + 0.5,
            f"1000 records: {small:.2f}s, 2000 records: {large:.2f}s — superlinear",
        )


class TestSourceHygiene(unittest.TestCase):
    """Static checks that need no fixture."""

    # Linux caps ONE argv element at 128 KiB (MAX_ARG_STRLEN = 32 pages);
    # macOS caps only the total. A program passed inline to awk crosses it
    # silently on every Mac and fails on every Linux box with "Argument list
    # too long", exit 126 — which is what CI reported from 5760b9b onward, when
    # the compiler's awk reached 136 KB, while every local run stayed green.
    MAX_ARG_STRLEN = 131072

    def test_no_shell_argument_can_exceed_the_linux_limit(self):
        """Every single-quoted string in every script stays well under what
        Linux will pass as one argument. Single-quoted strings have no escapes,
        so a naive scan between quotes is exact."""
        for path in sorted((SKILL_DIR / "scripts").rglob("*.sh")):
            with self.subTest(script=path.name):
                text = path.read_text()
                longest, i = 0, 0
                while True:
                    a = text.find("'", i)
                    if a < 0:
                        break
                    b = text.find("'", a + 1)
                    if b < 0:
                        break
                    longest, i = max(longest, b - a - 1), b + 1
                self.assertLess(
                    longest, self.MAX_ARG_STRLEN // 2,
                    f"{path.name}: a {longest}-byte quoted string is headed for "
                    f"MAX_ARG_STRLEN; hand it to the program as a file instead",
                )

    def test_the_compiler_hands_awk_its_program_as_a_file(self):
        """The one program large enough to matter goes through -f from a
        quoted heredoc, never inline. The heredoc also retires the apostrophe
        hazard the old single-quoted form had (2026-07-20)."""
        text = (SKILL_DIR / "scripts" / "internal" / "zamm-compile.sh").read_text()

        self.assertIn("<<'ZAMM_AWK_PROGRAM'", text)
        self.assertIn('-f "$AWK_PROG" "$MANIFEST"', text)
        self.assertIn('"$TMP_FILE.awk"', text.split("trap 'set +e")[1].split("\n")[0],
                      "the program file must be in the cleanup trap")

    def test_scripts_are_executable_by_their_declared_interpreter(self):
        """Every script must parse under the shell its shebang names."""
        import subprocess

        # recursive: zamm-run.sh at the top of scripts/, the rest in internal/
        for path in sorted((SKILL_DIR / "scripts").rglob("*.sh")):
            with self.subTest(script=path.name):
                shebang = path.read_text().splitlines()[0]
                interp = "bash" if "bash" in shebang else "sh"
                cp = subprocess.run(
                    [interp, "-n", str(path)], capture_output=True, text=True
                )
                self.assertEqual(cp.returncode, 0, f"{path.name}: {cp.stderr}")
