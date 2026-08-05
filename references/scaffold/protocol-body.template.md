## Script Path Resolution

The `zamm` skill directory is `<zamm-skill>`. Every `<zamm-skill>` token below stands for that directory (scripts live in its `scripts/` subdirectory); expand it when running the commands.

Commands are reached through one entrypoint, `zamm-run.sh`, which finds the project root itself: the nearest ancestor directory holding `zamm-memory/`, else the git top level. That is why no command below passes a root — running from a subdirectory resolves correctly on its own. Pass `--project-root <path>` only when the working directory is genuinely outside the target project.

## Session Start (MUST - do this before primary task work)

1. Protocol version check:
   - Read `zamm-memory/VERSION`.
   - Current protocol version is `3`.
   - If the file is missing or does not contain `3`, treat the project as needing a ZAMM migration and ask whether to run the matching guide under `<zamm-skill>/references/migrations/`.
   - Do not infer migration state from legacy filenames or record contents during routine startup; the version file is the required check.
   - Migration work updates `zamm-memory/VERSION` only after migration is complete.

2. Digest compile and cold-start read:
   - Run `bash <zamm-skill>/scripts/zamm-run.sh memory digest` (always; it is fast, deterministic, and safe to rerun).
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
4. If no plan matches the user request AND the request warrants a plan, create a new plan directory and `.plan.md` file using:
   - `<zamm-skill>/references/templates/plan.template.md`
   Then recompile the digest so its Plans tail lists the new plan.
   - Warrants a plan: multi-step work, changes that persist beyond the session, anything producing research artifacts or a decision worth revisiting, or work you expect to span sessions.
   - Does NOT warrant a plan: answering a question, reading or explaining code, a lookup, a one-line or single-file trivial edit, running a command for the human. Plan-less sessions are normal and expected — `## Session End (MUST)` covers them, and distillation still applies (a durable learning from a plan-less session is still written to the ledger).
   - The human overrides in either direction on request; when genuinely unsure, ask rather than defaulting to a plan directory nobody wanted.
5. Soft focus rule: prefer one active implementing plan at a time; if unclear, auto-pick by best match and ask the human only when ambiguity remains.

## Ledger Memory Model (MUST)

Active knowledge is an append-only ledger of immutable record files under `zamm-memory/knowledge/<YYYY>/`. There are no tiers, no ID counters, and no consolidation rituals: the compiler (`zamm-compile.sh`) derives liveness, vote totals, ranking, and supersede links from the records at read time. Ranking = author-rated importance decayed over the author-rated durability horizon, corrected by votes; fully decayed records go dormant (counted in the digest, not listed, always greppable in the ledger). Attention is bounded in two layers: up to ~75 full Digest blocks (actionable) and up to ~150 Headlines (reminders); further live records stay greppable but unlisted. Digest seats are balanced across top-level scope areas by a per-area score penalty (a weighted compromise, not a quota) so one hot topic cannot drown the others; a record with several area tags competes through its least-crowded area but pays a small score cost per extra tag, so precise tagging wins over tag-sprawl. Live guardrails never go dormant and are always included in the Digest layer: `!` is a safety contract, so a guardrail leaves the digest only through supersession or a tombstone, never through silent decay or downvotes.

What is and is not bounded: the ~75 Digest blocks and ~150 Headlines are the only capped sections. Live guardrails are admitted BEFORE that cap and can exceed it; competing heads under `Needs reconciliation`, every active plan, and the recently-archived tail are all listed in full. The digest is therefore bounded in its ranked layers, not in total size — an inflated guardrail count or a large conflict backlog grows it without limit. Keep guardrails rare (`memory check` warns past 15 live ones) and resolve conflicts rather than letting them accumulate.

Record file rules:
- One file is one immutable record. Never edit, rename, or delete a record file once committed (sole exception: `## Erasure (exceptional)`).
- Filename is the record ID: `YYYY-MM-DD-<topic-slug>-<suffix>.md`.
  - All lowercase; charset `[a-z0-9-]` only; slug at most 40 chars; date is the creation date.
  - `<suffix>` is 5 random chars from the 30-symbol alphabet `23456789abcdefghjkmnpqrstvwxyz` (lowercase Crockford base32 minus the visually ambiguous `0 1 i l o u` — 30 symbols, not 32). The suffix exists so uncoordinated writers on different machines cannot collide: collisions are only possible between records sharing the same date AND the same slug, so the 30^5 space is far larger than the risk it covers.
