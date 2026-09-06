# v3 — change map vs. v2

**This is a changelog, not a description of the system.** For how ZAMM behaves
today, read `README.md`, `SKILL.md` and `references/invariants.md`; entries
here describe decisions at the moment they were taken, and some of them have
since been reversed (see the 2026-08-08 sections).

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

## 2026-08-03 to 2026-08-06 — nine review rounds, condensed

This file used to carry a section per external review round. Most of those
sections described gates that no longer exist, which made a changelog read
like a description of the system. They are condensed here; the round-by-round
detail is in git history, where a changelog belongs.

**What those rounds produced that is still true.** Trust boundaries: every
reader of redaction policy, plans and records fails closed, and the exit-code
taxonomy (0 ok / 1 contract / 2 degraded-but-published / 3 refused-publish /
4 unreadable / 5 version mismatch) dates from here. Graph correctness:
supersede edges are validated in three passes so an invalid record can never
retire a valid neighbour, all cycles are detected rather than the first,
applied-edge aggregation and dangling references degrade honestly, and votes
cannot be forged or laundered by abandoning or archiving a plan. Validation:
one authoritative contract shared by `--check`, normal compile and the
generator, so `memory create` cannot write a record the compiler refuses.
Surfaces: the single `zamm-run.sh` entrypoint, the command surface v2 verbs,
`scripts/internal/`, and the state sidecar that stopped `status` and `memory
list` reverse-parsing rendered Markdown.

**What those rounds produced that has since been deleted.** From roughly the
fourth round onwards the findings were transaction-identity and concurrency
defects: the publish freeze-copy-validate-commit sequence, the mkdir
publication lock and its stale-lock reaper, the archivers' ledger
fingerprints, per-item re-hashing and post-move sweeps, the quarantine
sidecar rows that let publish re-check itself. Every one of them defended the
gap between two syscalls against a process running as the same user — an
actor that can rewrite these scripts between runs, and one no threat model
had ever named. The 2026-08-08 pass below removed all of it and wrote
`references/invariants.md` so the question has a stopping rule.

The honest summary is that those rounds were the cost of two unstated
requirements, not nine independent defects. The correctness work above stands;
the hardening work was answering a question nobody had asked.

## Locked 2026-08-08 (erasure becomes a record; shun.md retired)

The redaction capability was worth keeping — measured, not assumed: deleting
an erased record without it leaves every successor dangling, so `memory
check` fails permanently, and a copy that reappears through a merge, an old
branch or a restore walks straight back into the digest. What was not worth
keeping was the SHAPE. `shun.md` was the only file in the tree whose absence
loosened policy, so every way of making it unreadable needed its own
fail-closed patch: unreadable (round 7), symlinked (round 7), and finally a
DIRECTORY named shun.md, which `find -type f` skipped — silently emptying
the redaction set, resurrecting erased content, with exit 0 and a passing
check.

- **Erasure is now an ordinary record.** `type: erasure` with
  `erases: <id>[,<id>...]` and a required body (the reason). It rides the
  enumeration, contract validation, symlink refusal and unreadable handling
  every record already gets, so the bespoke parser and its whole class of
  failure modes are gone — and a redaction now carries its date, author and
  reason, which a bare id list never could. `memory create --type erasure
  --erases <id> <slug>` writes one. Locked by `Rev7ErasureRecords`.
- **The erasure set is built before any graph pass**, from every erasure
  record, quarantined or not: an erasure can only REMOVE content, so
  honouring a dubious one is safe while ignoring a valid one resurrects
  redacted material. A malformed erasure record still quarantines loudly.
- **A leftover `shun.md` refuses the compile** (exit 4) in every form —
  file, directory, symlink, unreadable — because ignoring it would resurrect
  exactly what it suppressed. Testing the PATH rather than a `find` is what
  makes every file type equal, which is the defect that started this.
  `references/migrations/shun-to-erasure-records.md` documents the one-time
  migration; no VERSION bump (a v3-internal mechanism change).
- **Unreadable and symlinked records are now fatal (exit 4), not
  quarantined.** A quarantine assumes we know what the record was; we do
  not, and an unreadable or unfollowed ERASURE record silently stops
  redacting. Nothing distinguishes one from any other unread file, so the
  ledger is treated as unreadable rather than smaller — the same rule the
  archived headers and the enumeration already followed. Existing locks in
  `test_remediation4`/`test_remediation5` were updated with the reason.

Locked 2026-08-08 (requirements pass — `references/invariants.md`): after
nine review rounds the write path had been hardened against an adversary
nobody had ever specified. The invariants file now states what ZAMM
guarantees — every output is a truthful reading of some state the ledger
actually had, every failure is repairable by rerunning, bytes are never
destroyed — and, just as load-bearing, what it does not: a same-privilege
hostile process is out of scope, because it can rewrite these scripts
between runs. A finding that violates no guarantee is closed, not fixed.
That file is the stopping condition the review loop lacked.

Five gates replace the accumulated per-site policy. **G1** — a record is
composed in a private temporary file, validated there, and claimed under its
final name with a no-clobber `ln`, so what is validated is what lands, by
construction. The draft state is gone: `memory create` takes the body on
stdin (or `--edit`), which also makes it one agent call instead of three, and
`--no-validate` replaces the `--immediate` gate for bulk migration. A
hand-written `<id>.md.draft` is still publishable, now in ~30 lines instead of
392. **G2** — the digest is derived and disposable, so it is recomputed rather
than protected: no compile lock, no post-commit comparison, no quarantine
sidecar rows. Two concurrent compiles each publish a coherent snapshot and the
last wins; a digest one record behind is ordinary staleness, and `memory
digest` is the whole repair. **G3** — absent is data, unreadable is an error;
that one distinction replaces every bespoke fatal/quarantine/warn choice on a
failed read. **G4** — archival is not a transaction. The compiler reads the
live and archived trees both, so a half-archived ledger is a valid ledger and
a rerun finishes the job; the fingerprints, per-item re-hashing and final
sweeps are gone from both archivers. What remains is the self-check on our own
inert rule, which no rerun would repair. **G5** — the ledger holds real files
and real directories, nothing else, justified by self-containment (a ledger
must travel with its repository) rather than by security.

