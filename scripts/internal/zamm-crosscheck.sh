#!/bin/sh
# ZAMM cross-check — validation that spans plans AND the ledger, run after the
# per-object checks (zamm-compile.sh --check, zamm-plan-check.sh) pass.
#
# A plan closing out declares Memory-upvotes / Memory-downvotes and, per the
# protocol, writes ONE votes record (type: votes, plan: <plan-dir>, up:/down:
# mirroring those fields). Nothing tied the two together: a Review plan could
# claim it upvoted a record with no votes record in the ledger, a votes record
# could disagree with the plan it names, or a votes record could name a plan
# that does not exist at all (minting ranking weight for nothing). This check
# reconciles them.
#
# It reads the set of ACTIVE (counted) votes records from the compiler
# (`--list-votes`: id<TAB>plan<TAB>up<TAB>down) rather than reconstructing
# "which votes record is superseded" from the filesystem — the compiler already
# owns that graph, and a shell substring match on supersedes: lines was both
# path-unsafe and prone to matching an id embedded in a longer id.
#
# Usage: zamm-crosscheck.sh [--project-root <path>]
# Exit code: 0 consistent, 1 one or more mismatches.

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
      echo "Usage: zamm-crosscheck.sh [--project-root <path>]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ZAMM_COMPILE overrides the compiler path (test-only DI seam, like elsewhere).
COMPILE="${ZAMM_COMPILE:-$SCRIPT_DIR/zamm-compile.sh}"
PLANS_DIR="$PROJECT_ROOT/zamm-memory/active/plans"
ARCH_PLANS="$PROJECT_ROOT/zamm-memory/archive/plans"
TAB=$(printf '\t')
nerr=0

err() { echo "zamm-xcheck: ERROR: $*" >&2; nerr=$((nerr + 1)); }

field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1 | sed 's/[[:space:]]*$//'; }

# a comma/whitespace separated id list -> sorted unique ids, one per line.
# Tabs split too: they are legal whitespace in BOTH the plan fields and the
# record lists, and normalizing only spaces made "id-a,<TAB>id-b" disagree
# with the semantically identical "id-b, id-a".
norm_set() {
  printf '%s\n' "$1" | tr ",$TAB " '\n' | grep -v '^[[:space:]]*$' | sort -u
}

# a plan slug names a real plan only when a .plan.md exists under it (active
# or archived). A bare directory is NOT enough: a hand-made empty dir under
# archive/plans/ would otherwise launder an orphan votes record. The slug
# charset guard is defense in depth behind the compiler contract — a path
# value ("..", "../plans") must never reach the filesystem lookup. Existence
# is answered by the checked manifest, so a symlinked dir or file (which the
# manifest refuses to follow) cannot vouch for a votes record.
plan_has_file() {
  case "$1" in ''|*[!a-z0-9-]*) return 1 ;; esac
  awk -F"$TAB" -v a="$PLANS_DIR/$1/" -v b="$ARCH_PLANS/$1/" '
    ($1 == "PLANFILE" && index($2, a) == 1) || ($1 == "ARCHFILE" && index($2, b) == 1) { found = 1; exit }
    END { exit found ? 0 : 1 }' "$PMF"
}

# The active (counted) votes records, one per line, from the compiler. If the
# compiler cannot produce the list (enumeration failure, protocol error), the
# cross-check must fail closed — an empty list read as "no votes records"
# would pass a ledger nobody actually enumerated. rc 2 (degraded but valid)
# still lists and is accepted.
VOTES_TMP=$(mktemp "${TMPDIR:-/tmp}/zamm-xcheck.XXXXXX")
CERR_TMP=$(mktemp "${TMPDIR:-/tmp}/zamm-xcheck-err.XXXXXX")
PMF=$(mktemp "${TMPDIR:-/tmp}/zamm-xcheck-pmf.XXXXXX")
trap 'rm -f "$VOTES_TMP" "$CERR_TMP" "$PMF"' EXIT HUP INT TERM

# The plan trees enter the cross-check only through the checked manifest; an
# unreadable tree must fail the check, not read as "no plans to reconcile".
MANIFEST_SH="${ZAMM_PLAN_MANIFEST:-$SCRIPT_DIR/zamm-plan-manifest.sh}"
if ! sh "$MANIFEST_SH" --project-root "$PROJECT_ROOT" > "$PMF"; then
  echo "zamm-xcheck: ERROR: cannot enumerate the plan tree; cross-check cannot run." >&2
  exit 4
