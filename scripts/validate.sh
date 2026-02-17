#!/usr/bin/env bash
set -euo pipefail

# ZAMM validate — checks memory health against spec constraints.
# Usage: bash validate.sh [--project-root <path>]

usage() {
  echo "Usage: validate.sh [--project-root <path>]"
  echo ""
  echo "  --project-root   Optional explicit repository root (default: current directory)"
  exit 1
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
  if [ ! -d "$PROJECT_ROOT_OVERRIDE" ]; then
    echo "ERROR: --project-root path does not exist: $PROJECT_ROOT_OVERRIDE"
    exit 1
  fi
  PROJECT_ROOT=$(cd "$PROJECT_ROOT_OVERRIDE" && pwd)
else
  PROJECT_ROOT="$PWD"
fi

KNOWLEDGE="$PROJECT_ROOT/zamm-memory/active/knowledge"
ERRORS=0
WARNINGS=0

MAX_CARDS=30
MAX_LINES=220
WEEKLY_THRESHOLD_DAYS=3
MONTHLY_THRESHOLD_DAYS=14
PROPOSAL_AGE_DAYS=1
PROPOSAL_AGE_MINUTES=$((PROPOSAL_AGE_DAYS * 24 * 60))
COMPLEXITY_SCALE_REGEX="^(peanuts|banana|grapes|capybara|badger|pitbull|piranha|shark|godzilla)$"
COMPLEXITY_DELTA_REGEX="^(lighter|as-expected|heavier)$"
MEMORY_ID_REGEX="^[WME][0-9]+$"

echo "ZAMM: validating ${PROJECT_ROOT}"
echo "---"

# --- Helper: check tier file ---
check_tier() {
  local file="$1"
  local prefix="$2"
  local threshold_days="$3"
  local name
  name=$(basename "$file" .md)

  if [ ! -f "$file" ]; then
    echo "ERROR: $file does not exist"
    ERRORS=$((ERRORS + 1))
    return
  fi

  # Card count (grep -c exits 1 on zero matches; || true suppresses without adding output)
  local card_count
  card_count=$(grep -cE "^${prefix}[0-9]+" "$file" 2>/dev/null || true)
  card_count=${card_count:-0}
  if [ "$card_count" -gt "$MAX_CARDS" ]; then
    echo "ERROR: $name has $card_count cards (max $MAX_CARDS)"
    ERRORS=$((ERRORS + 1))
  else
    echo "  OK: $name cards: $card_count / $MAX_CARDS"
  fi

  # Line count
  local line_count
  line_count=$(wc -l < "$file" | tr -d ' ')
  if [ "$line_count" -gt "$MAX_LINES" ]; then
    echo "WARN:  $name has $line_count lines (soft cap $MAX_LINES)"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  OK: $name lines: $line_count / $MAX_LINES"
  fi

  # Line length check (max 200 chars)
  local long_lines
  long_lines=$(awk 'length > 200' "$file" | wc -l | tr -d ' ')
  if [ "$long_lines" -gt 0 ]; then
    echo "WARN:  $name has $long_lines lines exceeding 200 characters"
    WARNINGS=$((WARNINGS + 1))
  fi

  # Evidence links
  if [ "$card_count" -gt 0 ]; then
    local evidence_count
    evidence_count=$(grep -cE "^\* Evidence:" "$file" 2>/dev/null || true)
    evidence_count=${evidence_count:-0}
    if [ "$evidence_count" -lt "$card_count" ]; then
      echo "WARN:  $name has $card_count cards but only $evidence_count evidence lines"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Last maintained: header — always validate presence and format
  local maintained_date
  maintained_date=$(grep -m1 "^Last maintained:" "$file" 2>/dev/null | sed 's/Last maintained: *//' | tr -d ' ')
  if [ -z "$maintained_date" ]; then
    echo "ERROR: $name is missing 'Last maintained:' header"
    ERRORS=$((ERRORS + 1))
  else
    local maintained_epoch today_epoch diff_days
    maintained_epoch=$(date -j -f "%Y-%m-%d" "$maintained_date" "+%s" 2>/dev/null || date -d "$maintained_date" "+%s" 2>/dev/null || echo "")
    today_epoch=$(date "+%s")
    if [ -z "$maintained_epoch" ] || [ "$maintained_epoch" = "0" ]; then
      echo "ERROR: $name has malformed 'Last maintained:' date: '$maintained_date'"
      ERRORS=$((ERRORS + 1))
    elif [ "$threshold_days" -gt 0 ]; then
      # Staleness check — only for tiers with a scheduled threshold
      diff_days=$(( (today_epoch - maintained_epoch) / 86400 ))
      if [ "$diff_days" -gt "$threshold_days" ]; then
        echo "WARN:  $name last maintained $diff_days days ago (threshold: $threshold_days)"
        WARNINGS=$((WARNINGS + 1))
      else
        echo "  OK: $name last maintained $diff_days days ago"
      fi
    else
      echo "  OK: $name has valid 'Last maintained:' date"
    fi
  fi
}

# --- Check tier files ---
echo "Knowledge tiers:"
check_tier "$KNOWLEDGE/WEEKLY.md" "W" "$WEEKLY_THRESHOLD_DAYS"
check_tier "$KNOWLEDGE/MONTHLY.md" "M" "$MONTHLY_THRESHOLD_DAYS"
check_tier "$KNOWLEDGE/EVERGREEN.md" "E" 0

# --- Helper: classify plan-like markdown file ---
is_plan_like_file() {
  local file="$1"
  local base markers
  base=$(basename "$file")
  markers=0

  # Canonical .plan.md suffix is definitive.
  if [[ "$base" =~ \.plan\.md$ ]]; then
    return 0
  fi

  # Legacy: canonical subplan naming without .plan.md suffix.
  if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.subplan-.*\.md$ ]]; then
    return 0
  fi

  # Heuristic fallback for legacy .md plans without the .plan.md suffix.
  if grep -qE "^Status: (Draft|Implementing|Review|Done|Abandoned)" "$file"; then
    markers=$((markers + 1))
  fi
  if grep -qE "^## Done-when|^Done when:" "$file"; then
    markers=$((markers + 1))
  fi
  if grep -qE "^## PR list|^PRs:" "$file"; then
    markers=$((markers + 1))
  fi
  if grep -qE "^## Docs impacted|^Docs impacted:" "$file"; then
    markers=$((markers + 1))
  fi

  # Two or more markers strongly indicate plan intent.
  if [ "$markers" -ge 2 ]; then
    return 0
  fi

  # Dated files with at least one plan marker are likely plans unless in diary/cold.
  if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.md$ ]] && [ "$markers" -ge 1 ]; then
    case "$file" in
      */diary/*|*/cold/*)
        return 1
        ;;
    esac
    return 0
  fi

  return 1
}

extract_field_value() {
  local file="$1"
  local field="$2"
  sed -n "s/^${field}:[[:space:]]*//p" "$file" | head -n1 | sed 's/[[:space:]]*$//'
}