`scripts/internal/zamm-lock.sh` and the stale-lock reaper are deleted: all
four call sites were operations that no longer need exclusion. `plan create`
now lets the same-slug race happen and detects losing it, which has an exact
signature — the whole rendered tree nested under its own temp name inside the
winner's directory. Three filesystem realities likelier than any adversary are
now handled where they were previously silent or misdiagnosed: the same id
live and archived (an interrupted cross-device move, a sync client putting a
file back) warns and prefers the live copy, identical basenames in two year
directories no longer also report a bogus case-fold collision, and Windows —
claimed in the README, exercised by no CI leg — is no longer claimed.

Net effect: about 1,100 lines out of 6,250 removed from the shell, and the
most defect-dense of them. Roughly two dozen tests were DELETED rather than
adapted, because a test guarding an abandoned gate is what makes
over-engineering permanent; the invariants each one protected were
re-expressed against whatever replaced the gate. 388 tests green.

Locked 2026-08-08 (straightening pass): seven loose ends from the
requirements pass above, the first of which was the round's own miss —
`references/invariants.md` was written as the stopping rule for future
reviews and then linked from nowhere an agent or reviewer would look. It is
now cited from README.md, SKILL.md's Authority section and the protocol
template, so it reaches every scaffolded project rather than this repo alone.

Code and documentation had also drifted apart on symlinks: G5 states one
uniform rule (real files and real directories only, justified by
self-containment) while `zamm-paths.sh` still judged by position, with a case
statement and a comment about dangling links that existed only because the
rule used to be non-uniform. The function is now
`zamm_verify_no_symlinks` and refuses any symlink anywhere under either
knowledge tree; the shun.md migration probe was moved ahead of it so a
leftover shun.md symlink still gets the migration instructions rather than
the generic refusal. Dead `! -name 'shun.md'` filtering came out of a live
enumeration in `zamm-run.sh`.

Draft staleness is gone: the 7-day threshold, `ZAMM_DRAFT_STALE_DAYS`, the
`AGE UNKNOWN` column and the `STALE DRAFTS` status line all existed because
drafts were once the only way to create a record and could rot for weeks. A
draft is now a deliberate two-step composition, so `memory drafts` lists them
and `status` counts them without rating them — which took `draft_age_days`
and with it the toolchain's only non-POSIX `stat` call out of `zamm-run.sh`.

The test suite was re-filed. `test_remediation.py` … `test_remediation8.py`
answered "what did round 6 complain about" and never "where is the test for
erasure": 80 of 86 classes were named for a review round. All 239 tests moved,
none deleted, into one file per invariant — `test_writes` (G1), `test_digest`
(G2), `test_failclosed` (G3), `test_archival` (G4), `test_ledger_shape` (G5)
— plus `test_graph`, `test_plan_validation` and `test_cli_safety` for the
domain rules that are not gates. Duplicated module-level fixtures moved into
`harness.py`. DELTAS.md itself lost 640 lines: its nine per-round sections
described mostly-deleted gates, so they are condensed into one honest section,
and the file now says at the top that it is a changelog rather than a
description of the system.

Finally the falsification the requirements pass skipped: the three genuinely
new locks (the live-and-archived warning, the case-fold diagnostic, and
plan-create loser detection) were run against baselines with each defect
reinjected, and all three fail there and pass here. 389 tests green.

## Locked 2026-08-28 (ZAMM writes nothing into .cursorignore)

The Cursor Agent Sandbox maps every `.cursorignore`-matched path to EPERM,
and ZAMM enumerates its trees with checked `find(1)` calls that fail closed
on an unreadable path (G3). Those two facts make `.cursorignore` an unusable
place for a `zamm-memory` rule: the rule does not hide the tree from ZAMM, it
breaks whichever command walks it. Commit 6c37ed1 moved `archive/**` out
after `memory digest` broke, but kept the plan-workdir rules on the theory
that workdirs are scratch nothing reads. Two commands read them anyway —
`status` (staleness scan) and `plan archive`, whose self-containment scan
*must* walk `workdir/` because G5 refuses a symlink at any position — so both
still failed closed in the sandbox.

So the rule is now categorical rather than case-by-case: **ZAMM writes no
rules into `.cursorignore` at all**, only a comment explaining why. Every
rule lives in `.cursorindexingignore`, which keeps retired trees and plan
scratch out of codebase search without denying reads. There is nothing left
to reason about per-path, which is the point — the previous split invited
exactly the judgement call that got it wrong twice.

Three consequences, each locked by a test:

- **Re-scaffold reclaims what earlier versions wrote.** Projects scaffolded
  before the managed block existed (skill ≤ the first v3 release wrote
  `.cursorignore` as a whole marker-less file) kept a bare
  `zamm-memory/archive/**` line above the block, so the prescribed remedy —
  re-run scaffold — reported success and left the bug in place. Scaffold now
  removes those exact lines wherever they sit and prints each removal. Exact
  whole-line matches only: a user rule that merely resembles one
  (`zamm-memory/archive/**/*.bak`) is theirs and stays, and `status` reports
  a hand-added `zamm-memory` rule as a warning rather than deleting it.
- **`status` watches the plan tree at the depth the digest compiles from**
  (`-mindepth 2 -maxdepth 2 -name '*.plan.md'`, the plan manifest's own
  depth). The unbounded walk conflated the `.plan.md` the compiler reads with
  `workdir/`, which nothing reads: scratch reported the digest STALE when
  recompiling could not change a byte of it, and unreadable scratch took the
  whole command down.
- **The skill stamp ignores dotfiles.** It hashed every file under
  `references/` and `scripts/`, so a `.DS_Store` in a working copy made the
  same commit hash differently there than in a clean clone — every clone
  reported STALE surfaces, and re-scaffolding could not fix it because it
  stamped the local value back in. The skill tracks no dotfile, so pruning
  them costs no coverage.

Smaller repairs in the same pass: a missing ignore template is now a hard
error instead of a silent skip (half an ignore split must not look healthy);
the malformed-block repair advice quotes the markers of the file it is
refusing rather than always AGENTS.md's HTML-comment form, which for a
gitignore-syntax file told the user to write a marker the script can never
match; and the v1/v2→v3 migration guide no longer claims
`archive/knowledge/` is unread by the compiler — the claim that produced this
whole class of bug. 426 tests green.

## Locked 2026-08-31 (the backlog: ideas as a third tree)

