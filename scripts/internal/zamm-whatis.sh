#!/bin/sh
# ZAMM whatis — "a search handed me this file; what is it, and does it still
# count?"
#
# Any search - grep, an editor index, a markdown search tool - ranks by
# resemblance and cannot tell a superseded, retired or archived record from
# the one in force. The failure mode is an agent citing history as current.
# This verb takes whatever the search returned - a path, a qmd:// URL, a
# record id, a plan id or a bare slug - finds it in every tree, live and
# archive, and prints the standing the compiler assigned, the chain it
# belongs to and, when the hit is history, the live head and its body. A
# dead record is not dug up: "superseded, here is what replaced it" is the
# answer. Read-only: no compile is published and nothing is written under
# the project.
#
# Usage: zamm-whatis.sh [--project-root <path>] [--brief] <ref>...
#
# Exit: 0 every ref resolved (a file outside the tree resolves too: it is
# reported as ordinary); 1 a ref matched nothing; 4 a tree was unreadable
# or did not compile (fail closed, invariants G3).
set -eu
LC_ALL=C
export LC_ALL

usage() {
  cat <<'USAGE'
Usage: zamm-run.sh whatis [--brief] <path|qmd-url|id|slug>...

  Identify anything a search handed you and say whether it still counts:
  which tree it lives in, its standing (live, dormant, superseded, retired,
  quarantined, erased, archived), the chain it belongs to and - when the
  hit is history - the live head and its body, which is what to cite.
  Plans report Status and progress. Files outside zamm-memory/ are
  reported as ordinary.

  <ref>    a path (any form), a qmd://<collection>/<path> URL, a record id,
           a plan id or a bare slug; a trailing :line[:count] is ignored.
           A slug prints every record that kept that slug; the chain listed
           under any hit is the graph, whatever the slugs along it.
  --brief  standing and chain only, no bodies
USAGE
  exit "${1:-1}"
}

PROJECT_ROOT="$PWD"
BRIEF=0
argc=$#
while [ "$argc" -gt 0 ]; do
  case "$1" in
    --project-root)
      if [ $# -lt 2 ] || [ ! -d "$2" ]; then
        echo "ERROR: --project-root requires an existing path" >&2
        exit 1
      fi
      PROJECT_ROOT=$(cd "$2" && pwd); shift 2; argc=$((argc - 2)) ;;
    --project-root=*)
      PROJECT_ROOT="${1#--project-root=}"
      [ -d "$PROJECT_ROOT" ] || { echo "ERROR: --project-root path does not exist: $PROJECT_ROOT" >&2; exit 1; }
      PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd); shift; argc=$((argc - 1)) ;;
    --brief) BRIEF=1; shift; argc=$((argc - 1)) ;;
    -h|--help) usage 0 ;;
    --) shift; argc=$((argc - 1))
        while [ "$argc" -gt 0 ]; do set -- "$@" "$1"; shift; argc=$((argc - 1)); done ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage 1 ;;
    *) set -- "$@" "$1"; shift; argc=$((argc - 1)) ;;
  esac
