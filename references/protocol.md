## Script Path Resolution

The `zamm` skill directory is `<zamm-skill>`. Every `<zamm-skill>` token below stands for that directory (scripts live in its `scripts/` subdirectory); expand it when running the commands.

Commands are reached through one entrypoint, `zamm-run.sh`, which finds the project root itself: the nearest ancestor directory holding `zamm-memory/`, else the git top level. Pass `--project-root <path>` only when the working directory is genuinely outside the target project.

## Session Start (MUST - do this before primary task work)

1. ONE command, whose output is the read: `bash <zamm-skill>/scripts/zamm-run.sh memory digest`. It recompiles and prints the digest; opening `zamm-memory/.compiled/memory.md` afterwards ingests the same text twice. Do not read it again this session unless records were written or merged since — your own `memory create` already recompiled. Its anatomy is in `<zamm-skill>/references/memory-reading.md`; the rules that must not wait:
   - A leading `!` is a guardrail — do not violate it. `+bg` means a Background section exists — open the record before a high-impact action. Records are advisory: verify before acting on one at high impact.
   - A `Needs reconciliation` section: reconcile this session (`## Reconciliation (MUST)` below).
   - No memory records at all: tell the human active memory is not initialized and ask whether to run `<zamm-skill>/references/initialization/existing-project.md`. Never create placeholder records to silence the prompt.
   - The tail carries `## Plans`, a `Backlog:` line and, only when journal digestion is due, a `Journal:` line — a nudge, never an obligation.
   - Never edit the digest; the record files are the only source of truth.
2. Identify the active plan from the digest's `## Plans` tail (status, progress, title; ranked Review, Implementing, Draft). A recently-archived list follows: check it before treating a referenced plan directory as missing after a pull.
3. If no plan matches the request AND the request warrants one — multi-step work, changes that persist beyond the session, research artifacts or a decision worth revisiting, work spanning sessions — create it (`plan create '<title>'`; `<zamm-skill>/references/plans-writing.md`) and recompile. Answering a question, explaining code, a lookup, a trivial edit or running a command does not warrant a plan; plan-less sessions are normal, and distillation still applies to them. When genuinely unsure, ask.
4. Prefer one active implementing plan at a time; if unclear, auto-pick by best match and ask the human only when ambiguity remains.

## Four trees, one boundary test

Everything an agent keeps goes into one of four trees under `zamm-memory/`, all immutable schema-3 records except plans, all written through the one entrypoint. The test that decides:

- asserts a durable reusable claim → KNOWLEDGE (`knowledge/`; ranked into the session digest)
- implies future action, no commitment → BACKLOG (`backlog/`; a pulled lens)
- commits to doing something → PLAN (`active/plans/`; mutable, with transitions and human-approved closure)
- happened, noteworthy, and neither → JOURNAL (`journal/`; a pulled timeline)

Each tree has an index and three layers under `<zamm-skill>/references/`; load the layer for what you are about to do, and only that:

| tree | index | reading | writing | maintenance |
| --- | --- | --- | --- | --- |
| knowledge | `memory.md` | `memory-reading.md` | `memory-writing.md` | `memory-maintenance.md` (supersede, votes, reconciliation, erasure, archive) |
| backlog | `backlog.md` | `backlog-reading.md` | `backlog-writing.md` | `backlog-maintenance.md` (decay, mark, promote) |
| plans | `plans.md` | `plans-reading.md` | `plans-writing.md` (incl. IDE-written plans) | `plans-maintenance.md` (transitions, close-out, archive) |
| journal | `journal.md` | `journal-reading.md` (incl. `journal digest`, the compiled summary) | `journal-writing.md` | `journal-maintenance.md` (review/settle, elevate: the stored claims) |

Each writing layer opens with who reads the record and at what zoom, because that is what decides how to write it. A file that is not about the action you are taking costs context and answers nothing.

## Rules every tree shares (MUST)

