#!/usr/bin/env bash
set -euo pipefail

# ZAMM plan status helper:
# - Scan active plan directories
# - Read each main .plan.md status
# - Print grouped buckets with counts and plan listings
#
# Usage:
#   bash zamm-status.sh [--project-root <path>]

usage() {
  echo "Usage: zamm-status.sh [--project-root <path>]"
  echo ""
  echo "  --project-root   Optional explicit repository root (default: current directory)"
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

read_last_updated() {
  local plan_file="$1"
  sed -n 's/^Last updated:[[:space:]]*//p' "$plan_file" | head -n1
}

normalize_status() {
  local raw="$1"
  local lowered

  lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    draft) echo "Draft" ;;
    implementing) echo "Implementing" ;;
    review) echo "Review" ;;
    done) echo "Done" ;;
    abandoned) echo "Abandoned" ;;
    *) echo "Unknown" ;;
  esac
}

print_bucket() {
  local bucket="$1"
  local label="$2"
  local rows_file="$3"
  local count

  count=$(awk -F $'\t' -v s="$bucket" '$1 == s { c++ } END { print c + 0 }' "$rows_file")
  echo "$label: $count"
  if [ "$count" -gt 0 ]; then
    awk -F $'\t' -v s="$bucket" '
      $1 == s {
        updated = ($4 == "" ? "n/a" : $4)
        printf "  - %s (plan dir: %s, Last updated: %s)\n", $3, $2, updated
      }
    ' "$rows_file"
  fi
  echo ""
}

PROJECT_ROOT_OVERRIDE=""
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
  PROJECT_ROOT="$(resolve_explicit_root "$PROJECT_ROOT_OVERRIDE")"
else
  PROJECT_ROOT="$PWD"
fi

ACTIVE_DIR="$PROJECT_ROOT/zamm-memory/active/plans"
if [ ! -d "$ACTIVE_DIR" ]; then
  echo "ERROR: active plans directory not found: $ACTIVE_DIR"
  echo "       Structural damage, not an empty project: scaffold always creates it."
  echo "       Run zamm-scaffold.sh in repo root or pass --project-root <repo-root>."
  exit 4
fi

# explicit templates, like every other temp in the toolchain: BSD mktemp
# with no template ignores TMPDIR and writes to the system temp directory
ROWS_FILE="$(mktemp "${TMPDIR:-/tmp}/zamm-status-rows.XXXXXX")"
MISSING_FILE="$(mktemp "${TMPDIR:-/tmp}/zamm-status-missing.XXXXXX")"
MF="$(mktemp "${TMPDIR:-/tmp}/zamm-status-mf.XXXXXX")"
trap 'rm -f "$ROWS_FILE" "$MISSING_FILE" "$MF"' EXIT

# Enumerate through the checked manifest: a find/glob over an unreadable tree
# reports "no plans" for plans nobody actually read; the manifest makes that
# case loud (exit 4) instead.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_SH="${ZAMM_PLAN_MANIFEST:-$SCRIPT_DIR/zamm-plan-manifest.sh}"
if ! sh "$MANIFEST_SH" --project-root "$PROJECT_ROOT" > "$MF"; then
  echo "ERROR: cannot enumerate the plan tree (unreadable, not empty)."
  exit 4
fi

# a missing plan root (archive/plans here; active/plans was guarded above) is
# structural damage — scaffold always creates both roots
if awk -F $'\t' '$1 == "MISSING" { found = 1 } END { exit found ? 0 : 1 }' "$MF"; then
  awk -F $'\t' -v r="$PROJECT_ROOT/" '$1 == "MISSING" {
    p = $2; sub(r, "", p)
    print "ERROR: plan root missing: " p " -- structural damage, not an empty project."
  }' "$MF"
  echo "       Restore it (zamm-scaffold.sh recreates the directory), then investigate."
  exit 4
fi

plan_dir_count=0

while IFS= read -r plan_dir; do
  [ -n "$plan_dir" ] || continue
  plan_dir_count=$((plan_dir_count + 1))
  rel_plan_dir="${plan_dir#"$PROJECT_ROOT"/}"
  main_plan_file="$(resolve_main_plan_file "$plan_dir")"

  if [ -z "$main_plan_file" ]; then
    echo "$rel_plan_dir" >> "$MISSING_FILE"
    continue
  fi

  status_raw="$(read_plan_status "$main_plan_file")"
  status="$(normalize_status "$status_raw")"
  last_updated="$(read_last_updated "$main_plan_file")"
  rel_plan_file="${main_plan_file#"$PROJECT_ROOT"/}"

  printf '%s\t%s\t%s\t%s\n' \
    "$status" \
    "$rel_plan_dir" \
    "$rel_plan_file" \
    "$last_updated" >> "$ROWS_FILE"
done < <(awk -F $'\t' '$1 == "PLANDIR" { print $2 }' "$MF")

plan_file_count="$(wc -l < "$ROWS_FILE" | tr -d ' ')"
missing_count="$(wc -l < "$MISSING_FILE" | tr -d ' ')"

echo "ZAMM: plan status snapshot"
echo "Project root: $PROJECT_ROOT"
echo "Active plans directory: $ACTIVE_DIR"
echo "Plan directories scanned: $plan_dir_count"
echo "Main plan files found: $plan_file_count"
echo "Missing main .plan.md: $missing_count"
echo ""

if [ "$plan_dir_count" -eq 0 ]; then
  echo "No plan directories found under zamm-memory/active/plans."
  exit 0
fi

print_bucket "Draft" "Draft" "$ROWS_FILE"
print_bucket "Implementing" "Implementing" "$ROWS_FILE"
print_bucket "Review" "Review" "$ROWS_FILE"
print_bucket "Done" "Done" "$ROWS_FILE"
print_bucket "Abandoned" "Abandoned" "$ROWS_FILE"
print_bucket "Unknown" "Unknown" "$ROWS_FILE"

if [ "$missing_count" -gt 0 ]; then
  echo "Plan directories missing a main .plan.md:"
  while IFS= read -r rel_path; do
    echo "  - $rel_path"
  done < "$MISSING_FILE"
fi

# structural anomalies the manifest tagged (symlinks, stray files, unreadable
# plan files, duplicate ids) — informational here, errors in plan check
anom_count="$(awk -F $'\t' '$1 ~ /^(SYMLINK|NOTDIR|UNREADABLE|DUP|DEBRIS)$/' "$MF" | wc -l | tr -d ' ')"
if [ "$anom_count" -gt 0 ]; then
  echo "Invalid plan-tree entries ($anom_count; zamm-run.sh plan check reports them as errors):"
  awk -F $'\t' -v r="$PROJECT_ROOT/" '$1 ~ /^(SYMLINK|NOTDIR|UNREADABLE|DUP|DEBRIS)$/ {
    p = $2; sub(r, "", p); print "  - " $1 ": " p
  }' "$MF"
fi
