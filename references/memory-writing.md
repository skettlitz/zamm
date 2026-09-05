# Memory — writing a record

Read this before writing to the knowledge ledger. A record is immutable once
written and is reread at every session start by every agent on the project:
the most expensive text in the system, and the most useful when it is right.

## Who reads it, and at what zoom

Not you, and not now. Write for these readers, most frequent first:

- An agent at session start, mid-task, scanning up to ~75 digest blocks for
  the one that applies to what it is doing now. It sees
  `- headline [id +bg]` with the elaboration indented under it, grouped by
  area. It is not reading; it is matching. The first words must name the
  SITUATION — the file, the command, the phase, the tool — so the match
  happens before the sentence ends; then the instruction; then the why in
  one clause. Condition first: "When touching X, do Y because Z."
- The same agent reading ~150 `## Headlines`: the headline alone, and a
  decision whether to open the record. A headline that says "see below" or
  "important caveat about tests" makes that decision impossible; one that
  carries the rule makes opening unnecessary.
- An agent about to do something high-impact, which opened the record
  because of `+bg`. It wants evidence: the path, the command, the failing
  case, the history — enough to verify the claim, not a retelling of the
  headline.
- The reconciler after a merge, holding two competing records and deciding
  which is true from code, tests and context. A record that says WHERE its
  claim can be checked can be reconciled; one that only asserts cannot.
- The agent closing a plan, voting: records that helped get upvoted, ones
  that misled get downvoted, so ratings self-correct — but only for records
  precise enough to have helped or misled.
- The agent that supersedes it later, finding it by `memory list`, grep or
  the digest. Use the real names of things — the script, the flag, the
  directory — never "the tool" or "the config".
- `memory list` shows scope, slug and the first ~70 characters of the
  headline. The slug (the `<topic-slug>` you pass, at most 40 characters)
  is how people open the record: name the topic, not the fix —
  `awk-one-namespace`, not `fix-bug`.

Two tests before writing. Would an agent doing X recognize from the first
words that this block is about X? Could it act on the block without opening
the record? When the second answer is no, the headline is missing the
instruction, not detail.

## The body

- The FIRST PARAGRAPH is the headline: ONE imperative, actionable or
  guardrail statement, standalone-readable. One short sentence is the norm;
  ~300 characters is a ceiling, not a target. The digest joins the
  paragraph's lines into one line, so wrap freely in the file — it is still
  one statement. It is the entry's first line in the digest and its only
  line under Headlines.
- Optional elaboration paragraphs follow: a digest-worthy caveat, a key
  parameter, the load-bearing why. Everything above the first heading is
  the DIGEST BLOCK; hard limits are 12 lines and 1200 characters (the writer
  refuses more). Most records need two or three lines; a block near the
  limit is carrying Background material.
- `## Background` holds what only matters when working the topic: full
  reasoning, evidence paths, history, what was ruled out. Optional — omit it
  when the block carries everything. Its presence is the `+bg` marker.
- Brevity is part of the contract. The block is reread at every session
  start by every agent; the Background by whoever opens the record. Limits
  are ceilings, not space to fill: a one-sentence record that says the thing
  is complete, and a paragraph that could have been a sentence is a defect.
  Cut the preamble, the restated context and the hedges; keep the trigger,
  the rule and the why. Every word saved saves context and money for every
  reader after you.
- Never store secrets, tokens or credentials: records are effectively
  permanent, git history included. Never quote the human verbatim:
  paraphrase the substance and, where the register matters, describe the
  emotion ("strong frustration with rebuild times"). Records are
  team-visible; do not immortalize heat-of-the-moment phrasing, and do not
  characterize anyone's performance or mood.
- Other types: a `tombstone` body is a one-line reason; a `votes` body is
  empty; an `erasure` body says why the content had to go (required — it is
  the only account of a redaction that survives it).

## Rating: importance and durability

These two fields ARE the ranking: score = importance, decaying over the
durability horizon as its half-life, corrected by votes. Rate them for the
reader, not for how the moment feels.

- `importance`: `guardrail` | `useful` (default) | `minor`. A guardrail
  (`!` in the digest) means violating it breaks the project or wastes
  hours. It never decays and is always in the Digest layer — read by
  everyone, forever — so a handful per project, not per week; `memory check`
  warns past 15. Inflation is corrected by downvotes and erodes trust in
  every `!`.
- `durability`: `days` | `weeks` | `months` (default) | `years` |
  `permanent` — how long the statement will stay TRUE. A `days` note
  self-retires within weeks; a `permanent` guardrail never fades. Emotion
  and failure enter cheap (`days`/`weeks`) as hypotheses; a session that
  confirms the statement supersedes it upward. Refreshing a still-true
  record is one supersede away.

