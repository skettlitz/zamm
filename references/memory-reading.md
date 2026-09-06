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
- `whatis <path|qmd-url|id|slug>...` — what a thing is and whether it
  still counts: the tree, its standing (live and listed or unlisted,
  dormant, superseded, retired, quarantined, erased, archived), the chain
  it belongs to and, when the hit is history, the live head and the head's
  body — the answer is "superseded, cite this instead", never the dead
  record's own detail. Plans report Status and progress; a file outside
  `zamm-memory/` is reported as ordinary. A bare slug prints every record
  that kept that slug; the chain listed under any hit is the graph,
  whatever the slugs along it. Read-only; `--brief` drops the bodies.
- `memory check` — validate the ledger; prints `ZAMM check passed.` or the
  violations.

## Search results are leads

Any search — grep, an editor index, or a markdown search tool if the
project happens to have one (QMD is one: `qmd search` for exact words,
`qmd query` when its models are available, then `qmd get`) — is welcome
for "where did we write about X"; the digest is deliberately too small for
that question. None of them is required, and none can judge standing: they
rank by resemblance, so a superseded record, a retired chain or an
archived plan scores like the one in force. The rules ZAMM owns, whatever
the tool:

- Session start is still `memory digest`; a search is never a digest, and
  `.compiled/` is never read through a search tool.
- After a hit under `zamm-memory/`, `whatis` the path before citing or
  acting on it, and cite what it names as live. Unlisted and dormant
  records are still true; `archive/` is history; an active plan's Status
  and the digest win on conflict.
- A search tool never writes: records, ideas, episodes and plans go through
  `memory create`, `backlog add`, `journal add` and `plan create` only.
- `whatis` is only as good as the graph. An edge written in prose — a
  `supersedes:` line at the top of the body instead of the header — is
  invisible to the compiler, to search and to `whatis` alike, which is why
  `memory create` refuses such a body, `check` warns about existing ones
  and `whatis` flags them. Correct one with a new record carrying the key
  in its header.

## Trust

Records are advisory, not authoritative. A record superseding another
always outranks it; a record that conflicts with code or tests is drift —
verify before a high-impact action, and when you find one wrong, supersede
it with a `suspected drift` record (`memory-maintenance.md`). Precedence
when sources conflict: current human instruction, then code, tests and
contracts, then the active plan, then live records, then eternal and
archived notes.
