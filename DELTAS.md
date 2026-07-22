# v3 — change map vs. v2

This file records what changed in the v3 skill tree and why. Decisions
locked 2026-07-14/16: random 5-char suffix from a 30-symbol
reduced-Crockford alphabet; votes as one batch record per plan closure;
plan directories unchanged; digest attention budget Digests 75 full blocks +
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
| tuning constants (budgets, penalties, floor, vote weight) | `scripts/internal/zamm-compile.sh` header |
| record schema, ledger + plan semantics, MUST rules | `references/scaffold/protocol-body.template.md` |
| distillation trigger semantics | `references/distillation-triggers.md` |
| fill-in shapes | `references/templates/` |
| gated procedures (initialization, migration) | guides under `references/` |
| digest entry format | the digest's own self-describing header |
| activation, state dispatch, command mechanics | `SKILL.md` |
| concepts, pitch, human workflow | `README.md` |
| design rationale and change history | `DELTAS.md` |

## Locked 2026-07-20 (post external-review hardening)

An external technical review found nine defect classes; every one was
reproduced locally before any code changed. Two governing invariants came
out of that work:

- **Fail open on content, fail closed on authority.** An invalid record may
  be dropped from the digest, but it must never suppress, supersede, or
  outrank a valid one. Invalid input degrades itself, not its neighbours.
- **"No memory" and "unreadable memory" are different states.** Session
  start offers initialization when the digest is empty, so a compile failure
  that produced an empty-looking digest could invite re-seeding over an
  intact ledger. That path is now unreachable.

Compiler correctness:
- Per-process temp files + `trap` + one atomic `mv`. Concurrent compiles
  previously raced on a shared `memory.md.tmp`: 12 parallel runs left a
  56-byte digest with zero records. Now 0 failures, no stray temps.
- Digest header carries provenance: `files=N parsed=M live=L quarantined=Q`.
  Publishing is refused (exit 3, previous digest untouched) when records
  exist but none survived validation. A genuinely empty ledger still
  compiles the "not initialized" digest, so initialization stays reachable.
- Quarantine replaces fail-open leniency: a record failing the contract is
  excluded from liveness, supersession, votes and ranking, and its
  `supersedes:` edges are ignored — previously an invalid successor silently
  retired a valid guardrail while the compile exited 0. Casualties are listed
  under `## Degraded`. `--check` still exits non-zero.
- Reconciliation no longer consumes digest eligibility. Competing heads keep
  their FULL blocks in `## Digest` marked `~`; the reconciliation section is
  an index. Previously two conflicting guardrails collapsed to one-line
  headlines and their elaboration vanished exactly when knowledge conflicted.
- Superseded/tombstoned votes records stop counting, so superseding a votes
  record is a working correction path.
- Shunned IDs are valid redacted graph nodes: the documented erasure
  procedure (shun + delete) no longer leaves the ledger permanently failing
  `--check`.

Validator (one authoritative contract across `--check`, normal compile and
`zamm-new-memory.sh`): real Gregorian dates (leap years included), exact
filename contract (slug ≤40, suffix from the 30-symbol alphabet), scope
integrity (empty components, duplicate supersede targets), graph integrity
(self-supersession, cycles, supersede type rules), duplicate frontmatter keys
rejected, unknown keys warned with `x-` reserved for extensions, tombstone
reason required, votes body required empty. The generator gained calendar
validation for `--date` and now requires `--scope` for memory records rather
than emitting a skeleton that cannot compile.

Scaffold safety: `ensure_line` and the managed-block writer detect a missing
trailing newline before appending (a `.gitignore` ending without one had its
last rule and ours glued into a single invalid line) and write via temp +
rename with permissions preserved. VERSION gating became a strict state
machine — 3 proceeds, any other value refuses, missing-with-content refuses,
missing-and-empty is a fresh install — replacing an inference that silently
relabelled a v2 project as v3. Malformed AGENTS blocks refuse instead of
deleting from the begin marker to EOF. `.cursorignore` became a managed block
so user rules and ZAMM rules coexist. Non-git installs stamp a content hash
instead of the literal `local`, which could never detect drift. Missing
template fragments are fatal, so VERSION is never stamped by an install that
could not render the protocol.

