## ZAMM router (always on)

This project runs ZAMM v3, an append-only ledger memory for agents: immutable records under `zamm-memory/{knowledge,backlog,journal}/`, plans under `zamm-memory/active/plans/`, and a generated digest that is never edited.

The `zamm` skill directory is `<zamm-skill>`; every `<zamm-skill>` token below stands for it. Commands go through one entrypoint that finds the project root itself.

**Session start (MUST):** once per session, run

    bash <zamm-skill>/scripts/zamm-run.sh memory digest

and read what it prints: that output is the whole read. Rerun only after records are written or merged. A leading `!` marks a guardrail — do not violate it. Records are advisory: verify before a high-impact action. A `Needs reconciliation` section must be resolved this session (full protocol).

**Memory (ZAMM owns it):** when something is worth remembering — a correction, a standing rule, a hard-won result — write a record:

    bash <zamm-skill>/scripts/zamm-run.sh memory create --scope '<area>' <topic-slug> <<'EOF'
    <one sentence that says it; more only where a reader needs it>
    EOF

One step: it validates the record and lands it, or prints why not. Never edit or delete a written record — correct it with a new one carrying `supersedes:`. No secrets, ever; paraphrase the human, never quote them. The digest is reread every session, so say it once, in as few words as it takes.

**Plans (ZAMM owns them):** work that spans sessions runs in a plan directory — `plan create '<title>'`, `plan list`, `plan check`, `plan archive`. Status flow Draft -> Implementing -> Review -> Done/Abandoned; close-out needs learnings, telemetry and a votes record (full protocol).

**Backlog (ideas; latent work):** an idea worth keeping but not starting goes into the backlog, never into a Draft plan: `backlog add 'One sentence.'` (depth on stdin; `--scope area/subpath` when the topic is known). Read `backlog list` first and supersede or vote instead of duplicating. Ideas fade on their own; `backlog mark` pushes one into the digest, `backlog promote` turns it into a plan.

**Journal (episodes; backward-looking):** something that happened and is worth a trace but implies no action and asserts no durable fact — a side quest, an outage, a considered non-action — is `journal add 'One sentence.'`, never a short-lived knowledge record. Cue-driven, never a session-end ritual.

**Health:** `status` for an overview; `check` validates every tree.

**Read the layer for what you are about to do** (all under `<zamm-skill>/references/`, each opening with who will read what you write): a record → `memory-writing.md`; reconciliation, votes, erasure → `memory-maintenance.md`; an idea → `backlog-writing.md`; marking or promoting → `backlog-maintenance.md`; a plan, or an IDE-written plan file → `plans-writing.md`; a status change, close-out or archive → `plans-maintenance.md`; an episode → `journal-writing.md`; a question about what happened, or a summary of a period → `journal-reading.md` (`journal digest`, a read); a `Journal:` line in the digest, or storing a summary → `journal-maintenance.md`. The spine, `<zamm-skill>/references/protocol.md`, holds session start and end, the boundary test between the four trees and the rules they share: load it for an empty ledger, session end, or anything the router does not answer. The router is a map, not the manual.
