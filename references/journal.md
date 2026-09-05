# Journal — index

The journal is the fourth record tree: EPISODES — things that happened, are
worth a trace, and neither imply future action nor assert a durable claim.
It lives in `zamm-memory/journal/<YYYY>/` and is read on demand, never
through the session-start attention budget.

Boundary test, which is the whole decision:

- implies future action → backlog
- asserts a durable reusable claim → knowledge
- commits to doing something → plan
- happened, noteworthy, and neither → journal

Then load only what you are about to do:

| you are about to | read | roughly |
| --- | --- | --- |
| look at what happened, or answer "summarize June" | `journal-reading.md` | the six read surfaces incl. `journal digest` (the compiled summary, never stored) and one predicate grammar |
| record an episode | `journal-writing.md` | the cues, `journal add`, and what never to put in |
| act on a `Journal:` line in the digest, review and claim coverage, or STORE a period summary | `journal-maintenance.md` | digestion and the coverage rules |

Reading is free and safe. Writing an ENTRY is cheap and never refused.
Writing a COVERAGE CLAIM or an ELEVATION is neither: those are immutable
records about other records, so `journal-maintenance.md` is not optional
before `journal review`, `journal settle` or `journal elevate`.
