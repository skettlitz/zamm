#!/bin/sh
# ZAMM run — the single entrypoint. Everything else is reached through here.
#
# Usage: zamm-run.sh [--project-root <path>] <command> [args...]
#
# One command means one permission-allowlist entry instead of six, and one
# place to resolve the project root — so callers never pass --project-root
# just to avoid resolving against the wrong tree from a subdirectory.
#
# Four verbs mean the same thing in both groups: list, show, check, create.
# Delegation is `exec`, so exit codes, signals and environment (ZAMM_TODAY
# included) pass through untouched. Read-only views are built in here; every
# mutation and every gate lives in its own script.

set -eu
LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The other scripts are internal implementation, not a user surface: everything
# is reached through this one entrypoint (one permission-allowlist entry). They
# live in scripts/internal/; only zamm-run.sh sits at the top of scripts/.
INTERNAL="$SCRIPT_DIR/internal"

die() { echo "zamm: $*" >&2; exit 1; }

# 0 if $1 is a real Gregorian YYYY-MM-DD date (leap years respected). A single
# leading-zero strip keeps 2-digit fields base-10 without emptying "00".
valid_ymd() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  _y=${1%%-*}; _r=${1#*-}; _m=${_r%%-*}; _d=${_r#*-}
  _m=${_m#0}; _d=${_d#0}
  [ -n "$_m" ] && [ -n "$_d" ] || return 1
  [ "$_m" -ge 1 ] && [ "$_m" -le 12 ] || return 1
  [ "$_d" -ge 1 ] || return 1
  case "$_m" in
    4|6|9|11) _dim=30 ;;
    2) if { [ $((_y % 4)) -eq 0 ] && [ $((_y % 100)) -ne 0 ]; } || [ $((_y % 400)) -eq 0 ]
       then _dim=29; else _dim=28; fi ;;
    *) _dim=31 ;;
  esac
  [ "$_d" -le "$_dim" ]
}

usage() {
  cat <<'EOF'
Usage: zamm-run.sh [--project-root <path>] <command> [args...]

Project
  scaffold             install ZAMM here, or refresh the rendered surfaces
  status               health overview: ledger, plans, drift
  check                validate everything (memory + plans)
  help [<topic>]       this text, or help for one command

Memory
  memory digest        rebuild and print the digest
  memory list          index of live records, slug first
  memory show <slug>   one record in full
  memory check         validate the ledger
  memory create <slug> new record
  memory archive       move fully-retired chains out of the scan path

Plans
  plan list            active plans grouped by status
  plan show <slug>     one plan, with progress
  plan check           validate active plans
  plan create <title>  new plan directory and file
  plan archive         move terminal plans to the archive

The project root is found automatically: the nearest ancestor holding a
zamm-memory/ directory, else the git top level. Pass --project-root <path>
to override it.
EOF
  exit "${1:-0}"
}

group_usage() {
  case "$1" in
    memory) cat <<'EOF'
Usage: zamm-run.sh memory <command> [args...]

  digest               rebuild and print the digest
  list [--all] [--scope <area>]
                       index of live records (default: those in the digest)
  show <slug|id>       one record in full
  check                validate the ledger, write nothing
  create <slug>        new record
  archive [--dry-run]  move fully-retired chains out of the scan path
EOF
      ;;
    plan) cat <<'EOF'
Usage: zamm-run.sh plan <command> [args...]

  list                 active plans grouped by status
  show <slug>          one plan, with Done-when progress
  check                validate active plans
  create <title>       new plan directory and file
  archive              move terminal plans to the archive
EOF
      ;;
  esac
  exit "${2:-0}"
}

unknown() {
  echo "zamm: unknown command: $*" >&2
  echo "Run 'zamm-run.sh help' for the command list." >&2
  exit 2
}

