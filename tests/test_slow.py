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
# laptop: ~1.1s after the Phase 4 work, ~9.9s before it.
PERF_RECORDS = 4000
PERF_CEILING_SECONDS = 5.0


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

    def test_no_apostrophe_inside_the_awk_program(self):
        """zamm-compile.sh embeds its awk program in a single-quoted shell
        string, so ONE apostrophe — even in a comment — terminates the string
        and the shell tries to execute awk source. This happened on
        2026-07-20; see 2026-07-20-awk-block-apostrophe-hazard-dzpda.
        """
        text = (SKILL_DIR / "scripts" / "internal" / "zamm-compile.sh").read_text()
        lines = text.splitlines()

        starts = [i for i, ln in enumerate(lines) if ln.rstrip().endswith("awk \\")]
        self.assertTrue(starts, "could not locate the awk invocation")
        # the program opens on the first line after the invocation that ends
        # in a quote, and closes on the first line that starts with one
        begin = next(
            i for i in range(starts[0], len(lines)) if lines[i].rstrip().endswith("'")
        )
        end = next(
            (i for i in range(begin + 1, len(lines)) if lines[i].startswith("'")), None
        )
        self.assertIsNotNone(end, "could not locate the end of the awk program")

        offenders = [
            (i + 1, lines[i])
            for i in range(begin + 1, end)
            if "'" in lines[i]
        ]
        self.assertEqual(
            offenders,
            [],
            "apostrophe inside the awk block would break the script:\n"
            + "\n".join(f"  line {n}: {t}" for n, t in offenders),
        )

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
