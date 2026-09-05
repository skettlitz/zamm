# Journal — writing an entry

Read this before writing to the journal. It covers ENTRIES only: coverage
claims (`journal settle`) and period summaries (`journal elevate`) have
their own rules in `journal-maintenance.md`, and the two triggers that send
you there are at the bottom of this page.

## When

Capture is CUE-DRIVEN. There is no session-end "write your journal" step,
and no MUST anywhere in this file. Write when a cue fires:

- `side-quest` — unplanned work done, and why. *"Fixed the flaky teardown
  test while hunting the EPERM bug; unrelated to the plan, took an hour."*
- `exceptional-occurrence` — rare enough that a future reader hitting its
  echo would want the trace. *"CI was red four hours; upstream runner
  outage, nothing local."*
- `non-action` — a considered decision NOT to act, with no standing rule
  behind it. *"Measured parallelizing the compile; gain under 100ms, not
  pursuing."*
- `cross-plan-context` — why several things happened at once, when no single
  plan owns the story.
- `blind-spot` — noticed, looked at, deliberately left. (If you would
  promote it someday, it is a backlog idea instead.)

The set is open: `--cue <slug>` takes your own. The test is "would anyone
retracing this period want this trace?", never "what did I do today?".

## How

    zamm-run.sh journal add 'One sentence.'

A complete write: the sentence is the headline, the slug is derived, scope
defaults to `other`, durability to `weeks`, and piped stdin of any depth
parks under `## Background`. `time:`, `agent:` (`--agent` or `ZAMM_AGENT`)
and `user:` (the git identity) are stamped without a keystroke — provenance,
never a scoreboard.

One sentence is the norm, and it is complete on its own. Put on stdin only
what a reader retracing the period would need — never a diary, never what
the sentence already says. The timeline shows the headline; every extra word
is paid for by whoever opens the record.

Optional, all cheap:

- `--scope <area[/subpath]>` — when the topic is known.
- `--cue <slug>` — which cue admitted it.
- `--salience 1..10` — how noteworthy you found it. Orders reviews later; it
  never gates admission.
- `--axis name=value` — numeric ratings, repeatable. Exactly two types, told
  apart by the value itself: unipolar `0..10` written unsigned, bipolar
  `-5..+5` written ALWAYS signed (`+0` included).
- `--x key=value` — trial metadata in the experimental `x-` namespace.

## Who reads it, and when

Not you, and not today. An entry's readers arrive without today's context:

- A scanner sees the HEADLINE alone: the timeline, the year view of an
  unelevated month, `journal review` above 50 entries, every search row. It
  has to say what happened and why it matters, with the thing named -
  "Spent a day on the flaky teardown test; upstream runner outage, nothing
  local" - not "fixed the test", and not "interesting afternoon".
- The triage reviewer, weeks later, sees the WHOLE record (`journal review`
  prints entries in full, Background included) and decides whether anything
  in it is a fact for the knowledge ledger or an action for the backlog.
  Write for that decision: outcome, cause, what was ruled out. Leave out
  the narration.
- The elevation author, when the month is over, summarizes from headlines
  and blocks. An entry that names its own outcome summarizes itself.
- Someone hitting an echo of the episode a year later finds it through
  `journal search --text`, so use the real names of things.

## What never goes in

- Anything the boundary test routes elsewhere: implies action → backlog;
  durable reusable claim → knowledge; a commitment → plan.
- Secrets, tokens, credentials — the ledger is effectively permanent.
- Verbatim quotes of the human. Paraphrase the substance; where the register
  matters, describe the emotion.
- A rating of a PERSON. Axes rate the episode as it played in the work,
  never someone's inner state or health, and no first-party surface ranks
  authors by them.

Validation never rate-limits or refuses a well-formed capture: no caps, no
quotas, no noteworthiness gate in the write path. The bar is the cues above
and digestion afterwards, never refusal.

## The two triggers that need the maintenance rules

Writing entries needs nothing from `journal-maintenance.md`. Read it first
when either of these fires:

1. The session digest shows a `Journal:` line — digestion is due.
2. Someone asks you to STORE a summary of a period (an elevation), or to
   record what you reviewed. A request to summarize a period is answered
   first by `journal digest <period>`, which is a read and needs no rules;
   storing that summary is a separate action.