fi
crc=0
sh "$COMPILE" --project-root "$PROJECT_ROOT" --list-votes > "$VOTES_TMP" 2>"$CERR_TMP" || crc=$?
if [ "$crc" -ne 0 ] && [ "$crc" -ne 2 ]; then
  echo "zamm-xcheck: ERROR: compiler could not list votes records (rc=$crc); cross-check cannot run." >&2
  sed 's/^/  /' "$CERR_TMP" >&2
  exit 1
fi

# 1. orphan guard: every counted votes record must name a plan that exists
#    (active or archived). A nonexistent plan means the votes record is not
#    reconciled with any plan closure and is minting ranking weight on its own.
#    Read from a file (not a pipe) so err() increments survive.
while IFS="$TAB" read -r vid vplan vup vdown; do
  [ -n "$vid" ] || continue
  if [ -n "$vplan" ] && ! plan_has_file "$vplan"; then
    err "$vid: votes record names plan '$vplan', which has no active or archived plan (a <slug>/<slug>.plan.md)"
  fi
done < "$VOTES_TMP"

# check one plan file against the votes list. Agreement rules:
#   - a counted votes record naming this plan must match the declared sets,
#     whatever the status and whether the plan is active or archived —
#     otherwise a mismatch could be laundered by archiving the plan.
#   - declared Memory-upvotes/downvotes with NO votes record is an error for
#     terminal-ish statuses (Review|Done|Abandoned). In the archive, that rule
#     applies only when a declared target looks like a v3 record id: pre-v3
#     plans legitimately declare legacy card ids (W2, S18) whose votes were
#     migrated as seed-up/seed-dn, with no votes record to reconcile.
#   - Draft/Implementing plans may declare early; bookkeeping is checked at
#     Review, so absence of a votes record is not yet an error there.
check_plan_votes() {
  pf="$1"; archived="$2"
  slug=$(basename "$(dirname "$pf")")
  status=$(field "$pf" "Status")
  pu=$(norm_set "$(field "$pf" "Memory-upvotes")")
  pdn=$(norm_set "$(field "$pf" "Memory-downvotes")")

  # the (at most one) counted votes record naming this plan
  vrow=$(awk -F"$TAB" -v p="$slug" '$2 == p { print; exit }' "$VOTES_TMP")

  if [ -z "$vrow" ]; then
    [ -n "$pu" ] || [ -n "$pdn" ] || return 0
    if [ "$archived" = "1" ]; then
      printf '%s\n%s\n' "$pu" "$pdn" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-' || return 0
    else
      case "$status" in Review|Done|Abandoned) ;; *) return 0 ;; esac
    fi
    err "$slug: plan declares Memory-upvotes/downvotes but no active votes record names this plan (write one: type: votes, plan: $slug)"
    return 0
  fi

  vid=$(printf '%s' "$vrow" | cut -d"$TAB" -f1)
  vu=$(norm_set "$(printf '%s' "$vrow" | cut -d"$TAB" -f3)")
  vd=$(norm_set "$(printf '%s' "$vrow" | cut -d"$TAB" -f4)")

  [ "$pu" = "$vu" ] || err "$slug: Memory-upvotes disagree with the votes record ($vid)"
  [ "$pdn" = "$vd" ] || err "$slug: Memory-downvotes disagree with the votes record ($vid)"
}

# 2. agreement, over BOTH trees: active plans AND archived plans. Restricting
#    this to active Review/Done let a mismatch be laundered two ways — abandon
#    the plan (Abandoned was skipped) or archive it (the archive was skipped
#    while the orphan guard still accepted archived directories).
while IFS="$TAB" read -r dtag pd; do
  [ -n "$pd" ] || continue
  arch=0; ftag="PLANFILE"
  if [ "$dtag" = "ARCHDIR" ]; then arch=1; ftag="ARCHFILE"; fi
  pf=$(awk -F"$TAB" -v t="$ftag" -v d="$pd/" '$1 == t && index($2, d) == 1 { print $2; exit }' "$PMF")
  [ -n "$pf" ] || continue
  check_plan_votes "$pf" "$arch"
done <<EOF
$(awk -F"$TAB" '$1 == "PLANDIR" || $1 == "ARCHDIR" { print }' "$PMF")
EOF

if [ "$nerr" -gt 0 ]; then
  echo "ZAMM cross-check failed: $nerr mismatch(es)." >&2
  exit 1
fi
echo "ZAMM cross-check passed."
