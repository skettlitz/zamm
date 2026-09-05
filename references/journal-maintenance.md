# Journal — maintenance (digestion and coverage)

Read this before `journal review`, `journal settle` or `journal elevate`.
Capturing entries needs none of it (`journal-writing.md`), and neither does
reading them (`journal-reading.md`).

The point of digestion is that the journal is written-mostly: episodes
accumulate, and something has to turn the durable parts into knowledge and
keep the rest readable without anyone re-reading a year of it.

## Three modes, and only three

COMPILE — `journal digest <YYYY[-MM]>`

The primary digest, and a pure READ: it prints a period view and stores
nothing, so it is never stale and never needs claiming. Flags and grammar
are in `journal-reading.md`. Everything below exists because the other two
modes write records.

TRIAGE — `journal review`, then `journal settle`

`journal review` shows what no claim has covered, oldest first (headlines
only above 50 entries). Read it, then distil: recurring patterns become
knowledge records, implied actions become backlog ideas — never a cross-tree
edge, always a new record in the target tree. Then `journal settle` claims
what you actually read, writing a watermark record whose headline says what
came of the review.

`--cue` and `--scope` on review are READING AIDS, never coverage units: a
settle after a filtered pass would claim more than you read. Chunk a large
backlog by date instead — `settle --through <date>` — and repeat.

ELEVATE — `journal elevate <kind> <YYYY[-MM]>`

Stores a summary of a COMPLETED period, body on stdin. `monthly` and
`yearly` ship; the set is open. The record is its own coverage, so no settle
follows it. Compiled views embed it, and the year view renders it INSTEAD of
that month's entries — which is why the rules below exist.

## What a summary is for

An elevation exists so a reader can STOP at it. Every consumer below is
someone who would otherwise have to read the period's entries; write for
them, from far to near:

- The year view (`journal digest <YYYY>`) shows, for an elevated month, the
  elevation's FIRST PHYSICAL LINE and nothing else of that month - the
  entries are gone from that view, replaced by that line. A headline that
  wraps is cut mid-sentence. So line one is the period in one sentence:
  what kind of period it was and the one or two things that made it so.
  Keep it on one line.
- The next elevation up is written from those lines. A yearly elevation's
  author reads the year view - twelve first lines plus the stats - so the
  first line of a monthly elevation is literally the raw material of the
  year's summary. Write it to be summarized: a verdict, not an inventory.
- The month view (`journal digest <YYYY-MM>`) shows the digest block -
  everything above the first heading, at most 12 lines and 1200 characters,
  validated like any record - above the entries. That block is the month
  for a reader who will not open entries: the few episodes that mattered,
  each with its outcome and why it matters to someone retracing, named by
  id in square brackets so `journal show` reaches them. It is not a list
  of entries (the record already names every entry it saw in `covered:`)
  and it is not a diary.
- `## Background` is for the reader who did open the record: what was
  tried, what was ruled out, and pointers to the plans, knowledge records
  and backlog ideas the period produced. Read on demand only.
- Someone hitting an echo of an episode a year later finds it through
  `journal search --text`, which matches bodies - so name things by their
  real names: the test, the service, the flag.

Two tests before writing. Could a reader who sees only line one decide
whether to open the month? Could a reader of the block skip every entry it
covers without losing a decision? When the second answer is no, the block
is missing an outcome, not words.

The settle headline is a summary too. `journal settle` takes one line on
stdin: what came of the review. Its reader is the NEXT reviewer, who sees it
as the watermark's headline (`journal search --class watermark`) and needs
to know what was already extracted - "two knowledge records, one backlog
idea, nothing else durable" - or that nothing was, so the same entries are
not mined twice. The default text says only that a review happened.

## Coverage rules

A wrong guess here is permanent, because the record is immutable and later
readers trust it.

- A claim NAMES the records it saw (`covered:`); it is not a date range. An
  entry written or merged in later under an older date was reviewed by
  nobody and must not be absorbed. `reviewed-through:` is the readable
  boundary; the effective one shown is the highest among unretired claims,
  since two concurrent claims are both true.
- `settle` and `elevate` REFUSE while the journal is degraded. Nobody can
  review a record the toolchain cannot read; fix `journal check` first.
- No claim may reach past the day it was written, and entries dated on that
  day are not covered by it. Settle again on a later day to pick them up —
  the digest will not nag you meanwhile.
- Only a COMPLETED period may be elevated. While a period is still running,
  `journal digest <period>` is the live answer and is always current.
- An elevation that missed entries of its period is STALE: the lens says so,
  the year view lists what it missed, and the kind falls due again. Correct
  one by SUPERSEDING it. Two left live for one period are competing claims,
  and the views name them rather than silently picking one.
- Digestion retires NOTHING. Entries are history; only decay collapses them
  in the lens. Supersession joins like classes — entry to entry, watermark
  to watermark, elevation to elevation — and only a tombstone crosses, so a
  coverage record can never swallow the episode it covers.

## The one session-start line

    Journal: triage due (27 undigested, oldest 2026-07-19); monthly due (2026-08) - zamm-run.sh journal review

It appears only when digestion is due, and it is a nudge, not an obligation:

- Triage is due at 25 undigested entries a settle could actually clear, or
  when one of them is older than 60 calendar days.
- An elevation kind nags only after your FIRST elevation of that kind — the
  first one opts in — and goes silent if the practice lapses (more than
  three of its own periods behind). `status` still reports it.
- A quiet or absent journal shows no line, and the digest is byte-identical
  to one from a project with no journal at all.
- `Journal: DEGRADED` means the tree has records the compiler could not
  read: run `journal check`, and expect the coverage verbs to refuse until
  it is clean.

## Erasure (exceptional)

A secret or personal data in an entry, an elevation or a watermark is
erased IN THIS TREE — an erasure record in `knowledge/` does nothing here:
`journal add --type erasure --erases <id> <slug>`, body = why the content
had to go; then delete the record file. Git history rewriting is a
separate, human-approved step. The full rules are the memory ones
(`memory-maintenance.md`), applied to this tree. An erased entry stays a
valid id for the claims that named it in `covered:`.

## Shape and policy

Three record classes share the tree, each resolving by value:

| class | is | marked by |
| --- | --- | --- |
| entry | one episode | `type: memory` |
| elevation | a stored summary of a period | `type: digest` + `digest:` + `covers:` |
| watermark | a triage coverage claim | `type: memory` + `reviewed-through:` (+ `pass:`) |

Refused in this tree: `guardrail` importance (there is no pushed surface to
guard), votes records (a timeline has no ranking to vote on), and `marked:`.
`OTHER_MAX` does not apply, since cheap capture legitimately defaults to
`other`. Elevations and watermarks never go dormant — they are retired only
by supersede, tombstone or erasure — while entries decay out of the lens and
stay greppable.

The journal-only keys are `cue`, `salience`, `axis-*`, `time`, `agent`,
`user`, `digest`, `covers`, `covered`, `reviewed-through` and `pass`. Each
is an error in the other trees; `x-` keys are legal everywhere.

Other skills are the journal's main operators: they read the seams
(`export`, `search`, `stats`, `digest`) and write only through `journal add`
and `journal elevate` — never derived state into the tree, never a policy
key outside `x-`.