normalize_lc() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

count_done_when_checkboxes() {
  local file="$1"
  awk '
    BEGIN { in_section=0; checked=0; unchecked=0 }
    /^## / {
      if ($0 == "## Done-when" || $0 == "## Done when") {
        in_section=1
        next
      }
      if (in_section) {
        in_section=0
      }
    }
    in_section {
      if ($0 ~ /^[[:space:]]*-[[:space:]]*\[[xX]\]/) {
        checked++
      } else if ($0 ~ /^[[:space:]]*-[[:space:]]*\[[[:space:]]\]/) {
        unchecked++
      }
    }
    END { printf "%d %d\n", checked, unchecked }
  ' "$file"
}

count_section_nonplaceholder_lines() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    BEGIN {
      header="## " section
      in_section=0
      count=0
    }
    /^## / {
      if ($0 == header) {
        in_section=1
        next
      }
      if (in_section) {
        in_section=0
      }
    }
    in_section {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "") {
        next
      }
      if (line ~ /^-[[:space:]]*\(none yet/) {
        next
      }
      count++
    }
    END { print count }
  ' "$file"
}

check_plan_wellbeing() {
  local file="$1"
  local status status_word
  local wb_before complexity_forecast wb_after complexity_felt complexity_delta
  local done_approved_by done_approved_at done_approval_evidence
  local memory_upvotes memory_downvotes
  local complexity_forecast_lc complexity_felt_lc complexity_delta_lc
  local needs_precheck=0
  local needs_postmortem=0
  local needs_done_approval=0
  local needs_review_completion=0
  local needs_learnings=0
  local done_checked=0 done_unchecked=0
  local learnings_entries=0

  status=$(extract_field_value "$file" "Status")
  status_word=$(printf '%s' "$status" | awk '{print $1}')

  wb_before=$(extract_field_value "$file" "Wellbeing-before")
  complexity_forecast=$(extract_field_value "$file" "Complexity-forecast")
  memory_upvotes=$(extract_field_value "$file" "Memory-upvotes")
  memory_downvotes=$(extract_field_value "$file" "Memory-downvotes")
  wb_after=$(extract_field_value "$file" "Wellbeing-after")
  complexity_felt=$(extract_field_value "$file" "Complexity-felt")
  complexity_delta=$(extract_field_value "$file" "Complexity-delta")
  done_approved_by=$(extract_field_value "$file" "Done-approved-by")
  done_approved_at=$(extract_field_value "$file" "Done-approved-at")
  done_approval_evidence=$(extract_field_value "$file" "Done-approval-evidence")

  case "$status_word" in
    Draft|Implementing|Review|Done|Abandoned|"")
      ;;
    *)
      echo "  WARN:  invalid plan status '$status_word' in $file (expected Draft|Implementing|Review|Done|Abandoned)"
      WARNINGS=$((WARNINGS + 1))
      ;;
  esac

  case "$status_word" in
    Implementing|Review|Done|Abandoned)
      needs_precheck=1
      ;;
  esac

  if [ "$needs_precheck" -eq 1 ] && [ -z "$wb_before" ]; then
    echo "  WARN:  missing Wellbeing-before for plan status $status_word in $file"
    WARNINGS=$((WARNINGS + 1))
  fi

  if [ "$needs_precheck" -eq 1 ] && [ -z "$complexity_forecast" ]; then
    echo "  WARN:  missing Complexity-forecast for plan status $status_word in $file"
    WARNINGS=$((WARNINGS + 1))
  fi

  if [ -n "$complexity_forecast" ]; then
    complexity_forecast_lc=$(normalize_lc "$complexity_forecast")
    if ! [[ "$complexity_forecast_lc" =~ $COMPLEXITY_SCALE_REGEX ]]; then
      echo "  WARN:  invalid Complexity-forecast '$complexity_forecast' in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  case "$status_word" in
    Review|Done|Abandoned)
      needs_postmortem=1
      ;;
  esac

  case "$status_word" in
    Done)
      needs_done_approval=1
      ;;
  esac

  case "$status_word" in
    Review|Done)
      needs_review_completion=1
      ;;
  esac

  case "$status_word" in
    Review|Done|Abandoned)
      needs_learnings=1
      ;;
  esac

  read -r done_checked done_unchecked < <(count_done_when_checkboxes "$file")
  learnings_entries=$(count_section_nonplaceholder_lines "$file" "Learnings")

  if [ -n "$complexity_felt" ]; then
    complexity_felt_lc=$(normalize_lc "$complexity_felt")
    if ! [[ "$complexity_felt_lc" =~ $COMPLEXITY_SCALE_REGEX ]]; then
      echo "  WARN:  invalid Complexity-felt '$complexity_felt' in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if [ -n "$complexity_delta" ]; then
    complexity_delta_lc=$(normalize_lc "$complexity_delta")
    if ! [[ "$complexity_delta_lc" =~ $COMPLEXITY_DELTA_REGEX ]]; then
      echo "  WARN:  invalid Complexity-delta '$complexity_delta' in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  check_memory_vote_ids "$file" "Memory-upvotes" "$memory_upvotes"
  check_memory_vote_ids "$file" "Memory-downvotes" "$memory_downvotes"

  if [ "$needs_postmortem" -eq 1 ]; then
    if [ -z "$wb_after" ]; then
      echo "  WARN:  missing Wellbeing-after for plan status $status_word in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
    if [ -z "$complexity_felt" ]; then
      echo "  WARN:  missing Complexity-felt for plan status $status_word in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
    if [ -z "$complexity_delta" ]; then
      echo "  WARN:  missing Complexity-delta for plan status $status_word in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if [ "$needs_done_approval" -eq 1 ]; then
    if [ -z "$done_approved_by" ]; then
      echo "  WARN:  missing Done-approved-by for plan status Done in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
    if [ -z "$done_approved_at" ]; then
      echo "  WARN:  missing Done-approved-at for plan status Done in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
    if [ -z "$done_approval_evidence" ]; then
      echo "  WARN:  missing Done-approval-evidence for plan status Done in $file"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if [ "$needs_review_completion" -eq 1 ] && [ "$done_unchecked" -gt 0 ]; then
    echo "  WARN:  status $status_word requires all existing Done-when items checked in $file (found $done_unchecked unchecked item(s))"
    WARNINGS=$((WARNINGS + 1))
  fi

  if [ "$needs_learnings" -eq 1 ] && [ "$learnings_entries" -eq 0 ]; then
    echo "  WARN:  status $status_word requires non-placeholder Learnings content in $file"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_memory_vote_ids() {
  local file="$1"
  local field="$2"
  local value="$3"
  local token token_count invalid_count

  if [ -z "$value" ]; then
    return
  fi

  token_count=0
  invalid_count=0

  # Accept comma/pipe/whitespace-separated IDs like: W14, M18 | E2
  while IFS= read -r token; do
    token=$(printf '%s' "$token" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[.;:]$//')
    if [ -z "$token" ]; then
      continue
    fi
    token_count=$((token_count + 1))
    if ! [[ "$token" =~ $MEMORY_ID_REGEX ]]; then
      invalid_count=$((invalid_count + 1))
    fi
  done < <(printf '%s\n' "$value" | tr ',| ' '\n')

  if [ "$token_count" -eq 0 ] || [ "$invalid_count" -gt 0 ]; then
    echo "  WARN:  invalid ${field} '$value' in $file (expected IDs like W14, M18)"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# --- Check proposals ---
echo ""
echo "Proposals:"
PROPOSALS_DIR="$KNOWLEDGE/_proposals"
if [ -d "$PROPOSALS_DIR" ]; then
  proposal_count=$(find "$PROPOSALS_DIR" -name "*.md" -not -name ".*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$proposal_count" -gt 0 ]; then
    echo "  PENDING: $proposal_count proposal(s) waiting for review"
    # Check for old proposals
    old_proposals=$(find "$PROPOSALS_DIR" -name "*.md" -not -name ".*" -mmin "+$PROPOSAL_AGE_MINUTES" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$old_proposals" -gt 0 ]; then
      echo "  WARN:  $old_proposals proposal(s) older than ${PROPOSAL_AGE_DAYS} day(s)"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo "  OK: no pending proposals"
  fi
else
  echo "  ERROR: _proposals/ directory missing"
  ERRORS=$((ERRORS + 1))
fi

# --- Check edit logs ---
echo ""
echo "Edit logs:"
for log in WEEKLY.log.md MONTHLY.log.md EVERGREEN.log.md DECISIONS.log.md; do
  if [ -f "$KNOWLEDGE/_edits/$log" ]; then
    echo "  OK: $log exists"
  else
    echo "  ERROR: $log missing"
    ERRORS=$((ERRORS + 1))
  fi
done

# --- Check decisions index ---
echo ""
echo "Decisions:"
if [ -f "$KNOWLEDGE/decisions/INDEX.md" ]; then
  echo "  OK: INDEX.md exists"
else
  echo "  ERROR: decisions/INDEX.md missing"
  ERRORS=$((ERRORS + 1))
fi

# --- Check workstream template ---
echo ""
echo "Workstream template:"
TEMPLATE="$PROJECT_ROOT/zamm-memory/active/workstreams/_TEMPLATE"

if [ -e "$TEMPLATE/WORKSTREAM_STATE.md" ]; then
  echo "  OK: _TEMPLATE/WORKSTREAM_STATE.md"
elif [ -e "$TEMPLATE/STATE.md" ]; then
  echo "  WARN:  _TEMPLATE/STATE.md found (legacy filename); prefer WORKSTREAM_STATE.md"
  WARNINGS=$((WARNINGS + 1))
else
  echo "  ERROR: _TEMPLATE/WORKSTREAM_STATE.md missing"
  ERRORS=$((ERRORS + 1))
fi

for item in plans working diary cold; do
  if [ -e "$TEMPLATE/$item" ]; then
    echo "  OK: _TEMPLATE/$item"
  else
    echo "  ERROR: _TEMPLATE/$item missing"
    ERRORS=$((ERRORS + 1))
  fi
done

# --- Check for misplaced plan files ---
echo ""
echo "Plan placement:"
if [ -d "$PROJECT_ROOT/zamm-memory" ]; then
  misplaced=0
  misplaced_samples=""
  misplaced_sample_count=0
  while IFS= read -r candidate; do
    case "$candidate" in
      */zamm-memory/active/workstreams/*/plans/*|*/zamm-memory/archive/workstreams/*/plans/*)
        continue
        ;;
    esac

    if is_plan_like_file "$candidate"; then
      misplaced=$((misplaced + 1))
      if [ "$misplaced_sample_count" -lt 5 ]; then
        misplaced_samples="${misplaced_samples}\n    - $candidate"
        misplaced_sample_count=$((misplaced_sample_count + 1))
      fi
    fi
  done < <(find "$PROJECT_ROOT/zamm-memory" -type f -name "*.md" 2>/dev/null)

  stray_plans=0
  stray_samples=""
  stray_sample_count=0
  while IFS= read -r candidate; do
    case "$candidate" in
      */zamm-memory/*|*/_TEMPLATE/*|*/.cursor/*|*/node_modules/*|*/.git/*)
        continue
        ;;
    esac
    if [ "$(basename "$candidate")" = "AGENTS.md" ]; then
      continue
    fi
    if is_plan_like_file "$candidate"; then
      stray_plans=$((stray_plans + 1))
      if [ "$stray_sample_count" -lt 5 ]; then
        stray_samples="${stray_samples}\n    - $candidate"
        stray_sample_count=$((stray_sample_count + 1))
      fi
    fi
  done < <(find "$PROJECT_ROOT" -type f -name "*.md" 2>/dev/null)

  if [ "$misplaced" -gt 0 ]; then
    echo "  ERROR: $misplaced plan file(s) found inside zamm-memory but outside workstreams/*/plans/"
    ERRORS=$((ERRORS + 1))
    if [ -n "$misplaced_samples" ]; then
      echo "  INFO: sample misplaced files:"
      printf '%b\n' "$misplaced_samples"
    fi
  fi
  if [ "$stray_plans" -gt 0 ]; then
    echo "  WARN:  $stray_plans plan-like file(s) found outside zamm-memory/ (review for false positives)"
    WARNINGS=$((WARNINGS + 1))
    if [ -n "$stray_samples" ]; then
      echo "  INFO: sample stray files:"
      printf '%b\n' "$stray_samples"
    fi
  fi
  if [ "$misplaced" -eq 0 ] && [ "$stray_plans" -eq 0 ]; then
    echo "  OK: no misplaced plan files detected"
  fi
else
  echo "  SKIP: zamm-memory/ not found"
fi

# --- Check plan wellbeing + memory signal fields ---
echo ""
echo "Plan wellbeing + workflow signals:"
PLAN_DIR="$PROJECT_ROOT/zamm-memory/active/workstreams"
plan_files_found=0
if [ -d "$PLAN_DIR" ]; then
  while IFS= read -r plan_file; do
    if is_plan_like_file "$plan_file"; then
      plan_files_found=$((plan_files_found + 1))
      check_plan_wellbeing "$plan_file"
    fi
  done < <(find "$PLAN_DIR" -type f -path "*/init-*/plans/*.md" ! -name ".gitkeep" 2>/dev/null | sort)

  if [ "$plan_files_found" -eq 0 ]; then
    echo "  OK: no plan files found"
  else
    echo "  Checked wellbeing and workflow signal fields in $plan_files_found plan file(s)"
  fi
else
  echo "  SKIP: active workstreams not found"
fi

# --- Check Cursor rule ---
echo ""
echo "Cursor integration:"
if [ -f "$PROJECT_ROOT/.cursor/rules/zamm.mdc" ]; then
  echo "  OK: .cursor/rules/zamm.mdc exists"
else
  echo "  WARN:  .cursor/rules/zamm.mdc not found"
  WARNINGS=$((WARNINGS + 1))
fi

# --- Summary ---
echo ""
echo "---"
echo "Validation complete: $ERRORS error(s), $WARNINGS warning(s)"
if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
