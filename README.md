# Zippy Agentic Memory Mill (ZAMM)

ZAMM is project memory for coding agents that cannot bloat and cannot merge-conflict.
Every fact is one immutable markdown file. What an agent reads at session start is a
digest recompiled from all of them, ranked and bounded, so the ledger grows without limit
while the reading stays a few hundred lines.

The mechanics, not the promise:

- **One record, one file, never edited.** A record is named by date, slug and a random
  suffix and lands through one command that validates it first and writes nothing on
  failure. A correction is a new file carrying `supersedes: <old-id>`; the old one drops
  out of view and stays in history.
- **Two writers, two added files.** Branches and machines writing memory never produce a
  conflicting hunk. When both corrected the same record, the next digest lists the two heads
  under `Needs reconciliation` and the agent writes one record that supersedes both.
- **Ranking is declared once and prunes itself.** The author rates importance (`guardrail`,
  `useful`, `minor`) and durability (`days` to `permanent`); the score decays over that
  horizon, and plan outcomes vote records up or down. A `days` note retires itself, a
  `permanent` guardrail never fades, and a decayed record goes dormant: unlisted, still on
  disk, still greppable.
- **Four trees, one record format, one boundary test.** Knowledge (what is true), backlog
  (what we might do), journal (what happened) and plans (what we are doing) share the same
  immutable records and the same graph; only the lens differs.
- **Reads never write, and writes fail closed.** Every lens is derived and regenerable;
  every command either lands a valid record or lands nothing. The contract is written down in
  `references/invariants.md`: every output is a truthful reading of some state the ledger
  actually had, every failure is repairable by rerunning, bytes are never destroyed.
- **No runtime to install.** POSIX sh and awk, one entrypoint, one permission rule for the
  agent harness. The suite of 600-odd tests runs against the real scripts on stock macOS and
  Linux in CI.

ZAMM memory is advisory: it complements code, tests and documentation and never outranks
them. Canonical skill name and folder: `zamm`.

## Session start is one command

```sh
bash <zamm-skill>/scripts/zamm-run.sh startup
```

It prints two lines — what the project holds, and the path of the digest:

```
ZAMM v3 · 34 live · 3 guardrails · 2 plans (1 blocked) · 11 ideas (2 hot) · 47 episodes
digest ready: zamm-memory/.compiled/zamm-digest.md
```

Below them, two more lines when something is wrong with the project — never more than two:

```
defects: 1 contested group, 2 quarantined records, skill drift
details: zamm-memory/.compiled/zamm-defects.md
```

That file carries a section per defect — what it means, what it costs, the one command that
addresses it. Every startup writes it, so it also says when there is nothing wrong, and any
other compile deletes it, so if it is there it is current. A
healthy project prints neither line. The explanations used to print in full at session
start, four lines each; the content was right and the place was wrong, because a defect
needs room to explain itself and session start is the one surface with none. How to read the
digest is not repeated either — the rendered router in `AGENTS.md` carries it, and the same
agent read that minutes earlier.

Reading that file, whole, is the whole read. Top to bottom: a `Needs reconciliation` index when a merge
left two heads; marked backlog ideas; up to 200 records balanced across knowledge areas so
one hot topic cannot drown the rest, each with its elaboration where the budget could afford
it (a leading `!` is a guardrail, `+bg` means a Background section exists, `+el` means the
elaboration did not fit); counts for the unlisted and the dormant; the active plans with
status and progress; the recently archived plan ids; one backlog line; and, only when
journal digestion is due, one `Journal:` line.
Nothing else has to be discovered. The agent reruns it only after records were written or
merged.

## Four trees, one boundary test

Implies action and is current work: a **plan**. Implies action, but not now: the
**backlog**. Asserts a durable fact: **knowledge**. Implies no action and asserts no fact,
yet worth a trace: the **journal**. The archive is the exit for all four.

- **Knowledge** — `memory create --scope <area> <slug>` with the body on stdin. The first
  paragraph is the headline an agent mid-task can act on alone; detail under `## Background`
  is read on demand. Corrections supersede, retirements are tombstones, votes ride on plan
  closure. Eight fixed scope areas keep the digest balanced.
