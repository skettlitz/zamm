# Z-Agents Memory Mill (ZAMM)

ZAMM is a bounded memory system for agentic software work. It helps humans and
agents re-enter fast, keep parallel initiatives coordinated, and preserve
history without polluting day-to-day search.

Core model: **WEEKLY -> MONTHLY -> EVERGREEN** knowledge tiers with hard limits,
plus initiative-scoped work areas and explicit archive boundaries.

Canonical skill name/folder is `zamm` (from `SKILL.md` frontmatter `name`).

## Project Status

**Early testing.** The core protocol and scripts work, but expect rough edges,
breaking changes, and missing documentation. Feedback and bug reports are
welcome.

## What This Repo Contains

- `SKILL.md`: the skill definition and operating protocol.
- `scripts/`: scaffold + maintenance + reporting + packaging/self-test helpers.
- `references/zamm-spec.md`: full design spec.
- `references/AGENTS.md.template`: template for non-Cursor agent runtimes.
- `references/zamm-rule.mdc.template`: Cursor rule template.

## Installation

Get the source first, then copy it to the right location for your environment.

### Step 1 — Get the Source

**Clone from GitHub:**

```bash
git clone https://github.com/skettlitz/zamm.git
```

**Or download and unzip:**

Download the latest zip from the repository and unzip it. GitHub names the
folder `zamm-main` by default — rename it to `zamm`.

### Step 2 — Install for Your Environment

Choose **one** of the targets below (or combine them).

#### Cursor (personal — all projects)

```bash
mkdir -p ~/.cursor/skills
cp -r zamm ~/.cursor/skills/zamm
```

The skill is available in every Cursor project after restart.

#### Cursor (project-level — shared via repo)

```bash
cd /path/to/your/project
mkdir -p .cursor/skills
cp -r /path/to/zamm .cursor/skills/zamm
```

Commit `.cursor/skills/zamm/` so collaborators pick it up automatically.

#### Codex

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
cp -r zamm "${CODEX_HOME:-$HOME/.codex}/skills/zamm"
```

Restart Codex to pick up the new skill.

### Step 3 — Verify

Open a project in Cursor (or start a Codex session) and ask the agent:

> Scaffold ZAMM in this project.

The agent will run `scaffold.sh`, creating the `zamm-memory/` tree, `AGENTS.md`,
`.cursor/rules/zamm.mdc`, and `.cursorignore`. Everything after this point is
agent-driven — see `SKILL.md` for the full operating protocol.

## Keeping Up to Date

If you cloned the repo, pull the latest changes and re-copy:

```bash
cd /path/to/zamm
git pull
cp -r . ~/.cursor/skills/zamm   # or whichever target from Step 2
```

If you downloaded a zip, replace the folder with the new version.

## Read Next

- Full operating protocol: `SKILL.md`
- Full design spec: `references/zamm-spec.md`
- Agent runtime template: `references/AGENTS.md.template`
- Cursor rule template: `references/zamm-rule.mdc.template`
