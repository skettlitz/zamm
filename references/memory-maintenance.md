# Memory — maintenance

Read this before superseding, merging, retiring or voting on records, before
reconciling after a merge, before erasing, and before archiving. Reading
needs none of it (`memory-reading.md`); a first record needs
`memory-writing.md`.

## What the toolchain guarantees

`references/invariants.md` states it: every output is a truthful reading of
some state the ledger actually had, every failure is repairable by
rerunning, and bytes are never destroyed. Staleness, a digest one record
behind, and a half-finished archive are normal operation — rerun the
command. A hostile process running as your own user is out of scope. Read
it before reporting a defect or adding a safeguard.

## How ranking works

There are no tiers, counters or consolidation rituals: the compiler derives
liveness, vote totals, ranking and supersede chains from the records at read
time. Score = author-rated importance decayed over the author-rated
durability (its half-life), corrected by votes; fully decayed records go
dormant (counted, unlisted, greppable). Two capped layers, ~75 Digest blocks
and ~150 Headlines; digest seats are balanced across top-level areas by a
per-area penalty (a weighted compromise, not a quota): a record with several
area tags competes through its least-crowded area but pays a small score
cost per extra tag, so precise tagging beats tag-sprawl. Live guardrails
never go dormant and are admitted before the cap: `!` is a safety contract
that leaves the digest only through supersession or a tombstone. Everything
else in the digest is uncapped — competing heads, every active plan, the
recently-archived tail — so keep guardrails rare (`memory check` warns past
15) and resolve conflicts instead of accumulating them.

## Correcting records

Never edit, rename, move or delete a record file (sole exceptions: erasure
below, and `memory archive`). Every correction is a new record:

- Update: a new record with `supersedes: <old-id>`. The old file stays; the
  compiler hides it and links the chain.
- Merge duplicates: ONE record whose body unifies the statements and whose
  `supersedes:` lists every merged id.
- Retire: a tombstone — `memory create --type tombstone --supersedes <id>
  <slug>`, body a one-line reason.
- Suspected stale but unverified: supersede with a `suspected drift` record
  plus a note on how to verify.
- Refresh a still-true record near its horizon: supersede with re-rated
  importance and durability.
- An idea that turned out to be a fact: a knowledge record here plus a
  backlog tombstone pointing at it — never a cross-tree supersede.

## Votes

Votes are records, never edited counters: `memory create --type votes
--plan <plan-dir> --up <ids> --down <ids> <slug>` with an empty body — one
batch per plan close-out, skipped only when both lists are empty. They
attach to the exact record voted on and aggregate over its ancestor chain.
To correct a vote, supersede the votes record with a corrected one (or
tombstone it); never cast an opposite vote to cancel. A votes record may
only supersede another votes record.

## Reconciliation (MUST, in the session the digest shows it)

After a merge or pull, two branches may have superseded the same record
independently. Both successors stay live (added files never conflict in
git); the digest lists the group under `Needs reconciliation`, and each head
keeps its full block in `## Digest` marked `~`, so nothing is hidden.

- When ground truth IS determinable — from code, git history, tests or
  context — write ONE record whose body merges the competing statements (or
  picks the correct one, saying why) and whose `supersedes:` lists ALL
  competing head ids.
- When it CANNOT be determined, leave the heads unmerged. Do not invent a
  merged claim to clear the warning: the ledger is append-only, so a
  fabricated union is permanent, while the `suspected drift` marker excusing
  it decays out of the digest long before the claim does. Tell the human the
  group is unresolved, say what evidence would settle it (a file to read, a
  test to run, a person to ask), and leave both heads live. The digest keeps
  surfacing the group; that is the intended steady state.
- "Keep every restriction from both heads" is a legitimate merge only when
  the claims are compatible and you can say so — not when they contradict,
  when one describes retired behavior, or when the union would block work
  that should be possible.
- Never resolve by editing or deleting the head files, and never prefer one
  by timestamp: timestamps across machines are display metadata, not
  causality.

## Erasure (exceptional)

Only for secrets or personal data committed by mistake. Each tree compiles
on its own, so the erasure record must live IN THE TREE OF THE RECORD IT
ERASES: an erasure written into `knowledge/` does nothing for a journal or
backlog record, and deleting the original afterwards leaves any returning
copy unprotected.

1. Write an erasure record naming the id, in that record's tree, body = why
   the content had to go:
   - knowledge: `memory create --type erasure --erases <id> <slug>`
   - backlog: `backlog add --type erasure --erases <id> <slug>`
   - journal: `journal add --type erasure --erases <id> <slug>`
   Compilers of that tree ignore the erased id from then on, including a
   stray copy that reappears from a merge or a restore.
2. Delete the record file.
3. Git history rewriting (`git filter-repo` or equivalent) is a separate,
   explicitly human-approved operation: ask, never assume.

An erased id stays a valid graph node: records superseding it remain valid
and keep their chain; it contributes no content, votes or durability; votes
pointing at it are dropped. Successors are never rewritten. Projects
predating this carry `zamm-memory/knowledge/shun.md`; the compiler refuses
to run while it exists — migrate each listed id to an erasure record, then
delete it.

## Archive

`memory archive` moves fully-retired chains to
`zamm-memory/archive/knowledge/`: only chains where nothing still affects
the digest — no live memory record and no live votes record, because votes
aggregate over the whole ancestor chain and a dead ancestor of a live head
is load-bearing. Archived records stay greppable and their ids resolvable;
the command verifies the digest is unchanged and rolls back otherwise.
Nothing else under `zamm-memory/knowledge/` is ever moved or renamed: the
add-only layout is what keeps merges conflict-free.
