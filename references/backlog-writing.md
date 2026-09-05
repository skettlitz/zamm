# Backlog — writing an idea

Read this before capturing an idea. It is cheap: one sentence is a complete
record, and validation never gates on merit — the lens and decay do that.

## Who reads it

- The triage reader scanning the lens, dozens of ideas at a time under area
  headings that count them: `- area/subpath: headline [id +bg]`. The
  headline must say what would be done and, in a clause, why it is worth
  doing — "Cache the parsed frontmatter between passes; three passes re-read
  every file" — not "improve the compiler".
- The agent who opens it (`backlog show`) before starting: `## Background`
  is the case and the sketch — what it would change, what it depends on,
  what was already considered. When the idea is promoted, that is the seed
  of the plan's Scope and Approach.
- Every agent at every session start, once the idea is MARKED: the marked
  lane pushes the headline into the digest until it is promoted or
  unmarked, and a marked headline reads as a commitment.
- The sharpener and the voter: someone re-ups or refines an idea by
  superseding it, and votes on it instead of duplicating. An idea that names
  its thing by its real name is found; a vague one gets a duplicate.

## How

    bash <zamm-skill>/scripts/zamm-run.sh backlog add 'One sentence.' [--scope area/subpath]

Scope defaults to `other`. When the topic is already known, say so:
`--scope domain/lobby` — the lens clusters same-subpath siblings inside
their area block, headings carry per-subpath counts, and `backlog list
--scope` filters; none of that works over an undifferentiated `other` pile.
Pipe any depth on stdin: it lands under `## Background` (unbounded), and the
lens shows the headline with `+bg`.

- Read `backlog list` BEFORE adding. Prefer correction over accretion:
  supersede an existing idea to sharpen or re-up it (`--supersedes <id>`;
  superseding refreshes its decay clock), or vote on it (`backlog add --type
  votes --up <id> <slug>`; triage votes carry no `plan:`), instead of adding
  a near-duplicate.
- One idea = one thing you would promote. Siblings you might start
  separately are separate records SHARING a subpath, never one blob and
  never a new taxonomy.
- `guardrail` importance is refused here: guardrails are safety contracts of
  the knowledge digest, not a scheduling signal. The marked lane is how an
  idea earns pushed attention.
- The permanence rules hold here as everywhere: no secrets, paraphrase the
  human. Brevity: the headline is read dozens at a time; the Background by
  the one who does the work.
