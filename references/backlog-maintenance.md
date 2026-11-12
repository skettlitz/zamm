# Backlog — maintenance

## Decay is the default triage

Ideas nobody touches sink to dormancy on their own: counted in the lens,
listed by `backlog list --all`, always greppable. Never strike through, edit
or delete idea records; fading is the sanctioned no-ceremony "no".
Superseding or upvoting an idea refreshes its clock. A lane decision (mark,
unmark, park, unpark) is also a supersede and restarts the clock, but earns
no durability credit: after it the idea fades like a fresh one.

Decay is slow (an untouched `useful`/`months` idea leaves the hot list after
about three months and goes dormant after about a year) and it cannot tell
"set aside on purpose" from "nobody cared". When the human decides an idea
does not fit now, park it.

## The parked lane

`backlog park <slug|id> '<reason>' [--until YYYY-MM-DD]` supersedes the idea
with `parked: <date>` and `park-reason: <reason>` (and `park-until:`): it
leaves the lens at once, collapsed to a count like the dormant tail, and
stops decaying. `backlog list --all` lists every parked idea with its date,
end date and reason. The reason is required and is one line (at most 200
characters): why it does not fit now, and ideally what would bring it back.
Paraphrase the human, as everywhere.

`--until` is the way back, and it is a timeout: on that day the park is over
by itself. Nothing is written and nothing asks; the idea is simply in the list
again, its line saying `(was parked <date>: <reason>)`, with its decay clock
restarted at the date, so it comes back hot and fades from there if nobody
acts on it. There is no default: without `--until` the idea stays out of sight
until someone unparks it, so give a date when there is one. To end a park early,
`backlog unpark`; to extend one, `backlog park` again with a later date.

The lane resolves exactly like the marked lane below: a superseding record
that omits the keys INHERITS the park, its reason and its date (sharpen a
parked idea without unparking it; the write says it stays parked); a
tombstone ends the lane for everything behind it. Parking again keeps the day
first parked; a reason or date you pass replaces the current one, and one you
omit is kept. An idea sits in one lane at a time: `backlog mark` on a parked
idea lifts the park, and `backlog park` on a marked idea withdraws the mark,
each in the same record. Parked ideas cost the session digest nothing.

Every lane decision is a whole copy of the idea, so a rewrite that should
also change the lane carries the decision itself rather than being followed
by a lane command: `backlog add --supersedes <id> '<sentence>' --unpark`, or
`--park --reason '<why>' [--until <date>]`, `--mark [--reason '<why now>']
[--until <date>]`, `--unmark`. `--park` and `--mark` also work on a new idea
(capture it already set aside). The rules are the lane commands' own.

## The marked lane

`backlog mark <slug|id>` supersedes the idea with `marked: <date>`: it
renders in the session digest (`## Marked backlog`, one headline with the
mark date) and stops decaying until promoted, unmarked (`backlog unmark`,
which writes an explicit `marked: no`), tombstoned, or past its `--until` date
(below). A superseding record
that omits the key INHERITS the lane; the mark date is the day first
selected and survives re-ups. Decisions resolve by graph precedence: a
decision on a descendant overrides its ancestors', a tombstone ends the lane
for everything behind it, and only genuinely parallel forks fall back to a
deterministic id tiebreak — never timestamps. Keep the lane small: it is
pushed into every session, and the compiler nags past its soft cap.

`backlog mark <slug|id> ['<why now>'] [--until YYYY-MM-DD]` may also say why
and for how long (`mark-reason:`, one line of at most 200 characters, and
`mark-until:`). The reason shows beside the headline in the digest, so give
one when the headline does not already say it. `--until` is a timeout, as on a
park: on that day the mark is over by itself and the idea is an ordinary one,
its line saying `(was marked <date>)`, with its decay clock restarted at the
date. Nobody is told, so a date suits a mark that only matters for a while; a
mark that must stay until someone decides takes no date. Marking a marked idea
again keeps the mark date; a reason or date you pass replaces the current one,
and one you omit is kept. Passing neither refuses, as it always did.

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
