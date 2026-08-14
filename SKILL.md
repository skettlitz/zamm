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

`<zamm-skill>/references/invariants.md` states what the toolchain guarantees and, just as
importantly, what it deliberately does not. Read it before reporting a defect or hardening
anything: a finding that violates none of its three guarantees is out of scope by design, not
an oversight.

Drift rule: the `SKILL-BLOCK:zamm:BEGIN version=...` stamp in `AGENTS.md` records the skill
version that rendered it. When it differs from the installed skill, tell the human and offer
`zamm-run.sh scaffold` before proceeding under the old rules.

## Dispatch by repository state

| Situation | Action | Reference |
| --- | --- | --- |
| no `zamm-memory/`, user asked for ZAMM | run scaffold (Commands below); report the files it touched | — |
| no `zamm-memory/`, no explicit request | do not scaffold; offer it | — |
| a command refuses with a protocol-version error (exit 5) | do what its message says — it names the remedy per case (install, migrate, or update the skill); never scaffold over a pre-v3 tree | `references/migrations/` |
| session start | one `memory digest` run — its stdout IS the digest, so read that and do not also open the compiled file; reread only after records were written or merged. Do not pre-check the protocol version: every operational command refuses on a mismatch and prints the fix, so a check the agent performs adds nothing | `Session Start (MUST)` |
| digest shows `Needs reconciliation` | resolve it this session | `Reconciliation (MUST)` |
| digest shows no live records | ask before initialization; never write placeholder records | `references/initialization/existing-project.md` |
| a distillation cue fires: remember-this; correction/standing rule; strong emotion with substance; repeated failure or dead end; pointable research result | ledger write transaction (below) | `Distillation (MUST)`; full semantics: `references/distillation-triggers.md` |
| plan moves to `Review` or `Abandoned` | learnings + votes record + telemetry fields | `Plan Status Transitions (MUST)` |
| plan `Done` (human-approved, from `Review` only) | archive flow | `Archive Flow (Optional)` |
| secrets or personal data landed in a record | exceptional erasure; git-history rewriting needs separate human approval | `Erasure (exceptional)` |

Referenced section names live in the rendered runtime files / protocol template above.

## Ledger write transaction

1. Compose the body first: memory → digest block (headline paragraph + optional elaboration, optional `## Background`); tombstone → one-line reason; erasure → why the content had to go; votes → no body at all. Paraphrase the human — never verbatim quotes; describe the emotion instead of the raw words.
2. Pass it on stdin to one command, which validates the record and lands it with the digest rebuilt:
   ```sh
   bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area[/subpath][, area2]>' <topic-slug> <<'EOF'
   <the record body>
   EOF
   ```
   Add `--type`, `--importance`, `--durability`, `--supersedes`, `--erases`, `--up`/`--down`, `--plan` as applicable. On rejection nothing is written and the violations are printed; fix the body or the flags and re-run.
3. `bash <zamm-skill>/scripts/zamm-run.sh memory check` — confirm the ledger still passes as a whole; fix every violation until it prints `ZAMM check passed.`
4. Never edit a written record; correct it with a new record carrying `supersedes:`.

## Commands

- Scaffold / refresh: `bash <zamm-skill>/scripts/zamm-run.sh scaffold` — idempotent; creates the `zamm-memory/` tree, edits `.gitignore`/`.gitattributes`, writes `AGENTS.md` (managed block), `.cursor/rules/zamm.mdc`, `.cursorignore`; prints a summary and next steps. Always re-renders the managed surfaces, so it is also how you refresh after a skill update. Refuses to run over a pre-v3 memory tree.
- Compile / validate: see the transaction above.
- Plan status buckets: `bash <zamm-skill>/scripts/zamm-run.sh plan list`
- Archive terminal plans: `bash <zamm-skill>/scripts/zamm-run.sh plan archive` — moves terminal plan directories; refuses any plan that fails `plan check`.
- Validate plans: `bash <zamm-skill>/scripts/zamm-run.sh plan check` — required fields for the declared status, unchecked Done-when items.
- Validate everything: `bash <zamm-skill>/scripts/zamm-run.sh check` — ledger + plans, one exit code.
- Health overview: `bash <zamm-skill>/scripts/zamm-run.sh status` — read-only.
- Browse the ledger: `bash <zamm-skill>/scripts/zamm-run.sh memory list [--all] [--scope <area>]` and `memory show <slug|id>`.
- Hand-composed drafts (the two-step alternative to stdin): `memory publish <slug|id>` lands one, `memory drafts` lists those not yet published, `memory discard <slug|id>` shows and deletes one. A draft is inert: `<id>.md.draft` is not a `*.md` file, so no compile enumerates it — only `publish` reads one, as a validated overlay, before landing it.
- Retire storage: `bash <zamm-skill>/scripts/zamm-run.sh memory archive` — moves fully-retired chains out of the scan path; verifies the digest is unchanged.
- New plan: `bash <zamm-skill>/scripts/zamm-run.sh plan create '<title>'`; inspect one with `plan show <slug>`.

## Gated guides

- Existing-project initialization (`references/initialization/existing-project.md`): only after the human accepts the empty-ledger prompt or explicitly asks.
- Major-version migrations (`references/migrations/`): only on `VERSION` mismatch, legacy tier files, or an explicit upgrade request; `VERSION` is updated only after migration completes.