# ---- pull --project-root out of the argument list, wherever it appears ----
# Rotating each kept argument to the end preserves order while dropping the
# flag, so it works before or after the subcommand.
PROJECT_ROOT_ARG=""
argc=$#
while [ "$argc" -gt 0 ]; do
  case "$1" in
    --project-root)
      [ $# -ge 2 ] || die "--project-root requires a path"
      # an explicitly-given but empty path must error, not silently fall
      # through to auto-discovery (a confused deputy when a caller expands an
      # unset variable into the argument)
      [ -n "$2" ] || die "--project-root requires a non-empty path"
      PROJECT_ROOT_ARG="$2"; shift 2; argc=$((argc - 2)) ;;
    --project-root=*)
      PROJECT_ROOT_ARG="${1#--project-root=}"; shift; argc=$((argc - 1))
      [ -n "$PROJECT_ROOT_ARG" ] || die "--project-root= requires a non-empty path" ;;
    *)
      set -- "$@" "$1"; shift; argc=$((argc - 1)) ;;
  esac
done

resolve_root() {
  dir=""
  if [ -n "$PROJECT_ROOT_ARG" ]; then
    [ -d "$PROJECT_ROOT_ARG" ] ||
      die "--project-root path does not exist: $PROJECT_ROOT_ARG"
    (cd "$PROJECT_ROOT_ARG" && pwd)
    return 0
  fi
  dir=$PWD
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -d "$dir/zamm-memory" ]; then printf '%s\n' "$dir"; return 0; fi
    dir=$(dirname "$dir")
  done
  if top=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ]; then
    printf '%s\n' "$top"; return 0
  fi
  return 1
}

require_root() {
  if ! ROOT=$(resolve_root); then
    echo "zamm: cannot find a project root." >&2
    echo "  looked for: a zamm-memory/ directory in $PWD or any parent," >&2
    echo "              then the git top level." >&2
    echo "  Pass --project-root <path>, or run 'zamm-run.sh scaffold' to" >&2
    echo "  install ZAMM here." >&2
    exit 1
  fi
}

# scaffold installs INTO a project that may not have zamm-memory/ yet, so a
# failed lookup falls back to the working directory instead of erroring.
root_or_cwd() { ROOT=$(resolve_root) || ROOT=$PWD; }

# ---------------- built-in read-only views ----------------

digest_field() { sed -n '1s/.*[( ]'"$1"'=\([0-9][0-9]*\).*/\1/p' "$DIGEST" 2>/dev/null; }

