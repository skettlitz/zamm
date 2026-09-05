# Plans — writing one

## When

Warrants a plan: multi-step work, changes that persist beyond the session,
anything producing research artifacts or a decision worth revisiting, or
work you expect to span sessions. Does NOT: answering a question, reading
or explaining code, a lookup, a one-line or single-file trivial edit,
running a command for the human. Plan-less sessions are normal, and
distillation still applies to them. The human overrides in either direction;
when genuinely unsure, ask rather than defaulting to a plan directory nobody
wanted. Prefer one active implementing plan at a time; if unclear, auto-pick
by best match and ask only when ambiguity remains.

## Who reads it

- Every agent at every session start reads the Plans tail: status, progress
  and the TITLE. The title is the plan to everyone who has not opened it:
  "Cache frontmatter between passes", not "Compiler work".
- The agent picking the work up next session reads `plan show`. Scope
  (`In` / `Out`) says what is and is not this plan. `## Done-when` is the
  checklist it works from: write outcomes that can be checked, not
  activities — `- [ ] memory digest under 200ms on the 500-record fixture`,
  not `- [ ] optimize`. `## Approach` is the sketch it follows.
- The human approving Review → Done reads Done-when (all checked),
  `## Learnings`, and the approval evidence.
- The distiller at close-out reads Learnings to write knowledge records:
  write each learning as a candidate record — trigger, rule, why — not as a
  diary of the work.
- The reader a year later, in the archive, reads `## Loose ends` and the
  telemetry to understand why it ended as it did and how the estimate held
  up.

## How

`plan create '<title>'` creates
`zamm-memory/active/plans/<YYYY-MM-DD-slug>/<same>.plan.md` from
`references/templates/plan.template.md` and says what to fill next;
`backlog promote <id>` does the same from an idea, with `Origin-idea:`
provenance. Then recompile the digest (`memory digest`) so the Plans tail
lists it.

Layout: one directory is one plan context; the main file carries the
`.plan.md` suffix (recommended `<plan-dir>.plan.md`, date-first slug);
transient artifacts go under `<plan-dir>/workdir/`; the archive moves the
whole directory to `zamm-memory/archive/plans/`.

Fields at creation: `Status: Draft`; `Scope:` with `* In:` and `* Out:`;
`## Done-when` checkboxes (only `- [ ]`, `- [x]` and `- [X]` count; anything
else is malformed); `## Approach`; `Last updated:`. Before `Implementing`:
`Execution-context-before` (what makes this hard or uncertain going in:
unknowns, missing access, risky surfaces, coordination) and
`Complexity-forecast` (one of
`ant|gecko|raccoon|capybara|badger|octopus|manatee|shark|godzilla|kraken`;
`kraken` is the off-scale wicked marker — scope a bounded probe with
closeable Done-when items, never "solve it"; cues in
`references/complexity-animals.md`). These fields describe the WORK, never
a person: plan files are committed and team-visible, so personal and
health-adjacent detail stays out.

## An IDE-written plan (offsite backfill; MUST)

Cursor planning mode and similar may write an offsite `.plan.md` that is not
ZAMM format. Treat it as input, never as the ledger. When one was created or
updated for the current task and no matching ZAMM plan exists — or the ZAMM
plan lacks its scope — then in the same turn: create or update the ZAMM plan
from the template, mirror the essential scope (Scope, Done-when, Approach),
record the offsite source path for traceability, set `Implementing` if work
remains or `Review` if it is complete and awaiting approval, and from then
on apply all bookkeeping in the ZAMM plan only.
