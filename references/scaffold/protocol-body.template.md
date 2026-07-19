## Script Path Resolution

The `zamm` skill directory is `<zamm-skill>`. Every `<zamm-skill>` token below stands for that directory (scripts live in its `scripts/` subdirectory); expand it when running the commands.

## Session Start (MUST - do this before primary task work)

1. Protocol version check:
   - Read `zamm-memory/VERSION`.
   - Current protocol version is `3`.
   - If the file is missing or does not contain `3`, treat the project as needing a ZAMM migration and ask whether to run the matching guide under `<zamm-skill>/references/migrations/`.
   - Do not infer migration state from legacy filenames or record contents during routine startup; the version file is the required check.
   - Migration work updates `zamm-memory/VERSION` only after migration is complete.

2. Digest compile and cold-start read:
   - Run `bash <zamm-skill>/scripts/zamm-compile.sh` (always; it is fast, deterministic, and safe to rerun).
   - On a new chat/session, read `zamm-memory/.compiled/memory.md` once.
   - The digest has two attention layers (same approximate space budget as ~100 full entries, ~2.25× coverage):
     - `## Digest` — up to ~75 actionable full blocks (headline + elaboration). A leading `!` marks a guardrail — do not violate it.
     - `## Headlines` — up to ~150 one-line reminders that knowledge exists on a topic; not enough to act on alone — open the record when the trigger matches.
     Pointers look like `[record-id votes +bg]`. `+bg` means the file holds a Background section; open it before high-impact action. Trailing counts cover unlisted-live (below Digests+Headlines budget) and dormant (below score floor); grep `zamm-memory/knowledge/` when digging into those.
   - If the digest has already been read in the current chat/session and no new records were written or merged since, do not reread it.
   - Never edit the digest; it is generated and gitignored. The ledger record files under `zamm-memory/knowledge/` are the only source of truth.
   - If the digest contains a `Needs reconciliation` section, perform reconciliation this session (see `## Reconciliation (MUST)`).
   - If the ledger contains no memory records, tell the human active memory has not been initialized and ask whether to run `<zamm-skill>/references/initialization/existing-project.md`. Do not create placeholder records to silence initialization prompts.

3. Identify the active plan from the digest's `## Plans` tail — a compact entry per active plan (status line with progress, then title), ranked Review, Implementing, Draft; terminal plans still in `active/` are flagged archive-ready. A short recently-archived list follows: check it before treating a referenced plan directory as missing after a pull.
4. If no plan matches the user request, create a new plan directory and `.plan.md` file using:
   - `<zamm-skill>/references/templates/plan.template.md`
   Then recompile the digest so its Plans tail lists the new plan.
5. Soft focus rule: prefer one active implementing plan at a time; if unclear, auto-pick by best match and ask the human only when ambiguity remains.

## Ledger Memory Model (MUST)

Active knowledge is an append-only ledger of immutable record files under `zamm-memory/knowledge/<YYYY>/`. There are no tiers, no ID counters, and no consolidation rituals: the compiler (`zamm-compile.sh`) derives liveness, vote totals, ranking, and supersede links from the records at read time. Ranking = author-rated importance decayed over the author-rated durability horizon, corrected by votes; fully decayed records go dormant (counted in the digest, not listed, always greppable in the ledger). Attention is bounded in two layers: up to ~75 full Digest blocks (actionable) and up to ~150 Headlines (reminders); further live records stay greppable but unlisted. Digest seats are balanced across top-level scope areas by a per-area score penalty (a weighted compromise, not a quota) so one hot topic cannot drown the others; a record with several area tags competes through its least-crowded area but pays a small score cost per extra tag, so precise tagging wins over tag-sprawl. Live guardrails never go dormant and are always included in the Digest layer: `!` is a safety contract, so a guardrail leaves the digest only through supersession or a tombstone, never through silent decay or downvotes.

