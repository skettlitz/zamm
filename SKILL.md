---
name: zamm
description: Bounded memory workflow for agentic development. Use when initializing or operating ZAMM in a repository: scaffolding zamm-memory, creating plan directories and plans, archiving terminal plan directories, and syncing AGENTS/Cursor rule runtime files from canonical scaffold fragments.
---

# Zippy Agentic Memory Mill (ZAMM)

Use this skill to run the ZAMM workflow with minimal context overhead.

## Required References

Read these files as needed instead of duplicating policy in this file:

1. `<zamm-skill>/references/scaffold/protocol-body.template.md` (shared protocol source template)
2. `<zamm-skill>/references/scaffold/agents-header.template.md` (AGENTS header fragment template)
3. `<zamm-skill>/references/scaffold/rule-header.mdc` (Cursor rule header fragment)
4. `<zamm-skill>/references/scaffold/` (scaffold seed templates consumed by `zamm-scaffold.sh`)
5. `<zamm-skill>/references/templates/plan-template.plan.template.md` (agent copy-edit template for new plans)

For all MUST-level protocol details, follow:
`<zamm-skill>/references/scaffold/protocol-body.template.md`.

## Script Path Resolution

Resolve `<zamm-skill>` once per session using:
`<zamm-skill>/references/scaffold/protocol-body.template.md` under `## Script Path Resolution`.
Scripts are always under `<zamm-skill>/scripts/`.

## Core Commands

```bash
bash <zamm-skill>/scripts/zamm-scaffold.sh [--project-root <path>] [--overwrite-templates]
bash <zamm-skill>/scripts/zamm-archive.sh [--project-root <path>] [--archive]
bash <zamm-skill>/scripts/zamm-status.sh [--project-root <path>]
```

## Minimal Runbook

1. Session start: follow `Session Start (MUST)` in
   `<zamm-skill>/references/scaffold/protocol-body.template.md`.
2. During work: follow `Plan Directory Model (MUST)` and `Plan Status Transitions (MUST)`.
3. Session end: follow `Session End (MUST)`.

## Maintenance Rule

Keep this file concise. Put detailed contracts and examples in `references/`.
When editing protocol templates, update canonical scaffold fragments.
`zamm-scaffold.sh` composes runtime files directly from those fragments.
