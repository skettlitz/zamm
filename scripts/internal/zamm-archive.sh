#!/usr/bin/env bash
set -euo pipefail

# ZAMM plan archive helper:
# - List plan directories in active/plans that are terminal
# - Optionally archive them (prefer git mv, fallback to mv)
#
# Usage:
#   bash zamm-archive.sh [--archive] [--project-root <path>]
#
# Default behavior is list-only (safe dry run).

usage() {
  echo "Usage: zamm-archive.sh [--archive] [--project-root <path>]"
  echo ""
  echo "  --archive          Move matching plan directories to zamm-memory/archive/plans"
  echo "                     (tries git mv first, falls back to mv)"
  echo "  --project-root     Optional explicit repository root (default: current directory)"
  exit "${1:-1}"
}

resolve_explicit_root() {
  local path="$1"
  if [ ! -d "$path" ]; then
    echo "ERROR: --project-root path does not exist: $path"
    exit 1
  fi
  (cd "$path" && pwd)
}

# The main plan file comes from the checked manifest (readable, non-symlink,
# non-subplan candidates only), never from a private find.
resolve_main_plan_file() {
  local plan_dir="$1"
  awk -F $'\t' -v d="$plan_dir/" '$1 == "PLANFILE" && index($2, d) == 1 { print $2; exit }' "$MF"
}

read_plan_status() {
  local plan_file="$1"
  sed -n 's/^Status:[[:space:]]*//p' "$plan_file" | head -n1 | awk '{print $1}'
}

ARCHIVE_MODE=0
PROJECT_ROOT_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --archive)
      ARCHIVE_MODE=1
      shift
      ;;
    --project-root)
      if [ $# -lt 2 ]; then
        echo "ERROR: --project-root requires a path"
        exit 1
      fi
      PROJECT_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "ERROR: unknown argument: $1"
      usage
      ;;
  esac
done

if [ -n "$PROJECT_ROOT_OVERRIDE" ]; then
  PROJECT_ROOT=$(resolve_explicit_root "$PROJECT_ROOT_OVERRIDE")
else
  PROJECT_ROOT="$PWD"
fi

# Defense in depth: directly invocable, so re-prove the canonical roots are
# real directories inside the project before moving plans through them (a
# symlinked archive/plans would receive the moves outside the project).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/zamm-paths.sh"
zamm_verify_roots "$PROJECT_ROOT" || exit 4

ACTIVE_DIR="$PROJECT_ROOT/zamm-memory/active/plans"
ARCHIVE_DIR="$PROJECT_ROOT/zamm-memory/archive/plans"

if [ ! -d "$ACTIVE_DIR" ]; then
  echo "ERROR: active plans directory not found: $ACTIVE_DIR"
  echo "       Structural damage, not an empty project: scaffold always creates it."
  echo "       Run zamm-scaffold.sh in repo root or pass --project-root <repo-root>."
  exit 4
fi

if [ ! -d "$ARCHIVE_DIR" ]; then
  mkdir -p "$ARCHIVE_DIR"
fi

# Initialized empty, not just declared: `declare -a X` leaves X unset, and
# `${#X[@]}` under `set -u` is an "unbound variable" error on some bash
# versions (GitHub's ubuntu runner among them) while older bashes tolerate it.
READY_SLUGS=()
READY_REASONS=()

# Candidates come from the checked manifest: a find over an unreadable tree
# would report "nothing archive-ready" for plans nobody actually read.
MANIFEST_SH="${ZAMM_PLAN_MANIFEST:-$SCRIPT_DIR/zamm-plan-manifest.sh}"
# explicit template, like every other temp in the toolchain: BSD mktemp
# with no template ignores TMPDIR and writes to the system temp directory
MF="$(mktemp "${TMPDIR:-/tmp}/zamm-plan-archive-mf.XXXXXX")"
trap 'set +e; rm -f "$MF"; :' EXIT

# No lock. Archival is not a transaction (references/invariants.md, G4): a
# plan that has not moved yet is simply a plan that has not moved yet, and a
# rerun finishes the batch. What is still undone on failure is a move whose
# own post-move validation fails — see the rollback below.
if [ "$ARCHIVE_MODE" -eq 1 ]; then
  mkdir -p "$PROJECT_ROOT/zamm-memory/.compiled"
fi

if ! sh "$MANIFEST_SH" --project-root "$PROJECT_ROOT" > "$MF"; then
  echo "ERROR: cannot enumerate the plan tree (unreadable, not empty); refusing to archive." >&2
  exit 4
fi
if awk -F $'\t' '$1 == "MISSING" { found = 1 } END { exit found ? 0 : 1 }' "$MF"; then
  echo "ERROR: a plan root is missing (structural damage, not an empty project); refusing to archive." >&2
  exit 4
fi

while IFS= read -r plan_dir; do
  [ -n "$plan_dir" ] || continue
  slug=$(basename "$plan_dir")
  main_plan_file=$(resolve_main_plan_file "$plan_dir")

  if [ -z "$main_plan_file" ]; then
    continue
  fi

  status=$(read_plan_status "$main_plan_file")
  case "$status" in
    Done|Abandoned)
      READY_SLUGS+=("$slug")
      READY_REASONS+=("status: $status")
      ;;
  esac
