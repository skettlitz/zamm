#!/usr/bin/env bash
set -euo pipefail

# ZAMM plan archive helper:
# - List plan directories in active/plans that are terminal
# - Optionally archive them with git mv
#
# Usage:
#   bash archive-done-initiatives.sh [--archive] [--project-root <path>]
#
# Default behavior is list-only (safe dry run).

usage() {
  echo "Usage: archive-done-initiatives.sh [--archive] [--project-root <path>]"
  echo ""
  echo "  --archive          Move matching plan directories to zamm-memory/archive/plans via git mv"
  echo "  --project-root     Optional explicit repository root (default: current directory)"
  exit 1
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
      usage
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
  echo "       Run scaffold.sh in repo root or pass --project-root <repo-root>."
  exit 1
fi

if [ ! -d "$ARCHIVE_DIR" ]; then
  mkdir -p "$ARCHIVE_DIR"
fi

if [ "$ARCHIVE_MODE" -eq 1 ]; then
  if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: --archive requires a git repository at project root: $PROJECT_ROOT"
    exit 1
  fi
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
  echo "Dry run only. Re-run with --archive to move these with git mv."
  exit 0
fi

echo "Archiving plan directories..."
moved=0
skipped=0
failed=0
i=0
for slug in "${READY_SLUGS[@]}"; do
  src_rel="zamm-memory/active/plans/$slug"
  dst_rel="zamm-memory/archive/plans/$slug"
  reason="${READY_REASONS[$i]}"
  i=$((i + 1))

  if [ -e "$PROJECT_ROOT/$dst_rel" ]; then
    echo "  SKIP: target already exists for $slug ($dst_rel)"
    skipped=$((skipped + 1))
    continue
  fi

  # Ensure source is in the index so git mv works (handles ignored/untracked plan dirs).
  git -C "$PROJECT_ROOT" add -f "$src_rel"

  if git -C "$PROJECT_ROOT" mv "$src_rel" "$dst_rel"; then
    echo "  MOVED: $slug ($reason) via git mv"
    moved=$((moved + 1))
  else
    echo "  FAIL:  could not archive $slug"
    failed=$((failed + 1))
  fi
done

echo ""
echo "Archive summary: moved=$moved skipped=$skipped failed=$failed"
if [ "$failed" -gt 0 ]; then
  exit 1
fi