done
[ $# -ge 1 ] || { echo "ERROR: whatis needs at least one path, id or slug" >&2; usage 1; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/zamm-paths.sh"
zamm_verify_roots "$PROJECT_ROOT" || exit 4
zamm_verify_no_symlinks "$PROJECT_ROOT" || exit 4
PHYS_ROOT=$(cd "$PROJECT_ROOT" && pwd -P)
MEM="$PROJECT_ROOT/zamm-memory"
TAB=$(printf '\t')

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/zamm-whatis.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT HUP INT TERM
: > "$TMPD/seen"

FAILED=0

# ---------------------------------------------------------------- state rows
# One compile per tree touched, cached for the run, and NEVER called inside a
# command substitution: the compiler's exit 4 (unreadable, not empty) must
# reach the top level and end the run, not vanish in a subshell and leave an
# empty row set that reads as "no such record". Sets ROWS.
rows_for() {
  _rf_t="$1"; ROWS="$TMPD/$_rf_t.rows"
  [ -f "$ROWS" ] && return 0
  if [ ! -d "$MEM/$_rf_t" ]; then
    : > "$ROWS"
    return 0
  fi
  if ! sh "$SCRIPT_DIR/zamm-compile.sh" --project-root "$PROJECT_ROOT" --tree "$_rf_t" --list-state > "$ROWS" 2> "$ROWS.err"; then
    echo "ERROR: the $_rf_t tree did not compile (unreadable, or the compiler could not run); cannot judge standing." >&2
    sed 's/^/  /' "$ROWS.err" >&2
    exit 4
  fi
  # The compiler reads only the HEADER of an archived record (its content
  # must never leak into ranking), so archived rows carry no headline. A
  # chain listing without headlines is unreadable, and this verb is the one
  # place reading the archive is the point: fill them in here.
  while IFS="$TAB" read -r _rf_id _rf_st _rf_rest; do
    [ -n "$_rf_id" ] || continue
    if [ "$_rf_st" = "archived" ]; then
      _rf_p=$(printf '%s\n' "$_rf_rest" | cut -f7)
      _rf_h=$(file_headline "$PROJECT_ROOT/$_rf_p")
      _rf_rest=$(printf '%s\n' "$_rf_rest" | cut -f1-7)
      printf '%s\t%s\t%s\t%s\t-\n' "$_rf_id" "$_rf_st" "$_rf_rest" "${_rf_h:--}"
    else
      printf '%s\t%s\t%s\n' "$_rf_id" "$_rf_st" "$_rf_rest"
    fi
  done < "$ROWS" > "$ROWS.fill"
  mv "$ROWS.fill" "$ROWS"
}

# first paragraph after the frontmatter, joined to one line - the headline
# the compiler would have shown; a pre-v3 note with no frontmatter and a
# title falls back to the title
file_headline() {
  [ -f "$1" ] || return 0
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    { sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
    $0 ~ /^#/ { if (started) exit; title = $0; sub(/^#+[ \t]*/, "", title); exit }
    $0 == "" { if (started) exit; next }
    { started = 1; h = (h == "") ? $0 : h " " $0 }
    END { if (h == "") h = title; gsub(/\t/, " ", h); print h }
  ' "$1"
}

# Was <id> listed by the last published lens of <tree>? 0 yes, 1 no, 2 the
# sidecar is missing or from another compile than the lens (unknown).
listed() {
  case "$1" in
    knowledge) _ls_d="$MEM/.compiled/memory.md";  _ls_s="$MEM/.compiled/state.tsv" ;;
    backlog)   _ls_d="$MEM/.compiled/backlog.md"; _ls_s="$MEM/.compiled/backlog-state.tsv" ;;
    *)         _ls_d="$MEM/.compiled/journal.md"; _ls_s="$MEM/.compiled/journal-state.tsv" ;;
  esac
  [ -f "$_ls_d" ] && [ -f "$_ls_s" ] || return 2
  _ls_sg=$(awk -F"$TAB" '$1 == "generation" { print $2; exit }' "$_ls_s" 2>/dev/null) || return 2
  _ls_ag=$(sed -n 's/^<!-- zamm-generation: \(.*\) -->$/\1/p' "$_ls_d" 2>/dev/null | tail -1)
  [ -n "$_ls_sg" ] && [ "$_ls_sg" = "$_ls_ag" ] || return 2
  awk -F"$TAB" -v id="$2" '$1 == "select" && $2 == id { f = 1 } END { exit f ? 0 : 1 }' "$_ls_s"
}

lens_name() {
  case "$1" in
    knowledge) echo "the digest" ;;
    backlog)   echo "the backlog lens" ;;
    *)         echo "the journal lens" ;;
  esac
}

# body of a record file without its frontmatter, leading blank lines
# dropped, indented for the report
print_body() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    { sub(/\r$/, "") }
    !started && $0 ~ /^[ \t]*$/ { next }
    { started = 1; print "    " $0 }
  ' "$1"
}

# row field <n> of the row for <id> in $ROWS
field() { awk -F"$TAB" -v id="$1" -v n="$2" '$1 == id { print $n; exit }' "$ROWS"; }

