---
type: memory
scope: <primary-area[/subpath][, area2[, area3]] — 1-3 tags from: domain | contracts | conventions | internals | quality | tooling | ops | meta (or `other` alone when none fit). Primary tag = display home, may carry a subpath; secondary tags are bare areas that give the record extra selection doors. Prefer the closest real area over `other`; tag only areas the record genuinely serves — each extra tag costs ranking.>
importance: <guardrail | useful | minor — guardrail: violating this breaks the project or wastes hours (rare!)>
durability: <days | weeks | months | years | permanent — how long this stays true; ranking decays over this horizon>
supersedes: <old-record-id[, other-id]>
created: __TODAY__
schema: 3
---

<Headline — first paragraph: ONE imperative, actionable or guardrail
statement an agent mid-task can recognize as its situation and act on
alone. One short sentence is the norm; ~300 chars is a ceiling, not a
target. Leads a ## Digest entry (with elaboration) and
is the only line under ## Headlines.>

<Optional elaboration: a digest-worthy caveat, a key parameter, the
load-bearing why. Headline + elaboration form the digest block — hard limits
12 lines / 1200 chars; most records need two or three lines. The block is
reread at every session start by every agent, so say it once and stop.>

## Background

<Optional deep detail: full reasoning, evidence paths, history. Only read
on demand (+bg marker). Delete this whole section when the digest block
carries everything. Delete the supersedes line when not replacing an older
record. This template is for a hand-composed
`<id>.md.draft` landed with `zamm-run.sh memory publish`; the one-step path
is `zamm-run.sh memory create`, which takes this body on stdin and writes
the frontmatter and the collision-safe filename itself.>
