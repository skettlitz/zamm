#!/bin/sh
# ZAMM memory archive — move fully-inert records out of the compiler scan path.
#
# Usage: zamm-memory-archive.sh [--project-root <path>] [--dry-run]
#
# Only records in a supersede component with NO live memory record and NO live
# votes record are moved. Votes aggregate over the whole ancestor chain of a
# record, so a dead ancestor of a live head is load-bearing: moving it would
# silently drop the vote signal of its descendants and dangle their
# supersedes: target. zamm-compile.sh --list-inert owns that rule, because it
# already owns the graph.
#
# Archived records stay in the working tree (still greppable) and their ids
# stay resolvable — the compiler registers archived filenames as known-inert
# reference targets.

set -eu
LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT="$PWD"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      if [ $# -lt 2 ] || [ ! -d "$2" ]; then
        echo "ERROR: --project-root requires an existing path" >&2
        exit 1
      fi
      PROJECT_ROOT=$(cd "$2" && pwd)
      shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: zamm-memory-archive.sh [--project-root <path>] [--dry-run]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Defense in depth: directly invocable, so re-prove the canonical roots are
# real directories inside the project before moving records through them (a
# symlinked archive/knowledge would receive the moves outside the project).
. "$SCRIPT_DIR/zamm-paths.sh"
zamm_verify_roots "$PROJECT_ROOT" || exit 4

# ZAMM_COMPILE overrides the compiler path. Test-only dependency-injection
# seam (like ZAMM_TODAY): it lets a fault-injection test substitute a compiler
# that fails on recompile or lies in --list-inert, so the rollback path is
# covered by an automated test rather than a one-off manual sabotage. Unset in
# normal use.
COMPILE="${ZAMM_COMPILE:-$SCRIPT_DIR/zamm-compile.sh}"
DIGEST="$PROJECT_ROOT/zamm-memory/.compiled/memory.md"
ARCHIVE_ROOT="$PROJECT_ROOT/zamm-memory/archive/knowledge"

echo "ZAMM: memory archive"
echo "Project root: $PROJECT_ROOT"

# No lock and no ledger fingerprint. Archival is not a transaction
# (references/invariants.md, G4): the compiler reads the live and the archived
# tree both, so a record that has not moved yet is simply a record that has not
# moved yet, and a rerun completes the job. What IS still checked is our own
# inert rule — see the digest comparison at the end.
mkdir -p "$PROJECT_ROOT/zamm-memory/.compiled"

# Never archive out of a ledger that does not validate: the inert rule is a
# graph conclusion, and a broken graph cannot support one.
if ! sh "$COMPILE" --project-root "$PROJECT_ROOT" --check >/dev/null 2>&1; then
  echo "ERROR: ledger does not pass --check; refusing to archive." >&2
  echo "       Fix the errors first: zamm-run.sh memory check" >&2
  exit 1
fi

sh "$COMPILE" --project-root "$PROJECT_ROOT" >/dev/null

INERT=$(sh "$COMPILE" --project-root "$PROJECT_ROOT" --list-inert)

if [ -z "$INERT" ]; then
  echo "No inert records: every record still belongs to a live chain."
  exit 0
fi

COUNT=$(printf '%s\n' "$INERT" | wc -l | tr -d ' ')
echo "Inert records (fully-retired chains): $COUNT"
printf '%s\n' "$INERT" | while IFS= read -r f; do
  [ -n "$f" ] && echo "  - ${f#"$PROJECT_ROOT/"}"
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "Dry run only. Re-run without --dry-run to move them."
  exit 0
fi

# Nothing moves until every source is confirmed present and every destination
# confirmed absent, so a move can never overwrite an archived record (bytes are
# never destroyed). Afterwards the digest below the header must be
# byte-identical: archiving removes records that by definition influence
# nothing, so a difference means OUR inert rule admitted something
# load-bearing. That is the one failure worth undoing here, because no later
# run would undo it — so completed moves are logged and rolled back. Nothing
# else is: an interrupted archive is a valid, half-archived ledger.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/zamm-archive.XXXXXX")
SRCLIST="$WORK/sources"
MOVELOG="$WORK/movelog"
BEFORE="$WORK/before"
AFTER="$WORK/after"
: > "$MOVELOG"
STATE="preflight"   # preflight -> moving -> done

rollback() {
  [ -s "$MOVELOG" ] || return 0
  echo "       rolling back completed moves..." >&2
  while IFS="$(printf '\t')" read -r rdest rsrc; do
    [ -n "$rdest" ] || continue
    # Undo only moves that ACTUALLY happened. The log is written BEFORE each
    # move, so a logged entry whose dest does not exist (killed between log and
    # mv) never moved, and one whose src is already back was rolled back
    # already — both are skipped, making rollback safe to run at any point.
    if [ -e "$rdest" ] && [ ! -e "$rsrc" ]; then
      mkdir -p "$(dirname "$rsrc")"
      git -C "$PROJECT_ROOT" mv "$rdest" "$rsrc" 2>/dev/null || mv "$rdest" "$rsrc"
    fi
  done < "$MOVELOG"
}

cleanup() {
  # errexit off for the whole cleanup: one failing rm must never abort the
  # trap before the rollback completes and the lock is released.
  set +e
  # Any exit that is not a clean success undoes every completed move and
  # restores the digest, so a failed or interrupted archive leaves the ledger
  # exactly as it was found. Runs ONCE, on EXIT.
  if [ "$STATE" != "done" ]; then
    rollback
    sh "$COMPILE" --project-root "$PROJECT_ROOT" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
  :
}
# A signal trap that only runs cleanup would RESUME execution at the
# interrupted point afterwards (POSIX), using a work dir cleanup just deleted
# and double-running cleanup on the eventual exit. Re-exit into the single EXIT
# handler instead, so a caught signal terminates and cleans up exactly once.
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s\n' "$INERT" | grep -v '^[[:space:]]*$' > "$SRCLIST" || true
# compare below the header AND without the generation trailer: the trailer is
# a checksum over the whole file (header included), so it legitimately changes
# whenever the header's files= count drops — it is pairing metadata, not
# digest content.
tail -n +2 "$DIGEST" | sed '/^<!-- zamm-generation: /d' > "$BEFORE"

# 1. preflight: every source present, every destination absent. Refusing a
#    collision here means the bare-mv fallback can never overwrite an existing
#    archived record. No move has happened yet, so this exit needs no rollback.
while IFS= read -r src; do
  [ -n "$src" ] || continue
  if [ ! -f "$src" ]; then
    echo "ERROR: inert source no longer exists: ${src#"$PROJECT_ROOT/"}" >&2
    exit 1
  fi
  base=$(basename "$src")
  year=$(echo "$base" | cut -c1-4)
  # the year directory is a dynamic component the root check cannot list: a
  # symlinked archive/knowledge/<year> would receive the moves outside the
  # project
  if [ -L "$ARCHIVE_ROOT/$year" ]; then
    echo "ERROR: zamm-memory/archive/knowledge/$year is a symlink; refusing to archive through it." >&2
    exit 1
  fi
  dest="$ARCHIVE_ROOT/$year/$base"
  if [ -e "$dest" ]; then
    echo "ERROR: archive destination already exists: ${dest#"$PROJECT_ROOT/"}" >&2
    echo "       refusing to overwrite an archived record." >&2
    exit 1
  fi
done < "$SRCLIST"

# 2. move, logging each completed move BEFORE the next so the recovery map is
#    always complete. A mv failure here aborts (set -e); the trap rolls back.
echo ""
echo "Archiving..."
STATE="moving"
while IFS= read -r src; do
  [ -n "$src" ] || continue
  base=$(basename "$src")
  year=$(echo "$base" | cut -c1-4)
  dest_dir="$ARCHIVE_ROOT/$year"
  # tolerate mkdir's status (it FAILS on a dangling symlink and silently
  # accepts an existing one), then judge by what is actually there
  mkdir -p "$dest_dir" 2>/dev/null || true
  if [ -L "$dest_dir" ] || [ ! -d "$dest_dir" ]; then
    echo "ERROR: ${dest_dir#"$PROJECT_ROOT/"} is a symlink or not a real directory; rolling back." >&2
    exit 1
  fi
  dest="$dest_dir/$base"
  # Log the intended move BEFORE performing it: a crash between the mv and a
  # later log append would otherwise hide a completed move from rollback,
  # leaving one record stranded under archive/. rollback tolerates a logged
  # move that never happened (dest absent).
  printf '%s\t%s\n' "$dest" "$src" >> "$MOVELOG"
  if git -C "$PROJECT_ROOT" mv "$src" "$dest" 2>/dev/null; then
    :
  else
    mv "$src" "$dest"
  fi
  echo "  MOVED: $base"
done < "$SRCLIST"

# 3. recompile and verify the digest is unchanged. A failed recompile and a
#    changed digest each roll back (via the trap on exit 1). Exit 2 (a digest
#    published but degraded by unrelated records) is a successful recompile —
#    the diff below still verifies this archive changed nothing.
crc=0
sh "$COMPILE" --project-root "$PROJECT_ROOT" >/dev/null 2>&1 || crc=$?
if [ "$crc" != "0" ] && [ "$crc" != "2" ]; then
  echo "" >&2
  echo "ERROR: the ledger did not recompile after archiving (rc=$crc); rolling back." >&2
  exit 1
fi
tail -n +2 "$DIGEST" | sed '/^<!-- zamm-generation: /d' > "$AFTER"
if ! diff -q "$BEFORE" "$AFTER" >/dev/null 2>&1; then
  echo "" >&2
  echo "ERROR: the digest changed after archiving; rolling back." >&2
  echo "       A record that changes the digest was not inert. This is a bug" >&2
  echo "       in the inert rule, not in your ledger — please report it." >&2
  exit 1
fi

# Success: the on-disk digest is already the post-archive one from step 3 and
# it matches below the header. Mark done so the trap keeps the moves.
STATE="done"
echo ""
echo "Archived $COUNT record(s) to zamm-memory/archive/knowledge/"
echo "Digest unchanged (verified). Records stay greppable in the working tree."
