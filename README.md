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

#### A. Codex — Repo-local (recommended)

Put ZAMM inside the repo so any collaborator who clones it gets the skill
automatically:

```bash
cd /path/to/your/project
mkdir -p .agents/skills
cp -r /path/to/zamm .agents/skills/zamm
```

Commit `.agents/skills/zamm/` so collaborators pick it up automatically.

If you keep ZAMM in this repo but want to *use* it in another repo, symlink it:

```bash
ln -s /path/to/zamm /path/to/other-repo/.agents/skills/zamm
```

#### B. Codex — User-global

Install once per user profile so ZAMM is available in any repo:

```bash
mkdir -p ~/.agents/skills
cp -r /path/to/zamm ~/.agents/skills/zamm
# or symlink instead of copy
```

#### C. Codex — Admin / shared machine (optional)

For managed dev boxes or containers where you want a standard skill set for
every user:

```bash
sudo mkdir -p /etc/codex/skills
sudo cp -r /path/to/zamm /etc/codex/skills/zamm
```

#### D. Cursor — personal (all projects)

```bash
mkdir -p ~/.cursor/skills
cp -r /path/to/zamm ~/.cursor/skills/zamm
```

The skill is available in every Cursor project after restart.

#### E. Cursor — project-level (shared via repo)

```bash
cd /path/to/your/project
mkdir -p .cursor/skills
cp -r /path/to/zamm .cursor/skills/zamm
```

Commit `.cursor/skills/zamm/` so collaborators pick it up automatically.

#### Legacy note

If you previously used `${CODEX_HOME:-$HOME/.codex}/skills` in older Codex
setups, that path may still work as a backward-compatibility fallback, but it is
no longer the primary discovery path. Prefer `.agents/skills/` (repo or user
scope) going forward.

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
cp -r . ~/.agents/skills/zamm   # or whichever target from Step 2
```

If you downloaded a zip, replace the folder with the new version.

## Read Next

- Full operating protocol: `SKILL.md`
- Full design spec: `references/zamm-spec.md`
- Agent runtime template: `references/AGENTS.md.template`
- Cursor rule template: `references/zamm-rule.mdc.template`