Record file rules:
- One file is one immutable record. Never edit, rename, or delete a record file once committed (sole exception: `## Erasure (exceptional)`).
- Filename is the record ID: `YYYY-MM-DD-<topic-slug>-<suffix>.md`.
  - All lowercase; charset `[a-z0-9-]` only; slug at most 40 chars; date is the creation date.
  - `<suffix>` is 5 random chars from the alphabet `23456789abcdefghjkmnpqrstvwxyz` (lowercase Crockford base32 without `0 1 i l o u`). The suffix exists so uncoordinated writers on different machines cannot collide.
- Prefer creating records with `bash <zamm-skill>/scripts/zamm-new-memory.sh <topic-slug>`; hand-written files MUST follow the same naming and schema rules.
- Never rename or move files or directories under `zamm-memory/knowledge/` (the add-only layout is what keeps ledger merges conflict-resistant; renames reintroduce ordinary git conflicts).
- Never store secrets, tokens, or credentials in records; ledger records are effectively permanent.
- Never quote the human verbatim in a record: paraphrase the substance and, where the register matters, describe the emotion (e.g. "strong frustration with rebuild times") instead of the raw words. Records are permanent and team-visible; profanity and heat-of-the-moment phrasing must not be immortalized.

Record schema — frontmatter is flat `key: value` lines between two `---` lines; every value is a plain string; lists are comma-separated; unknown keys are ignored; omit empty keys (one exception: a fresh votes skeleton from `zamm-new-memory.sh` carries empty `up:`/`down:` lines — fill at least one before committing; `--check` rejects a votes record with both empty):
- `type`: `memory` | `tombstone` | `votes`
- `scope`: 1-3 comma-separated area tags, e.g. `contracts/record-schema, conventions`. The first (primary) tag is `<area>[/<subpath>]` and is where the record displays; secondary tags are bare areas that give the record extra selection doors. Areas MUST come from the fixed v3 set:
  - `domain` — what the product is for: purpose, users, requirements, external constraints (e.g. "this tool targets solo maintainers, not enterprise fleets")
  - `contracts` — boundary shapes others depend on: schemas, formats, protocols, CLI/API surfaces, invariants — violation breaks interop or data (e.g. "record IDs are the filename stem; never rename under knowledge/")
  - `conventions` — self-imposed rules: naming, style, layout, wording — violation costs consistency, not correctness (e.g. "plan dirs use date-first slugs")
  - `internals` — how shipped things work and why they have that shape (e.g. "digest ranking decays over durability half-life")
  - `quality` — how correctness is verified: test strategy, checks, known failure modes of the artifact — not of the agent process (e.g. "compile --check before committing ledger writes")
  - `tooling` — dev-time things used, not shipped: commands, environment, platform quirks (e.g. "awk on macOS lacks gawk extensions; keep scripts POSIX")
  - `ops` — ship/run-time mechanics: release, versioning, deploy, migration (e.g. "bump zamm-memory/VERSION only after migration completes")
  - `meta` — agent/process failure patterns, corrections, collaboration norms with the human (e.g. "prefer reading the digest over re-scanning the ledger at cold start")
  - `other` — catch-all when none of the eight areas fit cleanly. MUST be the sole tag with no subpath. Prefer the closest real area first; use `other` only as temporary parking, then refile via supersession (`--check` fails above 5 live `other` records)

  Tag only areas the record genuinely serves: each extra tag adds a selection chance but costs ranking, so tag-sprawl is self-defeating. Never invent new top-level areas. Boundary-straddle example: a CLI flag that is both an interop surface and a naming rule → `contracts/cli-flags, conventions`.
- `importance`: `guardrail` | `useful` (default) | `minor`. `guardrail` means violating the statement breaks the project or wastes hours — expect a handful per project, not per week; rating inflation gets corrected by downvotes and erodes trust in the digest.
- `durability`: `days` | `weeks` | `months` (default) | `years` | `permanent` — how long the statement will stay true. Ranking decays over this horizon (it is the half-life), so a `days` note self-retires within weeks while a `permanent` guardrail never fades. Rate honestly; refreshing a still-true record is one supersede away.
- `supersedes`: record ID(s) this record replaces (comma-separated when merging)
- `created`: `YYYY-MM-DD` (must match the filename date)
- `schema`: `3`
- votes records additionally: `plan` (plan-dir slug), `up`, `down` (comma-separated record IDs)

