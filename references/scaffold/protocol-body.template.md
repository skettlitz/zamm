## Template Sync Contract (MUST)

Keep scaffold-consumed canonical files in:
- `<zamm-skill>/references/scaffold/`

In that directory:
- `protocol-body.template.md` is the shared protocol source template.
- `agents-header.template.md` and `rule-header.mdc` are surface-specific header templates.
- Remaining files are scaffold seed templates copied into project working trees.

Keep agent-authored plan template in:
- `<zamm-skill>/references/templates/plan-template.plan.template.md`

`zamm-scaffold.sh` concatenates `header + body` to create runtime files:
- `AGENTS.md`
- `.cursor/rules/zamm.mdc`

All content from `## Script Path Resolution` through `## Key Constraints` MUST remain text-identical across runtime surfaces.
Allowed differences are limited to file-format scaffolding before `## Script Path Resolution` (for example, `.mdc` frontmatter and AGENTS-specific intro lines).

## Script Path Resolution

The `zamm` skill directory is `<zamm-skill>` with scripts in subdirectory scripts/.

## Session Start (MUST — do this before any other work)

1. Read these files in order:
   - `zamm-memory/active/knowledge/EVERGREEN.md`
   - `zamm-memory/active/knowledge/MONTHLY.md`
   - `zamm-memory/active/knowledge/WEEKLY.md`

2. Count tier entries (`Wn`, `Mn`, `En`) in those files.
   - If any tier is at or above its upper tolerance bound, run consolidation per `## Knowledge Tier Motion (MUST)` before primary task work.
3. Identify the active plan directory under `zamm-memory/active/plans/`.
4. If no plan matches the user request, create a new plan directory and `.plan.md` file using:
   - `<zamm-skill>/references/templates/plan-template.plan.template.md`
5. Soft focus rule: prefer one active implementing plan at a time; if unclear, auto-pick by best match and ask the human only when ambiguity remains.

## Knowledge Tier Motion (MUST)

Tier names are symbolic, not calendar-bound. Treat them as memory layers with fixed caps and explicit motion rules.

Tier caps:
- WEEKLY: 30..37 cards
- MONTHLY: 12..16 cards
- EVERGREEN: 10..14 cards

Distillation ingress rule:
- When plan learnings are distilled, edit existing or append new WEEKLY cards at the end of `WEEKLY.md` first.
- After append, if any tier is at or above its upper tolerance bound, run consolidation immediately.

Consolidation trigger:
- Trigger on Session Start after reading + counting when any tier is at or above its upper bound.
- Trigger whenever distillation append pushes a tier to or above its upper bound.

Consolidation pass order:
1. WEEKLY consolidation
2. MONTHLY consolidation
3. EVERGREEN consolidation
4. Recount all tiers; repeat the pass order until all tiers are within tolerance windows.

Consolidation archive record (MUST):
- For every consolidation event, write one dated record file under:
  - `zamm-memory/archive/knowledge/consolidations/`
- Filename format:
  - `YYYY-MM-DD-HHMM-tier-consolidation.md`
- Do not use a single append-only log file; use one file per consolidation event.
- The record MUST include:
  1. Trigger (`session-start` or `post-distillation`)
  2. Tier counts before and after (`W`, `M`, `E`)
  3. Promotions, demotions, and drops performed
  4. One-line rationale for each dropped card
  5. Links/IDs for cards moved between tiers where applicable

WEEKLY consolidation (run when WEEKLY >= 37; reset to 30):
- Promote exactly 1 high-value WEEKLY card to MONTHLY (append at end of MONTHLY).
- Unify/edit overlapping WEEKLY cards when it improves clarity.
- Archive lowest-value/redundant WEEKLY cards until WEEKLY is 30.

MONTHLY consolidation (run when MONTHLY >= 16; reset to 12):
- Promote exactly 1 high-value MONTHLY card to EVERGREEN (append at end of EVERGREEN).
- Unify/edit overlapping MONTHLY cards when it improves clarity.
- Demote lower-value MONTHLY cards to WEEKLY (remove from MONTHLY; append to WEEKLY) until MONTHLY is 12.

EVERGREEN consolidation (run when EVERGREEN >= 14; reset to 10):
- Keep the 10 best, most durable cards in EVERGREEN.
- Consolidate by demotion only: demote overly similar/lower-signal EVERGREEN cards to MONTHLY (remove from EVERGREEN; append to MONTHLY) until EVERGREEN is 10.

## Plan Directory Model (MUST)

- Plan files live under `zamm-memory/active/plans/<plan-dir>/`.
- One directory is one plan context.
- The main plan file MUST use `.plan.md` suffix.
  - Recommended: `<plan-dir>.plan.md` with date-first slug (`YYYY-MM-DD-...`).
- Optional transient artifacts live under `<plan-dir>/workdir/`.
- Archive moves the full plan directory to `zamm-memory/archive/plans/<plan-dir>/`.
- `Done` and `Abandoned` are terminal; continue with a new plan directory.
- Do not maintain separate workstream state/index files. Discover plans by searching `zamm-memory/active/plans/**/*.plan.md` and reading `Status:`.

