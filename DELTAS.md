# Draft v3 — change map vs. v2

This directory is a complete draft of the v3 skill tree. Design rationale and
citations: `../research-report.md`. Decisions locked 2026-07-14/16: random
5-char base32 suffix; votes as one batch record per plan closure; plan
directories unchanged; digest attention budget Digests 75 full blocks +
Headlines 150 one-line reminders (tunable; ~same space as 100 full entries,
~2.25× coverage); two-form records (digest block above `## Background` =
headline paragraph (~300 chars soft guide, not a hard cap) + optional
elaboration, 2-10 lines, hard limits 12/1200; `## Background` = deep detail
read on demand); author-rated `importance` (guardrail 3.0 / useful 1.0 /
minor 0.3) x exponential decay with `durability` as half-life (days 7d /
weeks 30d / months 91d / years 365d / permanent none); dormancy floor 0.05;
Digests selected greedily with a per-area diversity penalty (guardrails
always included when live); Headlines are the next-ranked live reminders;
further live records are unlisted but greppable. Migrated records map
tiers to importance/durability (boulders -> guardrail/permanent,
cobbles -> useful/years, pebbles -> useful/months, sand -> useful/weeks) —
the earlier seed-tier score prior is dropped. Votes attach to the exact
record voted on and aggregate over its ancestor chain, so competing fork
heads never share head-specific votes.

Locked 2026-07-18 — fixed area set + soft multi-tag scopes: the top-level
scope areas are no longer negotiated per project; v3 ships a fixed set of 8
knowledge-kind areas (`domain`, `contracts`, `conventions`, `internals`,
`quality`, `tooling`, `ops`, `meta`) plus `other` as an explicit
catch-all when none of those areas fit (sole tag, no subpath, drained via
supersession; `--check` fails when more than 5 live records sit in `other`).
Prefer a real area over parking in `other`. A memory record
carries 1-3 ordered area tags (`scope: contracts/record-schema, conventions`);
the first (primary) tag may carry a subpath and is the record's display home,
secondary tags are bare areas for the selector only. Full-entry selection
becomes `log(score) - 0.25 x min over the record's tag areas of taken(area)
- 0.25 x (tags - 1)`: a record enters through its least-crowded door (more
tags = more chances), pays a parsimony cost per extra tag (fewer tags = bonus),
and on selection adds 1/tags to each tagged area's taken count (fractional
seat attribution). Both 0.25 constants are dogfooding knobs.

2026-07-18 cold-start role-play review fixes: vote weight is 0.5 per vote
(recency-decayed; one downvote demotes but can no longer single-handedly
delist a fresh useful record — applies to plan votes and migration seed
votes alike); the chain-depth bonus counts only single-target supersessions
(a reconciliation merge hop proves nothing about durability); Reconciliation
gained a cannot-determine rule (conservative-union merge record marked
`suspected drift`, confirm with the human — never leave heads unmerged);
the votes-skeleton empty `up:`/`down:` lines are now a documented schema
exception and zamm-new-memory.sh prints a fill-before-commit hint; digest
blank-line handling fixed (no double blanks after elaborated entries); the
scaffold expands only the first `<zamm-skill>` token (the definition in
Script Path Resolution) and later references stay as the alias, saving
~300 tokens per compiled runtime surface.

## New files

- `scripts/zamm-compile.sh` — POSIX sh + awk digest compiler (liveness,
  supersede chains, vote totals, ranking, reconciliation detection). Zero
  dependencies beyond stock sh/awk/find/sort. The digest renders one
  entry per live record: headline line (`- statement [id votes +bg]`) plus
  indented elaboration for up to ~75 Digests (full blocks); up to ~150
  Headlines (one-line reminders); `## Background` content never enters the
  digest — `+bg` marks records holding it, `!` marks guardrails. Ranking =
  importance x durability-decay + votes + chain depth; scores below the
  dormancy floor drop to a per-area count line (primary area). Full-entry
  selection: guardrails first, then greedy by `log(score) - GROUP_PENALTY x
  min-taken-over-tag-areas - TAG_COST x (tags - 1)` (both 0.25); a selected
  record adds 1/tags to each tagged area's taken count. Votes attach per
  record and aggregate over the ancestor chain (no fork bleed). `--check`
  enforces the full record contract: frontmatter present and closed, filename
  carries the 5-char uniqueness suffix, `created:` well-formed and matching
  the filename date and year directory, `schema: 3`, valid `type`,
  `importance` and `durability` present and valid on memory records,
  scope+body present, scope carries 1-3 tags from the fixed area set with
  no duplicates, subpath on the primary tag only, `other` alone and holding
  at most 5 live records, digest-block headline (first paragraph) present (a heading
  terminates it; headline length is a soft ~300 guide not enforced by --check), supersedes on tombstones, plan+up/down
  on votes records.
- `scripts/zamm-new-memory.sh` — creates collision-safe record files
  (date-slug-random-suffix) with the frontmatter skeleton; `--date` backdates
  filename, `created:`, and year directory together (for migration).