ZAMM had boxes for facts (knowledge records, pushed under a strict
attention budget) and active intentions (plans, pushed unbounded with full
lifecycle ceremony), and nothing for latent intentions — so wishes got
parked as Draft plans, billing every session start and carrying obligations
they could not honor. The backlog is the third box: ordinary immutable
schema-3 records in `zamm-memory/backlog/<YYYY>/`, compiled by the same
compiler behind a `--tree` flag into an UNCAPPED pulled lens
(`.compiled/backlog.md`, printed by `backlog list`) instead of the digest.
Everything below rendering policy is shared — enumeration, the G1-G5
discipline, validation, the supersede graph, votes, decay, dormancy — and
everything about an idea lives in its tree (votes, tombstones, erasures; no
cross-tree edges), which is also what keeps the change invisible to older
v3 toolchains: every walker enumerates named trees only, so no VERSION
bump and no migration.

Per-tree policy, locked in both directions: `importance: guardrail` is an
error in the backlog (its one power is digest admission; the marked lane is
how an idea earns pushed attention) while knowledge keeps guardrails;
backlog votes are plan-less triage votes while knowledge votes still
require `plan:`; OTHER_MAX does not apply in the backlog (capture defaults
to `other`, and because candidate validation is an error-line diff the cap
would have made the sixth context-free add refuse outright) while knowledge
keeps the cap.

Capture is the cheapest write in the toolchain: `backlog add 'One
sentence.'` is complete — slug derived, scope defaulted, the sentence is
the headline. An idea is progressive disclosure: piped stdin of any size (a
paragraph or a book) parks under `## Background` unless it carries its own
headings, the lens shows headlines only (`+bg` flags depth), `backlog show`
opens the record. The tree is created on demand; a treeless project lists
and checks as cleanly empty (absence is data).

The marked lane is the selected stage between latent and active:
`marked: <date>` on the head (via `backlog mark`/`unmark`, which supersede
with the key toggled) renders the idea in the session digest, exempts it
from dormancy, and nags past a soft cap of 7. The effective state is the
NEWEST marking decision in the applied chain, so a plain re-up inherits the
lane and its original date, and only the explicit `marked: no`, a promote,
or a tombstone leaves it. The digest carries exactly one `Backlog: N live
(M hot[, K marked])` line — `, 0 marked` never renders — and a degraded
backlog pass degrades the digest visibly (`Backlog: DEGRADED`, exit 2)
while an unreadable backlog tree fails it closed (exit 4, previous digest
untouched).

`backlog promote <id>` renders `Origin-idea:` into the plan file BEFORE the
publish rename, which is what makes an interrupted promote decidable on
retry: a same-slug plan with the matching origin is this promote's partial
result (the rerun finishes the tombstone), one without it refuses — the
create-then-stamp ordering an external re-review caught as a guarantee-2
violation before a line was written. 469 tests green.

## Locked 2026-08-31 (backlog round 2: exact origins, manifest authority, graph-precedence marks)

A second external review of the just-shipped backlog found four defects,
two reproduced live before fixing. All four were one class of error seen
four ways: a shortcut standing in for the real authority. Promote's replay
detection accepted SLUG equality as proof of identity, so promoting a
fresh idea that shared a slug with an already-promoted one "resumed" the
old promote and silently retired the new idea into a stranger's plan —
replay now keys on the EXACT Origin-idea id (of the resolved live head for
the crash leg, of the typed full id for the completed leg), and a slug
retry of a retired chain gets a pointer at the chain instead of adoption.
Promote also trusted the plan manifest's EXIT CODE while the manifest
represents damage as data rows (MISSING, UNREADABLE, SYMLINK, NOTDIR,
DUP, DEBRIS) with exit 0 — and the origin scan is mutation authority, so
an unseen plan could change the verdict; any anomaly row now refuses
before anything is created or retired (G3), stricter than zamm-archive's
MISSING-only rule because archive re-validates what it moves and the scan
IS promote's check.

The marked lane resolved decisions by lexically greatest record id —
but same-day ids order by RANDOM SUFFIX, so a same-day mark → unmark →
re-up resurrected the mark whenever the mark record drew the greater
suffix; and the walk crossed tombstones, so reviving a retired chain
inherited its dead mark. Decisions now resolve by GRAPH PRECEDENCE: a
descendant's decision dominates every ancestor's (superseding IS the act
of revising), tombstones are walls, and the deterministic id tiebreak
applies only to genuinely incomparable fork decisions — locked with
adversarial suffixes on both sides.

And `status` read the backlog sidecar through bare command substitutions
under set -e — the exact assign-then-fail behavior this ledger already
carries a record about — so a deleted backlog-state.tsv killed status
mid-output at exit 2 with no diagnostic. The lens/state pair now gets the
same generation-coherence check as the knowledge sidecar: report,
name the recompile remedy, finish the report. 474 tests green.

## Locked 2026-09-01 (backlog round 3: the graph is the authority)

A ten-angle adversarial review of round 2 produced 23 findings, eight of
the twelve correctness ones reproduced live, and they shared one lesson
round 2 had only half-learned: promote and the marked lane were still
reasoning over PROXIES for the supersede graph instead of the graph. The
fix is a new read-only compile mode — `--list-graph`: id, union-find
group, liveness, applied edges — and a promote rebuilt on it. A plan
origin belongs to the idea being promoted iff it is a graph ANCESTOR of
the resolved live head, so an interrupted promote converges even after
the head advances past the recorded origin (pre-fix, that retry printed
"Already promoted", exited 0, and never wrote its tombstone); a completed
promote replays as a no-op iff the origin family is fully retired, so the
exact id, an ancestor id, and the bare slug all converge while an
unrelated same-slug idea — a different component — can never be adopted.
resolve_live_idea now returns TYPED codes (live / none / ambiguous /
unreadable) with diagnostics captured once: ambiguity lists ids again,
unreadability refuses with G3 before any mutation decision, a superseded
needle names its live successor, and the find-glob probe that called two
live ideas "retired" and treated `*` as a pattern is deleted. The origin
scan reads PLANFILE and ARCHFILE rows in one awk pass (an archived plan
is the normal end state and must keep replay convergent), and the
manifest damage check is an ALLOWLIST of the five known-good tags — a
blocklist of anomaly tags fails open the day the manifest grows one.