Record body convention (MUST for `memory` records):
- The FIRST PARAGRAPH is the headline: ONE imperative, actionable or guardrail statement, standalone-readable (condition-first where it fits: "When touching X, do Y because Z"). Aim for roughly one short sentence (~300 characters as a soft guide, not a hard cap) — prefer a complete trigger-worthy statement over truncating mid-thought. It is the entry's first line in the digest — and its only line when the entry renders headline-only.
- Optional elaboration paragraphs may follow the headline: digest-worthy caveats, key parameters, the load-bearing why. Everything above the first heading is the DIGEST BLOCK (headline + elaboration); keep it 2-10 lines (hard limits: 12 lines, 1200 chars). Entries selected into `## Digest` render the whole block at session start (actionable). Entries selected into `## Headlines` render the headline only (a reminder to open the record if the topic matches).
- Detail that only matters when actively working the topic goes under a `## Background` heading: full reasoning, evidence paths, history. Optional — omit it when the digest block carries everything. Its presence earns the entry a `+bg` marker.
- `tombstone` body: a one-line reason. `votes` body: empty.

Semantics:
- Update a memory: write a NEW record with `supersedes: <old-id>`. The old file stays untouched; the compiler hides it and links the chain.
- Retire a memory: write a tombstone record (`type: tombstone`, `supersedes: <target-id>`).
- Merge duplicates: write ONE record whose body unifies the statements and whose `supersedes:` lists all merged record IDs.
- Vote: never edit counters anywhere; votes are their own records (see `## Plan Status Transitions (MUST)`).

## Distillation (MUST)

Mechanics:
- Prefer correction over accretion: supersede stale records, merge overlaps, add only genuinely new knowledge.
- Rate `importance`/`durability` honestly — they are the whole ranking system. Refresh a still-true record near its horizon by superseding with re-rated fields.
- Suspected-stale but unverified: supersede with a `suspected drift` record plus a verification note.
- A write is complete only after `zamm-compile.sh --check` passes and the digest is recompiled. Records are drafts until committed, immutable after.

Write a record when (compact cues; full semantics in `<zamm-skill>/references/distillation-triggers.md`):
- the human says remember this — same turn, no damping
- the human corrects you or states a standing rule, any tone — else it evaporates at session end
- the human shows strong emotion (complaint or praise) with substance behind it — record the substance, short-lived, never the raw words
- the same failure hits twice — cause + workaround now; still stuck: short-lived dead-end record (goal, tried, ruled out)
- research yields a conclusion whose details live in a pointable file — conclusion + pointer

Do not write: free-floating values with nowhere to recheck; external changes that broke nothing; churn during primary work. The cues are deliberately coarse — accept near-misses rather than paying for precision every session.

## Reconciliation (MUST)

- After a `git merge`/`git pull`, two branches may have independently superseded the same record. Both successors stay live (git does not conflict on added files) and the digest lists them under `Needs reconciliation`.
- Resolve in the same session the digest surfaces it: write ONE new record whose body merges the competing statements (or picks the correct one, stating why) and whose `supersedes:` lists ALL competing head IDs.
- If ground truth cannot be determined from code, git history, or context, still resolve now: write the merge record as the conservative union of the competing claims (keep every restriction, drop no warning), mark it `suspected drift` with a one-line verification note, and confirm with the human at the next opportunity. Never leave the heads unmerged because certainty is missing.
- Never resolve by deleting or editing the head files, and never silently prefer one head by timestamp; timestamps across machines are display metadata, not causality.

## Erasure (exceptional)

Only for secrets or personal data committed by mistake:
1. Append the record ID to `zamm-memory/knowledge/shun.md` (one ID per line, `#` comments allowed) so compilers ignore any stray copy.
2. Delete the record file.
3. Git history rewriting (`git filter-repo` or equivalent) is a separate, explicitly human-approved operation; ask, never assume.