- `references/templates/memory-record.template.md` — record schema template.
- `references/migrations/v1-v2-to-v3-memory.md` — combined migration guide
  (v1 Bedrock era and v2 Boulders era both migrate directly to v3).

## Changed files

- `references/scaffold/protocol-body.template.md` — knowledge sections
  rewritten: Ledger Memory Model / Distillation / Reconciliation / Erasure
  replace Knowledge Tier Motion; session start compiles+reads the digest;
  plan transitions write a votes record instead of editing card counters;
  precedence and key constraints updated. Plan-model sections unchanged.
- `scripts/zamm-scaffold.sh` — creates `knowledge/` instead of tier files;
  manages `.gitignore` (`zamm-memory/.compiled/`) and `.gitattributes`
  (`zamm-memory/**/*.md text eol=lf`); refuses to scaffold over pre-v3 trees
  (points to the migration guide); bedrock auto-migration removed; version 3.
- `references/scaffold/version.template` — `3`.
- `references/initialization/existing-project.md` — presents the fixed
  8-area set with boundary tests, then seeds ledger records rated with
  importance/durability and tagged with 1-3 areas; trigger is an empty
  digest instead of empty BOULDERS.md.
- `references/migrations/README.md` — current version 3; single combined
  guide.
- `SKILL.md` — runbook includes compile step; scaffold guard noted.
- `README.md` — ledger model replaces the tier/threshold documentation;
  animal complexity appendix unchanged.
- `references/scaffold/rule-header.mdc` — description no longer names the
  retired tiers.
- `references/eternal/knowledge.md` — initialization target is the ledger,
  not `active/knowledge/`; EK13/EK14 speak of records and supersession.

## Removed (not present in v3)

- `references/scaffold/knowledge-boulders|cobbles|pebbles|sand.template.md`
  — no tier files exist in v3.
- `references/migrations/v1-to-v2-memory.md` — superseded by the combined
  guide; preserved in git history.
- Tier thresholds, `Next ID` counters, consolidation pass rules, and
  consolidation archive records — replaced by compiler ranking and ordinary
  supersession.
- `zamm-memory/archive/knowledge/consolidations/` in new scaffolds
  (existing ones stay as history).

## Unchanged (copied verbatim)

- `scripts/zamm-archive.sh`, `scripts/zamm-status.sh`
- `references/templates/plan.template.md`
- `references/scaffold/agents-header.template.md`,
  `references/scaffold/cursorignore`
- `LICENSE`

## Not in this draft (generated per-project, not skill sources)

- `AGENTS.md`, `.cursor/rules/zamm.mdc`, `.cursorignore`, `zamm-memory/` —
  produced by `zamm-scaffold.sh` in target projects.

## Locked 2026-07-18 (post history-replay dogfood)

- **Live-only migration.** v1/v2 → v3 transfers only cards currently living in
  the active tier files. Do not import `archive/knowledge/consolidations/` (or
  other archive history) into the ledger. Smaller footprint, no promo-orphan
  heads, no fabricated reconciliation from bulk history. Leave the old archive
  on disk as v1/v2 history; git already preserves it.
- **Headline craft over mechanical rewrite.** Migration should preserve each
  card's statement essence as a clean digest headline (natural imperative or
  clear descriptive sentence). Do not mechanically prefix `Remember:`.
- **Optional git recovery.** Consolidations often lack full dropped-card bodies.
  If historical card text is needed for some other purpose and git history of
  the tier files is available, recovering text from git is an optional
  suggestion — never a migration requirement. Many projects will not have git
  (or deep enough history).
- **Deferred: cold archive offload.** Moving definitely-outdated ledger files
  (tombstoned / long-dormant) via `git mv` into a directory the compiler does
  not scan is deferred until more operational experience. Today dormancy +
  tombstones keep them out of the digest while remaining greppable in-tree.

## Locked 2026-07-18 (documentation refactor review)

Decisions from the two-reviewer README/SKILL refactor pass:

- **Live guardrails never go dormant.** `zamm-compile.sh` no longer marks
  guardrails dormant below the score floor; a live guardrail is always in the
  Digest layer. `!` is a safety contract — a guardrail leaves the digest only
  via supersession or tombstone, never silent decay or downvotes.
- **`--check` is a Distillation gate.** A ledger write is complete only after
  `zamm-compile.sh --check` passes and the digest is recompiled. The skeleton
  from `zamm-new-memory.sh` is a draft; records are immutable after commit,
  not before.
- **Precedence after skill updates:** the project's rendered runtime files are
  operative; SKILL.md mandates a drift notice via the `SKILL-BLOCK ... version=`
  stamp in `AGENTS.md` and offers `--overwrite-templates` before proceeding.
- **`--overwrite-templates` now refreshes every scaffold-managed runtime file**
  (`.cursor/rules/zamm.mdc` and `.cursorignore`; the `AGENTS.md` managed block
  is re-rendered on every run regardless).