done < <(awk -F $'\t' '$1 == "PLANDIR" { print $2 }' "$MF")

echo "ZAMM: plan archive helper"
echo "Project root: $PROJECT_ROOT"
echo "Archive-ready when: main plan status is Done or Abandoned"
echo ""

if [ "${#READY_SLUGS[@]}" -eq 0 ]; then
  echo "No archive-ready plan directories found in active/plans."
  exit 0
fi

echo "Archive-ready plan directories:"
i=0
for slug in "${READY_SLUGS[@]}"; do
  reason="${READY_REASONS[$i]}"
  echo "  - $slug ($reason)"
  i=$((i + 1))
done
echo ""

if [ "$ARCHIVE_MODE" -eq 0 ]; then
  echo "Dry run only. Re-run with --archive to move these (git mv with mv fallback)."
  exit 0
fi

# The same gate the dispatcher applies before archiving, enforced here too so
# invoking this helper DIRECTLY cannot move an invalid terminal plan into
# history (a Done plan with empty approval fields, say). It keys off the first
# Status: line to LIST candidates, but a plan that fails validation must never
# be moved regardless of how archiving was invoked.
PLAN_CHECK_SCRIPT="$SCRIPT_DIR/zamm-plan-check.sh"
if [ -f "$PLAN_CHECK_SCRIPT" ]; then
  if ! sh "$PLAN_CHECK_SCRIPT" --project-root "$PROJECT_ROOT" >/dev/null 2>&1; then
    echo "ERROR: plan check failed; refusing to archive." >&2
    sh "$PLAN_CHECK_SCRIPT" --project-root "$PROJECT_ROOT" 2>&1 >/dev/null | sed 's/^/  /' >&2
    exit 1
  fi
fi

# A plan is archived only when its own state AND its ledger side effects
# agree: archiving must not launder a plan whose votes record disagrees with
# its declared Memory-upvotes/downvotes (or whose votes record is missing).
XCHECK_SCRIPT="$SCRIPT_DIR/zamm-crosscheck.sh"
if [ -f "$XCHECK_SCRIPT" ]; then
  if ! sh "$XCHECK_SCRIPT" --project-root "$PROJECT_ROOT" >/dev/null 2>&1; then
    echo "ERROR: plan/ledger cross-check failed; refusing to archive." >&2
    sh "$XCHECK_SCRIPT" --project-root "$PROJECT_ROOT" 2>&1 >/dev/null | sed 's/^/  /' >&2
    exit 1
  fi
fi

# Preflight refuses collisions before anything moves, so a move can never
# overwrite archived history (bytes are never destroyed). Completed moves are
# logged and rolled back if a LATER gate fails — the post-move plan check is
# the one that matters, because a plan that only fails validation once it is
# archived would otherwise become permanent history that no rerun repairs.
COMPILE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/zamm-compile.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/zamm-plan-archive.XXXXXX")"
MOVELOG="$WORK/movelog"
: > "$MOVELOG"
STATE="preflight"   # preflight -> moving -> done

rollback() {
  [ -s "$MOVELOG" ] || return 0
  echo "       rolling back completed moves..." >&2
  # undo only moves that actually happened (dest present, src gone): the log is
  # written before each move, so this is safe to run at any interruption point
  while IFS=$'\t' read -r rdst rsrc; do
    [ -n "$rdst" ] || continue
    if [ -e "$rdst" ] && [ ! -e "$rsrc" ]; then
      # drop the provenance stamp before moving back: it marks "archived by
      # the v3 archiver", which is exactly what this undoes
      rm -f "$rdst/.zamm-archived"
      git -C "$PROJECT_ROOT" mv "$rdst" "$rsrc" >/dev/null 2>&1 || mv "$rdst" "$rsrc"
    fi
  done < "$MOVELOG"
}

