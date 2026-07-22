#!/bin/sh
# ZAMM plan check — validate the CURRENT STATE of every active plan.
#
# Usage: zamm-plan-check.sh [--project-root <path>]
#
# Snapshot validation, not transition validation: it asks "does this plan
# carry what its declared status requires", never "was this status reached
# legitimately". The second needs a history a mutable markdown file cannot
# prove; the first needs only the file in front of you — and it is what stops
# a plan claiming Done with empty approval fields from being archived.
#
# Exit code is the answer: 0 valid, 1 one or more plans invalid. Warnings do
# not fail the check.

set -eu
LC_ALL=C
export LC_ALL

PROJECT_ROOT="$PWD"
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
    -h|--help)
      echo "Usage: zamm-plan-check.sh [--project-root <path>]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

PLANS_DIR="$PROJECT_ROOT/zamm-memory/active/plans"
nerr=0
nwarn=0
nplans=0
nimpl=0
nterm=0

err() { echo "zamm-plan: ERROR: $*" >&2; nerr=$((nerr + 1)); }
warn() { echo "zamm-plan: WARNING: $*" >&2; nwarn=$((nwarn + 1)); }

field() {
  # field <file> <name>  -> value with surrounding space trimmed
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1 | sed 's/[[:space:]]*$//'
}

require() {
  # require <file> <rel> <status> <field...>
  f="$1"; rel="$2"; st="$3"; shift 3
  for name in "$@"; do
    if [ -z "$(field "$f" "$name")" ]; then
      err "$rel: status is $st but $name: is empty"
    fi
  done
}

# The animal complexity scale and the delta enum, kept in step with the
# protocol (references/scaffold/protocol-body.template.md) and the plan
# template comment.
COMPLEXITY_ANIMALS="ant gecko raccoon capybara badger octopus manatee shark godzilla kraken"
COMPLEXITY_DELTAS="lighter as-expected heavier"

in_set() {
  # in_set <needle> <space-separated set>
  needle="$1"
  for item in $2; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# Real Gregorian date, not just the digit shape (2026-99-99 and 2026-02-30 are
# rejected, leap years respected) — the same rule the compiler applies to
# record filenames. `10#` is not POSIX, so leading zeros are stripped by hand
# to avoid octal interpretation of 08/09.
valid_date() {
  d="$1"
  case "$d" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  y=${d%%-*}; rest=${d#*-}; mo=${rest%%-*}; dy=${rest#*-}
  mo=${mo#0}; dy=${dy#0}
  [ -n "$mo" ] && [ -n "$dy" ] || return 1
  [ "$mo" -ge 1 ] && [ "$mo" -le 12 ] || return 1
  [ "$dy" -ge 1 ] || return 1
  case "$mo" in
    4|6|9|11) dim=30 ;;
    2)
      if { [ $((y % 4)) -eq 0 ] && [ $((y % 100)) -ne 0 ]; } || [ $((y % 400)) -eq 0 ]
      then dim=29; else dim=28; fi
      ;;
    *) dim=31 ;;
  esac
  [ "$dy" -le "$dim" ]
}

# Print the body of one `## <heading>` section: the lines strictly between the
# heading and the next `## ` heading (or end of file). `### ` subsections stay
# inside. Used so Done-when and Learnings checks scan only their own section
# rather than the whole file — an unrelated checkbox under `## Approach` must
# not satisfy (or block) Done-when, and `## Learnings` as the final section
# must still be read (the old `sed '1d;$d'` deleted its only line).
section_body() {
  # section_body <file> <heading-text>
  # The heading must match EXACTLY (or be followed by whitespace), not by
  # prefix: `## Done-when-not` and `## Learnings-extra` are different sections
  # and must not pose as `## Done-when` / `## Learnings`.
  awk -v h="## $2" '
    $0 == h || substr($0, 1, length(h) + 1) == h " " || substr($0, 1, length(h) + 1) == h "\t" { inb = 1; next }
    inb && /^## / { inb = 0 }
    inb { print }
  ' "$1"
}

# `Scope:` heads a block (`* In:` / `* Out:` and bullets), so its value is not
# on the Scope: line itself. Non-empty means there is real text under it beyond
# the bare `* In:` / `* Out:` scaffolding, up to the next `## ` heading.
scope_has_content() {
  awk '
    /^Scope:/ { inb = 1; next }
    inb && /^## / { inb = 0 }
    inb { print }
  ' "$1" |
    sed 's/^\* In://; s/^\* Out://; s/[[:space:]]//g' |
    grep -q .
}

[ -d "$PLANS_DIR" ] || { echo "ZAMM plan check passed (no active plans directory)."; exit 0; }

