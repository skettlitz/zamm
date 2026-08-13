# ZAMM tests

Regression suite for the toolchain. Standard library only — no pytest, no
virtualenv, no install step.

```sh
cd tests
python3 -m unittest discover -s . -t .        # fast suite
ZAMM_SLOW=1 python3 -m unittest discover -s . -t .   # adds perf checks
python3 -m unittest test_regressions -v       # one file, verbose
```

The suite shells out to real scripts for nearly every assertion, so it is
process-spawn bound: expect a couple of minutes for the ~390 tests on a
laptop, and one file in a few seconds. Run one file while iterating.

CI runs the full suite on ubuntu-latest and macos-latest — that matrix is
what actually verifies the README's portability claim, since the tests shell
out to the real scripts and exercise BSD vs GNU `awk` and `stat`.

## Layout

Tests reach the scripts through `zamm-run.sh` (`Ledger.zamm()` and the
`compile`/`check`/`scaffold`/`new_memory`/`archive`/`status` helpers), so the
suite exercises the documented surface. `Ledger.run()` addresses one script
directly and exists for the few cases that need it.

| File | Covers |
| --- | --- |
| `harness.py` | `Ledger` fixture builder, script runners, assertions |
| `test_happy.py` | normal operation: compile, supersede, tombstone, merge, votes, scaffold, archive |
| `test_contract.py` | record-contract validation, one case per family |
| `test_semantics.py` | exit codes, warnings, clock determinism |
| `test_golden.py` | whole-digest byte comparison over an authored ledger |
| `test_budgets.py` | digest/headline caps, guardrail admission, dormant vs unlisted |
| `test_surfaces.py` | `zamm-status.sh`, scaffold re-render, `--help`, help-vs-dispatcher parity |
| `test_settings.py` | chain-depth cap, `other` area + OTHER_MAX, generator flags, ledger edge paths |
| `test_dispatcher.py` | `zamm-run.sh` routing, root resolution, `status` view |
| `test_surface_v2.py` | memory list/show/archive, plan show/check/create, top-level check |
| `test_regressions.py` | one lock per defect reproduced on 2026-07-19 |
| `test_slow.py` | performance ceilings, source hygiene (opt-in) |

Then one file per invariant from `references/invariants.md`, plus the domain
rules that are not gates:

| File | Protects |
| --- | --- |
| `test_writes.py` | **G1** — records and plans are written in one atomic claim; what is validated is what lands, and a refusal writes nothing |
| `test_digest.py` | **G2** — the digest is derived and disposable: recomputed, never protected; concurrent compiles may lag it but the ledger loses nothing |
| `test_failclosed.py` | **G3** — absent is data, unreadable is an error, on every surface |
| `test_archival.py` | **G4** — archival is a rerunnable sequence, never clobbers history, and undoes only what no rerun would repair |
| `test_ledger_shape.py` | **G5** — real files and real directories only; plus the duplicate-id realities the invariants promise to tolerate |
| `test_graph.py` | supersession, votes and erasure semantics |
| `test_plan_validation.py` | `plan check` and plan/ledger cross-check rules |
| `test_cli_safety.py` | help, argument handling, version and migration gates |

| `fixtures/golden_digest.md` | committed expected output |

## What the suite is allowed to assert

`references/invariants.md` is the rubric. A test may lock one of the three
guarantees (truthful output, rerun-repairable failure, bytes never destroyed)
or one of the five gates. A test that locks a defence against a same-privilege
hostile process — an unpredictable temporary name, a narrowed check-to-use
window, an identity check placed last — is asserting a non-goal, and the
2026-08-08 round deleted about two dozen of them.

That deletion is the point rather than a regret: a test for an abandoned gate
is what makes over-engineering permanent, because the next person reads it as
a requirement. When a gate goes, its tests go with it, and any invariant worth
keeping is re-expressed against whatever replaced the gate.

## Rules for fixtures

**All committed fixtures are synthetic.** Nothing here derives from real
project data. `data/` in the repository root holds copied live project trees
used for exploratory dogfooding; it is gitignored and must stay that way —
scrubbing real data for reuse here would be a leak risk with no diagnostic
benefit over purpose-built fixtures.

**Suffixes come from the 30-symbol alphabet** `23456789abcdefghjkmnpqrstvwxyz`.
Counter-style suffixes like `00000` are rejected by the validator (`0` and
`1` are excluded as visually ambiguous). Use `harness.suffix(n)`.

**The clock is always pinned.** Ranking decays over real dates, so the
harness sets `ZAMM_TODAY` on every run. Both `zamm-compile.sh` and
`zamm-scaffold.sh` honour it; it is a test-only seam.