## Plan Directory Model (MUST)

- Plan files live under `zamm-memory/active/plans/<plan-dir>/`.
- One directory is one plan context.
- The main plan file MUST use `.plan.md` suffix.
  - Recommended: `<plan-dir>.plan.md` with date-first slug (`YYYY-MM-DD-...`).
- Optional transient artifacts live under `<plan-dir>/workdir/`.
- Archive moves the full plan directory to `zamm-memory/archive/plans/<plan-dir>/`.
- `Done` and `Abandoned` are terminal; continue with a new plan directory.
- Do not maintain separate workstream state/index files. The compiled digest lists active plans compactly; when digging deeper, search `zamm-memory/active/plans/**/*.plan.md` and read `Status:`.
- Recompile the digest whenever a plan directory is created or archived (`zamm-archive.sh --archive` recompiles on its own); other status transitions are picked up by the recompile step of the ledger-write transaction during transition distillation.

## Offsite Planning Backfill (MUST)

Cursor planning mode may generate an offsite `.plan.md` that does not follow ZAMM format.
Treat offsite plans as input context, not as the execution ledger.

Trigger:
- An offsite `.plan.md` was created/updated for the current task.
- No matching in-repo ZAMM plan exists yet, or the existing ZAMM plan is missing the offsite scope updates.

Required actions (same turn, immediately after planning):
1. Create or update `zamm-memory/active/plans/<plan-dir>/<plan-dir>.plan.md` using
   `<zamm-skill>/references/templates/plan.template.md`.
2. Mirror essential scope into the ZAMM plan (`Scope`, `Done-when`, `Approach`).
3. Record the offsite plan source path in the ZAMM plan for traceability.
4. Set ZAMM status:
   - `Implementing` when execution work remains.
   - `Review` when execution is complete and waiting for human approval/closure.
5. From that point on, apply all transition bookkeeping only in the ZAMM plan file.
   Offsite plan files are non-authoritative scratch artifacts.

## Plan Status Transitions (MUST)

Primary trigger model:
- Plan bookkeeping is event-driven by transitions. Apply transition requirements when a transition is attempted or requested, not only at session end.
- Trigger events include:
  - setting/changing `Status:` in a plan file
  - human review outcomes for plans in `Review`
- `Session End` remains a safety backstop to catch anything missed.

Allowed transitions:
1. `Draft -> Implementing | Abandoned`
2. `Implementing -> Review | Abandoned`
3. `Review -> Implementing | Done`

Transition-time requirements:
- Global constraints:
  - `Done` may only be set via `Review -> Done` after explicit human approval.
  - `Done` and `Abandoned` are terminal. Do not resume work on a terminal plan; create a new plan.
- `Draft -> Implementing`:
  - Ensure scope + `Done-when` are filled.
  - Fill `Wellbeing-before` and `Complexity-forecast`.
- `Draft -> Abandoned`:
  - Record rationale under `## Loose ends`.
- `Implementing -> Review`:
  - Ensure all existing `Done-when` todos are checked. If an item became obsolete, remove it before moving to `Review`.
  - Reconcile stale/conflicting live records touched by this work per `## Distillation (MUST)` before adding new learnings.
  - Fill `## Learnings` (required; if no durable learning emerged, state that explicitly with a reason).
  - Distill durable learnings into the ledger as new records (superseding stale ones where applicable).
  - Fill `Memory-upvotes` / `Memory-downvotes` in the plan file with the ledger record IDs that helped or misled during this plan.
  - Write ONE votes record (`type: votes`, `plan: <plan-dir>`, `up:`/`down:` mirroring those plan fields). Skip only when both lists are empty.
  - Fill `Wellbeing-after`, `Complexity-felt`, and `Complexity-delta`.
  - Ask for human approval before `Done`.
- `Implementing -> Abandoned`:
  - Check off completed `Done-when` todos.
  - Record rationale and cleanup notes.
  - Apply the same distillation, learnings, votes-record, and wellbeing requirements as `Implementing -> Review`.