- Prefer creating records with `bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area[/subpath][, area2]>' <topic-slug>`; hand-written files MUST follow the same naming and schema rules. `memory create` writes an `<id>.md.draft` that the compiler ignores, so a record being composed never appears half-finished in the ledger; fill in the body, then run `zamm-run.sh memory publish <id>` to validate it and land it (it recompiles the digest on success, and leaves the file as a draft if it does not validate). Scripted/migration callers may pass `--immediate` to skip the draft and write the final `.md` directly.
- Never rename or move files or directories under `zamm-memory/knowledge/` (the add-only layout is what keeps ledger merges conflict-resistant; renames reintroduce ordinary git conflicts). Two documented exceptions: `## Erasure (exceptional)`, and `zamm-run.sh memory archive`, which moves whole retired chains to `zamm-memory/archive/knowledge/`. A chain qualifies only when nothing in it still affects the digest — no live memory record and no live votes record — because votes aggregate over the whole ancestor chain of a record, so a dead ancestor of a live head is load-bearing. Archived records stay greppable in the working tree and their ids stay resolvable; the command verifies the digest is unchanged and rolls back if it is not.
- Never store secrets, tokens, or credentials in records; ledger records are effectively permanent.
- Never quote the human verbatim in a record: paraphrase the substance and, where the register matters, describe the emotion (e.g. "strong frustration with rebuild times") instead of the raw words. Records are permanent and team-visible; profanity and heat-of-the-moment phrasing must not be immortalized.

Record schema — frontmatter is flat `key: value` lines between two `---` lines; every value is a plain string; lists are comma-separated; unknown keys are ignored; omit empty keys (one exception: a fresh votes skeleton from `zamm-run.sh memory create --type votes` carries empty `up:`/`down:` lines — fill at least one before committing; `memory check` rejects a votes record with both empty):
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
  - `other` — catch-all when none of the eight areas fit cleanly. MUST be the sole tag with no subpath. Prefer the closest real area first; use `other` only as temporary parking, then refile via supersession (`memory check` fails above 5 live `other` records)

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
- Correct a vote: supersede the votes record. A votes record that is superseded or tombstoned stops counting entirely, so superseding it with a corrected votes record (or retiring it with a tombstone) IS the correction path — never edit the original, and never cast an opposite vote to cancel one out. A votes record may only supersede another votes record.

## Distillation (MUST)

Mechanics:
- Prefer correction over accretion: supersede stale records, merge overlaps, add only genuinely new knowledge.
- Rate `importance`/`durability` honestly — they are the whole ranking system. Refresh a still-true record near its horizon by superseding with re-rated fields.
- Suspected-stale but unverified: supersede with a `suspected drift` record plus a verification note.
- A write is complete only after `bash <zamm-skill>/scripts/zamm-run.sh memory publish <id>` accepts the draft — publish validates the record and recompiles the digest in one step. Records are drafts until published, immutable after.

Write a record when (compact cues; full semantics in `<zamm-skill>/references/distillation-triggers.md`):
- the human says remember this — same turn, no damping
- the human corrects you or states a standing rule, any tone — else it evaporates at session end
- the human shows strong emotion (complaint or praise) with substance behind it — record the substance, short-lived, never the raw words
- the same failure hits twice — cause + workaround now; still stuck: short-lived dead-end record (goal, tried, ruled out)
- research yields a conclusion whose details live in a pointable file — conclusion + pointer

Do not write: free-floating values with nowhere to recheck; external changes that broke nothing; churn during primary work. The cues are deliberately coarse — accept near-misses rather than paying for precision every session.

## Reconciliation (MUST)

- After a `git merge`/`git pull`, two branches may have independently superseded the same record. Both successors stay live (git does not conflict on added files) and the digest lists them under `Needs reconciliation` — an index; each competing head also keeps its FULL block in `## Digest`, marked `~`, so conflicting detail is never hidden.
- Attempt resolution in the session the digest surfaces it: when ground truth IS determinable from code, git history, tests, or context, write ONE new record whose body merges the competing statements (or picks the correct one, stating why) and whose `supersedes:` lists ALL competing head IDs.
- If ground truth CANNOT be determined, leave the heads unmerged. Do not invent a merged claim to clear the warning: this ledger is append-only, so a fabricated union is permanent, while the `suspected drift` marker that excuses it decays out of the digest long before the claim does. An unresolved conflict is information; a manufactured resolution is a durable false record wearing a resolved badge.
  - Instead: tell the human the group is unresolved, state what evidence would settle it (a file to read, a test to run, a person to ask), and leave both heads live. The digest keeps surfacing the group until it is genuinely resolved — that is the intended steady state, not a failure.
  - Write a merge record ONLY when you believe it. "Keep every restriction from both heads" is a legitimate merge when the claims are compatible and you can say so; it is not a default escape hatch, and it is wrong when the heads contradict each other, when one describes retired behavior, or when combining the restrictions would block work that should be possible.
- Never resolve by deleting or editing the head files, and never silently prefer one head by timestamp; timestamps across machines are display metadata, not causality.

## Erasure (exceptional)

Only for secrets or personal data committed by mistake:
1. Append the record ID to `zamm-memory/knowledge/shun.md` (one ID per line, `#` comments allowed) so compilers ignore any stray copy.
2. Delete the record file.
3. Git history rewriting (`git filter-repo` or equivalent) is a separate, explicitly human-approved operation; ask, never assume.

