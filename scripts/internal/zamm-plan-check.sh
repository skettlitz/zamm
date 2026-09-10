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

# ZAMM_TODAY like every other date seam in the toolchain, so a block's age
# is testable and a pinned run stays deterministic.
TODAY=${ZAMM_TODAY:-$(date +%Y-%m-%d)}

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

# Parse the `## Blocked-on` log. An entry is
#   - YYYY-MM-DD [<class>]: <sentence>
# at column 0; the lines under it are its detail paragraph, and a `Resolved
# YYYY-MM-DD:` line among them closes it. Emits one tab-separated row per
# entry: ENTRY<TAB>date<TAB>class<TAB>has-sentence<TAB>is-open. A malformed
# entry still emits a row (class "-", or has-sentence 0) so the caller can name
# what is wrong, rather than silently parsing to nothing. An absent class is
# "-" and never the empty string: tab is an IFS WHITESPACE character, so an
# empty field would collapse into its neighbour and shift every field after it.
# The template's `- (no blocks recorded)` placeholder matches no entry shape,
# so an untouched plan reports nothing at all.
blocked_entries() {
  section_body "$1" "Blocked-on" | awk -v OFS="\t" '
    function flush() {
      if (cur == "") return
      print "ENTRY", cur, (kind == "" ? "-" : kind), (txt == "" ? 0 : 1), (res ? 0 : 1)
    }
    { sub(/\r$/, "") }
    /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
      rest = substr($0, 13)
      # Only `[` (a classed entry) or `:` (an unclassified one) opens an entry;
      # anything else after the date is ordinary prose and is left alone. The
      # separator is tested here rather than in the pattern because a bracket
      # expression holding `[` and `:` reads as a character-class opener.
      if (rest !~ /^[ \t]*\[/ && rest !~ /^[ \t]*:/) next
      flush()
      cur = substr($0, 3, 10)
      kind = ""
      # ` [<class>]: <sentence>` is the current shape; a bare `: <sentence>`
      # is an unclassified entry and is reported as such, never guessed at.
      if (match(rest, /^[ \t]*\[[^]]*\][ \t]*:/)) {
        kind = substr(rest, index(rest, "[") + 1)
        kind = substr(kind, 1, index(kind, "]") - 1)
        txt = substr(rest, RLENGTH + 1)
      } else {
        sub(/^[ \t]*:/, "", rest)
        txt = rest
      }
      sub(/^[ \t]+/, "", txt); sub(/[ \t]+$/, "", txt)
      sub(/^[ \t]+/, "", kind); sub(/[ \t]+$/, "", kind)
      res = 0
      next
    }
    cur != "" && /^[[:space:]]*Resolved [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]:/ { res = 1 }
    END { flush() }
  '
}

# The block classes, split on WHO CLEARS THE BLOCK — the one thing a reader of
# the digest needs in order to know whether it is their move:
#   human            a person on this team must decide, answer, approve or grant
#   plan:<plan-id>   another plan in this ledger must land first (named, and
#                    checked below: a dependency that lands silently is the
#                    failure mode this class exists to catch)
#   external         someone or something outside this team — an upstream
#                    release, a deploy, another team's queue
#   defect           something is broken and nobody has committed to fixing it
# If the answer is "nobody, ever", the plan is not blocked, it is Abandoned.
BLOCK_CLASSES="human plan external defect"

# How long a block of each class may sit before the check nags. One number for
# all of them would cry wolf: an unanswered human question at a week means
# someone dropped it, while an upstream release at a week is just Tuesday.
blocked_stale_days() {
  case "$1" in
    human)    echo 7 ;;
    defect)   echo 14 ;;
    plan|plan:*) echo 21 ;;
    external) echo 30 ;;
    *)        echo 14 ;;
  esac
}

