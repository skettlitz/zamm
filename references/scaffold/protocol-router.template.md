## ZAMM router (always on)

This project runs ZAMM v3, an append-only ledger memory for agents. Records live under `zamm-memory/knowledge/`, plans under `zamm-memory/active/plans/`; the compiled digest is generated — never edit it.

The `zamm` skill directory is `<zamm-skill>`; every `<zamm-skill>` token below stands for it. Commands go through one entrypoint that finds the project root itself.

**Session start (MUST):** compile and cold-read the context once per session — no version check first, the toolchain refuses and tells you the fix if the project needs one:

    bash <zamm-skill>/scripts/zamm-run.sh memory digest

Read `zamm-memory/.compiled/memory.md`. A leading `!` marks a guardrail — do not violate it. A `Needs reconciliation` section must be resolved this session (see full protocol).

**Memory (ZAMM owns it):** when something is worth remembering (a correction, a standing rule, a hard-won result), write a record:

    bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area>' <topic-slug> <<'EOF'
    <the record body>
    EOF

One step: it validates the record and recompiles the digest, and writes nothing at all if the record does not validate. Never edit or delete a written record — correct it with a new record carrying `supersedes:`.

**Plans (ZAMM owns them):** durable work runs in plan directories — `plan create '<title>'`, `plan list`, `plan check`, `plan archive` (same entrypoint). Status flow: Draft -> Implementing -> Review -> Done/Abandoned; close-out needs learnings, telemetry and a votes record (see full protocol).

**Health:** `status` for an overview; `check` validates memory and plans.

**Load the full protocol from `<zamm-skill>/references/scaffold/protocol-body.template.md` BEFORE:** initializing an empty ledger, reconciliation, plan transitions or close-out, record schema questions, erasure of secrets, or anything the router does not answer. The router is a map, not the manual.
