#!/usr/bin/env bash
set -euo pipefail

# ZAMM wellbeing report:
# - Summarize plan-level emotional check-ins and complexity forecast vs felt
# - Highlight mismatch hotspots by initiative
#
# Usage:
#   bash wellbeing-report.sh [--project-root <path>]

usage() {
  echo "Usage: wellbeing-report.sh [--project-root <path>]"
  echo ""
  echo "  --project-root   Optional explicit repository root (default: current directory)"
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

extract_field_value() {
  local file="$1"
  local field="$2"
  sed -n "s/^${field}:[[:space:]]*//p" "$file" | head -n1 | sed 's/[[:space:]]*$//'
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

PLAN_ROOT="$PROJECT_ROOT/zamm-memory/active/workstreams"
if [ ! -d "$PLAN_ROOT" ]; then
  echo "ERROR: active workstreams directory not found: $PLAN_ROOT"
  echo "       Run scaffold.sh in repo root or pass --project-root <repo-root>."
  exit 1
fi

tmp_data=$(mktemp)
trap 'rm -f "$tmp_data"' EXIT

while IFS= read -r plan_file; do
  initiative=$(basename "$(dirname "$(dirname "$plan_file")")")
  status=$(extract_field_value "$plan_file" "Status")
  status_word=$(printf '%s' "$status" | awk '{print $1}')
  complexity_forecast=$(extract_field_value "$plan_file" "Complexity-forecast")
  complexity_felt=$(extract_field_value "$plan_file" "Complexity-felt")
  complexity_delta=$(extract_field_value "$plan_file" "Complexity-delta")
  wellbeing_before=$(extract_field_value "$plan_file" "Wellbeing-before")
  wellbeing_after=$(extract_field_value "$plan_file" "Wellbeing-after")

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$initiative" \
    "$status_word" \
    "$complexity_forecast" \
    "$complexity_felt" \
    "$complexity_delta" \
    "$wellbeing_before" \
    "$wellbeing_after" \
    "$plan_file" >> "$tmp_data"
done < <(find "$PLAN_ROOT" -type f -path "*/init-*/plans/*.md" ! -name ".gitkeep" 2>/dev/null | sort)

rows=$(wc -l < "$tmp_data" | tr -d ' ')
echo "ZAMM wellbeing report"
echo "Project root: $PROJECT_ROOT"
echo "Plan files scanned: $rows"
echo ""

if [ "$rows" -eq 0 ]; then
  echo "No plan files found."
  exit 0
fi

echo "Plan snapshot:"
printf '%-24s %-12s %-12s %-12s %-12s %s\n' "initiative" "status" "forecast" "felt" "delta" "file"
awk -F'\t' '
{
  status = ($2 == "" ? "--" : $2)
  forecast = ($3 == "" ? "--" : $3)
  felt = ($4 == "" ? "--" : $4)
  delta = ($5 == "" ? "--" : $5)
  printf "%-24s %-12s %-12s %-12s %-12s %s\n", $1, status, forecast, felt, delta, $8
}
' "$tmp_data"

echo ""
echo "Complexity drift pairs (forecast -> felt):"
drift_pairs=$(awk -F'\t' 'tolower($3)!="" && tolower($4)!="" {printf "%s -> %s\n", tolower($3), tolower($4)}' "$tmp_data" | sort | uniq -c | sort -nr)
if [ -n "$drift_pairs" ]; then
  printf '%s\n' "$drift_pairs"
else
  echo "  (none with both fields set)"
fi

echo ""
echo "Mismatch hotspots by initiative (completed plans):"
mismatches=$(awk -F'\t' '
function low(s) { return tolower(s) }
$2 ~ /^(Done|Partial|Abandoned)$/ {
  if (low($3) != "" && low($4) != "" && low($3) != low($4)) print $1
}
' "$tmp_data" | sort | uniq -c | sort -nr)
if [ -n "$mismatches" ]; then
  printf '%s\n' "$mismatches"
else
  echo "  (no completed-plan mismatches with both fields set)"
fi

echo ""
echo "Top wellbeing-before phrases:"
top_before=$(awk -F'\t' '$6 != "" { print $6 }' "$tmp_data" | sort | uniq -c | sort -nr | head -n 10)
if [ -n "$top_before" ]; then
  printf '%s\n' "$top_before"
else
  echo "  (none)"
fi

echo ""
echo "Top wellbeing-after phrases:"
top_after=$(awk -F'\t' '$7 != "" { print $7 }' "$tmp_data" | sort | uniq -c | sort -nr | head -n 10)
if [ -n "$top_after" ]; then
  printf '%s\n' "$top_after"
else
  echo "  (none)"
fi