# ------------------------------------------------------------ record report
# describe_record <tree> <id> [<note>]; ROWS must already be set for <tree>
describe_record() {
  _dr_t="$1"; _dr_id="$2"; _dr_note="${3-}"
  rows_for "$_dr_t"
  _dr_row=$(awk -F"$TAB" -v id="$_dr_id" '$1 == id { print; exit }' "$ROWS")
  [ -n "$_dr_row" ] || return 1
  _dr_st=$(printf '%s\n' "$_dr_row" | cut -f2)
  _dr_cls=$(printf '%s\n' "$_dr_row" | cut -f3)
  _dr_sc=$(printf '%s\n' "$_dr_row" | cut -f4)
  _dr_cr=$(printf '%s\n' "$_dr_row" | cut -f5)
  _dr_vs=$(printf '%s\n' "$_dr_row" | cut -f6)
  _dr_bg=$(printf '%s\n' "$_dr_row" | cut -f7)
  _dr_path=$(printf '%s\n' "$_dr_row" | cut -f9)
  _dr_hl=$(printf '%s\n' "$_dr_row" | cut -f10)
  _dr_stray=$(printf '%s\n' "$_dr_row" | cut -f11)

  # one report per node, however many refs resolve to it
  if grep -qx "$_dr_t/$_dr_id" "$TMPD/seen"; then
    echo "$_dr_path"
    echo "  see above: the same record"
    return 0
  fi
  echo "$_dr_t/$_dr_id" >> "$TMPD/seen"

  # who supersedes THIS record (reverse edges), with their class
  _dr_by=$(awk -F"$TAB" -v id="$_dr_id" '
    { n = split($8, t, ","); for (i = 1; i <= n; i++) if (t[i] == id) print $1 "\t" $3 "\t" $2 }' "$ROWS")

  # the connected component through applied supersede edges, oldest first;
  # the record-id date prefix makes a plain sort chronological
  _dr_chain=$(awk -F"$TAB" -v start="$_dr_id" '
    {
      st[$1] = $2; cls[$1] = $3; hl[$1] = $10
      n = split($8, t, ",")
      for (i = 1; i <= n; i++) {
        if (t[i] == "" || t[i] == "-") continue
        adj[$1] = adj[$1] " " t[i]; adj[t[i]] = adj[t[i]] " " $1
      }
    }
    END {
      q[1] = start; seen[start] = 1; h = 1; tl = 1
      while (h <= tl) {
        c = q[h++]; m = split(adj[c], a, " ")
        for (i = 1; i <= m; i++) if (a[i] != "" && !(a[i] in seen)) { seen[a[i]] = 1; q[++tl] = a[i] }
      }
      nm = 0
      for (k in seen) mem[++nm] = k
      for (i = 2; i <= nm; i++) { v = mem[i]; j = i - 1; while (j >= 1 && mem[j] > v) { mem[j + 1] = mem[j]; j-- } mem[j + 1] = v }
      for (i = 1; i <= nm; i++) {
        k = mem[i]
        if (k in st) print k "\t" st[k] "\t" cls[k] "\t" hl[k]
        else print k "\tmissing\t-\t(named as a supersede target; no such record in this tree)"
      }
    }' "$ROWS")
  _dr_heads=$(printf '%s\n' "$_dr_chain" | awk -F"$TAB" '
    ($2 == "live" || $2 == "dormant") && $3 != "tombstone" && $3 != "votes" && $3 != "erasure" { print $1 "\t" $4 }')
  _dr_nchain=$(printf '%s\n' "$_dr_chain" | grep -c . || true)

  echo "$_dr_path"
  [ -n "$_dr_note" ] && echo "  note:      $_dr_note"
  _dr_arch=""
  case "$_dr_path" in zamm-memory/archive/*) _dr_arch=", archived" ;; esac
  if [ "$_dr_cls" = "-" ]; then
    echo "  what:      $_dr_t note without frontmatter (pre-v3)$_dr_arch"
  else
    echo "  what:      $_dr_t record ($_dr_cls)$_dr_arch"
  fi
  # A live standing is worded per class: only content records "count now".
  # A tombstone, votes or erasure record in effect is an instrument, and
  # "live - counts now" on a tombstone read as "this idea is in force".
  _dr_content=1
  case "$_dr_cls" in tombstone|votes|erasure) _dr_content=0 ;; esac
  case "$_dr_st" in
    live)
      if [ "$_dr_content" -eq 0 ]; then
        case "$_dr_cls" in
          tombstone) echo "  standing:  tombstone in effect - closes its chain; the idea it retired is withdrawn, not replaced" ;;
          votes)     echo "  standing:  votes record in effect - a plan outcome's votes, counted into ranking; not knowledge" ;;
          erasure)   echo "  standing:  erasure record in effect - the ids it names are redacted" ;;
        esac
      else
        if listed "$_dr_t" "$_dr_id"; then _dr_l="listed in $(lens_name "$_dr_t")"
        elif [ $? -eq 1 ]; then _dr_l="unlisted (below the budget of $(lens_name "$_dr_t")) - still true"
        else _dr_l="listing unknown (recompile: memory digest)"; fi
        echo "  standing:  live - counts now; $_dr_l"
      fi ;;
    dormant)
      echo "  standing:  dormant - live, but decayed below the floor; never listed. Still true unless superseded" ;;
    superseded)
      _dr_byids=$(printf '%s\n' "$_dr_by" | awk -F"$TAB" '$2 != "tombstone" { print $1 }' | paste -sd, - | sed 's/,/, /g')
      echo "  standing:  superseded by $_dr_byids - history; cite the live head below, not this" ;;
    retired)
      _dr_byids=$(printf '%s\n' "$_dr_by" | awk -F"$TAB" '$2 == "tombstone" { print $1 }' | paste -sd, - | sed 's/,/, /g')
      echo "  standing:  retired by tombstone $_dr_byids - withdrawn, not replaced" ;;
    quarantined)
      echo "  standing:  quarantined - invalid record, ignored by the compiler; fix it or supersede it"
      echo "  reason:    $(printf '%s' "$_dr_hl" | sed "s|^$PROJECT_ROOT/||; s|^$PHYS_ROOT/||")" ;;
    erased)
      echo "  standing:  erased - an erasure record names it; use nothing from it and delete the file (the record already retired it)" ;;
    archived)
      echo "  standing:  archived - fully-retired chain moved out of the scan path; history" ;;
    *)
      echo "  standing:  $_dr_st" ;;
  esac
  if [ -n "$_dr_stray" ] && [ "$_dr_stray" != "-" ]; then
    _dr_sk="${_dr_stray%%:*}"
    echo "  warning:   the body opens with \"$_dr_stray\" - a frontmatter key in the body is prose to the compiler:"
    echo "             no $_dr_sk was applied, and this report reflects the graph, not the author's intent."
    echo "             Correct it with a new record carrying the key in its header."
  fi
  # A live content record gets its own detail. History gets the chain and
  # the live head - not its own exhumed metadata and body.
  if [ "$_dr_st" = "live" ] || [ "$_dr_st" = "dormant" ]; then
    if [ "$_dr_content" -eq 1 ]; then
      _dr_meta="  scope: $_dr_sc   created: $_dr_cr   votes: $_dr_vs"
      [ "$_dr_bg" = "yes" ] && _dr_meta="$_dr_meta   background: yes"
      echo "$_dr_meta"
    else
      echo "  created: $_dr_cr"
    fi
    [ -n "$_dr_hl" ] && [ "$_dr_hl" != "-" ] && echo "  headline:  $_dr_hl"
  elif [ "${_dr_nchain:-0}" -le 1 ] && [ "$_dr_st" != "quarantined" ] && [ -n "$_dr_hl" ] && [ "$_dr_hl" != "-" ]; then
    echo "  headline:  $_dr_hl"
  fi
  if [ "${_dr_nchain:-0}" -gt 1 ]; then
    echo "  chain (oldest first):"
    printf '%s\n' "$_dr_chain" | awk -F"$TAB" -v me="$_dr_id" '
      { tag = ($1 == me) ? "  <- this" : ""; printf "    %s  [%s %s]  %s%s\n", $1, $2, $3, $4, tag }'
  fi
  _dr_own_is_head=0
  printf '%s\n' "$_dr_heads" | awk -F"$TAB" -v id="$_dr_id" '$1 == id { f = 1 } END { exit f ? 0 : 1 }' && _dr_own_is_head=1
  if [ "$_dr_own_is_head" -eq 0 ]; then
    if [ -n "$_dr_heads" ]; then
      printf '%s\n' "$_dr_heads" | awk -F"$TAB" '{ printf "  live head: %s  %s\n", $1, $2 }'
    else
      echo "  live head: none - nothing in this chain is in force"
    fi
  fi
  [ "$BRIEF" -eq 1 ] && return 0
  if [ "$_dr_own_is_head" -eq 1 ]; then
    echo "  body:"
    print_body "$PROJECT_ROOT/$_dr_path"
    return 0
  fi
  if [ "$_dr_st" = "live" ] && [ "$_dr_cls" = "tombstone" ]; then
    echo "  reason:"
    print_body "$PROJECT_ROOT/$_dr_path"
  fi
  if [ "$_dr_st" = "retired" ]; then
    printf '%s\n' "$_dr_by" | awk -F"$TAB" '$2 == "tombstone" { print $1 }' | while IFS= read -r _dr_tid; do
      [ -n "$_dr_tid" ] || continue
      _dr_tp=$(field "$_dr_tid" 9)
      [ -n "$_dr_tp" ] && [ -f "$PROJECT_ROOT/$_dr_tp" ] || continue
      echo "  retired because ($_dr_tid):"
      print_body "$PROJECT_ROOT/$_dr_tp"
    done
  fi
  printf '%s\n' "$_dr_heads" | while IFS="$TAB" read -r _dr_hid _; do
    [ -n "$_dr_hid" ] || continue
    _dr_hp=$(field "$_dr_hid" 9)
    [ -n "$_dr_hp" ] && [ -f "$PROJECT_ROOT/$_dr_hp" ] || continue
    echo "  in force now ($_dr_hid):"
    print_body "$PROJECT_ROOT/$_dr_hp"
  done
  return 0
}

# -------------------------------------------------------------- plan report
# Sets PLANS_MF; never called inside a substitution (same reason as rows_for)
plan_manifest() {
  PLANS_MF="$TMPD/plans.mf"
  [ -f "$PLANS_MF" ] && return 0
  if ! sh "$SCRIPT_DIR/zamm-plan-manifest.sh" --project-root "$PROJECT_ROOT" > "$PLANS_MF"; then
    echo "ERROR: cannot enumerate the plan tree (unreadable, not empty)." >&2
    exit 4
  fi
  if grep -q "^MISSING${TAB}" "$PLANS_MF"; then
    echo "ERROR: a plan root is missing (structural damage, not an empty project)." >&2
    exit 4
  fi
}

# describe_plan <abs plan file> <rel path of the ref> <kind line>
describe_plan() {
  _dp_pf="$1"; _dp_rel="$2"; _dp_kind="$3"
  _dp_dir=$(dirname "$_dp_pf")
  _dp_id=$(basename "$_dp_pf" .plan.md)
  _dp_progress=$(awk '
    { sub(/\r$/, "") }
    $0 == "## Done-when" || substr($0,1,13) == "## Done-when " || substr($0,1,13) == "## Done-when\t" { dw = 1; next }
    dw && /^## / { dw = 0 }
    dw && /^- \[[xX]\]/ { done++ }
    dw && /^- \[[ xX]\]/ { total++ }
    END { printf "%d/%d", done + 0, total + 0 }
  ' "$_dp_pf")
  _dp_status=$(sed -n 's/^Status:[[:space:]]*//p' "$_dp_pf" | head -1)
  _dp_upd=$(sed -n 's/^Last updated:[[:space:]]*//p' "$_dp_pf" | head -1)
  _dp_title=$(sed -n 's/^# //p' "$_dp_pf" | head -1)
  echo "$_dp_rel"
  echo "  what:      $_dp_kind"
  case "$_dp_dir" in
    */archive/plans/*)
      echo "  standing:  archived plan (Status: ${_dp_status:-?}) - finished work; history, never the active plan" ;;
    *)
      case "$_dp_status" in
        Done|Abandoned) echo "  standing:  active tree, terminal (Status: $_dp_status) - archive-ready; not current work" ;;
        Draft|Implementing|Review) echo "  standing:  active plan (Status: $_dp_status) - current work; its Status outranks any record" ;;
        *) echo "  standing:  active tree, Status: ${_dp_status:-missing} (unknown; plan check)" ;;
      esac ;;
  esac
  echo "  plan:      ${_dp_dir#"$PROJECT_ROOT/"}   done-when: $_dp_progress   last updated: ${_dp_upd:-n/a}"
  [ -n "$_dp_title" ] && echo "  title:     $_dp_title"
  [ "$BRIEF" -eq 1 ] && return 0
  echo "  head (through the first section; plan show $_dp_id for the whole plan):"
  awk '{ sub(/\r$/, "") } NR > 1 && /^## / { exit } { print "    " $0 }' "$_dp_pf"
}

# plan_for_dir <abs plan dir> -> main plan file from the manifest, or empty
plan_for_dir() {
  awk -F"$TAB" -v d="$1/" '($1 == "PLANFILE" || $1 == "ARCHFILE") && index($2, d) == 1 { print $2; exit }' "$PLANS_MF"
}

# describe_plan_path <rel path under active/plans or archive/plans>
describe_plan_path() {
  _pp_rel="$1"
  plan_manifest
  case "$_pp_rel" in
    zamm-memory/active/plans/*)  _pp_rest="${_pp_rel#zamm-memory/active/plans/}" ;;
    *)                           _pp_rest="${_pp_rel#zamm-memory/archive/plans/}" ;;
  esac
  _pp_dname="${_pp_rest%%/*}"
  _pp_dir="$PROJECT_ROOT/${_pp_rel%"$_pp_rest"}$_pp_dname"
  _pp_pf=$(plan_for_dir "$_pp_dir")
  if [ -z "$_pp_pf" ]; then
    echo "$_pp_rel"
    echo "  what:      inside the plan tree, but ${_pp_dir#"$PROJECT_ROOT/"} has no readable main plan file (plan check)"
    return 1
  fi
  _pp_abs="$PROJECT_ROOT/$_pp_rel"
  if [ "$_pp_abs" = "$_pp_pf" ]; then
    describe_plan "$_pp_pf" "$_pp_rel" "plan (main file)"
  else
    case "$_pp_rest" in
      */workdir/*) describe_plan "$_pp_pf" "$_pp_rel" "plan scratch (workdir/ - working files, not a record and not the plan's word)" ;;
      *.subplan-*.plan.md) describe_plan "$_pp_pf" "$_pp_rel" "subplan of the plan below" ;;
      *) describe_plan "$_pp_pf" "$_pp_rel" "a file inside a plan directory (not the plan itself)" ;;
    esac
  fi
}

# --------------------------------------------------------------- resolution
# find_records <needle> <outfile>: "tree<TAB>id" per match, every tree
find_records() {
  : > "$2"
  for _fr_t in knowledge backlog journal; do
    rows_for "$_fr_t"
    awk -F"$TAB" -v n="$1" -v t="$_fr_t" '
      {
        id = $1
        s = (length(id) > 17) ? substr(id, 12, length(id) - 17) : ""
        if (id == n || s == n) print t "\t" id
      }' "$ROWS" | sort >> "$2"
  done
}

# find_plans <needle> <outfile>: main plan file paths matching id or slug
find_plans() {
  plan_manifest
  awk -F"$TAB" -v n="$1" '
    $1 == "PLANFILE" || $1 == "ARCHFILE" {
      p = $2; k = split(p, pp, "/"); b = pp[k]; sub(/\.plan\.md$/, "", b)
      s = b; sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/, "", s)
      if (b == n || s == n) print p
    }' "$PLANS_MF" > "$2"
}

# by_needle <needle> [<note>]: every record and plan the needle names
by_needle() {
  _bn="$1"; _bn_note="${2-}"
  find_records "$_bn" "$TMPD/recs"
  find_plans "$_bn" "$TMPD/plans"
  if [ ! -s "$TMPD/recs" ] && [ ! -s "$TMPD/plans" ]; then
    echo "zamm: nothing named \"$_bn\" in any tree (knowledge, backlog, journal, plans; live or archived)." >&2
    echo "  A search hit that no longer exists here may have been erased; a docid (#abc123) is the search tool's, pass the path beside it." >&2
    FAILED=1
    return 0
  fi
  _bn_first=1
  while IFS="$TAB" read -r _bn_t _bn_id; do
    [ -n "$_bn_id" ] || continue
    [ "$_bn_first" -eq 1 ] || echo
    _bn_first=0
    describe_record "$_bn_t" "$_bn_id" "$_bn_note" || true
  done < "$TMPD/recs"
  while IFS= read -r _bn_pf; do
    [ -n "$_bn_pf" ] || continue
    [ "$_bn_first" -eq 1 ] || echo
    _bn_first=0
    describe_plan "$_bn_pf" "${_bn_pf#"$PROJECT_ROOT/"}" "plan (main file)"
  done < "$TMPD/plans"
}

unenumerated() {
  echo "$1"
  echo "  what:      under zamm-memory/$2/ but the compiler does not enumerate it (name or location outside the record contract; $2 check)"
  FAILED=1
}

# by_path <ref as given>
by_path() {
  _bp="$1"
  case "$_bp" in
    /*) _bp_abs="$_bp" ;;
    *)
      if [ -e "$PWD/$_bp" ]; then _bp_abs="$PWD/$_bp"
      else _bp_abs="$PROJECT_ROOT/$_bp"; fi ;;
  esac
  # physical form, so a project reached through a symlink still matches
  _bp_dir=$(dirname "$_bp_abs"); _bp_base=$(basename "$_bp_abs")
  if _bp_pd=$(cd "$_bp_dir" 2>/dev/null && pwd -P); then _bp_abs="$_bp_pd/$_bp_base"; fi
  case "$_bp_abs" in
    "$PROJECT_ROOT"/*) _bp_rel="${_bp_abs#"$PROJECT_ROOT"/}" ;;
    "$PHYS_ROOT"/*)    _bp_rel="${_bp_abs#"$PHYS_ROOT"/}" ;;
    *)
      echo "$_bp"
      echo "  what:      outside this project ($PROJECT_ROOT) - not a ZAMM record; pass --project-root if the ledger lives elsewhere"
      return 0 ;;
  esac
  if [ ! -e "$_bp_abs" ]; then
    # Stale search index: the file moved (memory archive, plan archive) or
    # was erased. Fall back to the name, which is the id, across every tree.
    case "$_bp_base" in
      *.plan.md)
        by_needle "${_bp_base%.plan.md}" "$_bp_rel does not exist here (archived since the search indexed it); resolved by name"
        return 0 ;;
      *.md)
        by_needle "${_bp_base%.md}" "$_bp_rel does not exist here (moved or erased since the search indexed it); resolved by name"
        return 0 ;;
    esac
  fi
  case "$_bp_rel" in
    zamm-memory/.compiled/*)
      echo "$_bp_rel"
      echo "  what:      generated lens (rebuilt by every compile) - never a source; cite the records it names, and read it only through memory digest / backlog list / journal digest" ;;
    zamm-memory/knowledge/*.md.draft|zamm-memory/backlog/*.md.draft|zamm-memory/journal/*.md.draft)
      echo "$_bp_rel"
      echo "  what:      unpublished hand-written draft - not a record yet; memory publish lands it, memory discard drops it" ;;
    zamm-memory/knowledge/*.md|zamm-memory/archive/knowledge/*.md)
      describe_record knowledge "${_bp_base%.md}" || unenumerated "$_bp_rel" knowledge ;;
    zamm-memory/backlog/*.md|zamm-memory/archive/backlog/*.md)
      describe_record backlog "${_bp_base%.md}" || unenumerated "$_bp_rel" backlog ;;
    zamm-memory/journal/*.md|zamm-memory/archive/journal/*.md)
      describe_record journal "${_bp_base%.md}" || unenumerated "$_bp_rel" journal ;;
    zamm-memory/active/plans/*|zamm-memory/archive/plans/*)
      describe_plan_path "$_bp_rel" || FAILED=1 ;;
    zamm-memory/*)
      echo "$_bp_rel"
      echo "  what:      part of the ZAMM tree, not a record (VERSION, a year directory, ...); nothing to judge" ;;
    *)
      echo "$_bp_rel"
      echo "  what:      ordinary project file, not a ZAMM record - nothing to judge; read it like any doc" ;;
  esac
}

nref=0
for ref in "$@"; do
  nref=$((nref + 1))
  [ "$nref" -eq 1 ] || echo
  if [ -z "$ref" ]; then
    echo "zamm: an empty ref (an unquoted empty variable?) names nothing." >&2
    FAILED=1
    continue
  fi
  r="$ref"
  case "$r" in
    qmd://*) r="${r#qmd://}"; r="${r#*/}" ;;
  esac
  case "$r" in
    '#'*)
      echo "$ref"
      echo "  what:      a search tool's docid, not a path; pass the path printed beside it"
      FAILED=1
      continue ;;
  esac
  # trailing :line or :line:count, as search tools print them
  r=$(printf '%s' "$r" | sed 's/:[0-9][0-9]*$//; s/:[0-9][0-9]*$//')
  case "$r" in
    */*|*.md|*.md.draft) by_path "$r" ;;
    *) by_needle "$r" ;;
  esac
done
exit "$FAILED"
