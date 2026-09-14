# Plans — maintenance (status transitions and close-out)

Bookkeeping is event-driven: apply a transition's requirements when the
transition is attempted or requested — setting `Status:`, or a human review
outcome — not only at session end. Session End is the backstop that catches
what was missed.

Allowed transitions: `Draft -> Implementing | Abandoned`;
`Implementing -> Blocked | Review | Abandoned`;
`Blocked -> Implementing | Abandoned`; `Review -> Implementing | Done`.
`Done` only via `Review -> Done` after explicit human approval. `Done` and
`Abandoned` are terminal: never resume a terminal plan; start a new one.
`Blocked` is NOT terminal and is never archive-ready.

## Requirements per transition

- `Draft -> Implementing`: Scope and Done-when filled;
  `Execution-context-before` and `Complexity-forecast` filled.
- `Draft -> Abandoned`: rationale under `## Loose ends`. A never-started
  draft needs nothing more; the checker asks for the full retrospective only
  once work happened (an `Execution-context-before` was filled, or a
  Done-when item checked).
- `Implementing -> Review`:
  1. Every Done-when item checked; remove items that became obsolete. Where
     the plan has a `## Why`, its `problem:` line is the item that matters:
     say under Done-when that it no longer happens, and how that was seen.
  2. Reconcile stale or conflicting live records touched by this work —
     supersede them (`memory-maintenance.md`) — before adding new
     learnings.
  3. Fill `## Learnings` (required; if nothing durable emerged, say so with
     a reason). Include why it ended this way: what moved in the `## Why`
     during the work — a trigger that turned out to be a symptom, an
     assumption that failed, an approach rejected mid-flight and why.
  4. Distill durable learnings into knowledge records
     (`memory-writing.md`), superseding stale ones.
  5. Fill `Memory-upvotes` / `Memory-downvotes` with the record ids that
     helped or misled, and write ONE votes record mirroring them —
     `memory create --type votes --plan <plan-dir> --up <ids> --down <ids>
     <slug>`, empty body. Skip only when both lists are empty.
  6. Fill `Execution-friction-after` (what actually cost time: tooling
     failures, flaky steps, missing docs, rework, waiting on answers),
     `Complexity-felt` (same animal scale) and `Complexity-delta`
     (`lighter|as-expected|heavier`).
  7. Ask the human for approval before `Done`. The question to put is
     whether the problem in `## Why` is gone, with the evidence — not
     whether the list is ticked.
- `Implementing -> Blocked`: `plan block --kind <class> <slug> '<sentence>'`,
  detail paragraph on stdin. One dated entry lands in `## Blocked-on` and the
  status flips. That is the whole ceremony, on purpose — see "Blocked" below.
- `Blocked -> Implementing`: `plan unblock <slug> '<how it cleared>'`. The open
  entry gains a `Resolved <date>:` line and the status returns; the entry
  itself is never deleted.
- `Blocked -> Abandoned`: the obstruction turned out to be fatal. Same
  requirements as `Implementing -> Abandoned` below — a blocked plan already
  passed through Implementing, so work happened. Do NOT `plan unblock` first:
  nothing cleared, and a `Resolved` line would say otherwise. `Abandoned` is
  the one status allowed to carry an open entry, and the digest keeps printing
  it — the block is the reason the plan died.
- `Implementing -> Abandoned`: check off what was completed; record the
  rationale and cleanup notes; then the same distillation, learnings, votes
  and telemetry as for Review. A `## Why` whose problem has gone by other
  means, or whose `assumes:` line has failed, is a legitimate rationale —
  write it as such rather than executing the plan to completion.
- A fork the plan did not anticipate, in any status: re-read `## Why` before
  choosing, and append the choice and its reason to the section (`alternatives:`,
  `enough:` or `assumes:`) so the next session inherits it.
- `Review -> Implementing`: capture the requested changes and re-open the
  relevant Done-when items.
- `Review -> Done`: only after explicit human approval while in Review. Fill
  `Done-approved-by`, `Done-approved-at` and `Done-approval-evidence`; set
  `Status: Done`; finish the file edits; then run `plan archive`.

## Blocked

`Blocked` says one thing to everyone reading the digest — human and agent —
"I cannot continue, and the reason will outlive this session". A human says
"start implementing"; the agent finds it cannot; it records why and sets the
status, instead of stopping silently and leaving a plan that still reads
`Implementing` with a stale date.

Entering costs exactly one sentence, and that is deliberate. Every other
transition here carries a retrospective, and a transition that costs anything
at the moment you hit a wall is a transition nobody makes.

Each entry names **who clears it** — the one thing that tells a reader whether
it is their move:

| class | who clears it |
| --- | --- |
| `human` | a person on this team: a decision, an answer, an approval, access |
| `plan:<plan-id>` | another plan in this ledger, named — verified to exist, and `plan check` warns once it lands |
| `external` | outside this team: an upstream release, a deploy, another team's queue |
| `defect` | nobody yet: something is broken and no one has committed to fixing it |

The class is required, never defaulted, because picking it is the thinking.
It also sets how long the block may sit before `plan check` nags — 7 days for
`human`, 14 for `defect`, 21 for `plan`, 30 for `external`. One number for all
of them would cry wolf: an unanswered question at a week means someone dropped
it; an upstream release at a week is just Tuesday.

Two bright lines:

- **Blocked, not Abandoned.** Blocked means the plan is still correct and
  resumes when the named obstruction clears. If you cannot name what would
  clear it, it is not blocked — it is Abandoned.
- **Blocked, not a question.** Set it when the obstruction outlives the
  session. An answer you will have in thirty seconds is a question; ask it.

The log is append-only. Entries are never deleted, they travel into the
archive with the plan, and they are what `Execution-friction-after` is
reconstructed from at closure rather than remembered.

Keep `Last updated:` current on every touched plan. Other status changes
are picked up by the digest recompile of the next ledger write; creating or
archiving a plan directory recompiles on its own or needs `startup`.

## Archive

`plan archive --list` previews archive-ready directories; `plan archive`
moves terminal plans to `zamm-memory/archive/plans/` and recompiles the
digest so the Plans tail reflects it; it refuses any plan that fails
`plan check`. Run it every time a plan reaches Done after its edits are
finished. Ledger records are never archived by this flow.

## Telemetry fields

`Execution-context-before`, `Complexity-forecast`, `Memory-upvotes`,
`Memory-downvotes`, `Execution-friction-after`, `Complexity-felt`,
`Complexity-delta`, `Done-approved-by`, `Done-approved-at`,
`Done-approval-evidence`. They describe the work — its friction, its
uncertainty, how the estimate held up — never anyone's inner state. Plan
files are committed and team-visible.
