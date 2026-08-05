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

## Locked 2026-08-03 (second external review remediation)

A second technical review scored the project a credible supervised beta and
listed six P0 integrity defects plus a set of High/lower findings. Every claim
was reproduced against the live scripts before any change; each fix ships with a
regression lock in `tests/test_remediation5.py`. The compile exit codes are now
a documented taxonomy: `0` clean, `1` check/usage failure, `2` published but
degraded (a `## Degraded` section is present), `3` refused (records exist but
none survived), `4` ledger enumeration failed (previous digest untouched), and,
at the dispatcher, `5` protocol-version mismatch.

P0 — trust boundary:
- **Enumeration fails closed.** The record scan was `{ find; find; } | sort |
  awk`, whose exit status is the pipeline tail, so a `find` that could not read
  a subtree returned 0 and the digest silently dropped those records. It now
  builds a manifest with every step checked; a traversal or sort failure exits 4
  and leaves the previous digest in place. An unreadable individual file
  quarantines with a clear reason instead of a misleading "missing frontmatter".
- **All cycles detected.** The early-return DFS quarantined only the first cycle
  and left stale grey state, so a second disjoint cycle reachable through a
  shared node was applied silently. Replaced with iterative Tarjan SCC: every
  strongly-connected component that is a cycle is quarantined as a unit,
  regardless of overlap or discovery order, and there is no recursion depth to
  overflow on a long chain.
- **Aggregation walks only applied edges.** Vote/ancestry aggregation read the
  raw `supersedes:` data, so a vote leaked into a valid head through a
  quarantined or dangling ancestor, and the walk was capped at 500 enqueued
  nodes (a silent truncation). It now traverses `asup[]` — the edges that
  actually survived validation — with a visited set and no cap.
- **Runtime version gate.** The scaffold refused an incompatible `VERSION`, but
  operational commands ignored it. The dispatcher now refuses every command that
  interprets ledger data when `VERSION` is missing/malformed/≠ 3 (exit 5),
  pointing at migration; `status` reports the mismatch instead of refusing.
- **Degraded is visible.** A dangling `supersedes:` target used to print to
  stderr but exit 0 with `quarantined=0` and no marker. Dangling references (and
  duplicate vote records) now render under `## Degraded` and force exit 2.

High / data model:
- **Vote hygiene.** A target repeated within `up:`/`down:`, or present in both,
  quarantines the votes record (no more forged `+3` from one record); more than
  one active votes record per plan is a degradation and only the newest counts.
- **Migration seeds bounded.** `seed-up`/`seed-dn` must be non-negative integers
  ≤ 10000 (a negative `seed-dn` used to ADD score); `migrated-from` must be a
  provenance token, not free text.
- **Archived records are supersede-addressable.** A new record may supersede an
  archived id (treated as known-inert, like a shunned id) instead of failing
  with "target not found".
- **Abandon rule matches the protocol.** `plan check` requires the full
  retrospective on an Abandoned plan only when work happened (an
  `Execution-context-before` was filled or a `Done-when` item checked); a
  never-started Draft→Abandoned needs only a `## Loose ends` rationale.
- **Plans reconcile with the ledger.** Top-level `check` runs a new
  `zamm-crosscheck.sh` that verifies a plan's `Memory-upvotes/downvotes` match
  an active votes record naming that plan.

Lifecycle, surfaces, docs:
- **Two-phase record creation.** `memory create` writes an `<id>.md.draft` the
  compiler ignores; `memory publish <id>` validates it and atomically renames it
  into the ledger (rolling back to a draft on failure), so a record composed
  over several edits never appears half-finished. `--immediate` keeps the old
  one-step behaviour for scripted/migration use. The generator now rejects an
  empty scope component (parity with the compiler) and every value-taking option
  reports a missing argument instead of a `set -u` crash.
- **Machine-readable state sidecar.** The compiler writes `.compiled/state.tsv`
  (counts + the ids the digest selected) beside `memory.md`; `status` and
  `memory list` read it instead of reverse-parsing Markdown — this fixes the
  contested-guardrail double-count in `status` and stops `memory list` from
  treating a record id embedded in a plan title as selected.
- **Drift stamp covers all normative inputs** (`SKILL.md`, all of `references/`,
  all of `scripts/`), not just the scaffold fragments — one-time re-scaffold.
