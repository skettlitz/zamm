---
name: zamm
description: Bounded memory workflow for agentic development. Use when initializing or operating ZAMM in a repository: scaffolding zamm-memory, creating plan directories and plans, archiving terminal plan directories, and syncing AGENTS/Cursor rule runtime files from canonical scaffold fragments.
---

# Zippy Agentic Memory Mill (ZAMM)

Use this skill to run the ZAMM workflow with minimal context overhead.

## Required References

For all MUST-level protocol details, follow: `<zamm-skill>/references/scaffold/protocol-body.template.md`.

This template is compiled into `.cursor/rules/zamm.mdc` and `AGENTS.md` by `bash <zamm-skill>/scripts/zamm-scaffold.sh`.

## Installation

Run `bash <zamm-skill>/scripts/zamm-scaffold.sh --project-root <repo-root>` to compile templates and generate the directory structure.
Use `--overwrite-templates` when refreshing existing runtime files.

## Minimal Runbook

1. Session start: follow `Session Start (MUST)` in the compiled runtime files (`AGENTS.md` or `.cursor/rules/zamm.mdc`).
2. During work: follow `Plan Directory Model (MUST)` and `Plan Status Transitions (MUST)`.
3. Session end: follow `Session End (MUST)`.