The marked lane's tombstone rule is now NODE-based: build_tombkill marks
every record behind any tombstone as lane-dead in one multi-source BFS,
so a revival starts outside the lane whichever record it supersedes —
the path-based wall held only for revivals that superseded the tombstone
itself, and superseding the dead CONTENT record inherited the dead mark.
The wall is REMOVED from the dominance pass, where it severed real
descent and handed comparable decisions back to the random-suffix
tiebreak; dominance is one multi-source BFS of pure ancestry, and
pushsups() is the single definition of edge expansion for every walk.
Cleanups from the same review: one guarded read of the backlog sidecar
behind the shared pair_coherent (closing the TOCTOU abort), id_to_slug
for the shell's id grammar, and the four test gaps locked — both revival
shapes, the no-match diagnostic, format-proof same-day assertions, and a
named failure when Origin-idea goes missing. 479 tests green.

## Locked 2026-09-01 (backlog lens legibility: cluster, count, filter)

First real-user feedback, and it confirmed the design's own contract: the
fix needed no new field, flag semantics, or taxonomy — the primary tag
already carried everything. Inside each `###` area block the lens now
clusters entries by full primary scope (clusters ordered by their hottest
member, rank order within, bare-area entries their own cluster), so
same-subpath siblings sit together instead of interleaving by rank across
the area; the heading carries the live counts with the subpath breakdown
(`### domain (7: lobby 4, art 2)`) — the statistics surface, keyed off the
primary tag since secondaries are bare areas by contract. `backlog list
--scope <tag>` is the query surface: a filtered row listing mirroring
`memory list --scope` exactly (any tag, prefix semantics, secondary doors
count; dormant excluded by default, `--all` adds it), while the unfiltered
lens stays the one pulled digest. The protocol now states the clustering
rule — one idea = one thing you would promote; siblings you might start
separately are separate records SHARING a subpath, never one blob, never a
new area — and nudges capture: `other` stays the cheap uncapped default,
but when the topic is already known, `--scope domain/lobby` is what makes
clusters and filters exist. Deliberately NOT built: any mechanical nudge
when `other` dominates — the box must not nag.

Dogfood note: this pass went through its own machinery — the feedback was
captured as three scoped backlog ideas, one was promoted (`backlog
promote`, Origin-idea recorded), and the siblings were tombstoned into the
plan. 482 tests green.

## Locked 2026-09-04 (the journal: episodes as a fourth tree)

ZAMM had boxes for facts (knowledge), active intentions (plans) and latent
intentions (backlog) and none for EPISODES — things that happened, worth a
trace, implying no action and asserting no durable claim — so they either
evaporated at session end or were forced into the knowledge ledger at `days`
durability, taxing the pushed digest. The journal is the fourth box:
ordinary immutable schema-3 records in `zamm-memory/journal/<YYYY>/`,
compiled by the same compiler behind `--tree journal` into a TIMELINE lens
(`.compiled/journal.md`, months newest first, dormant collapsed to per-month
counts) instead of a ranking. Three record classes share the tree and
resolve by VALUE, never by graph: entries (`type: memory`), elevations
(`type: digest` + `digest: <kind>` + `covers: <YYYY[-MM]>`, the newest
unretired one per kind and period is effective) and watermarks (`type:
memory` + `reviewed-through:` [+ `pass:`], the MAX date among unretired
claims is the effective watermark; undigested = created on or after it,
inclusive). `type: digest` is the first tree-local record type: the
new-type quarantine hazard is about trees older toolchains SCAN, and no
older toolchain enumerates `journal/` — ledger record 9ehf5 (superseding
apxr4) states the sharpened rule and landed BEFORE the code, as the external
review asked. Every other tree refuses the type and every journal-only key
(`cue`, `salience`, `axis-*`, `time`, `agent`, `user`, `digest`, `covers`,
`reviewed-through`, `pass`); `x-` stays warning-free everywhere.

Capture is cue-driven, never ritual — the 2026-02 no-daily-diary rule is
superseded by name with the sharpened form: episodes go to the journal on
a cue, durable points are distilled out at triage, and no session-end
obligation exists. `journal add 'One sentence.'` is complete (scope other,
durability weeks, stdin under `## Background`); optional `--cue` (open slug
set seeded with side-quest, exceptional-occurrence, non-action,
cross-plan-context, blind-spot), `--salience 1..10`, numeric axes
`--axis name=value` with exactly two self-describing types (unipolar 0..10
unsigned, bipolar -5..+5 always signed — no registry), and `--x key=value`
auto-prefixed into the experimental namespace. `time:`, `agent:`
(`ZAMM_AGENT`) and `user:` (the git identity) are stamped as provenance,
never a scoreboard. The capture contract — validation never rate-limits or
refuses a well-formed capture — lives in the protocol body and a test lock,
deliberately not in invariants.md.

Digestion is a trichotomy. COMPILE is the primary digest and is never
stored: `journal digest <YYYY[-MM]>` prints a month view (stats +
elevations + entries) or the year view (the digest of digests: per-month
rows, monthly elevations with headline fallback, the yearly elevation),
composable through `--detail`, `--stats`, `--elevations` and the shared
predicates — a skill's style is a saved invocation. TRIAGE extracts into
the other trees behind a claim: `journal review` (oldest first, headlines
above 50; `--cue`/`--scope` are reading aids, `--period` reads a calendar
span, `--pass` a custom pass) and `journal settle [--through <date>]`
(refuses a non-advancing or future date). ELEVATE stores judgment:
`journal elevate <kind> <period>` writes the record that IS the coverage.
Elevations and watermarks never go dormant (the second read-through caught
that a weeks-durability claim would otherwise have expired after ~130 days
and silently reopened everything behind it). One predicate grammar
(`--class --scope --cue --kind --covers --agent --user --axis --since
--until`, each negatable) drives `search`, `stats`, `export` and `digest`;
`journal export` is the versioned TSV seam (`# zamm-journal-export v1`, a
column-name row, readers map by name, columns only append) through which
other skills — the journal's main operators — read; they write only via
`add` and `elevate`.

