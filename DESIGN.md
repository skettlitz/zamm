# ZAMM design decisions

The decisions that are in force, and why. One paragraph each.

This file is the answer to "why is it like this". It sits between three others
and repeats none of them:

| File | Answers | Tense |
| --- | --- | --- |
| `README.md` | what ZAMM does and how to use it | present |
| **`DESIGN.md`** | **which choices shape it, and what each one costs** | **present** |
| `references/invariants.md` | what counts as a defect — the guarantees, gates and non-goals | present |
| `DELTAS.md` | how each decision was reached, including the ones later reversed | past |
| `scripts/internal/zamm-compile.sh` header | the tuning constants (caps, weights, half-lives) | present |

**Keeping it true.** When a decision changes, edit its entry here in place —
this file never carries history. The story of the change goes in `DELTAS.md`.
If the change moves a guarantee or a compromise, `references/invariants.md`
changes too. A choice that is not written down here is an implementation
detail, and may be changed without asking.

**Saying what kind of answer it is.** A decision rests on evidence (say when
it was measured and on what), on reasoning (which holds until someone breaks
the argument), on an external constraint (which changes when the environment
does), or on a judgement call (say whose, and when). A preference written as
if it were derived gets re-argued as a flawed proof; a number without a date
never gets re-measured. Where it matters, the entry says which.

---

## Principles

The few that decide most of the rest.

**Memory is advisory.** Records complement code, tests and documentation and
never outrank them. Agents verify before acting on anything high-impact. This
is why ZAMM can accept eventual consistency everywhere: a stale digest is a
nuisance, not an outage.

**Bytes are the only irreversible thing.** Records are never edited, moved in
place or deleted by ordinary operation; everything else is derived and
rebuildable. Care is spent in proportion: expensive on the write path,
cheap everywhere else. (`references/invariants.md`, guarantee 3.)

**Attention is the scarce resource, not bytes.** What memory costs is the
context every session spends before it starts work, so session start is the
most expensive surface in the system and gets the strictest editing. Length is
free only where nobody is obliged to read it.

**Say it once, where it renders.** A fact has one surface. Session start gets
what must be acted on now; a standing condition gets a reading on `status`; the
detail lives in a file. A notice that fires every session forever teaches the
reader to skip the notices that matter.

**Correctness has a stopping rule.** A finding that violates none of the three
guarantees in `references/invariants.md` is not a defect. Compromises are
allowed — if they are written down there and pinned by a test that asserts the
compromise itself, so the trade stays visible instead of becoming folklore.

**No runtime.** POSIX sh and POSIX awk, verified on stock macOS and Linux. A
dependency is a thing a user has to install before memory works, and memory
has to work in the first minute. The portability that bites is not awk
dialects but kernel limits: Linux caps one argv element at 128 KiB where macOS
caps only the total, so a large program goes to its interpreter as a file, and
a test holds every script to that.

---

## The ledger

**One record, one immutable file; the filename is the id.**
`YYYY-MM-DD-<slug>-<5 chars>`, the suffix drawn from a 30-symbol
reduced-Crockford alphabet. Two writers on two branches add two files, so git
never produces a conflicting hunk on memory. *Cost:* semantic conflicts still
exist; they surface as `Needs reconciliation` instead of as merge conflicts.

**Change by supersession, never by edit.** A correction is a new record
carrying `supersedes:`; a retirement is a tombstone; a redaction is an
`erasure` record. The graph, not the file, says what is current. *Cost:*
history accumulates — which is what archival is for.

**Erasure is an ordinary record.** It rides the same enumeration, validation
and fail-closed reads as everything else, rather than a special policy file
whose absence loosened policy. The erasure set is built before any graph pass,
and erasure is the one carve-out from rerun-fixes-it: an unreadable erasure
record stops publication outright.

**Four trees, one format, one boundary test.** Knowledge asserts a durable
fact; the backlog implies action but not now; the journal implies no action and
asserts no fact; a plan is current work. They share the record shape and the
graph and differ only in their lens. **Plans are the one mutable object** — a
directory with a living plan file — because work in progress is not a fact.

