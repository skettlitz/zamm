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
- The agent picking the work up next session reads `plan show`. `## Why`
  says what the plan is for, which is what it needs at any fork the plan
  did not foresee — and lets it notice when the problem has already gone.
  Scope (`In` / `Out`) says what is and is not this plan. `## Done-when` is the
  checklist it works from: write outcomes that can be checked, not
  activities — `- [ ] startup under 200ms on the 500-record fixture`,
  not `- [ ] optimize`. `## Approach` is the sketch it follows.
- The human approving Review → Done reads `## Why` against Done-when: is
  the problem gone, not only is the list ticked. Then `## Learnings` and
  the approval evidence.
- The distiller at close-out reads Learnings to write knowledge records:
  write each learning as a candidate record — trigger, rule, why — not as a
  diary of the work.
- The reader a year later, in the archive, reads `## Loose ends` and the
  telemetry to understand why it ended as it did and how the estimate held
  up.

## Why

Scope and Done-when are the record of doing; `## Why` is the record of
steering. A plan without it is a to-do list, and a to-do list has two failure
modes: it gets completed after its reason has gone, and the forks it did not
anticipate get decided by "easier". With the why, an agent at a fork chooses
the way the human would, the next session can notice the problem is already
gone, and approval can ask whether the problem is gone instead of whether the
boxes are ticked.

The reason is usually recoverable from the discussion even when nobody said
it outright. Derive it, write it, and say that you derived it: a misread
costs one round of plan review instead of a day of code review. Tag every
line with its source — `human:` (stated), `derived:` (from the discussion),
or `not revealed` — and treat `not revealed` on serious work as the moment
to ask.

One line per answer, only the ones that apply. A small plan answers three.
The template carries the section and the three usual lines and nothing else:
the questions live here, read once, not copied into every plan.

| ask | guards against | a good answer / a bad one |
| --- | --- | --- |
| **now** — what happened that made this the next thing? | losing the trigger; a later session cannot tell whether it is still live | "the first startup on the other project printed a four-sentence warning" / "it was next" |
| **problem** — who is hurt, how, observed how? | solving non-problems; a Done-when that cannot verify the problem is gone | "every agent pays 550ms and 20k tokens before reading anything" / "startup is slow" |
| **serves** — which standing goal or `DESIGN.md` principle does this advance? | a local win that breaks a global rule; work no principle asked for | "attention is scarce; session start is the most expensive surface" — or "nothing beyond the problem", which is a legitimate answer |
| **alternatives** — what else was considered, and why not? | re-litigating; retrying a known-bad path; keeping an option rejected after its reason expired | "content hash and git measure the same at 400 records; git is 7x at 4000" |
| **enough** — the compromise accepted, and what makes it acceptable? | gold-plating; endless hardening; a compromise that becomes folklore | "a symlink swap can skip one refusal; `check` never skips, nothing from it reaches a digest" |
| **assumes** — what does this rest on, and what if it fails? | decisions outliving their premises; a moot plan run to completion | "writes recompile as they land; everything else arrives by pull" |

Two more live elsewhere in the file: **why not** is the reason beside each
Scope `Out` item (and whether it means never or not now), and **why it ended
this way** goes under `## Learnings` at close-out, with the telemetry fields
as its numbers.

The checker does not require `## Why`. A plan without it predates the section
and is fully valid; nothing is backfilled. What the section changes is behaviour
at two moments: an agent re-reads it before choosing at a fork the plan did not
anticipate, and the human's approval question becomes "is the problem gone?".

## How

`plan create '<title>'` creates
`zamm-memory/active/plans/<YYYY-MM-DD-slug>/<same>.plan.md` from
`references/templates/plan.template.md` and says what to fill next;
`backlog promote <id>` does the same from an idea, with `Origin-idea:`
provenance. Then recompile the digest (`startup`) so the Plans tail
lists it.

Layout: one directory is one plan context; the main file carries the
`.plan.md` suffix (recommended `<plan-dir>.plan.md`, date-first slug);
transient artifacts go under `<plan-dir>/workdir/`; the archive moves the
whole directory to `zamm-memory/archive/plans/`.

Fields at creation: `Status: Draft`; `## Why` (above); `## Scope` with `* In:` and `* Out:` (older plans spell it `Scope:`; both are read);
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
