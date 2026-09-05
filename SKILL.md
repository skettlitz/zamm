---
name: zamm
description: Operate ZAMM project memory, backlog, journal and plans. Use when a repository contains a zamm-memory/ directory (session start, remembering or recalling project knowledge, capturing ideas or episodes, creating/finishing/reviewing/abandoning/archiving plans), when zamm-memory/VERSION mismatches after a pull, or when the user explicitly asks to install, initialize, migrate, update, or diagnose ZAMM. Do not activate for generic planning or memory questions unrelated to ZAMM.
---

# Zippy Agentic Memory Mill (ZAMM)

Definitions:
- `<zamm-skill>` = the directory containing this SKILL.md.
- `<repo-root>` = the target project root (contains, or will contain, `zamm-memory/`).
  Pass `--project-root <repo-root>` unless the working directory is positively the repo root.

## Authority

The operating contract is layered so an agent loads only what it is about to do. The spine,
`<zamm-skill>/references/protocol.md`, holds session start and end, the
boundary test between the four trees and the rules they share. Each tree — knowledge, backlog,
plans, journal — has an index (`references/memory.md`, `backlog.md`, `plans.md`, `journal.md`)
over three layers: `<tree>-reading.md`, `<tree>-writing.md` (opening with who reads what you
write, and at what zoom) and `<tree>-maintenance.md`. The scaffold renders only the always-on
ROUTER (`references/scaffold/protocol-router.template.md`) into `AGENTS.md` (managed block) and
`.cursor/rules/zamm.mdc`; the router maps actions to layers and copies none of them. README.md
is explanatory, never authoritative.

`<zamm-skill>/references/invariants.md` states what the toolchain guarantees and what it
deliberately does not. Read it before reporting a defect or hardening anything: a finding
outside its three guarantees is out of scope by design.

Drift: the `SKILL-BLOCK:zamm:BEGIN version=...` stamp in `AGENTS.md` records the skill version
that rendered it. `memory digest` reports a mismatch; offer `zamm-run.sh scaffold` before
proceeding under the old rules.

## Dispatch by repository state

| Situation | Action | Read |
| --- | --- | --- |
| no `zamm-memory/`, user asked for ZAMM | run scaffold; report the files it touched | — |
| no `zamm-memory/`, no explicit request | do not scaffold; offer it | — |
| a command refuses with exit 5 (protocol version) | do what its message says; never scaffold over a pre-v3 tree | `references/migrations/` |
| session start | one `memory digest` run; its stdout IS the digest. Reread only after records were written or merged | nothing further: the router's paragraph is the whole rule. `references/memory-reading.md` only when a marker in the digest is unclear; spine `Session Start` only for an empty ledger or a plan decision |
| digest shows `Needs reconciliation` | resolve it this session | `references/memory-maintenance.md` |
| digest shows no live records | ask before initialization; never write placeholder records | `references/initialization/existing-project.md` |
| a distillation cue fires: remember-this; a correction or standing rule; strong emotion with substance; the same failure twice; a pointable research result | ledger write (below) | `references/memory-writing.md` first; the cues in full: `references/distillation-triggers.md` |
| correcting, merging or retiring a record; voting; erasing a secret | a new record, never an edit | `references/memory-maintenance.md` |
| an idea worth keeping but not starting | `backlog list`, then `backlog add '<sentence>'` or supersede/vote an existing idea; never a Draft plan | `references/backlog-writing.md` first |
| marking an idea for implementation, or promoting one into a plan | `backlog mark` / `backlog promote` | `references/backlog-maintenance.md` |
| a noteworthy episode: implies no action, asserts no durable fact | `journal add '<sentence>'` — never a `days` knowledge record, never a session-end ritual | `references/journal-writing.md` first |
| someone asks what happened, or for a summary of a period | answer from `journal digest <period>` (compiled, never stored), `journal list`, `search`, `stats` — all read-only | `references/journal-reading.md` |
| digest shows a `Journal:` line; or you are asked to STORE a period summary, or to record what you reviewed | `journal review` → distill → `journal settle`; or `journal elevate <kind> <period>` — writes, separate from answering | `references/journal-maintenance.md` first |
| work that warrants a plan and none matches | `plan create '<title>'` | `references/plans-writing.md` first |
| plan moves to `Review` or `Abandoned` | learnings + votes record + telemetry fields | `references/plans-maintenance.md` |
| plan `Done` (human-approved, from `Review` only) | archive flow | `references/plans-maintenance.md` |
| an IDE planning mode wrote an offsite `.plan.md` | mirror it into a ZAMM plan the same turn | `references/plans-writing.md` |
| secrets or personal data landed in a record | exceptional erasure, written INTO THE TREE THE RECORD LIVES IN (`memory create` / `backlog add` / `journal add --type erasure --erases <id>`), then delete the file; history rewriting needs separate human approval | that tree's `-maintenance.md` |

"spine `X`" is the section of that name in the protocol body.

## Ledger write

1. Compose the body (`references/memory-writing.md` says who reads each part, and at what
   zoom). The first paragraph is the headline: one imperative statement an agent mid-task can
   recognize as its situation and act on alone. Elaborate only where it changes what they do;
   detail read on demand goes under `## Background`. Say it once, in as few words as it takes — the digest is reread at every
   session start by every agent on the project. Paraphrase the human, never quote; no secrets.
2. Land it in one step. It validates first; on rejection it prints the violations and writes
   nothing (an unknown scope area is refused with the valid set):
   ```sh
   bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area[/subpath][, area2]>' <topic-slug> <<'EOF'
   <the record body>
   EOF
   ```
   Flags as applicable: `--type`, `--importance`, `--durability`, `--supersedes`, `--erases`,
   `--up`/`--down`, `--plan`.
3. Never edit a written record; correct it with a new one carrying `supersedes:`.

## Commands

One entrypoint, `bash <zamm-skill>/scripts/zamm-run.sh <group> <verb>`. `help [<topic>]` is the
reference for flags and semantics — read it rather than guessing.

- Project: `scaffold` (install, or refresh the rendered surfaces after a skill update; idempotent;
  refuses a pre-v3 tree), `status`, `check` (every tree, one exit code), `help`.
- `memory`: `digest`, `list [--all] [--scope]` (default: the digest's records; `--all`: every live one), `show`, `create`, `check`, `archive`;
  hand-composed drafts: `publish`, `drafts`, `discard`.
- `backlog`: `add`, `list [--all] [--scope]`, `show`, `mark` / `unmark`, `promote`, `check`.
- `journal`: `add`, `list`, `show`, `search`, `stats`, `digest`, `export`, `review`, `settle`,
  `elevate`, `check`.
- `plan`: `create`, `list`, `show`, `check`, `archive`.

## Gated guides

- Existing-project initialization (`references/initialization/existing-project.md`): only after the human accepts the empty-ledger prompt or explicitly asks.
- Major-version migrations (`references/migrations/`): only on `VERSION` mismatch, legacy tier files, or an explicit upgrade request; `VERSION` is updated only after migration completes.
