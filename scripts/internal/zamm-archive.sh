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

resolve_main_plan_file() {
  local plan_dir="$1"
  find "$plan_dir" -maxdepth 1 -type f -name "*.plan.md" ! -name "*.subplan-*.plan.md" | sort | head -n1
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

ACTIVE_DIR="$PROJECT_ROOT/zamm-memory/active/plans"
ARCHIVE_DIR="$PROJECT_ROOT/zamm-memory/archive/plans"

if [ ! -d "$ACTIVE_DIR" ]; then
  echo "ERROR: active plans directory not found: $ACTIVE_DIR"
  echo "       Run zamm-scaffold.sh in repo root or pass --project-root <repo-root>."
  exit 1
fi

if [ ! -d "$ARCHIVE_DIR" ]; then
  mkdir -p "$ARCHIVE_DIR"
fi

declare -a READY_SLUGS
declare -a READY_REASONS

while IFS= read -r plan_dir; do
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
done < <(find "$ACTIVE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

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
PLAN_CHECK_SCRIPT="$(cd "$(dirname "$0")" && pwd)/zamm-plan-check.sh"
if [ -f "$PLAN_CHECK_SCRIPT" ]; then
  if ! sh "$PLAN_CHECK_SCRIPT" --project-root "$PROJECT_ROOT" >/dev/null 2>&1; then
    echo "ERROR: plan check failed; refusing to archive." >&2
    sh "$PLAN_CHECK_SCRIPT" --project-root "$PROJECT_ROOT" 2>&1 >/dev/null | sed 's/^/  /' >&2
    exit 1
  fi
fi

# Transactional batch move, the same discipline zamm-memory-archive.sh uses:
# preflight refuses collisions before anything moves, every move is logged
# BEFORE it happens, and ANY failure or signal rolls every completed move back.
# The old loop archived some plans and SKIP-ed a colliding one, leaving a
# partial archive; and a mid-batch failure had no rollback at all.
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
      git -C "$PROJECT_ROOT" mv "$rdst" "$rsrc" >/dev/null 2>&1 || mv "$rdst" "$rsrc"
    fi
  done < "$MOVELOG"
}

cleanup() {
  if [ "$STATE" != "done" ]; then
    rollback
    [ -f "$COMPILE_SCRIPT" ] && sh "$COMPILE_SCRIPT" --project-root "$PROJECT_ROOT" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
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

# 3. recompile so the digest Plans tail reflects the moves; a failure rolls back
if [ -f "$COMPILE_SCRIPT" ]; then
  if ! sh "$COMPILE_SCRIPT" --project-root "$PROJECT_ROOT" >/dev/null 2>&1; then
    echo "ERROR: digest recompile failed after archiving; rolling back." >&2
    exit 1
  fi
  echo "Digest recompiled."
fi

STATE="done"
echo ""
echo "Archive summary: moved=$moved"