**Bugs found by exploratory dogfooding graduate to a minimized synthetic
case here** before the fix ships. Raw experience stays local; distilled
knowledge gets committed.

## Regenerating the golden digest

```sh
cd tests && ZAMM_UPDATE_GOLDEN=1 python3 -m unittest test_golden
```

Then read the diff carefully. An unexplained change means the selector
moved — diversity penalty, parsimony cost, guardrail admission, and the
headline budget all interact, and per-mechanic tests cannot catch that.

The suite used to be filed as `test_remediation.py` … `test_remediation8.py`,
one file per external review round. That is archaeology: it answers "what did
round 6 complain about", never "where is the test for erasure". The
2026-08-08 pass re-filed every one of those 239 tests under the behaviour it
protects, without deleting any of them. Round numbers survive only where a
class docstring explains what a defect actually was.

## Proving a regression lock is real

Tests in `test_regressions.py` were written *after* their fixes shipped,
which is weaker than red-first: such a test can accidentally encode the bug
as expected behaviour and pass forever while guarding nothing. Point the
suite at an older copy of the scripts to check that the locks actually fail:

```sh
# Extract the WHOLE skill tree at the old ref, not just scripts/. The scripts
# resolve their own skill directory as ../.. from themselves, so a bare
# scripts/ copy leaves scaffold unable to find references/ — and every
# scaffold-dependent test then dies with a FileNotFoundError that looks like
# a falsified lock but proves nothing.
rm -rf /tmp/old && mkdir -p /tmp/old
git archive <pre-fix-ref> | tar -x -C /tmp/old
cd tests && ZAMM_SCRIPTS_DIR=/tmp/old/scripts python3 -m unittest test_regressions
```

Against the pre-hardening scripts, 15 of the 17 locks fail. The two that
pass are guarding design choices rather than fixed defects, and their
docstrings say so.

This only applies to tests written against a behaviour that actually
changed. Most of `test_budgets.py`, `test_surfaces.py` and
`test_settings.py` cover behaviour that never broke, so there is nothing to
falsify against and they are ordinary tests — do not describe them as
regression locks. Checking is still worthwhile: the coverage-gap plan
claimed the guardrail-admission test was falsifiable, and running it against
the old compiler proved it was not.

## What is deliberately NOT covered yet

These are decisions, not oversights. The suite is scoped to happy paths, the
defects already proven real, and common edge cases:

- **Exhaustive contract tables.** One case per validation family, not one
  per rule.
- **Property-based DAG generation.** Random supersede graphs checked against
  invariants would find more than the hand-built graph cases do.
- **`durability: weeks`.** Identical code path to its four covered siblings.
- **Plan state transitions.** Deferred with the `zamm-plan` state machine
  they would test — asserting around prose-only rules is theater.
- **Case-fold collisions on a case-insensitive filesystem.** The test skips
  on macOS, because staging the collision requires a case-sensitive volume:
  the second file just overwrites the first. It runs on the Linux CI leg,
  which is required to run it (see below), and locally against a
  case-sensitive volume.

Closed by the 2026-07-20 coverage round: the digest budget constants,
`zamm-status.sh`, `--overwrite-templates`, `--help`, CHAINDEPTH_MAX,
OTHER_MAX and the `other` area, the generator flags, and four ledger edge
paths (erases-list spacing, case-fold, year-directory mismatch, duplicate id).

## Running on a case-sensitive filesystem

macOS is case-insensitive by default, so the case-fold collision check
cannot be staged there — the second file overwrites the first and the
compiler never sees a collision. A test that skips on every platform guards
nothing, so this is enforced from both ends:

- CI sets `ZAMM_REQUIRE_CASE_SENSITIVE=1` on the ubuntu leg, which turns the
  skip into a failure. If that leg ever stops being case-sensitive, the
  suite says so instead of quietly losing the check.
- Locally, run the whole suite against a case-sensitive volume:

```sh
hdiutil create -size 300m -fs "Case-sensitive APFS" -volname ZammCS /tmp/zammcs.dmg
hdiutil attach /tmp/zammcs.dmg
cd tests && TMPDIR=/Volumes/ZammCS ZAMM_SLOW=1 python3 -m unittest discover -s . -t .
hdiutil detach /Volumes/ZammCS      # when done
```

The full suite has been verified green under both filesystems — worth
repeating after any change to fixture layout, since case sensitivity is
exactly the kind of assumption that hides in a passing local run.

## Auditing coverage

When checking whether a setting is tested, grep for the **invocation**, not
the mention. A first audit pass reported `--overwrite-templates`,
`zamm-status.sh` and the `other` area as covered because each string
appeared in a docstring or a helper definition while no test ever ran
them.