## Offsite Planning Backfill (MUST)

Cursor planning mode may generate an offsite `.plan.md` that does not follow ZAMM format.
Treat offsite plans as input context, not as the execution ledger.

Trigger:
- An offsite `.plan.md` was created/updated for the current task.
- No matching in-repo ZAMM plan exists yet, or the existing ZAMM plan is missing the offsite scope updates.

Required actions (same turn, immediately after planning):
1. Create or update `zamm-memory/active/plans/<plan-dir>/<plan-dir>.plan.md` using
   `<zamm-skill>/references/templates/plan-template.plan.template.md`.
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
  - Reconcile stale/conflicting knowledge claims touched by this work before appending learnings:
    - Prefer editing existing cards in place when a claim is outdated.
    - Merge or retire duplicates when two cards encode the same rule.
    - Do not leave contradictory active cards across WEEKLY/MONTHLY/EVERGREEN; if verification is pending, mark `suspected drift` and add a verification note.
  - Fill `## Learnings` (required; if no durable learning emerged, state that explicitly with a reason).
  - Append new WEEKLY cards from those learnings (required), then consolidate tiers if any upper tolerance bound is reached.
  - Fill `Wellbeing-after`, `Complexity-felt`, and `Complexity-delta`.
  - Ask for human approval before `Done`.
- `Implementing -> Abandoned`:
  - Check off completed `Done-when` todos.
  - Record rationale and cleanup notes.
  - Reconcile stale/conflicting knowledge claims touched by partial work before appending learnings, using the same rules as `Implementing -> Review`.
  - Fill `## Learnings` (required; if no durable learning emerged, state that explicitly with a reason).
  - Append new WEEKLY cards from those learnings (required), then consolidate tiers if any upper tolerance bound is reached.
  - Fill `Wellbeing-after`, `Complexity-felt`, and `Complexity-delta`.
- `Review -> Implementing`:
  - Capture requested changes and re-open relevant `Done-when` items.
- `Review -> Done`:
  - Only after explicit human approval while plan is in `Review`.
  - Fill `Done-approved-by`, `Done-approved-at`, and `Done-approval-evidence`.
  - After setting `Status: Done` and finishing file edits, run:
    - `bash <zamm-skill>/scripts/zamm-archive.sh --archive`
- Update `Memory-upvotes` / `Memory-downvotes` when memory cards materially helped or misled execution.

## Wellbeing Telemetry (Plan Files)

Plans should include:
- `Wellbeing-before:` free text
- `Complexity-forecast:` one of `ant|gecko|raccoon|capybara|badger|octopus|manatee|shark|godzilla`
- `Memory-upvotes:` optional memory IDs that helped (for example `W14, M18`)
- `Memory-downvotes:` optional memory IDs that were misleading/inconsistent (only when problems were observed)
- `Wellbeing-after:` free text (fill on `Review` or `Abandoned`)
- `Complexity-felt:` same scale (fill on `Review` or `Abandoned`)
- `Complexity-delta:` `lighter|as-expected|heavier` (fill on `Review` or `Abandoned`)
- `Done-approved-by:` required when `Status: Done`
- `Done-approved-at:` required when `Status: Done`
- `Done-approval-evidence:` required when `Status: Done`

## Session End (MUST)

1. Execute plan transition bookkeeping for touched plans (if applicable), per `## Plan Status Transitions (MUST)`.
2. Ensure touched plans have current `Last updated:` date.
3. Ensure touched knowledge cards were reconciled for staleness/conflicts and durable learnings were appended to WEEKLY; then reconcile tier caps per `## Knowledge Tier Motion (MUST)` (required).
4. If the human requests cleanup or plans are terminal, run archive flow per `## Archive Flow (Optional)`.

## Archive Flow (Optional)

- Run `bash <zamm-skill>/scripts/zamm-archive.sh` to list archive-ready plan directories.
- Run `bash <zamm-skill>/scripts/zamm-archive.sh --archive` to move ready plan directories into `zamm-memory/archive/plans/`.
- Archive flow shall be triggered every time after a plan was marked `Status: Done` after file edits are finished.

## Plan Status Snapshot (Optional)

- Run `bash <zamm-skill>/scripts/zamm-status.sh` to view grouped plan counts and listings by status.
- Buckets are: `Draft`, `Implementing`, `Review`, `Done`, `Abandoned`, and `Unknown`.

## Precedence (when sources conflict)

1. Explicit current human instruction
2. Code, tests, contracts (executable truth)
3. Active plan file and terminal status semantics
4. Knowledge tiers (WEEKLY > MONTHLY > EVERGREEN)
5. Archive and historical notes

## Key Constraints

- Knowledge tiers are advisory, not authoritative. Verify before high-impact actions.
- Never store secrets, tokens, or credentials in memory files.
- If a memory claim conflicts with code/tests, mark as `suspected drift` and verify.
- Prefer correction over accretion: update stale cards in place before adding new cards that could duplicate or conflict.
- During primary task work, avoid unnecessary knowledge churn; keep edits targeted and durable.
