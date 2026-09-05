# Backlog — maintenance

## Decay is the only triage

Unmarked ideas sink to dormancy on their own: counted in the lens, listed by
`backlog list --all`, always greppable. Never strike through, edit or delete
idea records; fading is the sanctioned no-ceremony "no". Superseding or
upvoting an idea refreshes its clock.

## The marked lane

`backlog mark <slug|id>` supersedes the idea with `marked: <date>`: it
renders in the session digest (`## Marked backlog`, one headline with the
mark date) and stops decaying until promoted, unmarked (`backlog unmark`,
which writes an explicit `marked: no`) or tombstoned. A superseding record
that omits the key INHERITS the lane; the mark date is the day first
selected and survives re-ups. Decisions resolve by graph precedence: a
decision on a descendant overrides its ancestors', a tombstone ends the lane
for everything behind it, and only genuinely parallel forks fall back to a
deterministic id tiebreak — never timestamps. Keep the lane small: it is
pushed into every session, and the compiler nags past its soft cap.

## Promotion

`backlog promote <slug|id> ['<plan title>']` creates the plan (with
`Origin-idea:` provenance), retires the idea with a tombstone naming the
plan, and is safe to rerun after an interruption. From then on the work
lives in the plan (`plans-writing.md`).

## Retiring, and crossing trees

- Retire an idea explicitly with a tombstone: `backlog add --type tombstone
  --supersedes <id> <slug>`, body = the reason.
- An idea that turned out to be a FACT: a new knowledge record plus a
  backlog tombstone pointing at it — never a cross-tree supersede.
  Everything about an idea (votes, tombstones, erasures) lives in its own
  tree; there are no cross-tree edges.
- `backlog check` validates the tree.

## Erasure (exceptional)

A secret or personal data in an idea is erased IN THIS TREE — an erasure
record in `knowledge/` does nothing here: `backlog add --type erasure
--erases <id> <slug>`, body = why the content had to go; then delete the
record file. Git history rewriting is a separate, human-approved step. The
full rules are the memory ones (`memory-maintenance.md`), applied to this
tree.