Performance: insertion sort → heapsort, conflict grouping → single bucketing
pass, and a provably-safe early exit in greedy digest selection (scores are
descending and penalties are non-negative). 4000 records: 9.9s → 1.07s;
8000 records: 2.64s. Digest output verified byte-identical to the previous
compiler on a 400-record ledger exercising crowded areas, multi-tag records
and guardrails.

Protocol changes:
- **Reconciliation no longer forces fabrication.** The old rule required a
  "conservative union" merge record even when ground truth was undeterminable.
  In an append-only ledger that permanently records a claim nobody believed,
  and the `suspected drift` marker excusing it decays out of the digest long
  before the claim does. Unresolved groups now stay unresolved and visible,
  with a note of what evidence would settle them. A merge record is written
  only when its author believes it.
- Plans are required for substantive work only; question-answering, lookups
  and trivial single-file edits need none. Session start and session end
  previously contradicted each other on this.
- `Wellbeing-before`/`Wellbeing-after` → `Execution-context-before`/
  `Execution-friction-after`. The fields had no defined referent, and plan
  files are committed and team-visible, making a psychological reading a
  privacy problem. The renamed fields describe the work: uncertainty,
  missing access, tooling friction, rework. The Complexity
  forecast/felt/delta triple is unchanged — forecast-vs-actual is the
  measurable signal in that block.
- Chain-depth credit capped at 2 hops. Uncapped it compounded with inherited
  ancestor votes, so the statements revised most often — the least settled —
  ranked highest.
- `--check` warns above 15 live guardrails: guardrails bypass the digest
  budget and never decay, so inflation grows the surface silently.
- Bounded-attention claims corrected: only the 75 Digest blocks and 150
  Headlines are capped. Guardrails, conflict heads, active plans and the
  archived tail are listed in full.
- Every rendered command carries `--project-root <repo-root>`; the token is
  defined alongside `<zamm-skill>` in Script Path Resolution.
- Distillation triggers now separate attention lifetime from storage
  retention (`durability: days` still means "in git forever") and direct
  distillation at the technical rule, never identifiable interpersonal events.
- The migration guide gained a remediation path for plans left open across a
  migration: clear their v2 vote fields rather than converting them, since
  the signal already lives in migrated `seed-up`/`seed-dn` and a
  today-dated votes record would carry full recency weight.

Portability and naming honesty: README no longer claims the whole toolchain
is POSIX sh (`zamm-compile.sh` and `zamm-new-memory.sh` are; scaffold,
archive and status need bash). The ID suffix alphabet is documented as
30 symbols, not base32, with collision risk framed as birthday-bounded within
a shared date and slug.

