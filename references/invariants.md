# Invariants: what ZAMM guarantees, and what it deliberately does not

This file is the acceptance rubric for the toolchain. It exists because nine
consecutive review rounds hardened the write path against an adversary nobody
had ever specified, and the cost — roughly a fifth of the shell, concentrated
in the most defect-dense fifth — bought nothing a real user could observe.

A finding that does not violate one of the three guarantees below is **not a
defect**. Close it as out of scope and cite this file. That rule is the point
of the document; without a stopping condition, "could a hypothetical process
race us here?" always has another answer.

## The three guarantees

1. **Every output is a truthful reading of some state the ledger actually
   had.** A digest may be torn across files — record A as of 10:00:01 and
   record B as of 10:00:02 — and that is fine. What must never happen is an
   output describing a state the ledger never occupied.
2. **Every failure is repairable by rerunning.** No operation may leave the
   ledger in a state that a later, ordinary invocation cannot fix.
3. **Bytes are never destroyed.** Records are knowledge; nothing regenerates
   them. This is the only irreversible thing in the system, so it is the only
   thing that gets expensive care.

Everything else — staleness, torn reads, partial archival, a digest one
record behind — is normal operation under eventual consistency, not damage.

### The discriminator: absent vs. unreadable

Guarantee 2 needs to be decidable at runtime, and one distinction decides it:

- **Absent is data.** A record that is not there is a record that does not
  exist. A file a concurrent writer has not finished creating simply lands in
  the next digest. Rerunning fixes it, so we say nothing.
- **Unreadable is an error.** A permission fault, an I/O error, a directory
  where a file belongs. Rerunning does *not* fix it, so we report it, exit
  nonzero, and leave the previous digest untouched.

This single distinction replaces per-call-site policy. There is no third
category: no site gets its own bespoke choice between fatal, quarantine and
warning for a failed *read*.

## The five gates

**G1 — Creation is one atomic claim.** Compose the record in a temporary file,
re-read and validate it there (which is where a short write or a full disk is
caught), then claim its unique final name with `ln`, which is atomic and
refuses to clobber. No lock, no draft, no rollback, no post-commit
verification. The worst outcome is one orphan temporary file.

The record never exists on disk in a mutable, half-valid state, so the entire
class of "validate one object, commit another" defects cannot arise. This is
also why record content arrives on stdin rather than being edited in place: a
draft would be the only mutable object in an append-only store, and every
transaction defect we have ever fixed lived in moving it.

**G2 — The digest is disposable.** It is derived, gitignored and regenerable
by definition, so it is never protected, only recomputed. Compile writes a
temporary file and renames it into place; the rename is atomic, so a reader
sees the old digest or the new one and never a torn one. Two concurrent
compiles both write a coherent snapshot and the last one wins — which is
exactly guarantee 1. Nothing verifies a digest after writing it; if you doubt
it, run compile again.

**G3 — Reads fail loudly or not at all.** Every enumeration and every read
goes through one helper implementing the absent/unreadable distinction above.

**G4 — Archival is not a transaction.** A half-archived ledger is a *valid*
ledger: the compiler reads the live and archived trees both, so a record that
has not moved yet is simply a record that has not moved yet. Archival is
therefore a sequence of independent, idempotent moves. Move each item, never
clobber, report what moved and what did not, exit nonzero if any failed.
Rerunning completes the job. There is no fingerprint snapshot, no per-item
re-hash, no rollback log and no lock.

**G5 — The ledger is real files and real directories, nothing else.** Every
symlink anywhere under `zamm-memory/` is refused, at any position, whatever it
points at. The reason is self-containment rather than security: a ledger has
to travel with the repository, and a symlink means the knowledge lives
somewhere a clone will not have. One uniform rule also beats reasoning about
which positions are dangerous — and it happens to close the cloned-repository
case, where the symlink is static, committed content that a check can refuse
with no race involved.

## Non-goals, stated so reviews can stop

**A hostile process running as the same user is out of scope.** It can
`rm -rf zamm-memory/`, or edit these scripts and wait. Defending the gap
between two syscalls against an attacker who can rewrite the program between
runs is theatre. Concretely, none of the following are defects here:

- a temporary path being predictable
- a window between checking a file and using it
- an identity check that is not the last statement before an operation
- anything that requires a purpose-built same-privilege process, running
  concurrently, to observe

**Concurrency is defined against cooperative writers.** A human editor saving
a file mid-compile, or a second agent writing a record. Their worst case is a
torn read of one record, which quarantines that record with a warning and
resolves on the next run.

**Untrusted repository *content* is in scope.** A symlink or a hostile path
committed by someone else is static and cheap to refuse; G5 refuses it as a
side effect of requiring a self-contained ledger.

### The one carve-out

Rerun-fixes-it does not hold for **erasure**. A secret that reappears in a
digest has already been exposed, and a later run removing it does not undo
that. So an unreadable erasure record is an error under G3 and nothing
publishes — and unlike everything else in this document, that strictness is
not up for relaxation.

## What we assume about the filesystem, and what happens when it lies

These are likelier in practice than any adversary, and the gates above are
shaped by them rather than against them:

| Condition | What happens | Verdict |
| --- | --- | --- |
| Sync folder (Dropbox, iCloud, OneDrive) writes a `(conflicted copy)` file | duplicate record id | warn, prefer the live copy, keep going |
| Archive interrupted; one id present live *and* archived | duplicate record id | warn, prefer the live copy; rerun completes |
| Branch switch, rebase or stash mid-run | files appear and vanish wholesale | digest reflects some real state; rerun |
| Network filesystem where rename is not atomic | possible duplicate or late-visible record | as above; not defended in code |
| Crash mid-create | one orphan temporary file | `status` counts it; harmless |
| Case-insensitive filesystem collides two ids | persistent, not rerun-fixable | reported as an error |

The last row is the shape of everything we still treat as fatal: a condition
that a rerun would not clear.
