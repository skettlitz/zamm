#!/usr/bin/env bash
set -euo pipefail

# ZAMM initiative janitor:
# - List initiatives in active/workstreams that are marked done
# - Optionally archive them with git mv
#
# Usage:
#   bash archive-done-initiatives.sh [--archive] [--project-root <path>]
#
# Default behavior is list-only (safe dry run).

usage() {
  echo "Usage: archive-done-initiatives.sh [--archive] [--project-root <path>]"
  echo ""
  echo "  --archive          Move matching initiatives to zamm-memory/archive/workstreams via git mv"
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

ACTIVE_DIR="$PROJECT_ROOT/zamm-memory/active/workstreams"
ARCHIVE_DIR="$PROJECT_ROOT/zamm-memory/archive/workstreams"

if [ ! -d "$ACTIVE_DIR" ]; then
  echo "ERROR: active workstreams directory not found: $ACTIVE_DIR"
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

# Check if all main plans (not subplans) in an initiative have terminal status.
# A main plan being Done or Abandoned implies all its subplans are already terminal.
# Terminal statuses: Done, Abandoned.
all_main_plans_terminal() {
  local init_dir="$1"
  local plans_dir="$init_dir/plans"
  if [ ! -d "$plans_dir" ]; then
    return 1
  fi
  local main_plan_count=0
  local terminal_count=0
  while IFS= read -r plan_file; do
    main_plan_count=$((main_plan_count + 1))
    local plan_status
    plan_status=$(sed -n 's/^Status:[[:space:]]*//p' "$plan_file" | head -n1 | awk '{print $1}')
    case "$plan_status" in
      Done|Abandoned) terminal_count=$((terminal_count + 1)) ;;
    esac
  done < <(find "$plans_dir" -maxdepth 1 -name "*.plan.md" ! -name "*.subplan-*.plan.md" 2>/dev/null)
  if [ "$main_plan_count" -gt 0 ] && [ "$main_plan_count" -eq "$terminal_count" ]; then
    return 0
  fi
  return 1
}

declare -a READY_SLUGS
declare -a READY_REASONS

while IFS= read -r init_dir; do
  slug=$(basename "$init_dir")
  state_file="$init_dir/STATE.md"
  status=""

  if [ -f "$state_file" ]; then
    status=$(sed -n 's/^Status:[[:space:]]*//p' "$state_file" | head -n1 | awk '{print $1}')
  fi

  if [ "$status" = "Done" ]; then
    READY_SLUGS+=("$slug")
    READY_REASONS+=("Status: Done")
  elif all_main_plans_terminal "$init_dir"; then
    READY_SLUGS+=("$slug")
    READY_REASONS+=("all main plans terminal")
  fi
done < <(find "$ACTIVE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "_TEMPLATE" | sort)

echo "ZAMM: initiative janitor"
echo "Project root: $PROJECT_ROOT"
echo "Archive-ready when: Status: Done OR all main plans terminal"
echo ""

if [ "${#READY_SLUGS[@]}" -eq 0 ]; then
  echo "No archive-ready initiatives found in active/workstreams."
  exit 0
fi

echo "Archive-ready initiatives:"
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

echo "Archiving initiatives..."
moved=0
skipped=0
failed=0
i=0
for slug in "${READY_SLUGS[@]}"; do
  src_rel="zamm-memory/active/workstreams/$slug"
  dst_rel="zamm-memory/archive/workstreams/$slug"
  reason="${READY_REASONS[$i]}"
  i=$((i + 1))

  if [ -e "$PROJECT_ROOT/$dst_rel" ]; then
    echo "  SKIP: target already exists for $slug ($dst_rel)"
    skipped=$((skipped + 1))
    continue
  fi

  # If STATE.md doesn't say Done yet, update it before archiving
  state_file="$PROJECT_ROOT/$src_rel/STATE.md"
  if [ -f "$state_file" ]; then
    current_status=$(sed -n 's/^Status:[[:space:]]*//p' "$state_file" | head -n1 | awk '{print $1}')
    if [ "$current_status" != "Done" ]; then
      sed -i.bak "s/^Status:[[:space:]]*.*/Status: Done/" "$state_file"
      rm -f "$state_file.bak"
      git -C "$PROJECT_ROOT" add "$src_rel/STATE.md"
      echo "  SET:   $slug STATE.md -> Status: Done (was: $current_status)"
    fi
  fi

  # Ensure source is in the index so git mv works (handles untracked initiatives)
  git -C "$PROJECT_ROOT" add "$src_rel"

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