- **Conflict claims are defensive:** "conflict-resistant, not conflict-free" —
  add-only writes avoid ordinary content conflicts; semantic conflicts surface
  as explicit reconciliation; plan files remain mutable and can conflict.
- **Terminology:** the record body above `## Background` is the "digest block"
  (headline + elaboration) everywhere; "short form" retired. Scope catch-all is
  `other` (the earlier `inbox` name is retired).
- **Animal-scale definitions** live canonically as a comment in
  `references/templates/plan.template.md` (met when filling
  `Complexity-forecast`); the fuller cue table moved to
  `references/complexity-animals.md`. Removed from README entirely — the
  scale is agent-facing and the human surface stays lean.
- **Plans tail in the digest.** `zamm-compile.sh` appends `## Plans` — one
  compact 2-3 line entry per active plan: a status line (slug, complexity
  animal, done-when progress, last-updated), the plan title, and an `in:`
  scope line when the plan carries one inline. Entries are status-ranked
  (Review, Implementing, Draft; terminal plans still in `active/` flagged
  archive-ready). All active plans are listed — no budget. The tail ends with
  the newest 10 archived plan IDs (directory-mtime order, so archive moves
  arriving via git pull surface first) — a referenced plan that vanished from
  `active/` stays findable. Derived at compile time, so the
  no-maintained-index rule stands; session start no longer needs a separate
  plan-discovery pass and `zamm-status.sh` remains the on-demand verbose view.
  Recompile triggers: plan creation and archiving always recompile
  (`zamm-archive.sh --archive` does it itself); other transitions are caught
  by the ledger-write transaction's recompile during transition distillation.
- **Three explicit human-facing distillation triggers.** (1) An explicit
  "remember this" is written the same turn — the anti-churn damping never
  applies to explicit requests (precedence rank 1). (2) An emotional human
  complaint triggers a short-lived record (`days`/`weeks`) when substance
  sits behind the emotion — record the fact/cause/correction, never the
  emotion. (3) Exceptional praise triggers the symmetric short-lived record
  of what earned it, so following sessions repeat the pattern. All three:
  supersede with longer durability if the statement proves out.
- **Trigger prose compacted out of the always-on surface.** The Distillation
  section carries only one-line trigger cues plus a do-not-write line; full
  semantics, durability guidance, and rationale moved to
  `references/distillation-triggers.md`, read on demand. The cues are
  deliberately coarse — we accept some deviation from ideal firing rather
  than pay for precision in every session's context. The SKILL dispatch
  table likewise carries one trigger row instead of eight.
- **Corrections, research, and external-change triggers.** (1) A human
  correction or standing rule stated in passing distills at any emotional
  temperature (`conventions` / `meta`) — session instructions evaporate
  otherwise. (2) Significant research results (plan-less sessions included,
  per the Session End backstop) distill only with details in a pointable
  file: the record is conclusion + pointer; free-floating transient values
  with nowhere to recheck are forbidden. (3) External changes are not
  recorded on their own — only via the failure triggers or drift
  supersession; we cannot remember every little thing.
- **Never quote the human verbatim.** Records always paraphrase the human's
  substance and describe the emotion instead of recording raw words —
  ledger records are permanent and team-visible; profanity and
  heat-of-the-moment phrasing must never be immortalized. Stated in the
  record file rules (beside the no-secrets rule) and in the SKILL ledger
  write transaction.
- **Repeated-failure triggers.** The same failure twice distills at the
  moment of the repeat, not at plan closure. With a working alternative
  found: record cause + alternative (guardrail-grade when real time was
  wasted). Still stuck: record the dead end — goal, attempted approach,
  failure mode, what was ruled out — short-lived (`days`/`weeks`) so the
  attempt survives the session and the next one starts past it; the solving
  session supersedes it with the answer at longer durability.
- **`kraken` added as the off-scale wicked marker.** Wickedness is orthogonal
  to size: the problem looks solvable but never truly resolves — each attempt
  only redraws the perceived shape. Plans forecast `kraken` when facing one
  and MUST be scoped as bounded probes (closeable `Done-when`), never as
  "solve it"; each engagement's updated shape-perception gets distilled into
  the ledger.

### Documentation ownership map

One normative home per fact class; every other surface links or paraphrases
behavior — it never restates numbers.

| Fact class | Normative home |
| --- | --- |
| tuning constants (budgets, penalties, floor, vote weight) | `scripts/zamm-compile.sh` header |
| record schema, ledger + plan semantics, MUST rules | `references/scaffold/protocol-body.template.md` |
| distillation trigger semantics | `references/distillation-triggers.md` |
| fill-in shapes | `references/templates/` |
| gated procedures (initialization, migration) | guides under `references/` |
| digest entry format | the digest's own self-describing header |
| activation, state dispatch, command mechanics | `SKILL.md` |
| concepts, pitch, human workflow | `README.md` |
| design rationale and change history | `DELTAS.md`, `research-report.md` |
