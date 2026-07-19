---
name: zamm
description: Operate ZAMM project memory and plans. Use when a repository contains a zamm-memory/ directory (session start, remembering or recalling project knowledge, creating/finishing/reviewing/abandoning/archiving plans), when zamm-memory/VERSION mismatches after a pull, or when the user explicitly asks to install, initialize, migrate, update, or diagnose ZAMM. Do not activate for generic planning or memory questions unrelated to ZAMM.
---

# Zippy Agentic Memory Mill (ZAMM)

Definitions:
- `<zamm-skill>` = the directory containing this SKILL.md.
- `<repo-root>` = the target project root (contains, or will contain, `zamm-memory/`).
  Always pass `--project-root <repo-root>` to the scripts below unless the current working
  directory is positively verified to be the repo root.

## Authority

The full operating contract is `<zamm-skill>/references/scaffold/protocol-body.template.md`. The
scaffold renders it into the project runtime surfaces (`AGENTS.md` managed block,
`.cursor/rules/zamm.mdc`); in a scaffolded project those rendered files are operative — read the
template in full only when no rendered copy is in context. README.md is explanatory, never
authoritative.

Drift rule: the `SKILL-BLOCK:zamm:BEGIN version=...` stamp in `AGENTS.md` records the skill
version that rendered it. When it differs from the installed skill, tell the human and offer
`zamm-scaffold.sh --overwrite-templates` before proceeding under the old rules.

## Dispatch by repository state

| Situation | Action | Reference |
| --- | --- | --- |
| no `zamm-memory/`, user asked for ZAMM | run scaffold (Commands below); report the files it touched | — |
| no `zamm-memory/`, no explicit request | do not scaffold; offer it | — |
| `zamm-memory/VERSION` missing or ≠ `3` | ask before running the matching migration guide; never scaffold over a pre-v3 tree | `references/migrations/` |
| `VERSION` = `3`, session start | compile digest, cold-read once; reread only after new records were written or merged | `Session Start (MUST)` |
| digest shows `Needs reconciliation` | resolve it this session | `Reconciliation (MUST)` |
| digest shows no live records | ask before initialization; never write placeholder records | `references/initialization/existing-project.md` |
| a distillation cue fires: remember-this; correction/standing rule; strong emotion with substance; repeated failure or dead end; pointable research result | ledger write transaction (below) | `Distillation (MUST)`; full semantics: `references/distillation-triggers.md` |
| plan moves to `Review` or `Abandoned` | learnings + votes record + wellbeing fields | `Plan Status Transitions (MUST)` |
| plan `Done` (human-approved, from `Review` only) | archive flow | `Archive Flow (Optional)` |
| secrets or personal data landed in a record | exceptional erasure; git-history rewriting needs separate human approval | `Erasure (exceptional)` |

Referenced section names live in the rendered runtime files / protocol template above.

## Ledger write transaction

1. `bash <zamm-skill>/scripts/zamm-new-memory.sh --project-root <repo-root> --scope '<area[/subpath][, area2]>' <topic-slug>` — prints the created file path. Add `--type`, `--importance`, `--durability`, `--supersedes`, `--plan` as applicable.
2. Fill the skeleton: memory → digest block (headline paragraph + optional elaboration, optional `## Background`); tombstone → one-line reason; votes → at least one of `up:`/`down:`. Paraphrase the human — never verbatim quotes; describe the emotion instead of the raw words.
3. `bash <zamm-skill>/scripts/zamm-compile.sh --check --project-root <repo-root>` — fix every violation until it prints `ZAMM check passed.`
4. `bash <zamm-skill>/scripts/zamm-compile.sh --project-root <repo-root>` — refresh the digest (prints `ZAMM digest: <path>`).
5. Never edit a committed record; correct it with a new record carrying `supersedes:`.

## Commands

- Scaffold / refresh: `bash <zamm-skill>/scripts/zamm-scaffold.sh --project-root <repo-root>` — idempotent; creates the `zamm-memory/` tree, edits `.gitignore`/`.gitattributes`, writes `AGENTS.md` (managed block), `.cursor/rules/zamm.mdc`, `.cursorignore`; prints a summary and next steps. Add `--overwrite-templates` after a skill update to re-render every scaffold-managed runtime file. Refuses to run over a pre-v3 memory tree.
- Compile / validate: see the transaction above.
- Plan status buckets: `bash <zamm-skill>/scripts/zamm-status.sh --project-root <repo-root>`
- Archive terminal plans: `bash <zamm-skill>/scripts/zamm-archive.sh --project-root <repo-root> [--archive]` — lists ready plan directories; `--archive` moves them.

## Gated guides

- Existing-project initialization (`references/initialization/existing-project.md`): only after the human accepts the empty-ledger prompt or explicitly asks.
- Major-version migrations (`references/migrations/`): only on `VERSION` mismatch, legacy tier files, or an explicit upgrade request; `VERSION` is updated only after migration completes.