A shunned ID stays a valid graph node, so erasure does not break the ledger: records that supersede it remain valid and keep their place in the chain (`memory check` does not report a missing target), while the erased record contributes no content, no votes, and no durability credit. Votes pointing at it are dropped silently. Successors are NOT rewritten — never edit a committed record to remove a `supersedes:` pointer at an erased ID.

## Plan Directory Model (MUST)

- Plan files live under `zamm-memory/active/plans/<plan-dir>/`.
- One directory is one plan context.
- The main plan file MUST use `.plan.md` suffix.
  - Recommended: `<plan-dir>.plan.md` with date-first slug (`YYYY-MM-DD-...`).
- Optional transient artifacts live under `<plan-dir>/workdir/`.
- Archive moves the full plan directory to `zamm-memory/archive/plans/<plan-dir>/`.
- `Done` and `Abandoned` are terminal; continue with a new plan directory.
- Do not maintain separate workstream state/index files. The compiled digest lists active plans compactly; when digging deeper, search `zamm-memory/active/plans/**/*.plan.md` and read `Status:`.
- Recompile the digest whenever a plan directory is created or archived (`zamm-run.sh plan archive` recompiles on its own); other status transitions are picked up by the recompile step of the ledger-write transaction during transition distillation.

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
  - Fill `Execution-context-before` and `Complexity-forecast`.
- `Draft -> Abandoned`:
  - Record rationale under `## Loose ends`. A never-started draft needs nothing more — the checker asks for the full retrospective (telemetry + learnings) only once work has happened (an `Execution-context-before` was filled, or a `Done-when` item was checked).
- `Implementing -> Review`:
  - Ensure all existing `Done-when` todos are checked. If an item became obsolete, remove it before moving to `Review`.
  - Reconcile stale/conflicting live records touched by this work per `## Distillation (MUST)` before adding new learnings.
  - Fill `## Learnings` (required; if no durable learning emerged, state that explicitly with a reason).
  - Distill durable learnings into the ledger as new records (superseding stale ones where applicable).
  - Fill `Memory-upvotes` / `Memory-downvotes` in the plan file with the ledger record IDs that helped or misled during this plan.
  - Write ONE votes record (`type: votes`, `plan: <plan-dir>`, `up:`/`down:` mirroring those plan fields). Skip only when both lists are empty.
  - Fill `Execution-friction-after`, `Complexity-felt`, and `Complexity-delta`.
  - Ask for human approval before `Done`.
- `Implementing -> Abandoned`:
  - Check off completed `Done-when` todos.
  - Record rationale and cleanup notes.
  - Apply the same distillation, learnings, votes-record, and telemetry requirements as `Implementing -> Review`.
- `Review -> Implementing`:
  - Capture requested changes and re-open relevant `Done-when` items.
- `Review -> Done`:
  - Only after explicit human approval while plan is in `Review`.
  - Fill `Done-approved-by`, `Done-approved-at`, and `Done-approval-evidence`.
  - After setting `Status: Done` and finishing file edits, run:
    - `bash <zamm-skill>/scripts/zamm-run.sh plan archive`

## Execution Telemetry (Plan Files)

These fields describe the WORK — its friction, its uncertainty, how the
estimate held up. They are not about anyone's inner state: plan files are
committed and team-visible, so keep personal and health-adjacent detail out
of them entirely.

Plans should include:
- `Execution-context-before:` free text — what makes this hard or uncertain going in: unknowns, missing access, risky surfaces, coordination needed
- `Complexity-forecast:` one of `ant|gecko|raccoon|capybara|badger|octopus|manatee|shark|godzilla|kraken` (`kraken` is the off-scale wicked marker: the problem never truly resolves, so scope the plan as a bounded probe with closeable `Done-when` items, never as "solve it")
- `Memory-upvotes:` optional ledger record IDs that helped (for example `2026-05-14-tier-motion-x2f4a`)
- `Memory-downvotes:` optional ledger record IDs that were misleading/inconsistent (only when problems were observed)
- `Execution-friction-after:` free text (fill on `Review` or `Abandoned`) — what actually cost time: tooling failures, flaky steps, missing docs, rework, waiting on answers
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

- Run `bash <zamm-skill>/scripts/zamm-run.sh plan archive --list` to preview archive-ready plan directories without moving anything.
- Run `bash <zamm-skill>/scripts/zamm-run.sh plan archive` to move ready plan directories into `zamm-memory/archive/plans/`; it recompiles the digest afterwards so the Plans tail reflects the move.
- Archive flow shall be triggered every time after a plan was marked `Status: Done` after file edits are finished.
- Ledger records are never archived by this flow; superseded and tombstoned records simply stay in place and drop out of the digest.

## Plan Status Snapshot (Optional)

- Run `bash <zamm-skill>/scripts/zamm-run.sh plan list` to view grouped plan counts and listings by status.
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
