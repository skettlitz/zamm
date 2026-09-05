# Memory — index

The knowledge ledger holds DURABLE CLAIMS: statements about the project that
stay true across sessions and change what an agent does — rules, contracts,
hard-won results. Records are immutable files under
`zamm-memory/knowledge/<YYYY>/`; the compiler ranks them into the
session-start digest, the one surface every agent reads every session.

Boundary test, which is the whole decision:

- asserts a durable reusable claim → knowledge (here)
- implies future action → backlog
- commits to doing something → plan
- happened, noteworthy, and neither → journal

Then load only what you are about to do:

| you are about to | read | roughly |
| --- | --- | --- |
| read the digest, open a record, look something up | `memory-reading.md` | the digest's anatomy, what `[id votes +bg]` means, when to open a record |
| write a record | `memory-writing.md` | who reads it at each zoom, the body convention, schema and areas, the write, the cues |
| correct, merge, retire or vote; reconcile after a merge; erase a secret; archive | `memory-maintenance.md` | supersession, votes, reconciliation, erasure, archive, how ranking works |

Reading is free. A record is cheap to write and validated before it lands,
but it is immutable and reread at every session start by every agent - so
`memory-writing.md` is not optional before the first one.