- **Backlog** — `backlog add 'One sentence.'` captures; `backlog list` is the lens, hot to
  cold. Ideas cool into dormancy on their own unless superseded or voted up; `backlog mark`
  pushes one into the digest until `backlog promote` turns it into a plan or `unmark` drops
  it. Never a Draft plan for an idea nobody is starting.
- **Journal** — `journal add 'One sentence.'` records an episode: a side quest, an outage, a
  considered non-action. `journal list` is the timeline; `journal digest <period>` compiles a
  period view and stores nothing; `journal review` and `settle` triage behind a claim
  watermark; `journal elevate` stores a period summary as a record. Other skills read it
  through one predicate grammar and a versioned TSV export.
- **Plans** — `plan create '<title>'` opens a directory with a mutable plan file. Status runs
  Draft, Implementing, Review, then Done or Abandoned; only a human approves Done. Close-out
  writes learnings and a votes record into the ledger, and `plan archive` moves the directory
  out of active memory.
- **Blocked** — `plan block --kind <human|plan|external|defect> '<sentence>'` is how an agent
  says "I cannot continue, and the reason will outlive this session". The class says who
  clears it; the reason leads the digest Plans tail, above Review, so the whole team sees it
  without opening a file. `plan unblock '<how it cleared>'` returns the plan to Implementing
  and keeps the entry as execution telemetry. A `plan:<id>` block is checked: `plan check`
  says so when the dependency has already landed.

## One record

Composed by the agent, landed in one step. Everything above `## Background` is what the
digest shows; the rest is read on demand:

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

The digest entry it becomes (`!` marks a guardrail, `+bg` flags the Background section,
votes join the bracket as they accumulate):

```markdown
### tooling/shell
- ! Keep every script POSIX sh + awk; stock macOS awk has no gawk extensions, so
  gawk-isms break the toolchain for Mac users. [2026-07-18-awk-posix-only-7k3fq +bg]
  Applies to scripts/ and any generated hooks.
```

An idea and an episode are the same file shape with a different root: `backlog add` and
`journal add` write them from one sentence, and any depth rides below the headline.

The digest is delivered as a **file the agent reads**, not as command output. `startup`
recompiles and hands back a path; reading that file once, whole, is the session
read. This is not a detail of plumbing. Command output is capped — Claude Code cuts a Bash
result at 30000 characters and replaces the remainder with a short preview — so a digest
printed to stdout is truncated silently, and a session that gets a header and one entry
proceeds believing it read memory. A path cannot be truncated. `--inline` still prints the
digest for a reader with no file tool, and warns when the output will not survive.

That makes the surface's ceiling an attention budget rather than a plumbing one: what it
bounds is how much context memory takes from every session before any work starts. The
surface is bounded twice — by one entry count, which decides WHICH records are listed (200),
and by a soft character ceiling, which decides how much each listed record gets to say. When
the ceiling binds, entries give up their elaboration in reverse rank order and render as
their headline alone, marked `+el` so a reader knows there is more in the file. There used
to be two layers here, 75 full blocks and 150 headline-only reminders, and the split
predated the budget: with both in place a record could be demoted twice for one reason, and
the boundary between "actionable" and "a reminder that this exists" was a judgement about
content that the ranking never knew. Membership is one cap now, and detail is one budget. No record is ever dropped
to hit the number: a digest that sheds entries to look small is lying about the ledger, so
an oversized one goes over its budget and says so instead — in its own `Budget:` footer and
on `status`, not at session start. An overrun is a standing property of a ledger that has
grown, and only a human can decide what gets retired; a notice that fires every session
forever would just teach the reader to skip the notices that need acting on.

The same ledger is rendered a second time, as `.compiled/zamm-digest-full.md`: every record
that is still standing, dormant ones included, each with its full elaboration, no cap and no
budget. That one is for a person searching for something half-remembered — `+el` is exactly
the wrong answer to "where did I write that down" — and it says so at the top, because an
agent reading it at session start would pay for everything the ranking decided not to push.

