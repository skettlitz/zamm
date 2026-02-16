---
name: zamm
description: Z-Agents Memory Mill (ZAMM) — bounded knowledge system for agentic development. Scaffolds a /zamm-memory/ directory with tiered knowledge files (WEEKLY/MONTHLY/EVERGREEN), initiative workstreams, decision records, and session rituals. Use when setting up project memory, initializing ZAMM, scaffolding memory, managing knowledge tiers, running memory maintenance, creating initiatives or workstreams, or when the user asks about session rituals, knowledge cards, the librarian role, or memory architecture.
license: MIT
---

# Z-Agents Memory Mill (ZAMM)

Bounded, always-loaded knowledge tiers + initiative-scoped work areas + archival strategy.
Designed for grep-first retrieval, cooperative parallel work, and agents with imperfect memory.

For the full design spec: [references/zamm-spec.md](references/zamm-spec.md)

## When to Invoke

Core workflows:
- bootstrap ZAMM in a repository (`scaffold.sh`)
- run session-bound maintenance checks and janitor passes (`janitor-check.sh`)
- create plans by copying `_PLAN_TEMPLATE.plan.md`
- validate memory and plan hygiene (`validate.sh`)
- summarize wellbeing/drift or archive-ready initiatives (`wellbeing-report.sh`, `archive-done-initiatives.sh`)

Advanced maintainer workflows:
- run a quick smoke test before shipping (`self-test.sh`)
- package a clean distributable archive (`package-skill.sh`)

## Script Path Resolution

Resolve once per session. Use whichever path exists (check in order):

1. `<project-root>/.cursor/skills/zamm/scripts/` (Cursor project-level)
2. `~/.cursor/skills/zamm/scripts/` (Cursor personal)
3. `<project-root>/.agents/skills/zamm/scripts/` (Codex repo-level)
4. `~/.agents/skills/zamm/scripts/` (Codex user-level)
5. `/etc/codex/skills/zamm/scripts/` (Codex admin-level; shared machines)

All script references below use `<zamm-scripts>` as shorthand for the resolved directory.

## Scaffold a New Project

Run in the target project root:

```bash
bash <zamm-scripts>/scaffold.sh
```

Creates: `/zamm-memory/` tree (knowledge tiers, edit logs, proposals, decisions, workstream template, indexes, archive), `AGENTS.md`, `.cursor/rules/zamm.mdc` (always-on agent rule), and `.cursorignore` (archive/cold excluded by default).

**Idempotent** — safe to re-run; never overwrites existing files.

## Session Rituals

### Session Start (MUST)

1. Read EVERGREEN.md, MONTHLY.md, WEEKLY.md.
2. Identify active initiative; read its `STATE.md`.
3. If no matching initiative, create from `_TEMPLATE` or ask the human.
4. **Plan-first gate (MUST):** Before starting any implementation, create or locate the plan file for the current task. Copy `_PLAN_TEMPLATE.plan.md` from the initiative's `plans/` directory, rename to `YYYY-MM-DD-<slug>.plan.md`, fill in the header fields, scope, and Done-when. Set `Status: Implementing` when you begin work. NEVER implement first and create the plan afterward — the plan is the organizing tool, not a post-hoc record.

### Session End (MUST)

1. Plan bookkeeping first (for current plan files, if any):
   - Check off completed `Done-when` todos.
   - Update `Status:` to match reality (`Draft | Implementing | Review | Done | Partial | Abandoned | Superseded`).
     NEVER set `Done` directly — set `Review` and ask the human to confirm. `Done` is only set after human approval.
   - Refresh `PR list`, `Evidence`, and `Docs impacted` for this session's changes.
   - **Before setting `Review` (MUST):** fill the `## Learnings` section — what was learned, what surprised, what should be remembered. A plan cannot move to Review with empty learnings.
   - If status moved to `Review`, `Partial`, or `Abandoned`, fill `Wellbeing-after`, `Complexity-felt`, and `Complexity-delta`.
   - Update `Memory-upvotes` / `Memory-downvotes` when specific cards materially helped or misled.
