# Journal — reading

Every journal read is PULLED: none of this enters the session-start budget,
and none of it changes the ledger. Safe to run at any time.

## The surfaces

- `journal list [--all] [--scope <tag>] [--cue <slug>] [--since <date>]` —
  the timeline, newest month first, headline-only. Dormant entries collapse
  to per-month counts (`--all` lists them); a filter prints a row listing
  instead of the timeline.
- `journal show <id|slug>` — one record in full, `## Background` included.
- `journal search <predicates> [--text <pattern>] [--files]` — rows matching
  every predicate, newest first. `--text` greps bodies; `--files` prints
  paths for piping.
- `journal stats [--axis <name>] [<predicates>]` — aggregates for a human.
  The overview lists every axis with its type and COVERAGE (rated over
  total, always shown, so a sparse axis is never over-read) plus per-cue and
  per-agent counts; `--axis <name>` drills into per-month quartiles, and a
  bipolar axis adds the negative/zero/positive split.
- `journal digest <YYYY[-MM]>` — a compiled view of one period, printed and
  never stored. A month is stats + elevations + entries; a year is the
  digest of digests. Shape it with `--detail headlines|blocks|full`,
  `--stats none|summary|full`, `--elevations all|only|none`. Because it
  recompiles on every run it is always current — this is the right answer
  for "what happened in June", including while June is still running.
- `journal export [<predicates>]` — the versioned TSV seam applications
  read: a version line (`# zamm-journal-export v1`), a column-name row, then
  one row per record. Map columns BY NAME; within v1 they only append.

## One predicate grammar

`search`, `stats`, `digest` and `export` share it:

`--class entry|elevation|watermark`, `--scope <tag>` (prefix, any tag),
`--cue <slug>`, `--kind <elevation-kind>`, `--covers <period>` (prefix),
`--agent <token>`, `--user <token>`, `--axis name[(=|<|>)<integer>]`,
`--since <date>`, `--until <date>`.

A leading `!` negates a value (`--cue '!side-quest'`). Repeating one
predicate means "any of these"; different predicates must all hold.

## Exit codes

`0` clean. `2` the tree is DEGRADED — the rows you got are still valid, but
some records could not be read, so the set is short; the reason is on
stderr and `journal check` names them. `4` the tree could not be enumerated
at all. If you are a program consuming `export`, check the status: you
cannot see the `## Degraded` section a human would.