- `Review -> Implementing`:
  - Capture requested changes and re-open relevant `Done-when` items.
- `Review -> Done`:
  - Only after explicit human approval while plan is in `Review`.
  - Fill `Done-approved-by`, `Done-approved-at`, and `Done-approval-evidence`.
  - After setting `Status: Done` and finishing file edits, run:
    - `bash <zamm-skill>/scripts/zamm-archive.sh --archive`

## Wellbeing Telemetry (Plan Files)

Plans should include:
- `Wellbeing-before:` free text
- `Complexity-forecast:` one of `ant|gecko|raccoon|capybara|badger|octopus|manatee|shark|godzilla|kraken` (`kraken` is the off-scale wicked marker: the problem never truly resolves, so scope the plan as a bounded probe with closeable `Done-when` items, never as "solve it")
- `Memory-upvotes:` optional ledger record IDs that helped (for example `2026-05-14-tier-motion-x2f4a`)
- `Memory-downvotes:` optional ledger record IDs that were misleading/inconsistent (only when problems were observed)
- `Wellbeing-after:` free text (fill on `Review` or `Abandoned`)
- `Complexity-felt:` same scale (fill on `Review` or `Abandoned`)
- `Complexity-delta:` `lighter|as-expected|heavier` (fill on `Review` or `Abandoned`)
- `Done-approved-by:` required when `Status: Done`
- `Done-approved-at:` required when `Status: Done`
- `Done-approval-evidence:` required when `Status: Done`

## Session End (MUST)

1. Execute plan transition bookkeeping for touched plans (if applicable), per `## Plan Status Transitions (MUST)`.
2. Ensure touched plans have current `Last updated:` date.
3. Ensure durable learnings were distilled into ledger records and stale touched records were superseded per `## Distillation (MUST)` — plan-less research/Q&A sessions included.
4. If the digest showed `Needs reconciliation` and it was not yet resolved, resolve it now per `## Reconciliation (MUST)`.
5. If the human requests cleanup or plans are terminal, run archive flow per `## Archive Flow (Optional)`.

## Archive Flow (Optional)

- Run `bash <zamm-skill>/scripts/zamm-archive.sh` to list archive-ready plan directories.
- Run `bash <zamm-skill>/scripts/zamm-archive.sh --archive` to move ready plan directories into `zamm-memory/archive/plans/`; it recompiles the digest afterwards so the Plans tail reflects the move.
- Archive flow shall be triggered every time after a plan was marked `Status: Done` after file edits are finished.
- Ledger records are never archived by this flow; superseded and tombstoned records simply stay in place and drop out of the digest.

## Plan Status Snapshot (Optional)

- Run `bash <zamm-skill>/scripts/zamm-status.sh` to view grouped plan counts and listings by status.
- Buckets are: `Draft`, `Implementing`, `Review`, `Done`, `Abandoned`, and `Unknown`.

## Precedence (when sources conflict)

1. Explicit current human instruction
2. Code, tests, contracts (executable truth)
3. Active plan file and terminal status semantics
4. Live ledger records (as compiled in the digest; a record superseding another always outranks it)
5. Eternal initialization knowledge and archive/historical notes

## Key Constraints

- Ledger records are advisory, not authoritative. Verify before high-impact actions.
- The digest (`zamm-memory/.compiled/`) is generated, gitignored, and disposable; never commit it, never edit it, never treat it as the source of truth.
- The protocol version lives in `zamm-memory/VERSION`; update it only after completing a migration.
- Eternal doctrine belongs in `<zamm-skill>/references/eternal/knowledge.md`, not the ledger.
- An empty ledger means active memory has not been initialized; ask before running initialization and never add placeholder records.
- Major-version migration details belong in `<zamm-skill>/references/migrations/`, not in ledger records.
- Never store secrets, tokens, or credentials in memory files.
- If a record statement conflicts with code/tests, supersede it with a `suspected drift` record and verify.
- Prefer correction over accretion: supersede stale records before adding new ones that could duplicate or conflict.