2. Update initiative `STATE.md` (current plan + status, next 3 actions, blockers).
3. **Integrate learnings (MUST before archiving):** If the initiative is archive-ready, review `## Learnings` from each plan and distill them into WEEKLY knowledge cards. Learnings must not be lost to the archive.
4. **Archive check (MUST if initiative looks done):** If all main plans are now terminal (Done/Partial/Abandoned/Superseded) or STATE.md was set to Done, immediately run `bash <zamm-scripts>/archive-done-initiatives.sh --archive`. Do not defer this.
5. Append a handoff block to the diary log.
6. If new durable learning occurred, write a proposal to `_proposals/`.
7. Run janitor preflight and act on results:
   - `bash <zamm-scripts>/janitor-check.sh --quiet`
   - Exit `0`: no janitor work required.
   - Exit `1`: setup or metadata issue; note and escalate.
   - Exit `2`: run one bounded maintenance pass using the suggested profile(s) — see Maintenance section below for full details.

### Compaction / Context Reset (MUST when detected)

1. Before clear: update `STATE.md`, append diary handoff, park pending proposals.
2. After restart: rehydrate EVERGREEN → MONTHLY → WEEKLY → STATE.md → current plan.

## Knowledge Tiers

| Tier | File | Semantics | Staleness |
|------|------|-----------|-----------|
| L1 Now | WEEKLY.md | Current constraints, unknowns, active landmines | 3 days |
| L2 Stable | MONTHLY.md | Patterns that survived churn, recurring themes | 14 days |
| L3 Invariant | EVERGREEN.md | Architecture boundaries, core mental model | No schedule |

All tiers: max 30 cards, ~220 lines, one line = max 200 chars.

### Card Format

```
M18 (Scope: auth/oidc)
* Lineage: W14 | M18
* Claim: Token refresh failures usually come from clock skew.
* Evidence: plans/...oidc-rollout.plan.md; PR#1234
* Last verified: 2026-02-16
```

Each card includes:
- Active tier ID on the header line (`Wn` or `Mn` or `En`)
- `Lineage:` IDs earned so far (always keep prior IDs once assigned)
- Claim, Scope, Evidence, optional Last verified / Confidence / Expiry hint.

Lineage rules:
- New knowledge starts in WEEKLY with a new `Wn`.
- First promotion to MONTHLY assigns a new `Mn` and keeps the `Wn`.
- First promotion to EVERGREEN assigns a new `En` and keeps `Wn` + `Mn`.
- Demotion keeps all earned IDs; only active tier changes.
- Permanent removal is allowed only from WEEKLY.

## Maintenance (Inline Janitor)

No background process. Check triggers at session start and session end; run a bounded maintenance pass when triggered.

**Triggers** (any one fires maintenance):
- Pending proposals in `_proposals/` older than 1 day
- WEEKLY.md `Last maintained:` > 3 days
- MONTHLY.md `Last maintained:` > 14 days
- Any initiative that is archive-ready: `Status: Done` in STATE.md, OR all main plans (not subplans) have terminal status (Done/Partial/Abandoned/Superseded)

**Run invariants**:
- Every janitor run MUST make at least 1 improvement edit.
- Add/replace/demote/remove counts may be 0 when not needed.
- Improvement edit means one of: tighten claim/scope, refresh evidence, resolve drift/duplication, or update verification metadata.
- Never remove directly from EVERGREEN or MONTHLY; demote instead.

**Cleanup profiles**:

1. Monthly cleanup (when MONTHLY is stale):
   - Demote 0–2 cards from MONTHLY → WEEKLY.
   - Edit 1–3 cards in EVERGREEN (minimum 1).
   - Optionally add/replace 0–1 card in EVERGREEN if truly needed.

2. Weekly cleanup (when WEEKLY is stale):
   - Remove 0–3 cards from WEEKLY (permanent retirement happens only here).
   - Edit 1–5 cards in MONTHLY (minimum 1).
   - Optionally add/replace 0–2 cards in MONTHLY if truly needed.

3. Project-finish cleanup (when initiative is closing):
   - Distill project learnings into WEEKLY first.
   - Edit 1–5 cards in WEEKLY (minimum 1).
   - Optionally add/replace 0–2 cards in WEEKLY if truly needed.
   - Mark initiative `Status: Done` when archive-ready (`Closing` remains a staged review state before final archive).

