# Memory — reading

Every read here is pulled from files the compiler already ranked; none of it
changes the ledger.

## The digest

`bash <zamm-skill>/scripts/zamm-run.sh memory digest` recompiles and prints
the digest. That output is the whole session-start read; do not open
`zamm-memory/.compiled/memory.md` as well (the same text, ingested twice).
Rerun only after records were written or merged — your own `memory create`
already recompiled.

Its anatomy, top to bottom:

- Header: the date, file/live/quarantined counts, and the format legend.
- `## Needs reconciliation` — only after a merge left two live successors of
  one record: an index of the competing heads. Resolve it this session;
  `memory-maintenance.md` says how.
- `## Marked backlog` — only when ideas are marked: the ideas someone
  selected for implementation, one headline each. Implement or unmark.
- `## Digest (actionable; full blocks)` — up to ~75 records grouped under
  `### area/subpath` headings, balanced across areas so one hot topic cannot
  drown the rest. Each is `- headline [record-id votes +bg]` with its
  elaboration indented under it. A leading `!` is a GUARDRAIL: violating it
  breaks the project or wastes hours — do not. A leading `~` is a contested
  head, also listed under Needs reconciliation.
- `## Headlines (reminders)` — up to ~150 more records, headline only. Not
  enough to act on alone: when the topic matches what you are doing, open
  the record.
- Trailing counts: live records below the budget (unlisted) and dormant
  ones (decayed below the floor). Both stay in the ledger, greppable.
- `## Plans` — every active plan (status, progress, title) and the recently
  archived ones; `plans-reading.md`.
- `Backlog:` — one line of counts. `Journal:` — one line, only when
  digestion is due.

## The pointer

`[2026-05-14-tier-motion-x2f4a +3 +bg]`: the record id (its filename stem;
the date is its creation date), its vote total when non-zero, and `+bg`
when the file holds a `## Background` section. `+bg` is an instruction:
open the record before a high-impact action on that topic — the Background
is where the evidence, the paths and the history live.

## Opening and finding records

- `memory show <slug|id>` — one record in full.
- `memory list [--all] [--scope <area>]` — scope, slug, and the first ~70
  characters of the headline. By default ONLY the records the digest
  selected (the ~75 blocks and ~150 headlines); `--all` lists every live
  record, including the unlisted and the dormant. Before adding knowledge
  that might overlap, it is `--all` you want.
- `grep -r <term> zamm-memory/knowledge/` — the ledger is plain files;
  dormant and unlisted records are found this way.
- `memory check` — validate the ledger; prints `ZAMM check passed.` or the
  violations.

## Trust

Records are advisory, not authoritative. A record superseding another
always outranks it; a record that conflicts with code or tests is drift —
verify before a high-impact action, and when you find one wrong, supersede
it with a `suspected drift` record (`memory-maintenance.md`). Precedence
when sources conflict: current human instruction, then code, tests and
contracts, then the active plan, then live records, then eternal and
archived notes.
