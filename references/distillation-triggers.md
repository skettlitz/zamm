# Distillation triggers — full semantics

The always-on protocol carries only compact trigger cues; this file is the
reference behind them, read on demand. The cues are deliberately coarse: we
accept some deviation from the ideals below rather than pay for precision in
every session's context. When a cue fires and you are unsure how to shape the
record, this file decides.

One rule spans everything here: **paraphrase the human, never quote verbatim.**
Record the substance; where the register matters, describe the emotion
("strong frustration with rebuild times"). Records are permanent and
team-visible — profanity and heat-of-the-moment phrasing must never be
immortalized.

## Human signals

### "Remember this" (explicit request)

Distill immediately, in the same turn. The anti-churn damping never applies to
an explicit request — current human instruction is precedence rank 1. Shape
and rate the record honestly like any other; explicitness overrides *whether*
to write, not *how*.

### Corrections and standing rules (any temperature)

The human corrects your approach or states a standing rule or decision in
passing ("use X not Y", "never touch Z", "we're going with Postgres"). This
fires regardless of emotional tone — the trigger is the correction, not the
heat. Scope: `conventions` for project rules, `meta` for collaboration norms.
Rationale: a session instruction evaporates at session end unless distilled;
calm corrections are the most common and most-leaked durable signal.

### Emotional complaint (with substance)

Fires only when something substantive sits behind the emotion: record the
underlying fact, cause, or correction — never the emotion as subject.
Durability `days`/`weeks`: a heat-of-the-moment signal enters the ledger as a
cheap hypothesis, not doctrine. Supersede with longer durability if it proves
out.

**Attention lifetime is not storage retention.** `durability` controls only
how fast a record decays out of the digest; the file itself stays in the
repository and in git history permanently. A `durability: days` record about
a bad afternoon is forgotten by the ranking within weeks and readable by the
whole team in five years.

So the trigger is the resulting technical rule, never the episode that
produced it. Record "the staging deploy needs the migration run first — this
broke twice" and not who was frustrated, who broke it, or what was said about
them. Do not write records that identify interpersonal friction, name
colleagues in a critical light, or characterise anyone's performance or
mood, unless the human explicitly asks for that to be retained. When the only
durable content would be the interpersonal event itself, write nothing.

### Exceptional praise

The symmetric positive trigger: record *what earned it* — the approach,
pattern, or decision — so following sessions repeat it. Durability
`days`/`weeks`; supersede upward if it keeps proving out.

## Failure signals

Both fire at the moment of the repeat, not at plan closure. The repetition is
itself the proof of substance — the third attempt should read the record, not
rediscover the trap.

### Trap with a working alternative found

Record cause + the working alternative. Scope: `meta` for agent/process traps,
`quality`/`tooling` for artifact or environment failure modes. Rate honestly:
a repeat that wasted real hours already meets the guardrail definition.

### Dead end, still unsolved

"Tried XY via Z, got stuck / failed several times." Record the goal, the
attempted approach, the failure mode, and what was ruled out — durability
`days`/`weeks`. Its purpose is surviving the session boundary so the next
attempt starts *past* the ruled-out path instead of re-walking it. The session
that later solves it supersedes the dead end with the working answer at longer
durability; the supersession chain preserves the what-we-tried-first history.

## Research results (pointable-file rule)

Significant research or exploration results — including from plan-less
Q&A/exploration sessions (the Session End backstop covers those explicitly) —
are distilled **only when the details live in a pointable file**: a research
report, workdir note, doc, or the source file itself. The record carries the
conclusion plus that pointer. This also covers costly lookups: when finding
something took real effort and the answer is one line, the record points at
where the truth lives.

Never record free-floating transient values ("X is 32.1") with no place to
recheck them — an uncheckable number turns dangerous the moment it goes stale.
If the details are not written down anywhere, either write them down first or
do not distill.

## Non-triggers

- **External changes** (dependency upgrades, API deprecations, upstream
  conventions) are not recorded on their own — we cannot remember every
  little thing. They enter the ledger only through the failure triggers
  (caused a bug or got work stuck) or a drift supersession of an existing
  record they contradict.
- **Churn during primary work**: outside the triggers above, keep writes
  targeted and durable; batch ordinary learnings into plan-closure
  distillation.

## Shared lifecycle

Short-lived entries (`days`/`weeks`) are hypotheses: they either fade with
their topic or get superseded upward (`months`/`years`) by a session that
confirms the statement still holds. Emotion and failure enter cheap; only
confirmation buys permanence. Votes correct ratings from the outside:
records that helped get upvoted at plan closure, misleading ones downvoted.