Neither file is rebuilt when nothing has moved. The compiler fingerprints its inputs and a
startup whose fingerprint matches the one stored beside the digest exits without compiling:
about 110ms against 550ms on a 400-record project. Under git it asks git — the object ids of
the committed ledger, plus the content of anything `status` calls dirty, untracked or
ignored — because a repository already has an authority on what changed, and one that scales:
at 4000 records that answer costs 20ms where reading the ledger costs 140ms. Without git it
reads the ledger and hashes it, which at a few hundred records is the same speed. Content
either way, never mtime: two edits inside one filesystem tick, a restored backup or a
`git checkout` that rewrites a file to the same size all leave a digest describing a ledger
that no longer exists, and memory that is confidently stale is worse than memory that is
slow. Writes recompile as they land, so the work happens where it belongs — at the end of a
session that wrote something, not at the start of every session that did not.
`startup --force` rebuilds regardless.

Digest budgets and scoring constants are deliberately not documented here: they are tuning
knobs, and their single authoritative home is the commented header of
`scripts/internal/zamm-compile.sh`. The digest explains its own entry format at the top of
every compile.

## Finding things

The digest is the read, not a search. When it is silent and the agent needs what was
written down, there is the full rendering beside it (`.compiled/zamm-digest-full.md`, the
same ledger with nothing left out) — and under that, plain files: `grep -r <term>
zamm-memory/` finds dormant and
unlisted records too, and any markdown search the project happens to have works as well
(QMD is one example; none is required, and none ever writes a record).

What no search can do is judge standing. It ranks by resemblance, so a superseded record, a
retired chain or an archived plan scores exactly like the one in force. That is what `whatis`
is for: hand it whatever the search returned and it says what the thing is and whether it
still counts.

```sh
bash <zamm-skill>/scripts/zamm-run.sh whatis --brief zamm-memory/knowledge/2026/2026-01-05-tier-motion-22222.md
```

```text
zamm-memory/knowledge/2026/2026-01-05-tier-motion-22222.md
  what:      knowledge record (memory)
  standing:  superseded by 2026-02-05-tier-motion-22223 - history; cite the live head below, not this
  chain (oldest first):
    2026-01-05-tier-motion-22222  [superseded memory]  Old rule about tier motion.  <- this
    2026-02-05-tier-motion-22223  [superseded memory]  Newer rule about tier motion.
    2026-03-05-tier-motion-22224  [live memory]  Current rule about tier motion.
  live head: 2026-03-05-tier-motion-22224  Current rule about tier motion.
```

It takes paths in any form, `qmd://` URLs with a line suffix, record ids, plan ids and bare
slugs, across every tree, live and archived. A dead hit is not dug up: the answer is the
chain and the live head, with the head's body unless `--brief`. Unlisted and dormant records
are still true; superseded, retired, erased and archived ones are not. Plans report their
Status, and an active plan's Status outranks any record.

The path carries the same signal for free. `memory archive` moves superseded and retired
records into `zamm-memory/archive/` as soon as they die, and the digest header counts what
is archive-ready. An archived record stays a lineage node, so the live head keeps every
ancestor vote and the digest is verified byte-identical after the move. `knowledge/` is what
is, `archive/` is what was: grep the first for the current state, and give a search tool the
same split, one index with the archive excluded and, if history questions matter, a second
one rooted at the archive.

## What the human does

ZAMM runs mostly agent-side. The human:

- approves plan closure (`Review -> Done`); agents cannot self-approve,
- approves one-time operations before they run: project scaffolding, initialization scans,
  protocol migrations, and any git-history erasure,
- marks the backlog ideas worth doing next, and occasionally answers "is this still true?"
  when the agent flags suspected-stale knowledge,
- reads the journal's period views when asked what happened, and lets the agent settle
  triage rather than treating it as a session ritual,
- sees every ledger write in ordinary code review: records are plain markdown files in git.

## What gets added to a project