Session-start exposure is one line, present only when due: `Journal: triage
due (N undigested, oldest D); monthly due (P)` — triage at 25 undigested or
60 days, elevation nudges opt-in by practice per built-in kind (first
elevation opts in; a lapse of more than three grains of the kind's own
period goes silent). Absent or quiet tree: byte-identical digest; degraded
pass: `Journal: DEGRADED` with exit 2; unreadable tree: exit 4, previous
digest untouched. The sidecar carries the effective watermarks and
elevations, what is due, and per month x cue x axis nearest-rank quartiles
over entries and `created:` dates (the instrument for the bar-slips risk;
the status drift flag over it is deferred on calibration grounds).

## Locked 2026-09-04 (journal review rounds: what the design named, the code now measures)

Two passes over the shipped journal - a probe of the running toolchain and a
line-by-line read - found seven defects, every one an edge the design had
named while the code measured something adjacent to it.

The inclusive triage boundary means a claim dated D cannot cover the entries
of D (fail-open: same-day work is never silently skipped). Nothing measured
that, so a day of entries nagged `triage due` in every digest while the
settle the line asked for was refused as non-advancing, and `settle` both
printed and RECORDED, in an immutable body, a covered-count that included
the very entries the next read listed as undigested. Due-logic now counts
only what a settle would clear, so the nudge is always actionable; a claim
counts as covered what a later read treats as covered (created strictly
before its date) and names the boundary-day entries separately, in the
record as well as on screen.

Journal reads handed back a degraded tree under exit 0 - the export seam
included, whose consumer is a program that cannot see the `## Degraded`
section and would take a short dataset for the whole journal. Every journal
read now exits 2 with the explanation on stderr and the data still on
stdout. The shared internal list modes (`--list-live` and friends) keep
their exit-0 behaviour: `backlog promote` treats a non-zero list as an
unreadable tree, and coupling those would refuse promotion over an unrelated
quarantined record.

Class validation ran only for records carrying a journal KEY, so a bare
`type: digest` - which carries none - passed the contract and reached the
export as an elevation with no kind and no period; journal records are now
validated as classes unconditionally. An axis predicate checked only its
first character while awk coerces the operand with `+ 0`, so
`--axis mood=garbage` quietly became `mood == 0`; the name, operator and
integer operand are now a real grammar. `journal digest` selected elevations
straight from the state sidecar, so predicates narrowed the entries and left
every elevation in - effectiveness stays the sidecar, but WHICH elevations
to render is the shared grammar, and `--elevations only` now renders them at
whatever grain they sit.

Two elevations left live for one kind and period were resolved by the
greater record id, which within one day is the random suffix - the backlog
learned the same lesson about same-day ids in its round 2. A correction
supersedes (retiring its predecessor outright), so two live ones are
competing claims: the lens, the compiled views and the sidecar now name
them, and `journal elevate` prints the id to supersede instead of quietly
adding a second. Deliberately NOT fixed by comparing `time:` - that is
display metadata, never causality, and a clock skew between two machines
must not decide which digest a period has.

A third pass found five more, and one was the sharpest of the series:
`settle` and `elevate` wrote coverage while records sat quarantined. Nobody
could review an unreadable record, and the claim covers it by DATE the
moment it is repaired - it lands behind the watermark, or inside an elevated
period, never having been read, and no rerun takes that back (guarantee 2).
Both verbs now require a clean journal; capture is untouched, because a
quarantined neighbour is no reason to refuse an episode.

The rest were the same species as the round before. `journal digest`
suppressed its entry default whenever any `--class` was given, so
`--class watermark` listed watermarks under Entries; each section now ANDs
its own class onto the caller predicate through a separate key, which also
fixes repeated and negated classes. `--stats full` read its detailed table
from the unfiltered sidecar, printing statistics for the very records the
view had excluded; it is derived from the selected rows now. The 60-day
review-age boundary ran on daynum(), the deliberate approximation that
models every month as 31 days (and is documented as unfit where exactness
matters), so a 31 January entry was "older than 60 days" on 1 April, when it
is exactly 60; policy boundaries use exact Gregorian day arithmetic, decay
keeps its approximation. And `journal search --text` swallowed grep exit 2 -
a pattern that cannot compile, or a file that cannot be read - as "no
matches"; the pattern is validated once up front, and an unreadable record
now exits 4 (G3), which also meant moving the row loop out of the pipeline
subshell that had been discarding its exit.

A fourth pass found the model itself wanting, in the one place it had been
taken on faith: coverage was a DATE. An entry written or merged in after a
claim, dated before its boundary, counted as reviewed by a claim that never
saw it - `journal add --date`, or any teammate's older entry arriving in a
merge - and no rerun brought it back. Coverage is now by RECORD IDENTITY:
`settle` writes `covered:` naming the entries it reviewed, and undigested
means named by no claim of that pass rather than older than some date. A
hand-written claim with no `covered:` keeps the blunt date meaning, which is
a human asserting a range on their own authority. The compiler also refuses
a claim reaching past the day it was written - the CLI had refused future
dates all along, but a committed record is content like any other, and one
hand-written line claiming the year 9999 had marked every entry reviewed.

Elevations carry the same identity, for the same reason: the year view
renders an elevation INSTEAD of its period's entries, so an entry the
elevation never saw was invisible there for good. An elevation now names
what it saw; an entry of the period outside that list makes it stale, which
the lens reports, the year view lists under the month, and the due-logic
treats as needing elevation again. And a period still running can no longer
be elevated at all - freezing a period mid-flight was the same bug with a
narrower door, and for a running period the compiled view is the live
answer.

A fifth pass read the diff line by line and found eleven more, including
the first security-shaped defect of the series. Frontmatter was emitted with
`echo`, which expands backslash escapes on a POSIX /bin/sh - the shell CI
runs - so `journal add --x 'note=x\nreviewed-through: <date>'` broke out of
its own line and wrote a real coverage claim. The x- namespace exists
precisely so an escape hatch can never write a policy key, and capture is
the one path that never refuses. The emitter uses printf now, with a
source-level lock beside the behavioural one.

Two more ways a claim silently degraded to the date-only form it was built
to replace: `settle` and `elevate` omitted `covered:` when they covered
nothing, and the compiler read a missing key as "a human asserting the
range". Naming nothing is an exact statement, so the key is always written
and EXACTNESS IS PRESENCE - an empty `covered:` covers nothing, only a
record without the key is the blunt form. Settling twice on different days,
and elevating a quiet month, are both ordinary.