print_status() {
  DIGEST="$ROOT/zamm-memory/.compiled/memory.md"
  version=$(sed -n '1p' "$ROOT/zamm-memory/VERSION" 2>/dev/null | tr -d '[:space:]')
  stamp=$(sed -n 's/.*SKILL-BLOCK:zamm:BEGIN version=\([^ ]*\).*/\1/p' \
    "$ROOT/AGENTS.md" 2>/dev/null | head -1)

  printf 'ZAMM      version %s   root %s\n' "${version:-unknown}" "$ROOT"
  # Recompute the SAME content stamp scaffold wrote, so a skill tree edited
  # since the last scaffold (git checkout included) reads STALE.
  current=""
  if [ -f "$INTERNAL/zamm-skill-stamp.sh" ]; then
    current=$(sh "$INTERNAL/zamm-skill-stamp.sh" 2>/dev/null || true)
  fi
  if [ -z "$stamp" ]; then
    printf '          rendered surfaces: none found (run: zamm-run.sh scaffold)\n'
  elif [ -n "$current" ] && [ "$stamp" != "$current" ]; then
    printf '          rendered surfaces: %s -- STALE, skill is %s\n' "$stamp" "$current"
    printf '          run: zamm-run.sh scaffold\n'
  else
    printf '          rendered surfaces: %s\n' "$stamp"
  fi
  echo

  if [ ! -f "$DIGEST" ]; then
    echo 'Ledger    no compiled digest'
    echo '          run: zamm-run.sh memory digest'
  else
    printf 'Ledger    %s records, %s live, %s quarantined\n' \
      "$(digest_field files)" "$(digest_field live)" "$(digest_field quarantined)"
    dormant=$(sed -n 's/^Dormant (.*): //p' "$DIGEST" | head -1)
    [ -n "$dormant" ] && printf '          dormant: %s\n' "$dormant"
    unlisted=$(sed -n 's/^Unlisted live (.*): //p' "$DIGEST" | head -1)
    [ -n "$unlisted" ] && printf '          unlisted (below budget): %s\n' "$unlisted"
    printf '          guardrails: %s/15\n' "$(grep -c '^- !' "$DIGEST" 2>/dev/null || echo 0)"
    other=$(sed -n 's/^Other: \([0-9][0-9]*\) record.*/\1/p' "$DIGEST" | head -1)
    [ -n "$other" ] && printf '          other backlog: %s/5\n' "$other"
    if grep -q '^## Needs reconciliation' "$DIGEST" 2>/dev/null; then
      printf '          RECONCILIATION PENDING: %s group(s)\n' "$(grep -c '^### Heads of' "$DIGEST")"
    fi
    # The digest embeds active plans as well as knowledge records, so a plan
    # edited after the last compile makes it stale too — watch both trees.
    newer=$(find "$ROOT/zamm-memory/knowledge" "$ROOT/zamm-memory/active/plans" \
      -type f -name '*.md' -newer "$DIGEST" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${newer:-0}" -gt 0 ]; then
      printf '          STALE: %s file(s) newer than the digest\n' "$newer"
      echo '          run: zamm-run.sh memory digest'
    fi
    ninert=$(sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --list-inert 2>/dev/null | grep -c . || true)
    [ "${ninert:-0}" -gt 0 ] &&
      printf '          %s in fully-retired chains (zamm-run.sh memory archive)\n' "$ninert"
  fi
  echo

  plans_dir="$ROOT/zamm-memory/active/plans"
  total=0; terminal=0; summary=""
  for st in Draft Implementing Review Done Abandoned; do
    n=0
    for pd in "$plans_dir"/*/; do
      [ -d "$pd" ] || continue
      pf=$(find "$pd" -maxdepth 1 -type f -name '*.plan.md' ! -name '*.subplan-*' 2>/dev/null | sort | head -1)
      [ -n "$pf" ] || continue
      s=$(sed -n 's/^Status:[[:space:]]*//p' "$pf" | head -1 | awk '{print $1}')
      [ "$s" = "$st" ] && n=$((n + 1))
    done
    total=$((total + n))
    [ "$n" -gt 0 ] && summary="$summary$n $(echo "$st" | tr 'A-Z' 'a-z'), "
    case "$st" in Done|Abandoned) terminal=$((terminal + n)) ;; esac
  done
  if [ "$total" -eq 0 ]; then
    echo 'Plans     none active'
  else
    printf 'Plans     %s\n' "$(echo "$summary" | sed 's/, $//')"
    [ "$terminal" -gt 0 ] &&
      printf '          ARCHIVE-READY: %s (zamm-run.sh plan archive)\n' "$terminal"
  fi
  narch=0
  for ad in "$ROOT/zamm-memory/archive/plans"/*/; do [ -d "$ad" ] && narch=$((narch + 1)); done
  printf '          archived: %s\n' "$narch"
}

memory_list() {
  show_all=0; want_scope=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) show_all=1; shift ;;
      --scope)
        [ $# -ge 2 ] || die "--scope requires an area"
        [ -n "$2" ] || die "--scope requires a non-empty area"
        want_scope="$2"; shift 2 ;;
      --scope=*)
        want_scope="${1#--scope=}"
        [ -n "$want_scope" ] || die "--scope= requires a non-empty area"
        shift ;;
      -h|--help) group_usage memory 0 ;;
      *) die "memory list: unknown argument: $1" ;;
    esac
  done
  DIGEST="$ROOT/zamm-memory/.compiled/memory.md"
  # Default view is what is actually influencing the agent: the records the
  # digest lists. --all adds the unlisted and dormant tail.
  filter=""
  if [ "$show_all" -eq 0 ]; then
    [ -f "$DIGEST" ] || die "no digest yet; run: zamm-run.sh memory digest"
    filter=$(grep -oE '\[[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+' "$DIGEST" | tr -d '[' | sort -u)
  fi
  tab=$(printf '\t')
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --list-live |
  while IFS="$tab" read -r id primary alltags headline; do
    [ -n "$id" ] || continue
    if [ "$show_all" -eq 0 ]; then
      printf '%s\n' "$filter" | grep -qx "$id" || continue
    fi
    if [ -n "$want_scope" ]; then
      # match the requested area against ANY tag — the data model calls
      # secondary tags "selection doors", so a browse must see them too. The
      # primary keeps its optional /subpath; secondaries are bare areas.
      matched=0
      old_ifs=$IFS; IFS=,
      for tag in $alltags; do
        case "$tag" in "$want_scope"|"$want_scope"/*) matched=1; break ;; esac
      done
      IFS=$old_ifs
      [ "$matched" -eq 1 ] || continue
    fi
    slug=$(printf '%s' "$id" | sed 's/^[0-9-]\{11\}//; s/-[a-z0-9]\{5\}$//')
    # display the primary scope (the record's home); all tags were used above
    printf '%-22s %-34s %s\n' "$primary" "$slug" "$(printf '%s' "$headline" | cut -c1-72)"
  done
}

resolve_record() {
  # <slug|id> -> exactly one path, or list candidates and exit non-zero
  needle="$1"
  matches=$(find "$ROOT/zamm-memory/knowledge" "$ROOT/zamm-memory/archive/knowledge" \
    -type f -name '*.md' ! -name 'shun.md' 2>/dev/null |
    while IFS= read -r f; do
      b=$(basename "$f" .md)
      s=$(printf '%s' "$b" | sed 's/^[0-9-]\{11\}//; s/-[a-z0-9]\{5\}$//')
      # if/then, not `[ ] && ...`: a failing test as the last command of an
      # AND-OR list trips set -e and kills the loop on the first non-match
      if [ "$b" = "$needle" ] || [ "$s" = "$needle" ]; then
        printf '%s\n' "$f"
      fi
    done)
  n=$(printf '%s\n' "$matches" | grep -c . || true)
  if [ "${n:-0}" -eq 0 ]; then
    echo "zamm: no record matches \"$needle\"" >&2
    echo "  try: zamm-run.sh memory list --all" >&2
    exit 1
  fi
  if [ "$n" -gt 1 ]; then
    # Superseding records reuse the slug, so ambiguity is usually a chain.
    # Listing the generations IS the answer to "why did this change?".
    echo "zamm: \"$needle\" matches $n records:" >&2
    printf '%s\n' "$matches" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      echo "  $(basename "$f" .md)" >&2
    done
    echo "  Use the full id to pick one." >&2
    exit 1
  fi
  printf '%s\n' "$matches"
}

memory_show() {
  case "${1-}" in -h|--help) group_usage memory 0 ;; esac
  [ $# -ge 1 ] || die "memory show: need a slug or record id"
  [ $# -le 1 ] || die "memory show: too many arguments (one slug or id)"
  path=$(resolve_record "$1")
  rel="${path#"$ROOT/"}"
  case "$rel" in
    */archive/knowledge/*) echo "# $rel  (ARCHIVED - fully-retired chain)" ;;
    *) echo "# $rel" ;;
  esac
  echo
  cat "$path"
}

plan_show() {
  case "${1-}" in -h|--help) group_usage plan 0 ;; esac
  [ $# -ge 1 ] || die "plan show: need a plan slug"
  [ $# -le 1 ] || die "plan show: too many arguments (one slug)"
  needle="$1"
  all=$(find "$ROOT/zamm-memory/active/plans" "$ROOT/zamm-memory/archive/plans" \
    -maxdepth 2 -type f -name '*.plan.md' ! -name '*.subplan-*' 2>/dev/null)

  # Tiered resolution, the same precedence resolve_record uses for records:
  # an exact plan id wins, then an exact slug, and only then a substring match.
  # Ambiguity is reported within the FIRST tier that matches anything, so
  # `plan show alpha` resolves the plan `alpha` even when `alpha-beta` exists —
  # the old substring-only match called that a two-way tie.
  matches=""
  for tier in id slug substr; do
    matches=$(printf '%s\n' "$all" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      b=$(basename "$f" .plan.md)
      s=$(printf '%s' "$b" | sed 's/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-//')
      # leading ( on every pattern: inside $( ), a bare case-pattern ) closes
      # the command substitution in POSIX parsers
      case "$tier" in
        (id)   if [ "$b" = "$needle" ]; then printf '%s\n' "$f"; fi ;;
        (slug) if [ "$s" = "$needle" ]; then printf '%s\n' "$f"; fi ;;
        (substr) case "$b" in (*"$needle"*) printf '%s\n' "$f" ;; esac ;;
      esac
    done)
    [ -n "$matches" ] && break
  done
  n=$(printf '%s\n' "$matches" | grep -c . || true)
  [ "${n:-0}" -eq 0 ] && die "no plan matches \"$needle\""
  if [ "$n" -gt 1 ]; then
    echo "zamm: \"$needle\" matches $n plans:" >&2
    printf '%s\n' "$matches" | while IFS= read -r f; do
      [ -n "$f" ] && echo "  $(basename "$f" .plan.md)" >&2
    done
    echo "  Use the full plan id to pick one." >&2
    exit 1
  fi
  pf="$matches"
  # Count checkboxes ONLY inside the ## Done-when section (exact heading, not a
  # prefix), and only valid markers — a checkbox under ## Approach must not
  # inflate the total, and `[?]` is not a done item.
  progress=$(awk '
    $0 == "## Done-when" || substr($0,1,13) == "## Done-when " || substr($0,1,13) == "## Done-when\t" { dw = 1; next }
    dw && /^## / { dw = 0 }
    dw && /^- \[[xX]\]/ { done++ }
    dw && /^- \[[ xX]\]/ { total++ }
    END { printf "%d/%d", done + 0, total + 0 }
  ' "$pf")
  echo "# ${pf#"$ROOT/"}"
  printf 'Status: %s   Done-when: %s\n' \
    "$(sed -n 's/^Status:[[:space:]]*//p' "$pf" | head -1)" "$progress"
  case "$pf" in */archive/plans/*) echo "(archived)" ;; esac
  echo
  cat "$pf"
}

plan_create() {
  # --help in ANY position is help, never a title: `plan create T --help`
  # otherwise created a plan literally titled "T --help".
  for a in "$@"; do
    case "$a" in -h|--help) group_usage plan 0 ;; esac
  done
  [ $# -ge 1 ] || die "plan create: need a title"
  title="$*"
  # The title becomes the `# <title>` heading line: it must stay ONE line, or a
  # newline injects further document structure (a second `Status: Done` line
  # ahead of the template's `Status: Draft`, which the raw archive helper then
  # reads as archive-ready).
  nl=$(printf '\nx'); nl=${nl%x}
  cr=$(printf '\rx'); cr=${cr%x}
  case "$title" in
    *"$nl"*|*"$cr"*) die "plan create: title must be a single line" ;;
  esac
  slug=$(printf '%s' "$title" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' |
    sed 's/^-*//; s/-*$//' | cut -c1-60)
  [ -n "$slug" ] || die "plan create: title produced an empty slug"
  today=${ZAMM_TODAY:-$(date +%Y-%m-%d)}
  valid_ymd "$today" || die "plan create: refusing an impossible date: $today"
  plans="$ROOT/zamm-memory/active/plans"
  dir="$plans/$today-$slug"
  [ -e "$dir" ] && die "plan already exists: ${dir#"$ROOT/"}"
  # ZAMM_PLAN_TEMPLATE overrides the template path (test-only seam, like
  # ZAMM_TODAY): it lets a test inject a template that renders an invalid plan
  # and exercise the validate-then-cleanup path. Unset in normal use.
  template="${ZAMM_PLAN_TEMPLATE:-$SCRIPT_DIR/../references/templates/plan.template.md}"
  [ -f "$template" ] || die "missing plan template: $template"

  # Build the whole plan directory privately, then publish it with one atomic
  # rename. The title is DATA, never a program: the old `sed "s|...|# $title|"`
  # let a title containing the sed delimiter, `&`, or a backslash corrupt the
  # command (a title like "R&D | Ops" made sed exit non-zero AFTER mkdir, so a
  # broken plan directory and an empty .plan.md were left behind — and a plan
  # with no Status: line then failed `plan check` for the whole project). Here
  # the title reaches awk through the environment (no -v escape processing),
  # and nothing is placed under active/plans/ until the rendered file passes
  # validation.
  mkdir -p "$plans"
  tmp=$(mktemp -d "$plans/.tmp-plan-XXXXXX") ||
    die "plan create: could not create a temporary directory"
  # cleanup on ANY non-success exit or signal; disarmed after the rename
  trap 'rm -rf "$tmp"' EXIT HUP INT TERM
  mkdir "$tmp/workdir"
  pf="$tmp/$today-$slug.plan.md"
  ZAMM_PLAN_TITLE="$title" awk -v today="$today" '
    $0 == "# <Plan title>"             { print "# " ENVIRON["ZAMM_PLAN_TITLE"]; next }
    $0 == "Last updated: <YYYY-MM-DD>" { print "Last updated: " today; next }
    { print }
  ' "$template" > "$pf"

  # validate the rendered result BEFORE anything lands in active/plans/
  [ -s "$pf" ] || die "plan create: rendered an empty plan file"
  grep -q '^Status: Draft' "$pf" ||
    die "plan create: rendered plan is missing 'Status: Draft'"
  if grep -q '<Plan title>' "$pf"; then
    die "plan create: title placeholder was not substituted"
  fi

  # re-check for a collision that appeared while rendering, then publish
  [ -e "$dir" ] && die "plan already exists: ${dir#"$ROOT/"}"
  mv "$tmp" "$dir"
  trap - EXIT HUP INT TERM

  echo "${dir#"$ROOT/"}/$today-$slug.plan.md"
  echo "Created. Fill Scope and Done-when, then set Status: Implementing." >&2
}