**A fixed set of eight areas, plus `other`.** Scopes are not negotiated per
project: a fixed vocabulary is what lets the selector balance a digest across
topics. `other` is a waiting room capped at five live records; `check` fails
past that.

**Votes ride on plan closure.** One votes record per closed plan, attached to
the exact records voted on and aggregated over their ancestor chain, so
competing heads never share each other's votes.

**Archive early.** Superseded and retired records leave `knowledge/` as soon as
they die. Archived records remain lineage nodes — edges and votes still apply —
so moving them changes no rank, and the archiver proves it: the digest below
its header must be byte-identical after the move. The path then carries a
signal: `knowledge/` is what is, `archive/` is what was.

---

## Writing

**Creation is one atomic claim.** The body arrives on stdin, is composed and
validated in a temporary file, and claims its final name with `ln`, which
refuses to clobber. No drafts, no locks, no rollback. (G1.)

**One validator.** `memory create`, `check` and the compiler share one
contract, so a write cannot land a record the compiler would refuse.

**Writes recompile as they land.** A session that wrote something leaves the
digest current behind it. This is what lets session start assume that most of
the time nothing has changed.

---

## Plans

**A plan carries its why.** Scope and Done-when are the record of doing;
`## Why` is the record of steering — what triggered it, who is hurt, what it
serves, what was rejected, what was traded, what it assumes — each line tagged
with its source (`human:`, `derived:`, `not revealed`). Without it a plan is a
to-do list, which gets completed after its reason has gone and has its
unforeseen forks decided by "easier". *Cost:* a few lines per plan, and the
discipline to derive the reason from the discussion rather than invent one.
Applies to plans created from 2026-09-13; older plans are valid without it and
nothing is backfilled.

**Approval asks whether the problem is gone.** Not whether the list is ticked.
The `problem:` line is written so that Done-when can say it no longer happens.

**A vanished problem or a failed assumption is grounds to stop.** Abandoning
on that basis is the plan working as designed, and is written as such.

---

## Ranking and the digest

**Score is declared once and prunes itself.** The author rates importance
(`guardrail`, `useful`, `minor`) and durability, which is a half-life; plan
outcomes vote. Below a floor a record goes dormant: unlisted, on disk,
greppable. Guardrails never decay. The numbers are tuning, and live only in the
compiler header.

**One ranked section, capped at 200.** Membership is decided by a greedy
selection that balances areas (a record enters through its least-crowded area
tag and pays a small cost for each extra tag). Guardrails are seated first and
may exceed the cap. *Replaced:* 75 full blocks plus 150 headline reminders,
which predated the budget and demoted records twice for one reason.

**The space budget buys expansion, never membership.** Every listed record
shows its headline; elaboration is bought in rank order until a soft character
ceiling is spent, and `+el` marks what did not fit. The ceiling itself, 80 000
characters (~20k tokens), is a judgement call — the human's, 2026-09-12, made
knowing that on a ~400-record ledger it fills: the merged section costs about
25% more context per session than the two layers did, in exchange for ~100
more records shown with their detail. Revisit if sessions start on a ledger
where the first useful record sits below the fold. Nothing is ever dropped to
make the number: a digest that sheds entries is lying about the ledger, so an
oversized one goes over and says so, in its own `Budget:` footer and on
`status` — never at session start.

**The digest is a file, not command output.** Harnesses cap command output and
replace the rest with a preview, silently; a session handed a truncated digest
believes it read memory. A path cannot be truncated.

**Two renderings, because two readers have opposite budgets.** `zamm-digest.md`
is bounded for an agent paying context per line. `zamm-digest-full.md` is the
same ledger with no cap, no budget and no decay floor, for a person searching.
Each says which it is. The full rendering is a second process, not a mode of
the first, so the file an agent reads never depends on what a human asked for.

