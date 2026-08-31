# Zippy Agentic Memory Mill (ZAMM)

Coding agents forget everything between sessions. The usual fix — one growing memory file — bloats
until nobody reads it, and merge-conflicts the moment two machines or branches write to it.

ZAMM gives agents durable project memory that prunes itself and merges cleanly, wrapped in a
lightweight operating workflow that combines three things:

- task execution through plan directories,
- an **append-only knowledge ledger** of immutable record files, compiled into a bounded ranked
  digest at session start,
- archive hygiene that moves finished plan contexts out of active memory.

In short: plan while doing, distill what lasts as immutable records, let the compiler rank the
rest. The ledger is unbounded; attention is bounded.

ZAMM memory is advisory: it complements code, tests, and documentation and never outranks them.

Canonical skill name/folder is `zamm`.

## How it works in sixty seconds

1. Plans hold current work: mutable files with explicit status transitions and human-approved
   closure.
2. Durable learnings become small immutable record files under `zamm-memory/knowledge/<year>/`.
   Writers only ever add uniquely named files; committed records are never edited.
3. Corrections do not touch old records: a new record declares `supersedes: <old-id>` and the old
   file simply drops out of view while staying in history.
4. At session start the agent runs `zamm-run.sh memory digest`, which ranks all live records — author-rated
   importance, decaying over an author-rated shelf-life, corrected by votes from plan outcomes —
   and emits a bounded digest: an actionable top section balanced across knowledge areas (so one
   hot topic cannot drown the rest), one-line reminders below it, and counts for everything else.
   Fully decayed records go dormant: unlisted, but still greppable in the ledger. The digest
   ends with a compact listing of active plans (status, progress, title) plus the most
   recently archived plan IDs, so session start needs no separate plan discovery and a plan
   that moved to the archive on another machine stays findable after a pull.
5. Finished plans move to the archive.

Here is one record file — composed by the agent and landed in one step by
`zamm-run.sh memory create`, which validates it and writes nothing at all if it fails the
contract. Immutable once written. Everything above `## Background` is what the digest shows; the
rest is read on demand:

```markdown
# zamm-memory/knowledge/2026/2026-07-18-awk-posix-only-7k3fq.md
---
type: memory
scope: tooling/shell
importance: guardrail
durability: years
created: 2026-07-18
schema: 3
---
Keep every script POSIX sh + awk; stock macOS awk has no gawk extensions, so
gawk-isms break the toolchain for Mac users.

Applies to scripts/ and any generated hooks.

## Background
Found when gensub() failed on macOS 14 (awk 20200816). ...
```

`importance` and `durability` are the whole ranking system, and the agent sets them when it
writes the record (`--importance guardrail --durability years`). Rank decays over the durability
horizon, so an honest `days` note retires itself while a `permanent` guardrail never fades.

The digest entry it becomes (`!` marks a guardrail — do not violate; `+bg` flags a Background
section worth opening before high-impact action; votes join the bracket as they accumulate):

```markdown
### tooling/shell
- ! Keep every script POSIX sh + awk; stock macOS awk has no gawk extensions, so
  gawk-isms break the toolchain for Mac users. [2026-07-18-awk-posix-only-7k3fq +bg]
  Applies to scripts/ and any generated hooks.
```

To update this memory later, the agent writes a new record with
`supersedes: 2026-07-18-awk-posix-only-7k3fq` — the old file never changes. If two branches
update the same memory independently, git merges cleanly (two added files) and the next digest
flags both heads under `Needs reconciliation`; the agent resolves them by writing one record
that supersedes both.

Digest budgets and scoring constants are deliberately not documented here: they are tuning
knobs, and their single authoritative home is the commented header of `scripts/internal/zamm-compile.sh`.
The digest itself explains its own entry format at the top of every compile.

## What the human does

ZAMM runs mostly agent-side. The human:

- approves plan closure (`Review -> Done`) — agents cannot self-approve,
- approves one-time operations before they run: project scaffolding, initialization scans,
  protocol migrations, and any git-history erasure,
- occasionally answers "is this still true?" when the agent flags suspected-stale knowledge,
- sees every ledger write in ordinary code review — records are plain markdown files in git.

## What gets added to a project

| Path | Purpose | Committed? |
| --- | --- | --- |
| `zamm-memory/knowledge/<YYYY>/` | immutable ledger records | yes |
| `zamm-memory/active/plans/`, `zamm-memory/archive/plans/` | plan contexts | yes |
| `zamm-memory/VERSION` | installed protocol version (`3`) | yes |
| `zamm-memory/.compiled/memory.md` | generated digest | no (gitignored) |
| `AGENTS.md` managed block | rendered runtime protocol | yes |
| `.cursor/rules/zamm.mdc` | rendered runtime protocol (Cursor) | when used |
| `.gitignore`, `.gitattributes`, `.cursorignore`, `.cursorindexingignore` | required lines appended / created | yes |

## Install the skill (human)

```bash
git clone https://github.com/skettlitz/zamm.git
```

Copy into your skills subdirectory (e.g. `~/.cursor/skills` or `~/.agents/skills`). Ensure the
subdirectory is named `zamm` and contains `SKILL.md`.

Pick one location and keep it the same across a team. The scaffold records the resolved skill
path in the rendered `AGENTS.md` (as `~/...` when it lives under your home directory, or
`<project-root>/...` when it is vendored into the repo), and that file is committed — so
teammates who install elsewhere will see that one line flip back and forth in git.