run_check_all() {
  rc=0
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --check || rc=1
  sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" || rc=1
  exit "$rc"
}

# `help [topic...]` — read-only usage for any command, exit 0. It NEVER
# dispatches a verb. Built-in views print inline usage; delegated commands
# forward --help to their own script, each of which parses --help before any
# mutation. The old mechanism rewrote `help X` to `X --help` and dispatched
# normally, so `help plan create` reached the plan_create built-in, which read
# --help as the title and created a plan directory literally named for it.
# Help must be observably read-only, so routing is explicit here rather than
# trusting every verb to treat --help as help.
do_help() {
  case "${1:-}" in
    "") usage 0 ;;
    memory)
      case "${2:-}" in
        digest|check) exec sh "$INTERNAL/zamm-compile.sh" --help ;;
        create)       exec sh "$INTERNAL/zamm-new-memory.sh" --help ;;
        archive)      exec sh "$INTERNAL/zamm-memory-archive.sh" --help ;;
        *)            group_usage memory 0 ;;  # incl. list/show (built-in views)
      esac
      ;;
    plan)
      case "${2:-}" in
        list)    exec bash "$INTERNAL/zamm-status.sh" --help ;;
        check)   exec sh "$INTERNAL/zamm-plan-check.sh" --help ;;
        archive) exec bash "$INTERNAL/zamm-archive.sh" --help ;;
        *)       group_usage plan 0 ;;          # incl. show/create (built-in)
      esac
      ;;
    scaffold) exec bash "$INTERNAL/zamm-scaffold.sh" --help ;;
    *)        usage 0 ;;                        # status, check, help, unknown
  esac
}