---

## Session start

**One command, two lines, one file read.** What the project holds, and the
digest path. How to read the file is in the router the agent already loaded
from `AGENTS.md`, so the report does not repeat it.

**Defects: two more lines and a file.** The types with their counts, and the
path of `zamm-defects.md`, which explains each one and names its remedy. Every
startup writes it — so "none" is an answer, not an absence — and every other
compile deletes it, so a report that exists is current. An empty ledger is not
a defect; line one already says so.

**Standing state is not a defect.** A digest over its budget, or guardrails
past their soft cap, is a property of a ledger that has grown, and only a human
can resolve it. It reads on `status`, flagged against its limit, and nowhere
that fires every session.

**Compile only when the inputs moved.** The inputs are fingerprinted; a match
with the fingerprint stored beside the digest skips the compile.
*Under git*, git answers: the object ids of the committed ledger, plus the
content of whatever `status` reports as dirty, untracked or ignored. That is
the question as it actually arises — local writes recompile themselves, and
everything else arrives through a pull — and it stays flat as the ledger grows.
*Without git*, the tree is read and hashed. **Content, never mtime**, in both:
a stale digest that looks current is worse than a slow one. **Today is an
input**, because scores decay by date; that costs one compile per day. This
one is the agent's call (2026-09-12), taken against the human's stated
preference that decay could be ignored, on the reasoning that a digest whose
dormancy silently lags is the same stale-memory failure the content hash
exists to prevent. Revisit if one compile per day is ever noticed. Our own
`.compiled/` output is excluded from both tiers, or no run could ever match the
one before it.

**Reuse derived answers under the same rule.** If nothing moved, the last
compile's plan manifest and skill stamp are still correct, so session start
reads them instead of recomputing. Caches are opt-in per caller.

---

## Surfaces and channels

**One entrypoint.** Every operation goes through `zamm-run.sh`, because agent
harnesses allowlist by prefix and one entry is one permission rule.

**stderr only where nothing renders.** A compile that renders a digest puts its
errors and warnings in the digest (`## Degraded`) and prints nothing extra.
`--check` and the read-only seams (`--list-*`, `--export`) render nothing, so
they print everything; a fatal error prints on any path, because it aborts
before anything renders.

**Exit codes are a taxonomy.** 0 ok, 1 contract violation, 2 published but
degraded, 3 refused to publish, 4 unreadable, 5 version mismatch. A skipped
compile replays the code the last real compile earned, so a skip never reads
as a repair.

**`status` is read-only and trusts no cache.** It is the surface whose job is to
notice staleness, so it enumerates and hashes for itself every time and writes
nothing to the project.

---

## Correctness posture

The rubric is `references/invariants.md`: every output is a truthful reading of
some state the ledger had, every failure is repairable by rerunning, bytes are
never destroyed — with absent-versus-unreadable as the runtime discriminator,
and a same-user hostile process out of scope.

**Compromises in force**, each written up there and pinned by a test:

| Compromise | What it gives up | Why it is acceptable |
| --- | --- | --- |
| The fingerprint is not a validator | a record swapped for a symlink to an identical copy (untracked, or anywhere without git) can skip one refusal | `check` and `--force` never skip; every compile that runs still refuses; nothing from the symlink reaches a digest. Accepted by the human, 2026-09-12: "symlinks are unlikely" — a judgement about how the ledger is used, not a derivation |
| Skill-stamp cache keyed on mtimes | a skill file restored with an old timestamp can delay a drift notice | ordinary edits, checkouts and upgrades all move mtimes; `status` computes fresh |

---

## Where each kind of decision lives

| Kind | Home |
| --- | --- |
| a choice and its reason | here |
| a guarantee, gate, non-goal or compromise | `references/invariants.md` |
| a tuning constant | `scripts/internal/zamm-compile.sh`, commented header |
| the agent-facing rule | `references/protocol.md` and the per-tree layers |
| how a decision was reached | `DELTAS.md` |