`journal review` crashed on any entry rated salience 1 or 2: the sort key
was printed %02d and the metadata line evaluated $((10 - 09)), an invalid
octal literal, aborting the default full-detail read mid-record. The
salience travels as its own field now. The refuse-to-publish gate counted
entries only, so a journal holding coverage records and one malformed file
refused outright while export returned the survivors - it counts every live
class, and the lens header reports all three. The same-day notice (and the
sentence settle wrote into an immutable body) explained the exclusion by a
date comparison that identity coverage had made false. `journal search` and
`journal stats` each parsed the whole tree twice, compiling a lens neither
of them reads. A failed `journal show` pointed at `memory list --all`. And
three smaller ones: dead status variables in `journal list`, a no-op
self-assignment in `journal digest`, and hardcoded plurals where the file
already had a helper.

A sixth pass found three more, all of them the identity model being trusted
where it was not yet enforced. `covered:` ids were checked for SYNTAX only,
so a claim could name a QUARANTINED record - one nobody could read, hence
one nobody reviewed - and absorb it the moment it was repaired; ids must now
resolve to a readable entry of this journal that the claim could have seen
(before its boundary, inside its period), and a claim whose list does not
hold up carries no coverage at all. Fail closed on authority means fail open
on the entries: they stay undigested, and the void claim is surfaced in the
lens like any other degradation.

The three provenance stamps were joined into ONE string that every caller
expanded unquoted, so `ZAMM_TIME='12:00 --reviewed-through <date>'` injected
flags and turned an ordinary `journal add` - the verb that never refuses -
into a valid date-only watermark, hiding every backdated episode written
afterwards. The clock stamp is validated and the three values are passed as
separate quoted arguments.

And because entries and watermarks share `type: memory`, type compatibility
alone let a coverage claim SUPERSEDE an episode: `journal check` passed on a
tree whose export no longer held the entry at all. Supersession inside the
journal now joins compatible classes; only a tombstone retires across them.

A seventh pass found four more, two of them about who owns an answer. The
year renderer RE-DERIVED coverage by parsing the elevation record itself,
with stricter rules than the compiler: it rejected `covered :` and a CRLF
file, both of which the compiler accepts, so the compiler reported an
elevation stale while the view silently dropped the entry it had missed.
Which entries an elevation missed is one answer and the compiler owns it -
it now emits them by id in the sidecar and the renderer reads that. The two
frontmatter helpers in the runner were also taught the compiler rules
(trim the key, strip a carriage return), so no third parser drifts either.

An invalid `covered:` list was treated like an absent one, falling back to
date coverage: a claim that did not hold up went on suppressing exactly the
entries it named. Exact-and-broken means EMPTY, not blunt, so every entry of
the period reads as uncovered and the elevation is stale until it is
written again.

The digest added its period bounds under the caller predicate keys, whose
repeated values OR together - so `digest 2026-06 --since 2026-06-15` widened
back to all of June and `--until 2026-07` pulled July into June. The bounds
are section-scoped keys now, as `--class` already was, and they intersect.
And the digest summary grouped axis values by NAME, taking the type from
whichever value arrived first, so one name carrying both spellings reported
a bipolar median under a unipolar label; a name and a type together are the
axis, which is how the detailed table had always read it.

The eighth pass found the one reader the seventh had missed: `fm_body`
still located the end of the frontmatter by matching a bare `---`, so a CRLF
record never matched its own closing fence and its body read as EMPTY. A
valid CRLF elevation passed `journal check` and then rendered as a heading
with nothing under it, in the month view and the year view alike - and since
the entries it covers are suppressed in favour of that summary, the period
ended up described by nothing at all. The same reader feeds `backlog mark`,
where an empty body is not a missing line of output but a refused write. All
three frontmatter readers in the runner now normalize line endings exactly
as the compiler does, and a body copied forward lands as LF, which is what
.gitattributes asks of the tree.

A ninth pass moved into the shared surfaces, where two of the three defects
predate the journal entirely. Supersede validation consulted the ARCHIVED
header whenever one existed, while the apply pass acted on the live copy -
so with the live-and-archived duplicate an interrupted archive leaves
behind, an edge was judged by a header that carries a type but no journal
class, and a watermark could retire an entry with check none the wiser.
Validation now reads the copy the edge will actually kill, which is the
condition the apply pass already used.

`--list-live` wrote raw scopes and headlines into TSV, and it is what
`memory list` and `backlog list --scope` read: a headline containing a TAB
lost everything after it (in the reproduction, the half of the sentence that
said ONLY AFTER APPROVAL), and a tab inside a scope shifted the columns so
the record vanished from a scoped listing. It is TAB-sanitized now, like
every other machine surface here.

And the plans tail normalized field VALUES while matching section headings
against raw lines, so a plan converted to CRLF compiled with no Done-when
census at all - the digest, `plan show` and the plan checker each read that
section by an exact heading. All three normalize the line first.

580 tests green under dash with ZAMM_SLOW=1 on a case-sensitive volume;
each new lock fails against the pre-fix scripts.


## Locked 2026-09-05 (startup surfaces: say less at session start)

