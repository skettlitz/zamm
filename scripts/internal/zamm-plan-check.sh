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

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
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
# protocol spine (references/protocol.md) and the plan
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

# The retrospective a plan must carry once work has happened: execution
# telemetry plus non-placeholder learnings. Required unconditionally on Review
# and Done, and on an Abandoned plan ONLY if work actually happened (see the
# work-happened heuristic below) — a never-started Draft->Abandoned is exempt,
# matching the protocol, which asks a bare draft only for a Loose-ends rationale.
require_retrospective() {
  _pf="$1"; _rel="$2"; _st="$3"
  require "$_pf" "$_rel" "$_st" "Execution-friction-after" "Complexity-felt" "Complexity-delta"
  _cfe=$(field "$_pf" "Complexity-felt")
  if [ -n "$_cfe" ] && ! in_set "$_cfe" "$COMPLEXITY_ANIMALS"; then
    err "$_rel: Complexity-felt \"$_cfe\" is not on the animal scale ($COMPLEXITY_ANIMALS)"
  fi
  _cd=$(field "$_pf" "Complexity-delta")
  if [ -n "$_cd" ] && ! in_set "$_cd" "$COMPLEXITY_DELTAS"; then
    err "$_rel: Complexity-delta \"$_cd\" is not one of: $COMPLEXITY_DELTAS"
  fi
  # Learnings must say something, even if that something is "nothing durable"
  _learn=$(section_body "$_pf" "Learnings" | grep -v '^[[:space:]]*$' || true)
  case "$_learn" in
    "") err "$_rel: status is $_st but ## Learnings is empty" ;;
    *"none yet"*) err "$_rel: status is $_st but ## Learnings still holds the template placeholder" ;;
  esac
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
    { sub(/\r$/, "") }
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

# The plan tree is enumerated by the shared checked manifest, never by a
# private glob: a glob over an unreadable directory expands to nothing and
# reports "0 plans" for a tree nobody actually read. Manifest failure is
# exit 4 (unreadable, not empty), matching the ledger-side taxonomy.
MANIFEST_SH="${ZAMM_PLAN_MANIFEST:-$SCRIPT_DIR/zamm-plan-manifest.sh}"
MF=$(mktemp "${TMPDIR:-/tmp}/zamm-plan-check-mf.XXXXXX")
trap 'rm -f "$MF"' EXIT HUP INT TERM
if ! sh "$MANIFEST_SH" --project-root "$PROJECT_ROOT" > "$MF"; then
  echo "zamm-plan: ERROR: cannot enumerate the plan tree; refusing to report plans as valid." >&2
  exit 4
fi
TAB=$(printf '\t')

# A missing plan root outranks per-plan validation: scaffold always creates
# both roots, so absence is structural damage (a deleted or renamed tree),
# not an empty plan set — refusing (exit 4, like an unreadable tree) keeps
# "the plans are gone" from reading as "there are no plans".
missing=$(awk -F"$TAB" '$1 == "MISSING" { print $2 }' "$MF")
if [ -n "$missing" ]; then
  printf '%s\n' "$missing" | while IFS= read -r m; do
    echo "zamm-plan: ERROR: plan root missing: ${m#"$PROJECT_ROOT/"} -- structural damage, not an empty project." >&2
  done
  echo "zamm-plan: ERROR: restore the directory ('zamm-run.sh scaffold' recreates it), then investigate what removed it." >&2
  exit 4
fi