# ---------------- dispatch ----------------

[ $# -gt 0 ] || usage 0

# `help`, `--help`, `-h` at the top route to the read-only help printer and
# never fall through to dispatch — see do_help for why the old rewrite was
# unsafe.
case "$1" in
  help|--help|-h) shift; do_help "$@" ;;
esac

cmd="$1"; shift
INTERP="sh"
TARGET=""

case "$cmd" in
  memory)
    [ $# -gt 0 ] || group_usage memory 0
    verb="$1"; shift
    case "$verb" in
      digest)
        # --help must reach the user, not the /dev/null the compile output goes to
        case "${1-}" in
          -h|--help) exec sh "$INTERNAL/zamm-compile.sh" --help ;;
        esac
        require_root
        sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" "$@" >/dev/null
        cat "$ROOT/zamm-memory/.compiled/memory.md"
        exit 0
        ;;
      list)    require_root; memory_list "$@"; exit 0 ;;
      show)    require_root; memory_show "$@"; exit 0 ;;
      check)   TARGET="zamm-compile.sh"; set -- --check "$@" ;;
      create)  TARGET="zamm-new-memory.sh" ;;
      archive) TARGET="zamm-memory-archive.sh" ;;
      help|--help|-h) group_usage memory 0 ;;
      *) unknown "memory $verb" ;;
    esac
    require_root
    ;;

  plan)
    [ $# -gt 0 ] || group_usage plan 0
    verb="$1"; shift
    case "$verb" in
      list)   TARGET="zamm-status.sh"; INTERP="bash" ;;
      show)   require_root; plan_show "$@"; exit 0 ;;
      create) require_root; plan_create "$@"; exit 0 ;;
      check)  TARGET="zamm-plan-check.sh" ;;
      archive)
        case "${1-}" in -h|--help) exec bash "$INTERNAL/zamm-archive.sh" --help ;; esac
        require_root
        # A plan that fails validation must not become archived history:
        # this is what stops a Done plan with empty approval fields.
        sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" >/dev/null || {
          echo "zamm: plan check failed; refusing to archive." >&2
          sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" >/dev/null 2>&1 || true
          sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" 2>&1 >/dev/null | sed 's/^/  /' >&2
          exit 1
        }
        exec bash "$INTERNAL/zamm-archive.sh" --project-root "$ROOT" --archive "$@"
        ;;
      help|--help|-h) group_usage plan 0 ;;
      *) unknown "plan $verb" ;;
    esac
    require_root
    ;;

  scaffold)
    TARGET="zamm-scaffold.sh"; INTERP="bash"
    # scaffold always re-renders the managed surfaces on its own now; the old
    # --overwrite-templates injection is gone along with the flag.
    root_or_cwd
    ;;

  status)
    case "${1-}" in -h|--help) usage 0 ;; esac
    [ $# -eq 0 ] || die "status takes no arguments (got: $*)"
    require_root; print_status; exit 0 ;;
  check)
    case "${1-}" in -h|--help) usage 0 ;; esac
    [ $# -eq 0 ] || die "check takes no arguments (got: $*)"
    require_root; run_check_all ;;

  *) unknown "$cmd" ;;
esac

[ -f "$INTERNAL/$TARGET" ] || die "missing script: $INTERNAL/$TARGET"

# exec, not a subshell: the child's exit code is this command's exit code.
# zamm-compile.sh exit 3 ("records exist but none survived; refusing to
# publish") is load-bearing and must not be flattened to 1.
exec "$INTERP" "$INTERNAL/$TARGET" --project-root "$ROOT" "$@"
