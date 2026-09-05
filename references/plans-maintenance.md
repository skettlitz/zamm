# Plans — maintenance (status transitions and close-out)

Bookkeeping is event-driven: apply a transition's requirements when the
transition is attempted or requested — setting `Status:`, or a human review
outcome — not only at session end. Session End is the backstop that catches
what was missed.

Allowed transitions: `Draft -> Implementing | Abandoned`;
`Implementing -> Review | Abandoned`; `Review -> Implementing | Done`.
`Done` only via `Review -> Done` after explicit human approval. `Done` and
`Abandoned` are terminal: never resume a terminal plan; start a new one.

## Requirements per transition

- `Draft -> Implementing`: Scope and Done-when filled;
  `Execution-context-before` and `Complexity-forecast` filled.
- `Draft -> Abandoned`: rationale under `## Loose ends`. A never-started
  draft needs nothing more; the checker asks for the full retrospective only
  once work happened (an `Execution-context-before` was filled, or a
  Done-when item checked).
- `Implementing -> Review`:
  1. Every Done-when item checked; remove items that became obsolete.
  2. Reconcile stale or conflicting live records touched by this work —
     supersede them (`memory-maintenance.md`) — before adding new
     learnings.
  3. Fill `## Learnings` (required; if nothing durable emerged, say so with
     a reason).
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
  7. Ask the human for approval before `Done`.
- `Implementing -> Abandoned`: check off what was completed; record the
  rationale and cleanup notes; then the same distillation, learnings, votes
  and telemetry as for Review.
- `Review -> Implementing`: capture the requested changes and re-open the
  relevant Done-when items.
- `Review -> Done`: only after explicit human approval while in Review. Fill
  `Done-approved-by`, `Done-approved-at` and `Done-approval-evidence`; set
  `Status: Done`; finish the file edits; then run `plan archive`.

Keep `Last updated:` current on every touched plan. Other status changes
are picked up by the digest recompile of the next ledger write; creating or
archiving a plan directory recompiles on its own or needs `memory digest`.

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
