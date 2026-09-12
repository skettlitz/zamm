# Memory — reading

Every read here is pulled from files the compiler already ranked; none of it
changes the ledger.

## The digest

`bash <zamm-skill>/scripts/zamm-run.sh startup` recompiles the digest
and hands back its path. **Reading that file, whole, is the session read.**
The command's own output is a handoff: two lines — what the project holds and
where the digest is — plus two more when something is wrong with the project,
naming the defect types and the report that explains them
(`.compiled/zamm-defects.md`). It is not the digest, and an agent that stops
there has read nothing. How to read the file is not repeated there; it
is in the router the same agent read from `AGENTS.md` moments earlier.

Open the file with a file-reading tool. Do NOT `cat`, `head` or `tail` it:
command output is capped by the harness (Claude Code cuts a Bash result at
30000 characters and replaces the rest with a short preview), so a real
ledger piped that way is truncated silently — which reads to the session as
a memory that was consulted rather than one that was cut. The file itself has
no such limit. `--inline` prints the digest to stdout for a reader with no
file tool, and warns when the output will not survive the trip.

**Read it once per session.** Do not reread it after writing a record. The
digest is re-sent with every subsequent request for the rest of the session,
so a second read does not refresh anything — it puts a whole second copy in
the context, and a session that writes three records and rereads each time
carries four. On a large ledger that is the difference between one memory
read and four, for no new information: you already know what you just wrote,
and `memory create` reports the two things you could not have known — whether
the write left a reconciliation group open, and whether the record landed
below the entry caps where no session will be handed it.

Writes also recompile, so the file is already current for the NEXT session.
Reread within a session only if something outside it changed the ledger — a
pull, or another agent writing to the same tree.

Its anatomy, top to bottom:

- Header: the date, file/live/quarantined counts, and the format legend.
- `## Needs reconciliation` — only after a merge left two live successors of
  one record: an index of the competing heads. Resolve it this session;
  `memory-maintenance.md` says how.
- `## Marked backlog` — only when ideas are marked: the ideas someone
  selected for implementation, one headline each. Implement or unmark.
- `## Digest (actionable; full blocks)` — up to ~75 records grouped under
  `### area` headings (the fixed eight), balanced across areas so one hot
  topic cannot drown the rest. Each is `- subpath: headline [record-id votes
  +bg]` with its elaboration indented under it; the subpath names the one
  record inside its area, and is absent when the record has none. A leading `!` is a GUARDRAIL: violating it
  breaks the project or wastes hours — do not. A leading `~` is a contested
  head, also listed under Needs reconciliation. An entry ending `+el` had
  elaboration the space budget could not afford — open the record.
- `## Headlines (reminders)` — up to ~150 more records, headline only, under
  the same `### area` headings. Not enough to act on alone: when the topic
  matches what you are doing, open the record. Grouped rather than ranked
  flat, because that is how this layer is used — you scan it for a topic,
  not for the top of a list.
- `Budget:` — the digest's size against its soft character ceiling, and how
  many blocks kept their elaboration. `OVER BUDGET` means every entry is
  already collapsed to its headline and the total still exceeds the ceiling.
  Nothing was dropped and nothing is wrong: it is a reading on a mature
  ledger, not an error, and not something to raise at session start. Bring it
  up only when the human is already deciding what to retire, or when you have
  a concrete candidate to supersede.
- Trailing counts: live records below the entry caps (unlisted) and dormant
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

`+el` is the same instruction for a different reason: the record's digest
block HAS elaboration, and the space budget could not render it here. It
marks a shortfall in the surface, not in the record — the text is intact in
the file. A block with no elaboration is never marked, so `+el` always means
there is more to read.

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

- Session start is still `startup`; a search is never a digest, and
  `.compiled/` is never read through a search tool.
- After a hit under `zamm-memory/`, `whatis` the path before citing or
  acting on it, and cite what it names as live. Unlisted and dormant
  records are still true; `archive/` is history; an active plan's Status
  and the digest win on conflict.
- The path is the cheapest signal. `memory archive` moves superseded and
  retired records out of `knowledge/` as soon as they die, so a hit under
  `zamm-memory/archive/` is history before any command runs, and
  `grep -r <term> zamm-memory/knowledge/` sees only what still stands.
  Give a search tool the same split: index the project with
  `zamm-memory/archive/**`, `zamm-memory/.compiled/**` and plan `workdir/**`
  excluded for "what is", and, if history questions matter, a second
  collection rooted at `zamm-memory/archive/` for "what was". Superseded
  records that have not been archived yet still rank like current ones,
  which is why `whatis` stays the last word.
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