Deferred, not rejected: the executable plan state machine (its "Done implies
approval" guarantee needs a second user to pay for its surface), a
machine-checkable `evidence:` field, a 6-char suffix, a total-token digest
budget engine, and the vote-inheritance redesign (topic utility vs statement
correctness). The `.md.draft` record lifecycle the review proposed is
resolved rather than deferred: quarantine makes an unfinished skeleton
harmless.

Testing is tracked separately: synthetic-only fixtures ship in the repo, the
real playthrough data stays local, and a `ZAMM_TODAY` clock override (added
here) makes golden digests possible.

### Follow-on fixes found while building the test suite

- **Vote targets must be memory records.** The hardening pass specified this
  and shipped only the existence check, so a votes record could upvote a
  tombstone and pass `--check`. Now rejected. The offending target is
  skipped rather than quarantining the whole votes record, so co-listed
  valid votes still count.
- **`zamm-scaffold.sh` honours `ZAMM_TODAY`.** Its managed-block markers
  embed the date, so rendered surfaces were not reproducible and golden
  comparison of `AGENTS.md` / `.cursorignore` was impossible.
- **`--help` exits 0.** `zamm-scaffold.sh`, `zamm-archive.sh` and
  `zamm-status.sh` shared one `usage()` between an explicit help request and
  a bad argument, so `--help` exited 1 — which reads as failure and breaks
  `cmd --help && ...`. `usage()` now takes an exit code; bad arguments still
  exit 1.

### Test suite

`tests/` holds 101 standard-library tests (`python3 -m unittest discover`),
no dependencies and no virtualenv. Layers: happy paths, one regression lock
per defect reproduced on 2026-07-19, contract validation by family, exit-code
and warning semantics, a byte-compared golden digest, the attention budgets,
and the previously untested surfaces (`zamm-status.sh`,
`--overwrite-templates`, `--help`). CI runs ubuntu + macos, which is what
verifies the portability claim above.

Two disciplines are documented in `tests/README.md` because they are what
make the suite mean anything. Regression locks written after their fix are
run against the pre-fix scripts via `ZAMM_SCRIPTS_DIR` to prove they fail
there — 15 of 17 do, and the check caught one later test that was wrongly
claimed falsifiable. And the case-fold collision test, which can only run on
a case-sensitive filesystem, is protected by `ZAMM_REQUIRE_CASE_SENSITIVE=1`
on the Linux CI leg so it cannot silently skip everywhere and guard nothing.

## Locked 2026-07-20 (single entrypoint)

Everything is now reached through `scripts/zamm-run.sh`, a git-style
dispatcher over the five existing scripts. The scripts are unchanged and
still callable; they simply stop being the documented surface.

    zamm-run.sh scaffold             install/refresh ZAMM in this project
    zamm-run.sh status               health overview: ledger, plans, drift
    zamm-run.sh help [<topic>]
    zamm-run.sh memory compile       rebuild the digest
    zamm-run.sh memory check         validate the ledger, write nothing
    zamm-run.sh memory record <slug> create a record
    zamm-run.sh plan status          plan directories by status
    zamm-run.sh plan archive         archive terminal plan directories

**Driver: the permission surface.** Agent harnesses allowlist commands by
prefix, so five scripts meant five entries — and this repo's own config had
drifted to two exact-match entries covering two invocations of one script,
which stopped matching the moment a flag was added. One entrypoint means one
rule: `Bash(bash .../zamm-run.sh:*)`.

**The dispatcher resolves the project root**: nearest ancestor holding
`zamm-memory/`, else the git top level, with `--project-root` as an override
accepted in any position. Hardening item 5.8 had added that flag to every
rendered command because scripts resolving against cwd silently targeted the
wrong tree from a subdirectory; resolving in one place deletes the bug class
instead of documenting around it, and shortens every command in the
always-on surfaces. `scaffold` falls back to the working directory, since
installing into a fresh project must work where no ledger exists yet.

Naming decisions worth not relitigating:
- **`memory` / `plan` groups**, with `status`, `scaffold` and `help` at top
  level (the git shape). The grouping leaves room for the deferred
  `zamm-plan` state machine to land as `plan transition` without another
  pass over every doc site.
- **`record`, not `new`** — `new` is ambiguous beside a project-creating
  command, and `record` is the schema's umbrella noun (memory, tombstone and
  votes are all records), so it stays accurate for every `--type`.
- **`scaffold`, not `init`** — `init` names the act but not the thing, and
  collides with ledger initialization, which is a separate real operation
  with its own guide.
- **`check` as a first-class subcommand**, not `compile --check`.

`zamm-run.sh status` is new behaviour rather than re-plumbing: a read-only
health view aggregating what was previously scattered across compile stderr
and a separate script — version, rendered-surface drift against the
installed skill, ledger counts, dormant and unlisted totals, guardrail count
against its ceiling, `other` backlog, pending reconciliation groups, plan
buckets and archive-ready plans. It parses the existing digest rather than
recomputing, and reports a missing or stale digest instead of silently
regenerating one: a status command that mutates state makes "check the
state" change the state.

Exit codes pass through unchanged via `exec` — specifically the compiler's
exit 3 ("records exist but none survived; previous digest kept"), which a
dispatcher that flattened it to 1 would destroy. The test suite now reaches
the scripts through the dispatcher, so it exercises the documented path;
`Ledger.run()` remains as an escape hatch for addressing a wrapped script
directly.

## Locked 2026-07-20 (command surface v2)

The entrypoint grew into a user-centric surface. Four verbs mean the same
thing in both groups, and the gaps teach the data model: there is no
`update` (records are immutable — supersede) and no `delete` (append-only —
tombstone, or archive).

    zamm-run.sh scaffold / status / check / help
    zamm-run.sh memory digest | list | show | check | create | archive
    zamm-run.sh plan   list | show | check | create | archive

