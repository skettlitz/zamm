# Zippy Agentic Memory Mill (ZAMM)

ZAMM is a lightweight operating workflow for agentic software work.
It combines three things:
- task execution through plan directories,
- bounded memory distillation through **WEEKLY -> MONTHLY -> EVERGREEN** tiers,
- archive hygiene that moves finished plan contexts out of active memory.

In short: plan while doing, distill what lasts, archive the rest.

Canonical skill name/folder is `zamm`.

## Project Status

In **development and testing**; The structure is still evolving and tested on internal projects.

## Current Structure (Plan-Only Model)

`<zamm-skill>` means your installed skill directory (for example `~/.agents/skills/zamm` or `.agents/skills/zamm`).

Data is stored in `zamm-memory` in the project root with `active` and `archive` subdirectories.


## Knowledge motion model

- WEEKLY cap window: 30..37 cards
- MONTHLY cap window: 12..16 cards
- EVERGREEN cap window: 10..14 cards
- Plan learnings are collected during plan execution and appended into WEEKLY first.
- Consolidation is triggered when upper bounds are reached and then reduced to lower bounds.
- Distillation of valuable information via promotion into higher tier.
- Consolidation by demotion into lower tier or offloading into archive log.


## Installation

Clone from github

```bash
git clone https://github.com/skettlitz/zamm.git
```

Copy into skills subdirectory (e.g. `.cursor/skills` or `.agents/skills`). Ensure that the subdirectory is named `zamm` and contains `SKILL.md`.

The agent runs `zamm-scaffold.sh`, creating the plan-only `zamm-memory/` tree, `AGENTS.md`, `.cursor/rules/zamm.mdc`, and `.cursorignore`.

## Updating

Update `zamm` in skill directory, then run `zamm-scaffold.sh --overwrite-templates`.

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