4. Archive-ready cleanup (when initiative is archive-ready):
   - Triggered when STATE.md says `Done` OR all main plans have terminal status.
   - A main plan being Done implies all its subplans are terminal — only main plans need checking.
   - Archive immediately: `bash <zamm-scripts>/archive-done-initiatives.sh --archive`
   - The script uses `git mv` (MUST — never `cp`) and auto-sets STATE.md to Done if needed.

Remaining work is picked up by the next agent that boots.

## Concurrency

**Cross-runtime concurrency is possible** (Cursor + Codex plugin + Codex CLI), so maintenance stays proposal-first and bounded:
- During normal task execution, write changes as proposals in `_proposals/`.
- During maintenance, apply only a small batch (≤5 proposals + one tier health check).
- If maintenance edits race, reconcile by evidence and log the resolution in `_edits/`.

Proposal files use `_proposals/YYYY-MM-DD-agentX.md`.

## Plan Placement (MUST)

Before creating/updating a plan file:

1. Resolve repository root.
2. Resolve target initiative slug:
   - If user specified one, use it.
   - Else use the active workstream.
   - If ambiguous, ask the user.
3. Plan files MUST live at: `zamm-memory/active/workstreams/<initiative-slug>/plans/`
4. Filename MUST use the `.plan.md` suffix:
   - Main plan: `YYYY-MM-DD-<plan-slug>.plan.md`
   - Subplan: `YYYY-MM-DD-<parent-plan-slug>.subplan-<subslug>.plan.md`
5. Never create plan files outside `.../workstreams/*/plans/`.
6. If the path does not exist, create from `_TEMPLATE` first, then place the plan.

## Wellbeing Telemetry (Plan Files)

Each plan should capture a brief emotional and complexity check-in:
- `Wellbeing-before:` free text before implementation
- `Complexity-forecast:` one of:
  - `peanuts | banana | grapes | capybara | badger | pitbull | piranha | shark | godzilla`
- `Memory-upvotes:` optional memory IDs that helped (e.g., `W14, M18`)
- `Memory-downvotes:` optional memory IDs that were misleading/inconsistent (use only when issues were observed)
- `Wellbeing-after:` free text after implementation
- `Complexity-felt:` same scale as forecast
- `Complexity-delta:` `lighter | as-expected | heavier`

When plan status becomes `Done`, `Partial`, or `Abandoned`, fill the after/felt/delta fields.

## Initiatives

Each initiative: `/zamm-memory/active/workstreams/init-YYYY-MM-short-slug/` containing STATE.md, plans/, working/, diary/, cold/.

- **Create**: copy `_TEMPLATE`, fill STATE.md.
- **Run**: plans evolve in place; old scratch moves to cold/.
- **Close**: set `STATE.md` to `Status: Done`, promote learnings to tiers, update /docs, `git mv` to archive.

For templates (STATE.md, plan header, diary handoff, proposal, decision record): see Appendix A in [references/zamm-spec.md](references/zamm-spec.md).

## Validation

Check memory health:

```bash
bash <zamm-scripts>/validate.sh --project-root /path/to/project
```

Checks: card counts vs caps, missing evidence links, stale `Last maintained:` timestamps, orphaned proposals, misplaced plan files.

Also warns on missing/invalid wellbeing and complexity fields, and invalid memory vote IDs, in plan files.

## Janitor Preflight

Quickly check whether janitor work is needed at session boundaries (startup or handoff):

```bash
bash <zamm-scripts>/janitor-check.sh
```

Use `--quiet` for exit-code-only startup checks.

## Wellbeing Report

Summarize wellbeing and complexity drift:

```bash
bash <zamm-scripts>/wellbeing-report.sh
```

## Initiative Janitor

List archive-ready initiatives in active workstreams:

```bash
bash <zamm-scripts>/archive-done-initiatives.sh
```

Archive them automatically (uses `git mv`):

```bash
bash <zamm-scripts>/archive-done-initiatives.sh --archive
```

## Additional Resources

- **Full design spec (sections 0–15 + appendices)**: [references/zamm-spec.md](references/zamm-spec.md)
- **Per-project rule template**: [references/zamm-rule.mdc.template](references/zamm-rule.mdc.template)
