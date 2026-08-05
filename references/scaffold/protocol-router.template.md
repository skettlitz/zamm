## ZAMM router (always on)

This project runs ZAMM v3, an append-only ledger memory for agents. Records live under `zamm-memory/knowledge/`, plans under `zamm-memory/active/plans/`; the compiled digest is generated — never edit it.

The `zamm` skill directory is `<zamm-skill>`; every `<zamm-skill>` token below stands for it. Commands go through one entrypoint that finds the project root itself.

**Session start (MUST):** verify `zamm-memory/VERSION` reads `3` — anything else: ask before running a guide from `<zamm-skill>/references/migrations/`; never scaffold over it. Then compile and cold-read the context once per session:

    bash <zamm-skill>/scripts/zamm-run.sh memory digest

Read `zamm-memory/.compiled/memory.md`. A leading `!` marks a guardrail — do not violate it. A `Needs reconciliation` section must be resolved this session (see full protocol).

**Memory (ZAMM owns it):** when something is worth remembering (a correction, a standing rule, a hard-won result), write a record:

    bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area>' <topic-slug>
    # fill the printed .md.draft, then:
    bash <zamm-skill>/scripts/zamm-run.sh memory publish <topic-slug>

Publish validates the draft and recompiles the digest. Never edit or delete a published record — correct it with a new record carrying `supersedes:`.

**Plans (ZAMM owns them):** durable work runs in plan directories — `plan create '<title>'`, `plan list`, `plan check`, `plan archive` (same entrypoint). Status flow: Draft -> Implementing -> Review -> Done/Abandoned; close-out needs learnings, telemetry and a votes record (see full protocol).

**Health:** `status` for an overview; `check` validates memory and plans.

**Load the full protocol from `<zamm-skill>/references/scaffold/protocol-body.template.md` BEFORE:** initializing an empty ledger, reconciliation, plan transitions or close-out, record schema questions, erasure of secrets, or anything the router does not answer. The router is a map, not the manual.
