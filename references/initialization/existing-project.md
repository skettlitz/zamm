# Existing Project Initialization

Use this guide only when the human explicitly approves a comprehensive ZAMM initialization run, or when the compiled digest reports no live memory records and the human accepts the initialization prompt.

Initialization is a broad evidence-gathering pass that seeds the knowledge ledger. It is separate from normal session start and should not run automatically.

## Trigger

The compiled digest is the initialization signal:

- If `zamm-memory/.compiled/memory.md` reports zero live memory records, active memory is not initialized.
- Ask the human whether to run this initialization guide.
- Do not create placeholder records to silence the prompt.
- If the human declines, continue with the requested work and leave the ledger empty.

## Inputs

Read the project broadly enough to identify durable operating facts:

- README and project documentation.
- Package, build, test, lint, formatting, and dependency configuration.
- CI, deployment, release, container, and infrastructure files.
- Source layout and top-level module boundaries.
- Tests and test helper conventions.
- Local agent/rule/instruction files.
- Architecture, API, schema, migration, or generated-code ownership files.

Avoid dependency directories, generated output, binary assets, archives, large data files, and secrets unless the project explicitly uses them as source-of-truth files.

Read `<zamm-skill>/references/eternal/knowledge.md` as a rubric only. Do not copy eternal entries directly into the ledger.

## Proposal First

Before writing records, produce a seed proposal for human review unless the human explicitly asked to initialize and apply in one pass.

For each candidate, include:

- proposed `importance` and `durability` (see rubric below)
- proposed scope tags (1-3 areas, primary first; see area set below)
- proposed statement (the digest-block headline)
- source path evidence
- confidence
- open questions or suspected drift

Rejected candidates should be listed briefly when they are plausible but not worth active memory.

## Seeding Rules

The top-level scope areas are fixed by the protocol — the same 8 knowledge-kind areas in every project, so no per-project negotiation is needed:

- `domain` — purpose, users, requirements, external constraints
  - Example: "this CLI is for solo maintainers, not multi-tenant SaaS"
- `contracts` — boundary shapes others depend on: schemas, formats, protocols, CLI/API surfaces, invariants. Test vs `conventions`: if violated, does interop/data break, or does a reviewer frown?
  - Example: "record ID is the filename stem; never rename under knowledge/"
- `conventions` — self-imposed rules: naming, style, layout, wording
  - Example: "plan directories use date-first slugs `YYYY-MM-DD-...`"
- `internals` — how shipped things work and why they have that shape
  - Example: "digest ranking = importance × durability-decay + votes"
- `quality` — how correctness is verified: test strategy, checks, known failure modes of the artifact. Test vs `internals`: describing behavior vs describing how behavior is proven.
  - Example: "run `zamm-run.sh memory check` before committing ledger writes"
- `tooling` — dev-time things used, not shipped: commands, environment, platform quirks. Test vs `internals`: things you use vs things you ship.
  - Example: "macOS awk is not gawk; keep compile scripts POSIX"
- `ops` — ship/run-time mechanics: release, versioning, deploy, migration. Test vs `tooling`: matters while developing vs while shipping/running.
  - Example: "write `zamm-memory/VERSION` only after migration completes"
- `meta` — agent/process failure patterns, corrections, collaboration norms. Distinct from `quality`, which covers failure modes of the artifact, not of the process.
  - Example: "prefer the precompiled digest at cold start; recompile after ledger edits"
- `other` — catch-all when none of the eight fit cleanly (sole tag, no subpath). Prefer the closest real area; park here only temporarily and refile via supersession (`--check` fails above 5 live `other` records).

Every scope is 1-3 comma-separated tags, primary first (`<area>[/<subpath>]`, secondary tags bare). A record straddling a boundary takes both areas instead of forcing a choice (example: a CLI flag that is both an interop surface and a naming rule → `contracts/cli-flags, conventions`). A record that truly fits nowhere takes `other` alone and gets refiled later. Tag only what the record genuinely serves — extra tags cost ranking. Finer separation belongs in subpaths (`internals/archive-script`), never in invented areas.

Create one ledger record per accepted candidate with
`bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area/subpath>[, <area2>]' --importance <i> --durability <d> <slug>`, then fill the body (digest block: headline first paragraph + optional elaboration; optional `## Background`).

Rating rubric (these two fields are the whole ranking system):

- `importance: guardrail` — violating the statement breaks the project or wastes hours; should shape almost every future agent action. Expect 1-5 per project; more devalues the marker.
- `importance: useful` — durable constraints and stable repeated patterns: framework choices, source-of-truth boundaries, test strategy, layout/naming conventions, common commands (most seeds; 10-30 records).
- `importance: minor` — uncertain findings, suspected drift, near-term hints, verification notes (0-10 records).
- `durability`: how long the statement will stay true — `days`/`weeks` for observations and hints, `months` for conventions that churn, `years` for architectural constraints, `permanent` for invariants. Ranking decays over this horizon; fully decayed records go dormant automatically, so honest short ratings are how initialization notes clean themselves up.

A completed initialization should normally create at least one guardrail record. Initialization seed records are exempt from the plan-closure votes flow because there is no plan context; capture the seed rationale in the initialization record instead.

After seeding, run `bash <zamm-skill>/scripts/zamm-run.sh memory digest` and confirm the digest reflects the seeds.

## Initialization Record

After applying seeds, write one record under:

`zamm-memory/archive/knowledge/initializations/YYYY-MM-DD-HHMM-initialization.md`

The record should include:

- trigger and approver
- source inventory
- applied record IDs and statements
- rationale for seeded records
- rejected candidates
- unresolved questions
- commands/checks used during initialization

This keeps the digest lean while preserving auditability.