| Path | Purpose | Committed? |
| --- | --- | --- |
| `zamm-memory/knowledge/<YYYY>/` | immutable ledger records | yes |
| `zamm-memory/backlog/<YYYY>/` | immutable idea records (the backlog) | yes |
| `zamm-memory/journal/<YYYY>/` | immutable episode records, elevations and watermarks (the journal) | yes |
| `zamm-memory/active/plans/`, `zamm-memory/archive/plans/` | plan contexts | yes |
| `zamm-memory/VERSION` | installed protocol version (`3`) | yes |
| `zamm-memory/.compiled/` | generated digest, backlog lens and journal lens | no (gitignored) |
| `AGENTS.md` managed block | the always-on router (the full protocol stays in the skill, loaded on demand) | yes |
| `.cursor/rules/zamm.mdc` | the same router, for Cursor | when used |
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
  (each tree's `-maintenance.md` has its Erasure section).
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
startup              session start: recompile, then READ the digest it names
scaffold             install ZAMM here, or refresh the rendered surfaces
status               health overview: ledger, backlog, journal, plans, drift
check                validate everything (memory + backlog + journal + plans)
whatis <ref>...      what a path, qmd:// URL, id or slug is, and whether it
                     still counts: standing, supersede chain, the live head
help [<topic>]       this text, or help for one command

memory list          index of live records, slug first
memory show <slug>   one record in full
memory check         validate the ledger
memory create <slug> write a record; body on stdin (or --edit)
memory publish <slug>
                     validate a hand-written <id>.md.draft and land it
memory drafts        list hand-written drafts not yet published
memory discard <slug>
                     show and delete an unpublished draft
memory archive       move superseded and retired records into archive/

backlog add '<sentence>'
                     capture an idea; one sentence is enough
backlog list [--scope <tag>]
                     the whole live backlog, hot to cold (--all: dormant
                     too; --scope filters, e.g. domain/lobby)
backlog show <slug>  one idea in full
backlog mark <slug>  select an idea for implementation (pushed into the digest)
backlog unmark <slug>
                     deselect a marked idea
backlog promote <slug> ['<plan title>']
                     turn an idea into a plan and retire it
backlog check        validate the backlog ledger

journal add '<sentence>'
                     record an episode; one sentence is enough
journal list [--all] [--scope <tag>] [--cue <slug>] [--since <date>]
                     the timeline lens, newest first (--all: dormant too;
                     filters print a row listing)
journal show <slug>  one record in full
journal search <predicates> [--text <pattern>] [--files]
                     structured query: --class --scope --cue --kind
                     --covers --agent --user --axis --since --until
journal stats [--axis <name>] [<predicates>]
                     coverage-honest aggregates for the human
journal export [<predicates>]
                     the versioned TSV seam for applications
journal digest <YYYY[-MM]> [--detail ...] [--stats ...] [--elevations ...]
                     the compiled period view (never stored)
journal elevate <kind> <YYYY[-MM]>
                     summarize a completed period; body on stdin
journal review [--headlines] [--cue <slug>] [--scope <tag>] [--period <p>] [--pass <kind>]
                     read what triage has not covered yet
journal settle [--through <date>] [--pass <kind>]
                     claim triage coverage with a watermark record
journal check        validate the journal ledger

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

- The spine of the operating contract: `<zamm-skill>/references/protocol.md`
  (session start and end, the boundary test between the four trees, the rules they share),
  loaded on demand; the scaffold renders only the always-on router
  (`protocol-router.template.md`) into each project's runtime files
- Agent entry point and dispatcher: `SKILL.md`
- Each tree in layers an agent loads one at a time: an index (`<zamm-skill>/references/memory.md`,
  `backlog.md`, `plans.md`, `journal.md`) over `<tree>-reading.md`, `<tree>-writing.md` (which
  opens with who reads what you write) and `<tree>-maintenance.md`
- Plan template: `<zamm-skill>/references/templates/plan.template.md`
- Memory record template: `<zamm-skill>/references/templates/memory-record.template.md`
- Existing project initialization: `<zamm-skill>/references/initialization/existing-project.md`
- Major-version migrations: `<zamm-skill>/references/migrations/`
- Design decisions in force, and what each one costs: `DESIGN.md`
- Changelog and change map vs. v2: `DELTAS.md` (decisions as they were taken — some were later reversed; it is history, not current behaviour)

(`<zamm-skill>` means your installed skill directory, for example `~/.agents/skills/zamm`.)