## Scope

`scope`: 1–3 comma-separated area tags, e.g. `contracts/record-schema,
conventions`. The first (primary) tag is `<area>[/<subpath>]` and is where
the record displays (`### contracts/record-schema`); secondary tags are bare
areas that give the record extra selection doors. Digest seats are balanced
across top-level areas, and each extra tag costs a little ranking, so tag
only areas the record genuinely serves. The set is fixed; the writer refuses
anything else and prints it:

- `domain` — what the product is for: purpose, users, requirements,
  external constraints ("this tool targets solo maintainers, not
  enterprise fleets")
- `contracts` — boundary shapes others depend on: schemas, formats,
  protocols, CLI/API surfaces, invariants; violation breaks interop or data
  ("record IDs are the filename stem; never rename under knowledge/")
- `conventions` — self-imposed rules: naming, style, layout, wording;
  violation costs consistency, not correctness ("plan dirs use date-first
  slugs")
- `internals` — how shipped things work and why they have that shape
  ("digest ranking decays over durability half-life")
- `quality` — how correctness is verified: test strategy, checks, known
  failure modes of the artifact ("compile --check before committing ledger
  writes")
- `tooling` — dev-time things used, not shipped: commands, environment,
  platform quirks ("awk on macOS lacks gawk extensions; keep scripts
  POSIX")
- `ops` — ship- and run-time mechanics: release, versioning, deploy,
  migration ("bump zamm-memory/VERSION only after migration completes")
- `meta` — agent and process failure patterns, corrections, collaboration
  norms with the human ("prefer reading the digest over re-scanning the
  ledger at cold start")
- `other` — when none fit: the sole tag, no subpath, temporary parking to
  refile by supersession (`memory check` fails above 5 live `other`
  records)

A boundary-straddler takes two tags: a CLI flag that is both an interop
surface and a naming rule → `contracts/cli-flags, conventions`.

## The write

    bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area[/subpath][, area2]>' <topic-slug> <<'EOF'
    <the record body>
    EOF

One step. The record is composed in a private temporary file, validated by
a full compile, and only then linked into the ledger under its final name —
so it is either absent or complete and valid, and a rejected one leaves
nothing behind but the printed violations. It prints the record path on
success; that is the whole transaction, digest recompiled. Flags:
`--importance`, `--durability`, `--supersedes <id[,id]>`,
`--type tombstone|votes|erasure`, `--erases <id>`, `--up`/`--down <ids>`
and `--plan <plan-dir>` for votes, `--edit` to compose in `$EDITOR`,
`--no-validate` for bulk migration only (then `zamm-run.sh check` once at
the end).

The filename is the record id: `YYYY-MM-DD-<topic-slug>-<suffix>.md` —
lowercase `[a-z0-9-]`, slug at most 40 characters, date = creation date,
suffix 5 random characters from `23456789abcdefghjkmnpqrstvwxyz` so that
uncoordinated writers cannot collide. Hand-written files follow the same
rules: compose `<id>.md.draft` from
`references/templates/memory-record.template.md` and land it with
`memory publish <id>` (`memory drafts` lists the unpublished, `memory
discard` removes one). Frontmatter is flat `key: value` lines between two
`---` lines — every value a plain string, lists comma-separated, unknown
keys ignored, empty keys omitted: `type` (`memory` | `tombstone` | `votes`
| `erasure`), `scope`, `importance`, `durability`, `supersedes`, `created`
(must match the filename date), `schema: 3`. A votes record adds `plan`,
`up`, `down` and carries no body; an erasure record adds `erases`.

## When to write one

The cues are deliberately coarse; full semantics in
`references/distillation-triggers.md`:

- the human says remember this — same turn, no damping
- the human corrects you or states a standing rule, in any tone — else it
  evaporates at session end (`conventions` for project rules, `meta` for
  collaboration norms)
- the human shows strong emotion, complaint or praise, with substance
  behind it — record the substance, short-lived, never the words
- the same failure hits twice — cause + workaround now; still stuck, a
  short-lived dead-end record (goal, tried, ruled out)
- research yields a conclusion whose details live in a pointable file —
  conclusion + pointer; never a free-floating value with nowhere to recheck
  it

Do not write: external changes that broke nothing; churn during primary
work (batch ordinary learnings into plan close-out). Prefer correction over
accretion: `memory list --all --scope <area>` first — without `--all` the
list is only what the digest selected, and the record you would duplicate
may be an unlisted or dormant one — then supersede a stale record or merge
overlaps before adding one that could duplicate or conflict. Never
edit a written record; the correction path is a new record carrying
`supersedes:` (`memory-maintenance.md`).