A pass over what an agent reads before doing anything, with a small-context
agent in mind. Three principles: the router carries triggers and one command
each, never mechanics; a rule the toolchain states at the moment it matters
(the valid scope set on a bad `--scope`, the empty-body refusal, the digest
header's "do not open the compiled file") leaves the router; and a document
says which deeper document to load, not what it contains.

Router (every session, AGENTS.md and the Cursor rule): 506 -> 432 words while
ADDING four rules it had never carried - no secrets and paraphrase-never-quote
(the two permanence rules for writers), records are advisory so verify before
a high-impact action, and two more load-the-body triggers (session end, an
IDE-generated plan file). The backlog paragraph lost its mechanics (127 -> 64;
clustering, decay and lane precedence live in the body's Backlog section), the
journal paragraph names the one file to read before a first entry instead of
enumerating layers, and the session-start paragraph dropped the version-check
and do-not-open-the-file caveats the toolchain and the digest header now state
themselves.

SKILL.md: 1245 -> 855 words. Its Authority section claimed the scaffold
renders the protocol body into AGENTS.md and told the agent to read the
template only when no rendered copy is in context - wrong since the router
split: the scaffold renders the router, and an agent believing AGENTS.md was
the full protocol would never load the body. README carried the same claim in
its runtime-files table and its Learn more list; both corrected. Commands is
now a verb map per tree with `help [<topic>]` as the reference instead of a
paraphrase of it; the write transaction lost its redundant post-write
`memory check` (create already validates against the whole ledger) and gained
the brevity rule. Two dispatch rows were added: an IDE-written offsite plan
file (a MUST in the body with no trigger anywhere at startup) and the
read-only "what happened" question.

The empty-ledger digest line now says what to do at the moment it matters:
"ask the human before initializing, never write placeholder records". The
router had never carried that rule; the body and SKILL.md did, but an agent
reading only the digest saw "not initialized" and nothing else.

Brevity is written down as part of the record contract - in the body's
record-body convention, the record template, SKILL.md's write steps, the
router's memory paragraph and journal-writing.md: limits are ceilings, not
space to fill; one sentence that says the thing is a complete record; every
word in a digest block is reread at every session start by every agent, so
every word saved saves context and money for every reader after. The "2-10
lines" guidance, which read as a target, became "most records need two or
three".

Protocol body: Session Start dropped from 620 to 459 words by folding three
defensive bullets (recompile is the read; do not reread; do not open the file)
into two sentences and by describing the attention layers once, since the
digest header describes them again at read time.

580 tests green under dash with ZAMM_SLOW=1; no test pinned the reworded text,
and the one that reads the dispatcher against `help` still passes.

Same day, the write layers learned who READS what they write. The maintenance
file had said when an elevation may be written and what coverage it claims,
and nothing about what a good one is; measured against the renderer, the
facts were sharp enough to teach: the year view shows an elevated month as
the elevation's first PHYSICAL line and nothing else (a wrapped headline is
cut mid-sentence), the yearly elevation is written from twelve of those
lines, the month view shows the block (validated to 12 lines / 1200 chars
like any record), Background is read on demand, and `search --text` matches
bodies. So: line one is the period in one sentence written to be summarized;
the block is the few episodes that mattered with outcomes and ids, not an
inventory (`covered:` already names every entry); two tests before writing -
can a reader of line one decide whether to open the month, can a reader of
the block skip every entry without losing a decision. The settle headline
got the same treatment: its reader is the next reviewer, who needs to know
what was already extracted. journal-writing.md gained "who reads it, and
when" - a scanner sees the headline alone, the triage reviewer weeks later
sees the whole record and decides fact-or-action, the elevation author
summarizes from headlines - and the knowledge-record convention, SKILL.md and
the record template now name the headline's reader: an agent mid-task,
scanning the digest for the block that applies to what it is doing now.

## Locked 2026-09-05 (every tree in layers: reading, writing, maintenance)

The journal's four-layer shape - an index over a reading, a writing and a
maintenance file, each written for the agent about to do that one thing -
now applies to every tree. The protocol body, 5,221 words of MUSTs, schema,
mechanics and transitions that every deeper question loaded whole, is a
1,386-word SPINE: session start and end, the boundary test between the four
trees with a table of their layers, the rules every tree shares, the
distillation cues, reconciliation in three sentences, precedence and key
constraints. Everything else moved to `references/<tree>[-layer].md`:
memory (index 228, reading 484, writing 1,603, maintenance 931), backlog
(187 / 178 / 422 / 296), plans (158 / 159 / 562 / 467), beside the journal
files. The router's last paragraph maps actions to layers directly; SKILL.md's
dispatch table points its Read column at the file for each situation.

Every writing layer opens with WHO READS what you write and at what zoom,
measured against the renderer rather than asserted: a knowledge headline is
matched, not read, by an agent mid-task scanning ~75 blocks, so its first
words name the situation; the digest joins a wrapped headline into one line;
`memory list` shows the first ~70 characters and the slug is how a record
is opened; `+bg` is read as "verify here before a high-impact action"; the
reconciler needs to know where a claim can be checked; the closing agent
votes only on records precise enough to have helped or misled. A backlog
headline is read dozens at a time under counted area headings, its
Background by the one who does the work, and a marked headline by every
session as a commitment. A plan is its title to everyone who has not opened
it; Done-when is a checklist written as checkable outcomes; Learnings are
read by the distiller as candidate records. Each writing file ends with two
tests to apply before writing.

Duplication across files is deliberate where it makes the hot path
self-sufficient: the schema, the areas, the write command and the brevity
contract appear in memory-writing.md and are summarized in the spine; the
close-out steps appear in plans-maintenance.md and Session End points at
them. A rule-bearing-phrase probe over the old body (108 phrases) finds
every one in the new layout; the single dropped detail is the internal
note that a multi-tag record competes through its least-crowded area.

580 tests green under dash with ZAMM_SLOW=1; the scaffold stamp moved
(references/ is hashed), and the rendered router still expands its one
path token on the definition sentence.

## Locked 2026-09-05 (tenth review round: the archived exemption, and echo)

Two findings against `70b0afd`, both in families already met. The coverage
validator took the archived exemption before looking for a live copy - the
mirror image of the supersede check fixed two rounds earlier - so a claim
could name a live entry dated AFTER its own boundary and pass: the entry was
retired unread, `journal check` was clean, and `journal review` reported
nothing outstanding. Auditing every `in archived` site for the same shape
found one more: a vote whose target had an archived copy was dropped
silently instead of landing on the live record. Both now apply the
exemption only when no live copy exists, which is the condition the apply
pass and the supersede check already used.

The read verbs printed stored headlines with `echo`, which under dash - and
under macOS /bin/sh, whose bash runs with xpg_echo on - interprets backslash
escapes: a literal `\t` became a tab, and `\c` discarded the rest of the
line, headline and record pointer alike, in search, headline review and both
month-digest details. Export kept the text. Every site printing record text
goes through fixed-format `printf` now. Locked with one test per view as
subtests; because the harness runs the runner with `sh`, the lock falsifies
on macOS as well as under dash.

583 tests green under dash with ZAMM_SLOW=1; all three new locks fail
against the pre-fix tree (`7b39661`).

## Locked 2026-09-05 (layering review: the erasure route, list semantics, routing tests)

A colleague reviewed the layering and kept the structure; four gaps closed.
The shared erasure route sent every secret to the knowledge command, and
each tree compiles on its own, so an erasure record written into
`knowledge/` left a journal or backlog record visible - and deleting the
original afterwards left a returning copy unprotected. Every maintenance
file now carries its own tree's command (`memory create` / `backlog add` /
`journal add --type erasure --erases <id>`), the SKILL.md row says "into the
tree the record lives in", and a journal test proves the knowledge erasure
does nothing there while the journal one redacts.

