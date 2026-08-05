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
`zamm-run.sh scaffold` before proceeding under the old rules.

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
| plan moves to `Review` or `Abandoned` | learnings + votes record + telemetry fields | `Plan Status Transitions (MUST)` |
| plan `Done` (human-approved, from `Review` only) | archive flow | `Archive Flow (Optional)` |
| secrets or personal data landed in a record | exceptional erasure; git-history rewriting needs separate human approval | `Erasure (exceptional)` |

Referenced section names live in the rendered runtime files / protocol template above.

## Ledger write transaction

1. `bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area[/subpath][, area2]>' <topic-slug>` — prints the path of the created draft (`<id>.md.draft`). Add `--type`, `--importance`, `--durability`, `--supersedes`, `--plan` as applicable. Drafts are invisible to check and the digest until published.
2. Fill the skeleton: memory → digest block (headline paragraph + optional elaboration, optional `## Background`); tombstone → one-line reason; votes → at least one of `up:`/`down:`. Paraphrase the human — never verbatim quotes; describe the emotion instead of the raw words.
3. `bash <zamm-skill>/scripts/zamm-run.sh memory publish <topic-slug>` — validates the draft and, on success, lands it in the ledger and rebuilds the digest in one step (no separate digest command needed). On rejection the record returns to a draft with the violations printed; fix and re-run publish.
4. `bash <zamm-skill>/scripts/zamm-run.sh memory check` — confirm the ledger still passes as a whole; fix every violation until it prints `ZAMM check passed.`
5. Never edit a published record; correct it with a new record carrying `supersedes:`.

## Commands

- Scaffold / refresh: `bash <zamm-skill>/scripts/zamm-run.sh scaffold` — idempotent; creates the `zamm-memory/` tree, edits `.gitignore`/`.gitattributes`, writes `AGENTS.md` (managed block), `.cursor/rules/zamm.mdc`, `.cursorignore`; prints a summary and next steps. Always re-renders the managed surfaces, so it is also how you refresh after a skill update. Refuses to run over a pre-v3 memory tree.
- Compile / validate: see the transaction above.
- Plan status buckets: `bash <zamm-skill>/scripts/zamm-run.sh plan list`
- Archive terminal plans: `bash <zamm-skill>/scripts/zamm-run.sh plan archive` — moves terminal plan directories; refuses any plan that fails `plan check`.
- Validate plans: `bash <zamm-skill>/scripts/zamm-run.sh plan check` — required fields for the declared status, unchecked Done-when items.
- Validate everything: `bash <zamm-skill>/scripts/zamm-run.sh check` — ledger + plans, one exit code.
- Health overview: `bash <zamm-skill>/scripts/zamm-run.sh status` — read-only.
- Browse the ledger: `bash <zamm-skill>/scripts/zamm-run.sh memory list [--all] [--scope <area>]` and `memory show <slug|id>`.
- Retire storage: `bash <zamm-skill>/scripts/zamm-run.sh memory archive` — moves fully-retired chains out of the scan path; verifies the digest is unchanged.
- New plan: `bash <zamm-skill>/scripts/zamm-run.sh plan create '<title>'`; inspect one with `plan show <slug>`.

## Gated guides

- Existing-project initialization (`references/initialization/existing-project.md`): only after the human accepts the empty-ledger prompt or explicitly asks.
- Major-version migrations (`references/migrations/`): only on `VERSION` mismatch, legacy tier files, or an explicit upgrade request; `VERSION` is updated only after migration completes.