- **Scaffold** writes its managed block through a sibling temp file (atomic
  rename on the repo's own filesystem), and its next-steps use `plan create`
  and `memory create/publish` rather than manual `mkdir`/`cp`.
- **`plan archive --list`** is a real read-only preview; the docs no longer
  describe a nonexistent two-run flow. The README narrows the platform claim to
  macOS/Linux (CI-verified), Git Bash noted as unverified. The approximate
  372-day/31-month `daynum` is documented as decay-only, not a calendar count.

## Locked 2026-08-04 (second-pass review of the remediation)

An independent in-house review of the remediation above found ten further
defects, several at the trust boundary. All reproduced before fixing; locks are
the `Rev2*` classes in `tests/test_remediation5.py`.

- **`memory publish` is now interrupt-safe and pre-existing-degradation-safe.**
  The draft was renamed into place before validation with no rollback, so a
  Ctrl-C (or SIGKILL) between the rename and the recompile left a live record
  with a stale digest and no draft. A rollback trap now returns the record to a
  draft on any non-clean exit or signal (SIGKILL remains unpreventable, but an
  interrupted commit of a VALID record just needs a recompile, and an invalid
  one is quarantined+surfaced on the next compile — it fails safe). Validation
  also now blames only the draft (checks whether `--check` names its id) instead
  of gating on the whole ledger, so a valid draft publishes even when unrelated
  records are already quarantined, and the recompile treats exit 2 as success.
- **Invalid vote references degrade the publish.** A votes record naming a
  missing or non-memory target printed to stderr but published exit 0 with no
  Degraded section (normal compile and `--check` disagreed). Bad vote refs now
  render under `## Degraded` and force exit 2, matching dangling supersedes.
- **The plan↔votes cross-check reads the compiler graph.** A new compiler mode,
  `--list-votes`, emits the active (counted) votes records (`id<TAB>plan<TAB>up
  <TAB>down`); `zamm-crosscheck.sh` consumes it instead of reconstructing "which
  votes record is superseded" from the filesystem. This fixes three defects at
  once: a votes record naming a nonexistent plan is now caught (orphan guard); a
  vote id that is a substring of a longer id on a `supersedes:` line no longer
  reads as a false supersede; and a project path containing spaces no longer
  breaks the check (no word-split of `$(...)` output).
- **`plan archive` accepts a degraded recompile.** Exit 2 (a digest published
  but degraded by unrelated records) was treated as a failure and rolled the
  archive back, so unrelated ledger degradation blocked archiving a valid
  terminal plan. Both archive scripts now treat 0 and 2 as success.
- **Worked-on Abandoned plans are fully validated.** The work-happened branch
  required only the retrospective; it now also requires Execution-context-before,
  Complexity-forecast, and a `## Loose ends` rationale (matching
  Implementing→Abandoned). The Loose-ends check filters the trailing telemetry
  fields the template places under that heading.
- **The generator writes a normalized scope.** It validated trimmed tags but
  wrote the raw `--scope` argument, so a leading newline survived into a record
  the compiler then rejected. The written scope is now rebuilt from the trimmed
  tags.
- **No buggy sidecar fallback.** `status` and default `memory list` no longer
  fall back to reverse-parsing the digest when `state.tsv` is absent (that
  fallback reproduced the double-count and plan-title-leak bugs); they ask for a
  recompile instead. The sidecar is now renamed BEFORE the digest, so a fresh
  `memory.md` never pairs with a stale sidecar.
- **Help never hits the version gate.** `memory list/create/publish/show --help`
  and `plan create/check --help` exit 0 on a version-mismatched project; only
  real commands refuse.

## Locked 2026-08-04 (third-pass review: trust-boundary gaps)

A re-review of the second-pass remediation confirmed the first-order fixes but
found the trust boundaries around them still porous. All reproduced before
fixing; locks are `tests/test_remediation6.py` (`Rev3*` classes), each seen
failing against the pre-fix scripts.

- **Publish verdicts come from a before/after error diff, not a substring
  match.** `memory publish` judged the candidate by grepping its id in `--check`
  stderr. That failed both ways: an unrelated error whose path embedded the
  candidate id as a substring of a longer id rejected a valid draft, and a bad
  draft PUBLISHED whenever its new error named some other record (duplicate
  votes blame the canonical id) or none at all (`other holds 6 live records`).
  The ledger's `--check` error set is now captured before the rename and again
  after; any error line present only after was introduced by the candidate and
  rolls it back. Pre-existing errors still do not block a valid draft. A check
  that cannot run at all (rc >1, e.g. enumeration failure) fails closed. Both
  verdict paths roll back inline so the EXIT trap no longer misreports a
  validation failure as "publish interrupted". An automated process-group
  SIGINT test now covers the interrupt rollback.
- **`plan:` is a slug, never a path.** The compiler accepted any non-empty
  `plan:`, and the cross-check used the value in a filesystem lookup — so
  `plan: ..`, `plan: ../plans`, and `plan: ../../knowledge` all resolved to
  real directories and an orphan votes record passed `check` while applying its
  votes. The compiler now quarantines any `plan:` not matching
  `[a-z0-9][a-z0-9-]*`; the cross-check keeps a charset guard as defense in
  depth and requires an actual `<slug>/<slug>.plan.md` (an empty directory
  under `archive/plans/` is not a plan).
- **Vote bookkeeping cannot be laundered through Abandoned or the archive.**
  Agreement checking covered only active Review/Done plans. Now: a counted
  votes record must match its plan's declared sets whatever the status and
  whether the plan is active or archived; declared `Memory-upvotes/downvotes`
  with no votes record is an error for Review/Done/Abandoned and for archived
  plans whose declared targets look like v3 record ids. Pre-v3 archived plans
  declaring legacy card ids (`W2`, `S18`) are exempt — their votes were
  migrated as record seeds and have no votes record to reconcile.
- **Zero-live ledgers still degrade.** The zero-live branch exited 0 with a
  clean "not initialized" digest even when the ledger held invalid vote
  references or duplicate votes records. It now renders `## Degraded` under
  the not-initialized line and exits 2, so known graph defects can no longer
  masquerade as a healthy empty ledger.
- **`--list-votes` is a real TSV surface.** It emitted raw frontmatter values;
  a TAB is legal whitespace inside a vote list, so `up: a,<TAB>b` produced a
  fifth column and the cross-check read `b` as a downvote. Lists are now
  normalized (trimmed, empties dropped, interior tabs neutralized) before
  emission.
- **The digest/sidecar pair carries a generation token.** Rename ordering only
  chooses which mismatched pairing survives a crash between the two renames.
  Both files now carry the same generation token (a checksum of the digest
  content); `status` and default `memory list` verify it and treat a mismatch
  as "recompile" instead of mixing authorities. `memory archive`'s
  digest-unchanged comparison excludes the trailer (it covers the header,
  whose `files=` count legitimately drops).
- **Worked-on Abandoned plans inherit Scope/Done-when validation.** The
  work-happened branch now also requires In/Out scope content, at least one
  Done-when item, and well-formed checkboxes, so an empty scope or a `- [?]`
  marker cannot become valid by abandoning the plan.
- **The cross-check fails closed.** `--list-votes … || true` swallowed compiler
  failures, so an unenumerable ledger produced an empty votes list and the
  cross-check passed a ledger nobody read. It now accepts rc 0/2 only and
  fails loudly otherwise.

Known accepted residual: SIGKILL between the publish rename and recompile
still needs the next compile to reconcile (fails safe: the record is valid or
quarantined-and-surfaced).

## Locked 2026-08-04 (fourth pass: digest publication is serialized)

A fourth review pass confirmed every third-pass fix and reproduced two
remaining defects. Locks: `Rev4*` classes in `tests/test_remediation6.py`,
both seen failing against the pre-fix scripts.

- **Concurrent publishes can no longer lose a record from the digest.** Each
  compile snapshots the ledger into a private manifest and atomically renames
  its result into place — atomic against torn reads, but a lost-update hazard:
  an older, slower compile could land LAST and overwrite a newer digest with a
  stale but internally-coherent digest/sidecar pair (the generation token
  pairs the two files; it cannot rank two coherent pairs). Two interleaved
  publishes both reported success while the final digest silently omitted one
  record. Publish-mode compiles now take a project-scoped lock
  (`.compiled/.compile.lock`, portable mkdir mutex) held from BEFORE manifest
  enumeration until exit, so published ledger views are monotonically fresh:
  every published digest was enumerated after the previously published one,
  and a completed publish can never vanish from a later digest. Read-only
  modes (`--check`, `--list-*`) skip the lock; a lock abandoned by a killed
  compile is stolen once its recorded owner pid is gone; a lock held over 60s
  fails with exit 4 (previous digest untouched) and points at the directory.
  The regression lock interleaves two publishes deterministically via a
  PATH awk shim and asserts both records reach the final digest and sidecar.
- **Tabs in plan vote fields reconcile.** The cross-check normalized only
  commas and spaces when comparing a plan's `Memory-upvotes/downvotes` with
  the votes record, so a legal TAB separator made semantically identical sets
  disagree. `norm_set` now splits on tabs as well, both plan- and ledger-side.

## Locked 2026-08-04 (fifth pass: stale-lock recovery serialized)

A fifth review pass confirmed the fourth-pass fixes in normal operation and
reproduced one narrower race in the new stale-lock recovery itself. Lock:
`Rev5StaleLockReap` in `tests/test_remediation6.py`, seen failing against the
pre-fix scripts with the exact symptom (a record lost from the final digest).

- **Reaping a dead-owner lock is now serialized and revalidated.** Every
  contender independently read the stale pid, decided it was dead, and ran
  `rm -rf` on the lock — so two contenders could both authorize removal of
  the same stale lock, and the slower rm then destroyed the lock the faster
  contender had already REACQUIRED, putting two compiles back in flight (the
  original lost-update, resurrected through the recovery path). Removal now
  happens only while holding a second mutex (`.compiled/.compile.reaper`)
  and only after re-reading the pid file and confirming it still names the
  SAME dead owner. That revalidation is sound because a new owner can only
  appear after the stale directory is removed, and removal only happens
  inside the reaper mutex — a fresh owner that has not yet written its pid
  file reads as a changed pid and is left alone.
- **The cleanup trap checks ownership before releasing.** The EXIT trap
  removed the lock whenever this process had ever acquired it; it now
  releases only while the lock's pid file still names the exiting process,
  so even a hypothetical future mis-reap could not cascade into a second
  lock destruction.
- **Liveness probing tolerates EPERM.** `kill -0` reports failure for a live
  process owned by someone else; a `ps -p` fallback keeps such a lock from
  reading as dead.
- A reaper mutex abandoned by a process killed inside its microseconds-wide
  critical section is NOT auto-reaped (that would recurse the same problem);
  the 60s timeout message names both directories for manual recovery, and
  the previous digest stays untouched.

## Locked 2026-08-05 (third external review remediation)

Trust-boundary round: every reader of erasure policy, plans, and drafts now
fails closed, and publication is overlay-validated under one held lock.

- **shun.md fails closed.** An unreadable or symlinked shun file aborted
  nothing before: the compiler silently proceeded with an EMPTY substitute
  shun set and resurrected erased content into the digest. Both cases are now
  fatal (exit 4, previous digest untouched) — a failing READ must never widen
  validity. A missing shun.md stays a legal empty set.
- **Plans enumerate through one checked manifest.**
  `zamm-plan-manifest.sh` is the single tagged enumeration of both plan
  trees (PLANDIR/PLANFILE/SUBPLAN/ARCHDIR/ARCHFILE/SYMLINK/NOTDIR/
  UNREADABLE/DUP); plan check, the digest plans tail, status, plan list,
  the archive helper and the cross-check all consume it. A private glob
  over an unreadable tree used to report "0 plans" and `[ -d ]` followed
  symlinked directories into external content; now an unreadable tree is
  exit 4 everywhere and symlinked entries are rejected without ever being
  read (digest renders name-only Invalid lines).
- **Plan ids are unique across active AND archive.** `plan create` refuses a
  slug present in either tree; the manifest tags hand-made collisions DUP
  and plan check reports them.
- **Publish validates by overlay, not rename-then-check.** The compiler
  gained `--check --with-candidate <draft>`: it stages a private copy of the
  draft under its final id and validates the ledger as if published, so the
  live namespace never holds an unvalidated record. The verdict diffs
  `zamm-compile: ERROR:` lines only against a same-lock baseline — a
  warning-only candidate publishes cleanly even beside unrelated
  pre-existing errors.
- **The whole publish transaction runs under the compiler's publication
  lock** (extracted to `zamm-lock.sh`, delegated to child compiles via
  ZAMM_LOCK_HELD): baseline, overlay verdict, rename, recompile, sidecar
  commit. No concurrent compile can publish a digest naming a record that is
  later rolled back; the interruption trap recompiles under the still-held
  lock. `status` additionally cross-checks the sidecar file count against
  the records on disk and reports divergence as STALE.
- **Archived and shunned supersede targets are inert graph nodes.** Their
  ids, types and (for archived records, header-parsed) supersedes edges keep
  union-find grouping, conflict detection and lineage alive — two live
  successors of one retired target surface under Needs reconciliation again
  — while contributing no content, votes, or ranking credit. Type
  compatibility is enforced into the archive; "keep their place in the
  chain" is now true rather than aspirational.
- **`plan archive` gates on the plan/ledger cross-check** (both the
  dispatcher and the helper), so a plan whose votes record disagrees with
  its declared Memory-upvotes/downvotes cannot be laundered into history.
  `--list`/`--dry-run` stay gate-free.
- **Drafts are visible.** `memory drafts` lists unpublished `.md.draft`
  files with age (STALE past ZAMM_DRAFT_STALE_DAYS, default 7), `status`
  counts them, `memory discard` shows-then-deletes one (never a published
  record). SKILL.md/README/help now document the real transaction:
  create -> fill -> publish -> check.
- **Always-on surfaces shrank to a router.** scaffold renders
  `protocol-router.template.md` (~2.4KB per surface) into AGENTS.md and
  `.cursor/rules/zamm.mdc` instead of the full ~27KB protocol body; the
  full body stays in the skill, loaded on demand at the decision points the
  router names. Re-scaffolding migrates existing installs; the stamp change
  makes every scaffolded project read STALE once until re-scaffolded
  (expected).
- Mechanical: scaffold writes VERSION via temp-file + atomic rename; the
  status version-mismatch line points at migration guides instead of
  scaffold (which refuses pre-v3 trees); permission-bit tests skip with an
  explicit reason under root (geteuid()==0), where chmod 000 does not deny
  access.