Naming, decided against the alternatives:
- **`create` in both groups.** `record` promises capture but the command
  writes an empty skeleton, and it reads wrong for `--type tombstone|votes`.
- **`list`, not `status`,** for enumeration — `plan status` described how
  output was grouped, not what it was, and it squatted on the name a future
  `plan status <slug>` should own.
- **`scaffold`, not `init`** — `init` collides with ledger initialization,
  which is a separate gated operation.
- Flags that set frontmatter keep the frontmatter key as their name.

**All mode flags deleted.** `--rebuild` went because compiling costs less
than deciding whether to skip it (0.27s at 1000 records), taking the whole
staleness-cache bug class with it. `--apply` went because `status` and
`plan list` already answer "what would move". `--overwrite-templates` went
because managed surfaces are generated and stamped, so refresh is simply
what `scaffold` means. What remains is `--project-root` and the content
flags on `create`.

New behaviour, not renames:
- **`status`** — read-only health view: version, rendered-surface drift
  against the installed skill, ledger counts, dormant and unlisted totals,
  guardrail and `other` backlogs, pending reconciliation, plan buckets,
  archive-ready and inert counts. Parses the existing digest; reports a
  stale or missing one rather than silently regenerating.
- **`plan check`** — validates the CURRENT STATE of every active plan:
  required fields for the declared status, no unchecked Done-when items at
  closure, valid dates. It does not validate transitions, so it does not
  reopen the deferred state machine. `plan archive` now runs it and refuses
  any plan that fails — which closes the external review's High 2 finding
  that a `Done` plan with empty approval evidence archived cleanly.
- **`memory archive`** — moves fully-retired chains out of the compiler scan
  path. The rule is narrow on purpose: votes aggregate over the whole
  ancestor chain of a record, so a dead ancestor of a live head is
  load-bearing and must not move. Measured on this repo, 8 of 14 dead
  records are exactly that. A component qualifies only when it holds no live
  memory record and no live votes record. `zamm-compile.sh --list-inert`
  owns the rule because it already owns the graph; archived ids are globbed
  by filename so references stay resolvable; and the command verifies the
  digest is byte-identical afterwards, rolling back if it is not. Verified
  by sabotaging the rule in a copy: the rollback restored all 67 files.
  This is the second documented exception to the never-move-records MUST,
  alongside Erasure.

## Locked 2026-07-22 (scripts/internal reorganization)

`scripts/` held nine scripts flat, but only one — `zamm-run.sh` — is a user
surface: the single-entrypoint design routes every command through it (one
permission-allowlist entry, `Bash(bash .../zamm-run.sh:*)`), and the other
eight are internal implementation it `exec`s. The flat layout hid that, and it
was exactly what made a raw helper like `zamm-archive.sh` *look* invocable —
the direct-invocation risk two review passes flagged.

The eight internal scripts moved to `scripts/internal/`; `zamm-run.sh` stays at
the top of `scripts/`. So `ls scripts/` now shows the entrypoint and an
`internal/` directory, and nothing else.

- `zamm-run.sh` resolves the internal scripts through a new `INTERNAL=`
  `$SCRIPT_DIR/internal` variable; its own `../references/...` template path
  still hangs off `SCRIPT_DIR`.
- `zamm-scaffold.sh` and `zamm-skill-stamp.sh` walk to the skill root as
  `$(dirname "$0")/../..` (one level deeper than before); sibling references
  (`zamm-memory-archive.sh` → `zamm-compile.sh`, `zamm-archive.sh` →
  `zamm-plan-check.sh`) are unchanged, since those scripts moved together.
- No permission change: the internal scripts are child processes of an
  already-allowed `zamm-run.sh`, never invoked directly.
- The stamp already hashes `scripts/` recursively, so the content stamp shifts
  once (a one-time re-scaffold), and the syntax-check test now globs
  `scripts/` recursively.

Naming: a subdirectory, not an `_internal` filename prefix — it groups all
eight at once and signals "not the surface" more clearly, without churning
every reference for a weaker signal. `zamm-run.sh` keeps its name so the
permission rule and the ~48 doc references stay stable.