for pd in "$PLANS_DIR"/*/; do
  [ -d "$pd" ] || continue
  pd=${pd%/}
  slug=$(basename "$pd")
  nplans=$((nplans + 1))

  # exactly one main plan file
  nmain=$(find "$pd" -maxdepth 1 -type f -name '*.plan.md' ! -name '*.subplan-*' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$nmain" -eq 0 ]; then
    err "$slug: plan directory has no main .plan.md"
    continue
  elif [ "$nmain" -gt 1 ]; then
    err "$slug: plan directory has $nmain main .plan.md files (expected 1)"
    continue
  fi
  pf=$(find "$pd" -maxdepth 1 -type f -name '*.plan.md' ! -name '*.subplan-*' | head -1)
  rel="${pf#"$PROJECT_ROOT/"}"

  status=$(field "$pf" "Status")
  case "$status" in
    Draft|Implementing|Review|Done|Abandoned) ;;
    "") err "$rel: no Status: line"; continue ;;
    *) err "$rel: unknown Status \"$status\" (Draft|Implementing|Review|Done|Abandoned)"; continue ;;
  esac

  [ "$status" = "Implementing" ] && nimpl=$((nimpl + 1))
  case "$status" in Done|Abandoned) nterm=$((nterm + 1)) ;; esac

  lu=$(field "$pf" "Last updated")
  if [ -z "$lu" ]; then
    err "$rel: no Last updated: line"
  elif ! valid_date "$lu"; then
    err "$rel: Last updated is not a real YYYY-MM-DD date: $lu"
  fi

  # Done-when checkbox census, computed once within the ## Done-when section.
  # Valid markers are only '- [ ]' (open), '- [x]', '- [X]' (done); anything
  # else (e.g. '- [?]') is malformed and must NOT quietly count as an item or
  # as complete.
  dw_body=$(section_body "$pf" "Done-when")
  dw_valid=$(printf '%s\n' "$dw_body" | grep -cE '^- \[[ xX]\]' || true)
  dw_open=$(printf '%s\n' "$dw_body" | grep -cE '^- \[ \]' || true)
  dw_any=$(printf '%s\n' "$dw_body" | grep -cE '^- \[' || true)

  # status-conditional required fields
  case "$status" in
    Implementing|Review|Done)
      require "$pf" "$rel" "$status" "Execution-context-before" "Complexity-forecast"
      # a plan doing work must declare what it covers and have something to do
      scope_has_content "$pf" ||
        err "$rel: status is $status but Scope: has no In/Out content"
      [ "${dw_valid:-0}" -eq 0 ] &&
        err "$rel: status is $status but there are no Done-when items"
      [ "${dw_any:-0}" -gt "${dw_valid:-0}" ] &&
        err "$rel: Done-when has a malformed checkbox (use '- [ ]', '- [x]', or '- [X]')"
      cf=$(field "$pf" "Complexity-forecast")
      if [ -n "$cf" ] && ! in_set "$cf" "$COMPLEXITY_ANIMALS"; then
        err "$rel: Complexity-forecast \"$cf\" is not on the animal scale ($COMPLEXITY_ANIMALS)"
      fi
      ;;
  esac
  case "$status" in
    Review|Done|Abandoned)
      require "$pf" "$rel" "$status" "Execution-friction-after" "Complexity-felt" "Complexity-delta"
      cfe=$(field "$pf" "Complexity-felt")
      if [ -n "$cfe" ] && ! in_set "$cfe" "$COMPLEXITY_ANIMALS"; then
        err "$rel: Complexity-felt \"$cfe\" is not on the animal scale ($COMPLEXITY_ANIMALS)"
      fi
      cd=$(field "$pf" "Complexity-delta")
      if [ -n "$cd" ] && ! in_set "$cd" "$COMPLEXITY_DELTAS"; then
        err "$rel: Complexity-delta \"$cd\" is not one of: $COMPLEXITY_DELTAS"
      fi
      # Learnings must say something, even if that something is "nothing durable"
      learn=$(section_body "$pf" "Learnings" | grep -v '^[[:space:]]*$' || true)
      case "$learn" in
        "") err "$rel: status is $status but ## Learnings is empty" ;;
        *"none yet"*) err "$rel: status is $status but ## Learnings still holds the template placeholder" ;;
      esac
      ;;
  esac
  if [ "$status" = "Done" ]; then
    require "$pf" "$rel" Done "Done-approved-by" "Done-approved-at" "Done-approval-evidence"
    da=$(field "$pf" "Done-approved-at")
    if [ -n "$da" ] && ! valid_date "$da"; then
      err "$rel: Done-approved-at is not a real YYYY-MM-DD date: $da"
    fi
  fi

  # no unchecked work at closure — every Done-when item must be '- [x]'/'- [X]'.
  # Counted within the Done-when section only (an unchecked box under
  # ## Approach cannot false-fail closure), and a malformed marker is caught
  # above rather than being read as complete.
  case "$status" in
    Review|Done)
      [ "${dw_open:-0}" -gt 0 ] &&
        err "$rel: status is $status but $dw_open Done-when item(s) are unchecked"
      ;;
  esac
done

# advisory, not failures
[ "$nterm" -gt 0 ] &&
  warn "$nterm terminal plan(s) still in active/ (zamm-run.sh plan archive)"
[ "$nimpl" -gt 1 ] &&
  warn "$nimpl plans are Implementing; the protocol prefers one at a time"

if [ "$nerr" -gt 0 ]; then
  echo "ZAMM plan check failed: $nerr problem(s) across $nplans plan(s)." >&2
  exit 1
fi
echo "ZAMM plan check passed ($nplans plan(s), $nwarn warning(s))."
