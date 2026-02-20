# Z-Agents Memory Mill (ZAMM)

ZAMM is a bounded memory system for agentic software work. It provides a framework for plan execution and learnings distillation.

Learnings from implementation are distilled into **WEEKLY -> MONTHLY -> EVERGREEN** knowledge tiers with hard limits to keep context compact.

Canonical skill name/folder is `zamm`.

## Project Status

Development and testing iterations. The structure is still evolving and tested on internal projects.

## Current Structure (Plan-Only Model)

`<zamm-skill>` means your installed skill directory (for example `~/.agents/skills/zamm` or `.agents/skills/zamm`).

Canonical files in this skill:

- `<zamm-skill>/SKILL.md`: skill definition.
- `<zamm-skill>/scripts/zamm-scaffold.sh`: creates/refreshes scaffold-managed runtime files.
- `<zamm-skill>/scripts/zamm-archive.sh`: archives terminal plan directories.
- `<zamm-skill>/scripts/zamm-status.sh`: snapshots active plan statuses by bucket.
- `<zamm-skill>/references/scaffold/`: scaffold-consumed canonical files.
  - `agents-header.template.md`
  - `rule-header.mdc`
  - `protocol-body.template.md`
  - scaffold seed templates (`knowledge-*`, `cursorignore`)
- `<zamm-skill>/references/templates/plan-template.plan.template.md`: agent-authored plan template.

Runtime surfaces `AGENTS.md` and `zamm.mdc` are composed directly by `zamm-scaffold.sh` from:
- `<zamm-skill>/references/scaffold/agents-header.template.md`
- `<zamm-skill>/references/scaffold/rule-header.mdc`
- `<zamm-skill>/references/scaffold/protocol-body.template.md`

No separate render script is required.
During scaffold composition, runtime files resolve these shorthands to install-aware paths:
- `<zamm-skill>` -> `<project-root>...`, `~...`, or absolute fallback.

## Scaffold Output (Fresh Project)

Running `bash <zamm-skill>/scripts/zamm-scaffold.sh --project-root <repo-root>` produces:

```text
<repo-root>/
  AGENTS.md
  .cursor/rules/zamm.mdc
  .cursorignore
  zamm-memory/
    active/
      knowledge/
        EVERGREEN.md
        MONTHLY.md
        WEEKLY.md
      plans/
    archive/
      plans/
```

Current active model:

- Active plans live in `zamm-memory/active/plans/<plan-dir>/`.
- Each plan directory has one main `.plan.md` and optional `workdir/`.
- Terminal plan directories archive to `zamm-memory/archive/plans/<plan-dir>/`.
- Status snapshot helper: `bash <zamm-skill>/scripts/zamm-status.sh [--project-root <repo-root>]`.

Knowledge motion model (symbolic tiers, not calendar-bound):

- WEEKLY cap window: 30..37 cards (reset target: 30)
- MONTHLY cap window: 12..16 cards (reset target: 12)
- EVERGREEN cap window: 10..14 cards (reset target: 10)
- Plan learnings are appended into WEEKLY first.
- Consolidation is triggered when tiers are read and counted (Session Start) or when append reaches upper bounds (37/16/14).
- Consolidation pass order is WEEKLY -> MONTHLY -> EVERGREEN; repeat passes until all tiers are within tolerance windows.

Legacy paths are not part of current active workflow:

- `zamm-memory/active/workstreams/`
- `zamm-memory/active/indexes/`

## Legacy Migration Note

If an older repo still has active workstream/index trees, move them out of `active` and preserve them in archive to avoid operator confusion. Keep active plans in `zamm-memory/active/plans/`.

## Installation

Get the source first, then copy it to the right location for your environment.

### Step 1 — Get the Source

Clone from GitHub:

```bash
git clone https://github.com/skettlitz/zamm.git
```

Or download and unzip, then rename `zamm-main` to `zamm`.

### Step 2 — Install for Your Environment

Choose one target.

#### A. Codex — Repo-local (recommended)

```bash
cd /path/to/your/project
mkdir -p .agents/skills
cp -r /path/to/zamm .agents/skills/zamm
```

#### B. Codex — User-global

```bash
mkdir -p ~/.agents/skills
cp -r /path/to/zamm ~/.agents/skills/zamm
```

#### C. Codex — Admin / shared machine (optional)

```bash
sudo mkdir -p /etc/codex/skills
sudo cp -r /path/to/zamm /etc/codex/skills/zamm
```

#### D. Cursor — personal (all projects)

```bash
mkdir -p ~/.cursor/skills
cp -r /path/to/zamm ~/.cursor/skills/zamm
```

#### E. Cursor — project-level (shared via repo)

```bash
cd /path/to/your/project
mkdir -p .cursor/skills
cp -r /path/to/zamm .cursor/skills/zamm
```

### Step 3 — Verify

Open a project in Cursor (or start a Codex session) and ask the agent:

> Scaffold ZAMM in this project.

The agent runs `zamm-scaffold.sh`, creating the plan-only `zamm-memory/` tree, `AGENTS.md`, `.cursor/rules/zamm.mdc`, and `.cursorignore`.

## Keeping Up to Date

If you cloned the repo, pull and re-copy:

```bash
cd /path/to/zamm
git pull
cp -r . ~/.agents/skills/zamm
```

If you downloaded a zip, replace the folder with the new version.

## Read Next

- Full operating protocol: `SKILL.md`
- Shared protocol source: `<zamm-skill>/references/scaffold/protocol-body.template.md`
- Plan template: `<zamm-skill>/references/templates/plan-template.plan.template.md`


# Appendix

## Animal tiers for complexity estimation

`Complexity-forecast: ant|gecko|raccoon|capybara|badger|octopus|manatee|shark|godzilla`

| Level | Animal       | The character it signals | Typical cues                                                     |
| ----- | ------------ | ------------------------ | ---------------------------------------------------------------- |
| 1     | **ant**      | tiny + obvious           | one tiny surface, no debate, trivial validation                  |
| 2     | **gecko**    | small + quick            | small change, minimal side effects, easy to revert               |
| 3     | **raccoon**  | small but sneaky         | edge cases, odd environments, “it depends” lurking               |
| 4     | **capybara** | medium + chill           | normal feature slice, known path, steady work                    |
| 5     | **badger**   | medium + stubborn        | tricky testing, awkward constraints, needs persistence           |
| 6     | **octopus**  | many tentacles           | multiple components/dependencies, integration work, coordination |
| 7     | **manatee**  | big but gentle           | lots of work, **low drama**: predictable, repeatable steps       |
| 8     | **shark**    | big + toothy             | high consequence / blast radius, rollout/rollback matters        |
| 9     | **godzilla** | city-level               | initiative-sized, unknown unknowns, must be sliced + discovery   |