`memory list` was described as every live record; by default it lists only
what the digest selected (the help said so all along), and `--all` is every
live record. The dedupe instruction before adding knowledge now says
`memory list --all --scope <area>`, since the record you would duplicate
may be an unlisted or dormant one.

Two routing corrections: the session-start row of SKILL.md no longer
requires the spine and memory-reading.md - the router's paragraph is the
whole rule, and the extra files are conditional on an unclear marker or an
empty ledger - so the startup cost is what the router says it is; and a
request to summarize a period routes to `journal digest` (a read) first,
with storing an elevation or claiming coverage as a separate, explicitly
requested write. The journal index, the writing file's triggers and the
spine's table say the same.

Decisions on the rationale's open questions: `memory-*` stays aligned with
the CLI; the compact distillation cues stay in the spine; 532 router words
is acceptable; the spine is renamed `references/protocol.md` since nothing
renders it (the scaffold still requires it, under its new path; the
template-naming convention is untouched because the file is no longer a
template); the tiny reading layers stay; the least-crowded-area mechanism
went into memory-maintenance.md, not the writing path.

New: scenario routing tests in test_surfaces.py - from the router alone,
every action reaches a named, existing layer file that carries its command,
no surface points at a missing file, and each maintenance file names its own
tree's erasure command. A dangling pointer in a doc is a routing defect the
suite never saw before.

## Locked 2026-09-06 (search hits get a standing: `whatis`, `--list-state`)

A consumer project put a local markdown search tool (QMD: BM25 + vectors
over `**/*.md`, CLI and MCP) beside the ledger and asked the skill to own
the authority-vs-retrieval rules rather than every consumer reinventing
them. Its smoke test named the failure mode: archived plans and superseded
records ranked ~84% as if current, because a similarity ranker cannot see
`supersedes:`, tombstones, plan Status or `archive/`. Nothing in the
toolchain could answer "a search handed me this file - what is it?" in one
step: `memory show` marked only records already in `archive/`, and a
superseded, dormant or unlisted record printed exactly like a listed one.

New top-level verb `whatis <ref>...` (internal `zamm-whatis.sh`, read-only,
every tree, live and archive). A ref is a path in any form, a
`qmd://<collection>/<path>` URL (a trailing `:line[:count]` is ignored), a
record id, a plan id or directory, or a bare slug; a slug that names a chain
prints every generation, which is the graph. Per record: the tree and class,
the standing (live and listed or unlisted, dormant, superseded by, retired
by tombstone, quarantined with the reason, erased, archived), scope, votes,
headline, the connected supersede chain oldest first with `<- this`, the
live head(s), and - unless `--brief` - the body of what is in force: the
head's, or the tombstone's reason when nothing is. Plans report Status,
progress, title and head; `workdir/` scratch, subplans, `.compiled/`,
drafts, tree files and ordinary files outside `zamm-memory/` are each named
for what they are. A path that no longer exists (archived or erased since
the index was built) resolves by name with a note. Exit 1 when a ref names
nothing; 4 when a tree is unreadable or does not compile (G3).

The compiler gained `--list-state`, the surface behind it: one row per
record the graph knows - live tree, quarantined and erased included, and
archived ids from the inert headers - with the standing the compiler
assigned; `whatis` re-derives no liveness from filenames or frontmatter.
Archived rows carry no headline (the compiler reads only their header, by
design); `whatis` fills them from the file, since reading the archive is
the point there.

Routing: the router gains a Finding paragraph (the digest is the read, not a
search; a hit is a lead, never a standing; `whatis` before citing; archive
is history; never write or read `.compiled/` through a search tool),
SKILL.md a dispatch row for "the digest is silent and you need a citation",
and memory-reading.md the verb plus a "Search results are leads" section
naming QMD as the known instance. The skill stays tool-agnostic and ships
no QMD block of its own; consumers keep their collection names.

Field-note round, same day, from a worker running `whatis` against the
consumer's real ledger with its search tool's hits. Folded in:

- A body-leading frontmatter key (`supersedes: <id>` as the first body
  line) was invisible to the compiler, to search and to `whatis` alike:
  three same-day combat records in the consumer ledger claimed to replace
  each other in prose, so all three were live, the oldest sat in the
  digest, and the stray line was each record's headline. `memory create`
  (and every writer that funnels through it) now refuses such a body;
  `check` warns about existing ones without quarantining them (dropping
  true content to punish a typo would be worse); `--list-state` carries
  the stray line and `whatis` prints a warning naming it. `whatis` still
  re-derives no edge from prose - the report reflects the graph, and says
  so.
- `whatis` on a tombstone said "live - counts now": the compiler's
  liveness is per record, and a tombstone in effect is an instrument, not
  an idea in force. Standings are now worded per class (tombstone, votes,
  erasure record in effect); only content records count now.
- Fail-closed was broken in the verb: the per-tree compile ran inside a
  command substitution, so its exit 4 died in the subshell and an empty
  row set read as "the compiler does not enumerate it". The compile now
  runs at top level and ends the run. The compiler's read-only list modes
  also no longer create their scratch file (or `.compiled/` itself) beside
  the digest, so a sandbox that may read the tree but not write next to it
  still gets an answer.
- A dead hit is no longer dug up: a superseded, retired, erased or
  archived record reports its standing, the chain and the live head (and
  the head's body, or the tombstone's reason), not its own scope, votes and
  body. "This exists but is superseded; cite that instead" is the answer.
  Two refs resolving to one record print one report.
- The help promised that a slug prints the chain; it prints every record
  that kept the slug, and the chain under any hit is the graph whatever the
  slugs along it. Reworded. A pre-v3 archived note without frontmatter now
  shows its title as the headline.
- The search tool is optional and the skill says so: the router's Finding
  paragraph names grep first and "any markdown search you happen to have"
  (QMD as the example, `qmd search` rather than the model-backed `query`),
  and adds that unlisted and dormant records are still true.