cleanup() {
  # errexit off for the whole cleanup: one failing rm must never abort the
  # trap before the rollback completes and the lock is released
  set +e
  if [ "$STATE" != "done" ]; then
    rollback
    [ -f "$COMPILE_SCRIPT" ] && sh "$COMPILE_SCRIPT" --project-root "$PROJECT_ROOT" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
  rm -f "$MF"
  :
}
# Signals must terminate (re-exit into the single EXIT cleanup), not run
# cleanup and then resume on the now-deleted work dir.
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# 1. preflight: every source present, every destination absent. Refusing a
#    collision here keeps the batch all-or-nothing instead of a partial archive.
for slug in "${READY_SLUGS[@]}"; do
  src="$PROJECT_ROOT/zamm-memory/active/plans/$slug"
  dst="$PROJECT_ROOT/zamm-memory/archive/plans/$slug"
  if [ ! -e "$src" ]; then
    echo "ERROR: plan directory vanished before archiving: $slug" >&2
    exit 1
  fi
  if [ -e "$dst" ]; then
    echo "ERROR: archive destination already exists for $slug" >&2
    echo "       refusing to overwrite archived history (nothing was moved)." >&2
    exit 1
  fi
  # .zamm-archived is a RESERVED name: the archiver writes it as provenance
  # after the move, so a plan carrying one of its own (a symlink pointing at
  # an external file, above all — hidden entries never reach the manifest)
  # would have that target truncated by the stamp. Refuse before anything
  # moves.
  if [ -e "$src/.zamm-archived" ] || [ -L "$src/.zamm-archived" ]; then
    echo "ERROR: $slug contains a reserved .zamm-archived entry; refusing to archive." >&2
    echo "       That name is written by the archiver as provenance; remove it first." >&2
    exit 1
  fi
  # Archived history must be self-contained. A symlink anywhere in the plan
  # (nested ones are invisible to plan check, which only inspects depth-1
  # entries and depth-2 plan files) would archive a pointer to content the
  # repository does not hold — and could point outside it entirely.
  if ! links=$(find "$src" -type l); then
    echo "ERROR: cannot enumerate $slug (unreadable, not empty); refusing to archive." >&2
    exit 4
  fi
  if [ -n "$links" ]; then
    echo "ERROR: $slug contains symlink(s); refusing to archive a plan that is not self-contained:" >&2
    printf '%s\n' "$links" | sed "s|^$PROJECT_ROOT/|       |" >&2
    exit 1
  fi
done

# 2. move, logging each intended move BEFORE performing it
echo "Archiving plan directories..."
STATE="moving"
moved=0
i=0
for slug in "${READY_SLUGS[@]}"; do
  reason="${READY_REASONS[$i]}"
  i=$((i + 1))
  src_rel="zamm-memory/active/plans/$slug"
  dst_rel="zamm-memory/archive/plans/$slug"
  printf '%s\t%s\n' "$PROJECT_ROOT/$dst_rel" "$PROJECT_ROOT/$src_rel" >> "$MOVELOG"
  if git -C "$PROJECT_ROOT" mv "$src_rel" "$dst_rel" >/dev/null 2>&1; then
    echo "  MOVED: $slug ($reason) via git mv"
  else
    mv "$PROJECT_ROOT/$src_rel" "$PROJECT_ROOT/$dst_rel"
    echo "  MOVED: $slug ($reason) via mv"
  fi
  moved=$((moved + 1))
done

# 3. recompile so the digest Plans tail reflects the moves; a failure rolls back.
#    Exit 2 = the digest was PUBLISHED but is degraded by records unrelated to
#    this archive; that is a successful recompile, so only a real failure (rc
#    other than 0 or 2) rolls the archive back.
if [ -f "$COMPILE_SCRIPT" ]; then
  crc=0
  sh "$COMPILE_SCRIPT" --project-root "$PROJECT_ROOT" >/dev/null 2>&1 || crc=$?
  if [ "$crc" != "0" ] && [ "$crc" != "2" ]; then
    echo "ERROR: digest recompile failed after archiving (rc=$crc); rolling back." >&2
    exit 1
  fi
  echo "Digest recompiled."
fi

# 4. stamp v3 provenance OUTSIDE the plan file — plan check trusts the stamp
#    (or, as fallback, the template's always-present key) to decide which
#    archived plans it must validate, so later damage to the file's keys
#    cannot demote a v3 plan to "legacy" and dodge validation. Written before
#    the post-move check so the just-archived plans are validated AS stamped
#    v3 plans; a rollback removes the stamps with the moves.
for slug in "${READY_SLUGS[@]}"; do
  # never `> path`: a redirection FOLLOWS a symlink sitting at that name and
  # truncates its target. Write an unpredictably named private file, then
  # claim the reserved name with ln — which fails on EEXIST (symlink
  # included) instead of following or clobbering anything.
  stamp_tmp="$(mktemp "$ARCHIVE_DIR/$slug/.zamm-archived.XXXXXX")"
  printf 'schema: 3\n' > "$stamp_tmp"
  if ! ln "$stamp_tmp" "$ARCHIVE_DIR/$slug/.zamm-archived" 2>/dev/null; then
    rm -f "$stamp_tmp"
    echo "ERROR: could not write archive provenance for $slug (.zamm-archived exists); rolling back." >&2
    exit 1
  fi
  rm -f "$stamp_tmp"
done

# 5. the archived copies must still validate: plan check structurally
#    verifies newly archived v3 plans, so a mutation that somehow reached the
#    archive (or any archive-tree anomaly the move introduced) rolls the
#    whole batch back instead of becoming permanent history.
if [ -f "$PLAN_CHECK_SCRIPT" ]; then
  if ! sh "$PLAN_CHECK_SCRIPT" --project-root "$PROJECT_ROOT" >/dev/null 2>&1; then
    echo "ERROR: archived plans failed validation after the move; rolling back." >&2
    sh "$PLAN_CHECK_SCRIPT" --project-root "$PROJECT_ROOT" 2>&1 >/dev/null | sed 's/^/  /' >&2
    exit 1
  fi
fi

STATE="done"
echo ""
echo "Archive summary: moved=$moved"
