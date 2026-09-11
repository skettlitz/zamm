#!/usr/bin/env python3
"""Parallel test runner — the default way to run this suite.

The suite shells out to the real scripts for nearly every assertion, so it is
process-spawn bound, not CPU bound: ~750 tests at ~0.25s each is ~3 minutes
of mostly waiting on `sh` and `awk`. Nothing about that is parallel-unsafe —
every test builds its own throwaway project root under TMPDIR and never
touches the repository — so the wait divides.

One test FILE per worker, rather than one test: unittest already sequences
within a file, the per-file spread is wide enough to keep workers fed, and a
file is the unit a failure report has to name anyway.

    python3 run.py                  # every file, 4 workers
    python3 run.py -j 8             # more workers
    python3 run.py --serial         # one at a time (bisecting a flake)
    python3 run.py test_digest      # just these files
    python3 run.py -v test_budgets  # ... and show unittest's own output

ZAMM_JOBS sets the default worker count. ZAMM_SLOW=1 adds the perf checks,
as it does for plain unittest.

Every file gets a timeout (--timeout, default 300s) and a file that blows it
is reported as a failure. A shell toolchain that blocks on stdin hangs
forever rather than failing, and a suite that can hang teaches you to kill it
on a stopwatch instead of reading it.
"""

import argparse
import concurrent.futures as cf
import glob
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RAN = re.compile(r"^Ran (\d+) tests? in", re.M)


def run_file(mod, timeout, verbose):
    """Run one test module in its own interpreter. Returns a result row."""
    argv = [sys.executable, "-m", "unittest", mod]
    if verbose:
        argv.append("-v")
    t0 = time.time()
    try:
        p = subprocess.run(argv, cwd=HERE, capture_output=True, text=True,
                           timeout=timeout)
        out, code = p.stderr + p.stdout, p.returncode
    except subprocess.TimeoutExpired as e:
        # Whatever the file managed to emit first, then the verdict. unittest
        # buffers its dots, so a hung file usually emits nothing at all —
        # re-run it with -v, which names each test as it starts, and the last
        # name printed is the one that never returned.
        out = e.stderr.decode(errors="replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        out += f"\n\nTIMED OUT after {timeout}s. Re-run with -v to see which test hung:"
        out += f"\n  python3 run.py -v --timeout {timeout} {mod}"
        code = -1
    m = RAN.search(out)
    return mod, code, time.time() - t0, int(m.group(1)) if m else 0, out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="test modules (default: all test_*.py)")
    ap.add_argument("-j", "--jobs", type=int,
                    default=int(os.environ.get("ZAMM_JOBS", "4")),
                    help="parallel workers (default 4, or $ZAMM_JOBS)")
    ap.add_argument("--serial", action="store_true", help="one file at a time")
    ap.add_argument("--timeout", type=int, default=300,
                    help="per-file timeout in seconds (default 300)")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="pass -v to unittest and print each file's output")
    args = ap.parse_args()

    mods = [f[:-3] if f.endswith(".py") else f for f in args.files]
    if not mods:
        mods = sorted(os.path.basename(p)[:-3]
                      for p in glob.glob(os.path.join(HERE, "test_*.py")))
    if not mods:
        sys.exit("no test files found")
    jobs = 1 if args.serial else max(1, min(args.jobs, len(mods)))

    print(f"{len(mods)} files, {jobs} worker{'s' if jobs > 1 else ''}"
          f"{' (ZAMM_SLOW=1)' if os.environ.get('ZAMM_SLOW') else ''}")

    rows, t0 = [], time.time()
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        futs = {ex.submit(run_file, m, args.timeout, args.verbose): m for m in mods}
        for fut in cf.as_completed(futs):
            row = fut.result()
            rows.append(row)
            mod, code, dur, n, out = row
            mark = "ok  " if code == 0 else "FAIL"
            print(f"  {mark} {dur:6.1f}s  {n:4d}  {mod}", flush=True)
            if args.verbose:
                print(out)

    wall = time.time() - t0
    bad = [r for r in rows if r[1] != 0]
    total = sum(r[3] for r in rows)
    cpu = sum(r[2] for r in rows)

    if bad:
        for mod, _, _, _, out in sorted(bad):
            print(f"\n{'=' * 70}\n{mod}\n{'=' * 70}\n{out.rstrip()}")

    print(f"\n{total} tests in {wall:.1f}s wall ({cpu:.0f}s serial, "
          f"{cpu / wall if wall else 0:.1f}x)")
    if bad:
        print(f"FAILED: {', '.join(sorted(m for m, *_ in bad))}")
    else:
        print("OK")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
