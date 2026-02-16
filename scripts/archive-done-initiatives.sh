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

is_archive_ready_status() {
  local status="$1"
  case "$status" in
    Done)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

declare -a READY_SLUGS
declare -a READY_STATUSES

while IFS= read -r init_dir; do
  slug=$(basename "$init_dir")
  state_file="$init_dir/STATE.md"
  status="(missing)"

  if [ -f "$state_file" ]; then
    status=$(sed -n 's/^Status:[[:space:]]*//p' "$state_file" | head -n1 | sed 's/[[:space:]]*$//')
    if [ -z "$status" ]; then
      status="(missing)"
    fi
  fi

  if is_archive_ready_status "$status"; then
    READY_SLUGS+=("$slug")
    READY_STATUSES+=("$status")
  fi
done < <(find "$ACTIVE_DIR" -mindepth 1 -maxdepth 1 -type d -name "init-*" | sort)

echo "ZAMM: initiative janitor"
echo "Project root: $PROJECT_ROOT"
echo "Archive-ready statuses: Done"
echo ""

if [ "${#READY_SLUGS[@]}" -eq 0 ]; then
  echo "No archive-ready initiatives found in active/workstreams."
  exit 0
fi

echo "Archive-ready initiatives:"
i=0
for slug in "${READY_SLUGS[@]}"; do
  status="${READY_STATUSES[$i]}"
  echo "  - $slug (Status: $status)"
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
  status="${READY_STATUSES[$i]}"
  i=$((i + 1))

  if [ -e "$PROJECT_ROOT/$dst_rel" ]; then
    echo "  SKIP: target already exists for $slug ($dst_rel)"
    skipped=$((skipped + 1))
    continue
  fi

  if git -C "$PROJECT_ROOT" mv "$src_rel" "$dst_rel"; then
    echo "  MOVED: $slug (Status: $status)"
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