- One file is one immutable record; the filename is its id. Never edit, rename, move or delete a record once written — correct it with a new record carrying `supersedes:`, retire it with a tombstone. The add-only layout is what keeps merges conflict-free. Sole exceptions: erasure of a secret, written into the tree the record lives in (that tree's `-maintenance.md`), and the archive commands, which move whole retired chains.
- Write through the entrypoint (`memory create`, `backlog add`, `journal add`, `plan create`): each validates first and lands the record atomically, or prints why not and writes nothing.
- Never store secrets, tokens or credentials: records are effectively permanent. Never quote the human verbatim: paraphrase the substance and describe the emotion where the register matters. Records are team-visible; do not immortalize heat-of-the-moment phrasing or characterize anyone's performance or mood.
- Brevity is part of the contract. A digest block is reread at every session start by every agent; a Background section by whoever opens the record. Limits are ceilings, not space to fill: a one-sentence record that says the thing is complete, and a paragraph that could have been a sentence is a defect. Every word saved saves context and money for every reader after you.
- Records are advisory, never authoritative. Code, tests and contracts outrank them; a record that conflicts with them is drift — verify, then supersede it with a `suspected drift` record.
- Prefer correction over accretion: read the tree before adding (`memory list --all --scope <area>` — without `--all` the list is only what the digest selected; `backlog list`; `journal list`) and supersede, merge or vote instead of duplicating.
- Everything about a record lives in its own tree — votes, tombstones, erasures. No cross-tree `supersedes:` or vote edges: an idea that became a fact is a knowledge record plus a backlog tombstone.

## Distillation (MUST)

Write a knowledge record when a cue fires (compact cues; full semantics in `<zamm-skill>/references/distillation-triggers.md`, the record in `memory-writing.md`):
- the human says remember this — same turn, no damping
- the human corrects you or states a standing rule, in any tone — else it evaporates at session end
- the human shows strong emotion, complaint or praise, with substance behind it — record the substance, short-lived, never the words
- the same failure hits twice — cause + workaround now; still stuck, a short-lived dead-end record
- research yields a conclusion whose details live in a pointable file — conclusion + pointer

Do not write: free-floating values with nowhere to recheck them; external changes that broke nothing; churn during primary work — batch ordinary learnings into plan close-out. Rate `importance` and `durability` honestly; they are the whole ranking. The cues are deliberately coarse: accept near-misses rather than paying for precision every session.

## Reconciliation (MUST)

After a merge or pull, two branches may have superseded the same record independently; both stay live and the digest lists them under `Needs reconciliation`, each head keeping its full block marked `~`. In the session the digest shows it: when ground truth is determinable from code, history, tests or context, write ONE record that merges or picks, with `supersedes:` listing ALL competing heads. When it is not, leave both heads live and tell the human what evidence would settle it — never fabricate a merged claim to clear the warning, never edit or delete the heads, never prefer one by timestamp. The full procedure is in `<zamm-skill>/references/memory-maintenance.md`.

## Session End (MUST)

1. Apply transition bookkeeping to touched plans per `<zamm-skill>/references/plans-maintenance.md`, and keep their `Last updated:` current.
2. Ensure durable learnings were distilled into knowledge records and stale touched records superseded — plan-less sessions included.
3. If the digest showed `Needs reconciliation` and it is unresolved, resolve it now.
4. If plans are terminal or the human asks for cleanup, run `bash <zamm-skill>/scripts/zamm-run.sh plan archive`.

## Precedence (when sources conflict)

1. Explicit current human instruction
2. Code, tests, contracts (executable truth)
3. Active plan file and terminal status semantics
4. Live ledger records (as compiled in the digest; a record superseding another always outranks it)
5. Eternal initialization knowledge and archive/historical notes

## Key Constraints

- The digest (`zamm-memory/.compiled/`) is generated, gitignored and disposable: never commit it, never edit it, never treat it as the source of truth.
- The protocol version lives in `zamm-memory/VERSION`; update it only after completing a migration. Major-version migration details belong in `<zamm-skill>/references/migrations/`, not in ledger records.
- Eternal doctrine belongs in `<zamm-skill>/references/eternal/knowledge.md`, not in the ledger.
- An empty ledger means active memory has not been initialized: ask before running initialization, and never add placeholder records.
- What the toolchain guarantees, and what it deliberately does not, is `<zamm-skill>/references/invariants.md`: read it before reporting a defect or adding a safeguard.