# A `[plan:<id>]` block names a dependency inside this ledger, which is the
# whole reason that class is spelled differently from the rest: the id is
# verified to exist here, and — the payoff — an entry still OPEN against a plan
# that has already landed is reported, because a dependency that clears itself
# is precisely the one nobody notices.
check_block_dep() {
  # _bd_act: this entry is open AND its plan is still Blocked, i.e. someone is
  # genuinely waiting. Existence and self-reference are checked regardless.
  _bd_rel="$1"; _bd_date="$2"; _bd_id="$3"; _bd_self="$4"; _bd_act="$5"
  if [ "$_bd_id" = "$_bd_self" ]; then
    err "$_bd_rel: ## Blocked-on entry $_bd_date waits on itself ($_bd_id)"
    return 0
  fi
  _bd_row=$(awk -F"$TAB" -v OFS="$TAB" -v id="$_bd_id" '
    ($1 == "PLANDIR" || $1 == "ARCHDIR") {
      n = split($2, parts, "/")
      if (parts[n] == id) { print $1, $2; exit }
    }' "$MF")
  if [ -z "$_bd_row" ]; then
    err "$_bd_rel: ## Blocked-on entry $_bd_date names a plan that does not exist: $_bd_id"
    return 0
  fi
  [ "$_bd_act" = "1" ] || return 0
  _bd_tag=${_bd_row%%"$TAB"*}
  _bd_dir=${_bd_row#*"$TAB"}
  if [ "$_bd_tag" = "ARCHDIR" ]; then
    warn "$_bd_rel: still blocked on $_bd_id, which is archived -- the dependency landed (zamm-run.sh plan unblock)"
    return 0
  fi
  _bd_pf=$(awk -F"$TAB" -v d="$_bd_dir/" '$1 == "PLANFILE" && index($2, d) == 1 { print $2; exit }' "$MF")
  [ -n "$_bd_pf" ] || return 0
  _bd_st=$(field "$_bd_pf" "Status")
  case "$_bd_st" in
    Done|Abandoned)
      warn "$_bd_rel: still blocked on $_bd_id, which is $_bd_st -- the dependency landed (zamm-run.sh plan unblock)" ;;
  esac
}

# Exact calendar days between two YYYY-MM-DD dates (days-from-civil, the same
# algorithm the digest compiler uses for policy boundaries). A negative span
# clamps to 0, so a hand-typed future date never reads as stale.
days_between() {
  awk -v a="$1" -v b="$2" '
    function civildays(d,   y, m, dd, era, yoe, doy, doe) {
      if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 0
      y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
      if (m <= 2) y--
      era = int(y / 400); yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe - 719468
    }
    BEGIN { n = civildays(b) - civildays(a); print (n < 0 ? 0 : n) }'
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
    Draft|Implementing|Blocked|Review|Done|Abandoned) ;;
    "") err "$rel: no Status: line"; return 0 ;;
    *) err "$rel: unknown Status \"$status\" (Draft|Implementing|Blocked|Review|Done|Abandoned)"; return 0 ;;
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

  # The block log, and the invariant that carries the whole Blocked design.
  # It stays a SNAPSHOT rule, never a history: Blocked requires at least one
  # OPEN entry, and every other status requires none. That pair alone makes
  # "unblock without recording the resolution" structurally impossible, lets N
  # simultaneous blocks work with no extra machinery, and keeps a fully
  # resolved log legal in any status — it is execution telemetry, and it
  # travels into the archive with the plan.
  bl=$(blocked_entries "$pf")
  nbl_open=0
  while IFS="$TAB" read -r btag bdate bkind bhastext bopen; do
    [ "$btag" = "ENTRY" ] || continue
    [ "$bopen" = "1" ] && nbl_open=$((nbl_open + 1))
    valid_date "$bdate" ||
      err "$rel: ## Blocked-on entry date is not a real YYYY-MM-DD date: $bdate"
    [ "$bhastext" = "1" ] ||
      err "$rel: ## Blocked-on entry $bdate has no reason sentence"
    bdep=""
    case "$bkind" in
      human|external|defect) ;;
      plan:?*) bdep=${bkind#plan:} ;;
      plan) err "$rel: ## Blocked-on entry $bdate must name the plan it waits on: [plan:<plan-id>]" ;;
      -|"") bkind=""
            err "$rel: ## Blocked-on entry $bdate has no class; one of [human] [plan:<plan-id>] [external] [defect] says who clears it" ;;
      *) err "$rel: ## Blocked-on entry $bdate has unknown class \"$bkind\" ($BLOCK_CLASSES; plan takes a plan id)" ;;
    esac
    # "the dependency landed" is advice to act, so it is worth printing only
    # where acting is possible: an open entry on a plan that is actually
    # Blocked. An abandoned plan keeps its open entry forever by design and
    # must not nag about a dependency nobody is waiting for any more.
    bact=0
    [ "$bopen" = "1" ] && [ "$status" = "Blocked" ] && bact=1
    [ -n "$bdep" ] && check_block_dep "$rel" "$bdate" "$bdep" "$slug" "$bact"
    # Per-class staleness, on the OPEN entries of an active Blocked plan. Age
    # is the only pressure on the one non-terminal status nothing pushes
    # forward -- advisory, never a failure, because whether to chase the
    # obstruction or abandon the plan is a human call.
    if [ "$mode" = "active" ] && [ "$status" = "Blocked" ] && [ "$bopen" = "1" ] &&
       valid_date "$bdate"; then
      bage=$(days_between "$bdate" "$TODAY")
      bmax=$(blocked_stale_days "$bkind")
      [ "${bage:-0}" -ge "${bmax:-14}" ] &&
        warn "$rel: blocked $bage days on [${bkind:-unclassified}] since $bdate (nags at $bmax); unblock or abandon"
    fi
  done <<EOF
$bl
EOF
  case "$status" in
    Blocked)
      [ "${nbl_open:-0}" -eq 0 ] &&
        err "$rel: status is Blocked but ## Blocked-on has no open entry (a block needs a dated reason sentence)"
      ;;
    Abandoned)
      # The one status that may carry an open block, because it is the status
      # you reach when the obstruction turned out to be fatal. Nothing cleared
      # it, so demanding a Resolved line here would ask the log to record a
      # clearing that never happened -- and the entry is the whole reason the
      # plan died. The digest still prints the open block under the entry, so
      # abandoning hides nothing.
      :
      ;;
    *)
      [ "${nbl_open:-0}" -gt 0 ] &&
        err "$rel: status is $status but ## Blocked-on has $nbl_open open entry(ies); record how each cleared ('plan unblock'), or set Status: Blocked, or Abandoned if the obstruction proved fatal"
      ;;
  esac

  # status-conditional required fields
  case "$status" in
    Implementing|Blocked|Review|Done)
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
