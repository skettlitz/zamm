#!/usr/bin/env bash
set -euo pipefail

# ZAMM janitor preflight:
# - Fast check for whether janitor work is needed at a session boundary
#   (before primary task execution or before handoff).
# - Scans maintenance triggers and suggests matching cleanup profiles.
#
# Exit codes:
#   0 => no janitor work needed
#   1 => check failed (missing paths or malformed dates)
#   2 => janitor work needed
#
# Usage:
#   bash janitor-check.sh [--project-root <path>] [--quiet]

usage() {
  echo "Usage: janitor-check.sh [--project-root <path>] [--quiet]"
  echo ""
  echo "  --project-root   Optional explicit repository root (default: current directory)"
  echo "  --quiet          Exit-code only (no informational output)"
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

to_epoch() {
  local date_value="$1"
  date -j -f "%Y-%m-%d" "$date_value" "+%s" 2>/dev/null || date -d "$date_value" "+%s" 2>/dev/null || echo ""
}

extract_last_maintained() {
  local file="$1"
  grep -m1 "^Last maintained:" "$file" 2>/dev/null | sed 's/^Last maintained:[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

profile_exists() {
  local profile="$1"
  shift
  local item
  for item in "$@"; do
    if [ "$item" = "$profile" ]; then
      return 0
    fi
  done
  return 1
}

PROJECT_ROOT_OVERRIDE=""
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      if [ $# -lt 2 ]; then
        echo "ERROR: --project-root requires a path"
        exit 1
      fi
      PROJECT_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    --quiet)
      QUIET=1
      shift
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

KNOWLEDGE_DIR="$PROJECT_ROOT/zamm-memory/active/knowledge"
PROPOSALS_DIR="$KNOWLEDGE_DIR/_proposals"
WEEKLY_FILE="$KNOWLEDGE_DIR/WEEKLY.md"
MONTHLY_FILE="$KNOWLEDGE_DIR/MONTHLY.md"
WORKSTREAMS_DIR="$PROJECT_ROOT/zamm-memory/active/workstreams"

if [ ! -d "$KNOWLEDGE_DIR" ]; then
  echo "ERROR: knowledge directory missing: $KNOWLEDGE_DIR"
  exit 1
fi

if [ ! -f "$WEEKLY_FILE" ]; then
  echo "ERROR: missing WEEKLY.md: $WEEKLY_FILE"
  exit 1
fi

if [ ! -f "$MONTHLY_FILE" ]; then
  echo "ERROR: missing MONTHLY.md: $MONTHLY_FILE"
  exit 1
fi

if [ ! -d "$PROPOSALS_DIR" ]; then
  echo "ERROR: proposals directory missing: $PROPOSALS_DIR"
  exit 1
fi

if [ ! -d "$WORKSTREAMS_DIR" ]; then
  echo "ERROR: workstreams directory missing: $WORKSTREAMS_DIR"
  exit 1
fi

WEEKLY_THRESHOLD_DAYS=3
MONTHLY_THRESHOLD_DAYS=14
PROPOSAL_AGE_DAYS=1

today_epoch=$(date "+%s")

declare -a TRIGGERS
declare -a PROFILES
NEEDS_JANITOR=0

weekly_date=$(extract_last_maintained "$WEEKLY_FILE")
if [ -z "$weekly_date" ]; then
  echo "ERROR: WEEKLY.md missing 'Last maintained:' header"
  exit 1
fi
weekly_epoch=$(to_epoch "$weekly_date")
if [ -z "$weekly_epoch" ]; then
  echo "ERROR: malformed WEEKLY.md Last maintained date: '$weekly_date'"
  exit 1
fi
weekly_age_days=$(( (today_epoch - weekly_epoch) / 86400 ))
if [ "$weekly_age_days" -gt "$WEEKLY_THRESHOLD_DAYS" ]; then
  NEEDS_JANITOR=1
  TRIGGERS+=("WEEKLY stale: ${weekly_age_days}d > ${WEEKLY_THRESHOLD_DAYS}d")
  if ! profile_exists "weekly-cleanup" "${PROFILES[@]:-}"; then
    PROFILES+=("weekly-cleanup")
  fi
fi

monthly_date=$(extract_last_maintained "$MONTHLY_FILE")
if [ -z "$monthly_date" ]; then
  echo "ERROR: MONTHLY.md missing 'Last maintained:' header"
  exit 1
fi
monthly_epoch=$(to_epoch "$monthly_date")
if [ -z "$monthly_epoch" ]; then
  echo "ERROR: malformed MONTHLY.md Last maintained date: '$monthly_date'"
  exit 1
fi
monthly_age_days=$(( (today_epoch - monthly_epoch) / 86400 ))
if [ "$monthly_age_days" -gt "$MONTHLY_THRESHOLD_DAYS" ]; then
  NEEDS_JANITOR=1
  TRIGGERS+=("MONTHLY stale: ${monthly_age_days}d > ${MONTHLY_THRESHOLD_DAYS}d")
  if ! profile_exists "monthly-cleanup" "${PROFILES[@]:-}"; then
    PROFILES+=("monthly-cleanup")
  fi
fi

old_proposal_count=$(find "$PROPOSALS_DIR" -name "*.md" -not -name ".*" -mtime "+$PROPOSAL_AGE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
if [ "$old_proposal_count" -gt 0 ]; then
  NEEDS_JANITOR=1
  TRIGGERS+=("proposal backlog: ${old_proposal_count} proposal(s) older than ${PROPOSAL_AGE_DAYS}d")
fi

closing_count=0
done_count=0
plans_finished_count=0
while IFS= read -r init_dir; do
  state_file="$init_dir/STATE.md"
  if [ ! -f "$state_file" ]; then
    continue
  fi
  status=$(sed -n 's/^Status:[[:space:]]*//p' "$state_file" | head -n1 | sed 's/[[:space:]]*$//')
  status_word=$(printf '%s' "$status" | awk '{print $1}')
  if [ "$status_word" = "Closing" ]; then
    closing_count=$((closing_count + 1))
  elif [ "$status_word" = "Done" ]; then
    done_count=$((done_count + 1))
  else
    # Auto-detect: all main plans terminal → archive-ready even if STATE.md
    # was not updated. Only checks main plans (not subplans); a main plan
    # can only be Done or Abandoned if all its subplans are already terminal.
    plans_dir="$init_dir/plans"
    if [ -d "$plans_dir" ]; then
      main_plan_count=0
      terminal_count=0
      while IFS= read -r plan_file; do
        main_plan_count=$((main_plan_count + 1))
        plan_status=$(sed -n 's/^Status:[[:space:]]*//p' "$plan_file" | head -n1 | awk '{print $1}')
        case "$plan_status" in
          Done|Abandoned) terminal_count=$((terminal_count + 1)) ;;
        esac
      done < <(find "$plans_dir" -maxdepth 1 -name "*.plan.md" ! -name "*.subplan-*.plan.md" 2>/dev/null)
      if [ "$main_plan_count" -gt 0 ] && [ "$main_plan_count" -eq "$terminal_count" ]; then
        plans_finished_count=$((plans_finished_count + 1))
      fi
    fi
  fi
done < <(find "$WORKSTREAMS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "_TEMPLATE" | sort)

if [ "$closing_count" -gt 0 ]; then
  NEEDS_JANITOR=1
  TRIGGERS+=("project-finish candidates: ${closing_count} initiative(s) with Status: Closing")
  if ! profile_exists "project-finish" "${PROFILES[@]:-}"; then
    PROFILES+=("project-finish")
  fi
fi

if [ "$done_count" -gt 0 ] || [ "$plans_finished_count" -gt 0 ]; then
  NEEDS_JANITOR=1
  if [ "$done_count" -gt 0 ]; then
    TRIGGERS+=("archive-ready: ${done_count} initiative(s) with Status: Done")
  fi
  if [ "$plans_finished_count" -gt 0 ]; then
    TRIGGERS+=("archive-ready (auto-detected): ${plans_finished_count} initiative(s) where all main plans are terminal")
  fi
  if ! profile_exists "archive-ready" "${PROFILES[@]:-}"; then
    PROFILES+=("archive-ready")
  fi
fi

if [ "$QUIET" -eq 1 ]; then
  if [ "$NEEDS_JANITOR" -eq 1 ]; then
    exit 2
  fi
  exit 0
fi

echo "ZAMM janitor preflight"
echo "Project root: $PROJECT_ROOT"
echo "WEEKLY last maintained: $weekly_date (${weekly_age_days}d ago)"
echo "MONTHLY last maintained: $monthly_date (${monthly_age_days}d ago)"
echo ""

if [ "$NEEDS_JANITOR" -eq 0 ]; then
  echo "Result: no janitor action required."
  exit 0
fi

echo "Result: janitor action required."
echo "Triggers:"
for trigger in "${TRIGGERS[@]}"; do
  echo "  - $trigger"
done

if [ "${#PROFILES[@]}" -gt 0 ]; then
  echo "Suggested cleanup profiles:"
  for profile in "${PROFILES[@]}"; do
    echo "  - $profile"
  done
fi

echo ""
echo "Run one bounded janitor pass now (before primary task or before handoff)."
exit 2
