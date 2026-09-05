# Plans — index

A plan is COMMITTED work with obligations: a mutable file under
`zamm-memory/active/plans/<plan-dir>/` with explicit status transitions and
human-approved closure. It is the only mutable thing in the ledger and the
only one with ceremony — which is why an idea is not a plan and an episode
is not a plan.

Boundary test, which is the whole decision:

- commits to doing something → plan (here)
- implies future action, no commitment → backlog
- asserts a durable reusable claim → knowledge
- happened, noteworthy, and neither → journal

Then load only what you are about to do:

| you are about to | read |
| --- | --- |
| find the active plan, check progress, see what was archived | `plans-reading.md` |
| decide whether work warrants a plan; create one; mirror an IDE-written plan | `plans-writing.md` |
| change a status, close out, get Done approved, archive | `plans-maintenance.md` |