## Set up a project (agent, with your consent)

Ask your agent to set up ZAMM in the repository. It runs
`zamm-run.sh scaffold`, which creates the `zamm-memory/` tree and
writes the runtime files listed in the table above, printing every path it touched. The script
is idempotent and safe to rerun. If the ledger is empty afterwards, the agent asks before
running the initialization scan — a deliberate, human-approved pass over the existing project.

## Updating

Update the `zamm` skill directory, then have the agent run
`zamm-run.sh scaffold`: it re-renders every scaffold-managed runtime file
(`AGENTS.md` managed block, `.cursor/rules/zamm.mdc`, `.cursorignore`, `.cursorindexingignore`) from the installed skill.
Rendered runtime files carry a skill-version stamp; agents notice the drift and offer this
refresh on their own. ZAMM writes no ignore rules into `.cursorignore` (in
the Cursor sandbox an ignored path reads as EPERM, which breaks the commands
that must enumerate the ledger); retired trees and plan scratch are hidden
from search via `.cursorindexingignore` instead. A refresh removes the ignore
rules older ZAMM versions wrote into `.cursorignore`, printing each one; rules
you added yourself are left alone and reported by `status`.

Upgrading a project from tiered card memory (v1/v2): run the migration guide
`references/migrations/v1-v2-to-v3-memory.md` first; the scaffold refuses to run over a pre-v3
memory tree.

## Safety and limitations

- Never store secrets, tokens, credentials, or personal data in records. The ledger is
  append-only and lives in git, so true erasure is an exceptional, human-approved operation
  (see the Erasure section of the protocol).
- **Conflict-resistant, not conflict-free.** Normal knowledge writes add uniquely named files,
  so ordinary git content conflicts on memory are rare by construction. Semantic conflicts still
  exist — competing updates survive the merge and are reconciled explicitly — and plan files
  remain mutable and can conflict like any other file.
- Memory is advisory. Agents verify records against code and tests before high-impact actions
  and supersede suspected-stale entries instead of trusting them.

## Commands

Everything runs through one entrypoint, which finds the project root itself
(nearest ancestor holding `zamm-memory/`, else the git top level):

```
scaffold             install ZAMM here, or refresh the rendered surfaces
status               health overview: ledger, plans, drift
check                validate everything (memory + plans)
help [<topic>]       this text, or help for one command

memory digest        rebuild and print the digest
memory list          index of live records, slug first
memory show <slug>   one record in full
memory check         validate the ledger
memory create <slug> write a record; body on stdin (or --edit)
memory publish <slug>
                     validate a hand-written <id>.md.draft and land it
memory drafts        list hand-written drafts not yet published
memory discard <slug>
                     show and delete an unpublished draft
memory archive       move fully-retired chains out of the scan path

plan list            active plans grouped by status
plan show <slug>     one plan, with progress
plan check           validate active plans
plan create <title>  new plan directory and file
plan archive         move terminal plans to the archive
```

That listing is `zamm-run.sh help` verbatim; run it rather than trusting this page.

Pass `--project-root <path>` to override root detection. The underlying
scripts remain callable directly, but `zamm-run.sh` is the supported surface.

**One entrypoint means one permission rule.** Agent harnesses allowlist
commands by prefix, so a single entry covers every ZAMM operation:

```json
{ "permissions": { "allow": ["Bash(bash /path/to/zamm/scripts/zamm-run.sh:*)"] } }
```

## What ZAMM guarantees

`references/invariants.md` is the contract: every output is a truthful reading of some state
the ledger actually had, every failure is repairable by rerunning, and bytes are never
destroyed. It also records the non-goals — notably that a hostile process running as the same
user is out of scope, since it can rewrite these scripts between runs. Anything reported
against ZAMM should be measured against that file first; it is what keeps hardening bounded.

## Requirements and supported runtimes

- Bash plus POSIX awk and standard tools (find, sort, sed); no third-party runtime
  dependencies. Everything is reached through one entrypoint, `zamm-run.sh`, which
  picks the right interpreter per command: the compiler and record creator are POSIX
  sh, while scaffold, archive and status use bash features.
  Verified on stock macOS and Linux, both in CI. Windows is not supported.
- git is recommended (merging, history, erasure) but the ledger itself works without it.
- Runtime surfaces: `SKILL.md` for skill-based harnesses, the `AGENTS.md` managed block for
  AGENTS.md-reading runtimes, `.cursor/rules/zamm.mdc` for Cursor.

## Project Status

In **development and testing**; the structure is still evolving and tested on internal projects.

## Learn more

- Full operating contract: `<zamm-skill>/references/scaffold/protocol-body.template.md`
  (rendered into each project's runtime files by the scaffold)
- Agent entry point and dispatcher: `SKILL.md`
- Plan template: `<zamm-skill>/references/templates/plan.template.md`
- Memory record template: `<zamm-skill>/references/templates/memory-record.template.md`
- Existing project initialization: `<zamm-skill>/references/initialization/existing-project.md`
- Major-version migrations: `<zamm-skill>/references/migrations/`
- Changelog and change map vs. v2: `DELTAS.md` (decisions as they were taken — some were later reversed; it is history, not current behaviour)

(`<zamm-skill>` means your installed skill directory, for example `~/.agents/skills/zamm`.)