# structural anomalies the manifest tagged: each is a validation error here
# (the manifest only refuses outright when enumeration itself failed)
while IFS="$TAB" read -r tag p1 p2 p3; do
  case "$tag" in
    SYMLINK)    err "${p1#"$PROJECT_ROOT/"}: symlinked entries are not allowed in the plan tree (no symlinks)" ;;
    NOTDIR)     err "${p1#"$PROJECT_ROOT/"}: not a plan directory" ;;
    UNREADABLE) err "${p1#"$PROJECT_ROOT/"}: cannot read plan file (permission denied or I/O error)" ;;
    DEBRIS)     err "${p1#"$PROJECT_ROOT/"}: stray temporary directory from an interrupted or raced plan create; inspect its contents, then remove it" ;;
    DUP)        err "plan id \"$p1\" exists in both active and archive (${p2#"$PROJECT_ROOT/"}, ${p3#"$PROJECT_ROOT/"})" ;;
  esac
done < "$MF"

# check_plan_dir <plan dir> <main-file manifest tag> <active|archived>
# One plan directory's structural validation, shared between the trees.
# active: full validation plus the activity counters and advisories.
# archived: newly archived v3 plans — recognizable by the Execution-context-
# before: key the v3 template always carries — must still satisfy the same
# structural rules AND be terminal: archival is a move, not an amnesty, so a
# plan mutated between validation and the move (or after) is caught here.
# Legacy pre-v3 archives (no marker key) predate the schema and are left
# alone.
check_plan_dir() {
  pd="$1"; ftag="$2"; mode="$3"
  slug=$(basename "$pd")
  [ "$mode" = "active" ] && nplans=$((nplans + 1))

  # exactly one main plan file (manifest rows: PLANFILE/ARCHFILE = readable
  # main candidate, UNREADABLE = a main candidate that exists but cannot be
  # opened — already reported above, so it must not double-report as "no
  # main")
  nmain=$(awk -F"$TAB" -v t="$ftag" -v d="$pd/" '$1 == t && index($2, d) == 1 { n++ } END { print n + 0 }' "$MF")
  nunread=$(awk -F"$TAB" -v d="$pd/" '$1 == "UNREADABLE" && index($2, d) == 1 { n++ } END { print n + 0 }' "$MF")
  if [ "$mode" = "archived" ]; then
    # Malformed archived directories ALWAYS fail — silently skipping them
    # would let "move the main file away" (or add a second one) disable the
    # post-archive integrity gate entirely. An unreadable main candidate is
    # already an error above, so it does not double-report as "no main".
    if [ "$nmain" -eq 0 ]; then
      [ "$nunread" -eq 0 ] && err "$slug: archived plan directory has no main .plan.md (damaged archive)"
      return 0
    elif [ "$nmain" -gt 1 ]; then
      err "$slug: archived plan directory has $nmain main .plan.md files (expected 1)"
      return 0
    fi
  else
    if [ "$nmain" -eq 0 ]; then
      [ "$nunread" -eq 0 ] && err "$slug: plan directory has no main .plan.md"
      return 0
    elif [ "$nmain" -gt 1 ]; then
      err "$slug: plan directory has $nmain main .plan.md files (expected 1)"
      return 0
    fi
  fi
  pf=$(awk -F"$TAB" -v t="$ftag" -v d="$pd/" '$1 == t && index($2, d) == 1 { print $2; exit }' "$MF")
  rel="${pf#"$PROJECT_ROOT/"}"

  if [ "$mode" = "archived" ]; then
    # v3 provenance comes from OUTSIDE the file being validated first: the
    # .zamm-archived stamp the archiver writes beside the plan file, so
    # stripping keys from the file cannot demote a v3 plan to "legacy" and
    # dodge validation. The template's always-present Execution-context-
    # before: key stays as a fallback for v3 plans archived before stamping
    # existed. Neither present -> genuine pre-v3 archive, left alone.
    if [ ! -e "$pd/.zamm-archived" ] &&
       ! grep -q '^Execution-context-before:' "$pf" 2>/dev/null; then
      return 0
    fi
  fi

  status=$(field "$pf" "Status")
  case "$status" in
    Draft|Implementing|Review|Done|Abandoned) ;;
    "") err "$rel: no Status: line"; return 0 ;;
    *) err "$rel: unknown Status \"$status\" (Draft|Implementing|Review|Done|Abandoned)"; return 0 ;;
  esac

  if [ "$mode" = "archived" ]; then
    case "$status" in
      Done|Abandoned) ;;
      *) err "$rel: archived plan is not terminal (Status: $status)" ;;
    esac
  else
    [ "$status" = "Implementing" ] && nimpl=$((nimpl + 1))
    case "$status" in Done|Abandoned) nterm=$((nterm + 1)) ;; esac
  fi

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
    Review|Done)
      require_retrospective "$pf" "$rel" "$status"
      ;;
    Abandoned)
      # Work-happened heuristic: snapshot validation cannot see the transition,
      # so it infers whether work was done. A plan that reached Implementing
      # carries Execution-context-before; a plan that did any work checked off a
      # Done-when item. Either means this is an Implementing->Abandoned, which the
      # protocol says carries the SAME distillation/telemetry as
      # Implementing->Review PLUS a rationale and cleanup notes. A never-started
      # Draft->Abandoned has neither and is asked only for a Loose-ends rationale.
      work_happened=0
      [ -n "$(field "$pf" "Execution-context-before")" ] && work_happened=1
      [ "${dw_valid:-0}" -gt "${dw_open:-0}" ] && work_happened=1
      # a Loose-ends rationale is required either way (the abandonment reason).
      # The template places the trailing telemetry fields (Execution-friction-
      # after:, Complexity-*, Done-approved-*) physically under ## Loose ends
      # with no heading between, so filter those out — otherwise their mere
      # presence would satisfy the rationale check even when it is empty.
      loose=$(section_body "$pf" "Loose ends" \
        | grep -v '^[[:space:]]*$' | grep -v '(none yet)' \
        | grep -vE '^(Execution-friction-after|Complexity-felt|Complexity-delta|Done-approved-by|Done-approved-at|Done-approval-evidence):' \
        || true)
      [ -z "$loose" ] &&
        err "$rel: status is Abandoned but ## Loose ends has no rationale/cleanup notes"
      if [ "$work_happened" -eq 1 ]; then
        # the forward-direction fields a plan that did work must have had
        require "$pf" "$rel" "$status" "Execution-context-before" "Complexity-forecast"
        # ... including a real Scope and well-formed Done-when items: an
        # Implementing->Abandoned passed through Implementing, where these
        # are required, so their absence (or a malformed checkbox that
        # quietly counts as neither open nor done) must not become valid by
        # abandoning the plan.
        scope_has_content "$pf" ||
          err "$rel: status is Abandoned after work but Scope: has no In/Out content"
        [ "${dw_valid:-0}" -eq 0 ] &&
          err "$rel: status is Abandoned after work but there are no Done-when items"
        [ "${dw_any:-0}" -gt "${dw_valid:-0}" ] &&
          err "$rel: Done-when has a malformed checkbox (use '- [ ]', '- [x]', or '- [X]')"
        cf=$(field "$pf" "Complexity-forecast")
        if [ -n "$cf" ] && ! in_set "$cf" "$COMPLEXITY_ANIMALS"; then
          err "$rel: Complexity-forecast \"$cf\" is not on the animal scale ($COMPLEXITY_ANIMALS)"
        fi
        require_retrospective "$pf" "$rel" "$status"
      fi
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
  return 0
}

plandirs=$(awk -F"$TAB" '$1 == "PLANDIR" { print $2 }' "$MF")
while IFS= read -r pd; do
  [ -n "$pd" ] || continue
  check_plan_dir "$pd" PLANFILE active
done <<EOF
$plandirs
EOF

archdirs=$(awk -F"$TAB" '$1 == "ARCHDIR" { print $2 }' "$MF")
while IFS= read -r pd; do
  [ -n "$pd" ] || continue
  check_plan_dir "$pd" ARCHFILE archived
done <<EOF
$archdirs
EOF

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
