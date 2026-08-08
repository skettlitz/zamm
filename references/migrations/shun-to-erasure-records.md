# Migrating `shun.md` to erasure records

Applies to any v3 project holding `zamm-memory/knowledge/shun.md`. The
compiler refuses to run while that file exists, so this is a required,
one-time migration — not an optional cleanup.

## Why it changed

`shun.md` was a bare list of redacted record ids. It worked, but it was the
only file in the tree whose *absence* loosened policy: if it could not be
read, the compiler saw an empty redaction set and the erased content came
back. Each way of making it unreadable had to be patched separately —
unreadable (permissions), symlinked, and finally a *directory* named
`shun.md`, which the `-type f` enumeration skipped entirely and which
silently emptied the set with a passing `memory check`.

Erasure is now an ordinary record. It rides the enumeration, validation,
symlink refusal and unreadable handling every record already gets, so there
is no bespoke parser and no bespoke failure mode left. It also carries what
a bare id list could not: the date, the author, and the reason.

## Why the compiler refuses instead of ignoring the file

Silently ignoring a leftover `shun.md` would resurrect exactly the content
it was written to suppress — the failure this whole mechanism exists to
prevent. Refusing is the only safe reading of "this project redacts through
a mechanism I no longer implement".

## Steps

1. Read the ids out of the file (skip `#` comments and blank lines):

   ```sh
   grep -v '^[[:space:]]*#' zamm-memory/knowledge/shun.md | grep -v '^[[:space:]]*$'
   ```

2. For each id, write an erasure record. One record may erase several ids
   (`--erases a,b,c`) when they were redacted for the same reason; prefer one
   record per incident, not per id:

   The body says why the content had to go — it is required, and it is the
   only account of the redaction that survives it. If the original reason is
   unknown, say so plainly:

   ```sh
   bash <zamm-skill>/scripts/zamm-run.sh memory create \
     --type erasure --erases <id>[,<id>...] <slug> <<'EOF'
   Reason not recorded; migrated from shun.md on <date>.
   EOF
   ```

3. Delete the old list and verify:

   ```sh
   rm zamm-memory/knowledge/shun.md
   bash <zamm-skill>/scripts/zamm-run.sh memory check
   bash <zamm-skill>/scripts/zamm-run.sh memory digest
   ```

   `memory check` must pass and the digest must not contain the erased
   content. Erased ids stay valid graph nodes, so successors keep their place
   in the chain exactly as before.

No `zamm-memory/VERSION` change: this is a v3-internal mechanism change, not
a protocol version bump.
