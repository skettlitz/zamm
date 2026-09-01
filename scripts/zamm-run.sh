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

# Canonical-root verification (real directories, no symlinks, physically
# inside the project) — shared with every directly-invocable internal script.
. "$INTERNAL/zamm-paths.sh"

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
  status               health overview: ledger, backlog, plans, drift
  check                validate everything (memory + backlog + plans)
  help [<topic>]       this text, or help for one command

Memory
  memory digest        rebuild and print the digest
  memory list          index of live records, slug first
  memory show <slug>   one record in full
  memory check         validate the ledger
  memory create <slug> write a record; body on stdin (or --edit)
  memory publish <slug>
                       validate a hand-written <id>.md.draft and land it
  memory drafts        list hand-written drafts not yet published
  memory discard <slug>
                       show and delete an unpublished draft
  memory archive       move fully-retired chains out of the scan path

Backlog
  backlog add '<sentence>'
                       capture an idea; one sentence is enough
  backlog list [--scope <tag>]
                       the whole live backlog, hot to cold (--all: dormant
                       too; --scope filters, e.g. domain/lobby)
  backlog show <slug>  one idea in full
  backlog mark <slug>  select an idea for implementation (pushed into the digest)
  backlog unmark <slug>
                       deselect a marked idea
  backlog promote <slug> ['<plan title>']
                       turn an idea into a plan and retire it
  backlog check        validate the backlog ledger

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
  create <slug>        write a record; body on stdin (or --edit)
  publish <slug|id>    validate a hand-written <id>.md.draft and land it
  drafts               list hand-written drafts not yet published
  discard <slug|id>    show and delete an unpublished draft
  check                validate the ledger, write nothing
  archive [--dry-run]  move fully-retired chains out of the scan path
EOF
      ;;
    plan) cat <<'EOF'
Usage: zamm-run.sh plan <command> [args...]

  list                 active plans grouped by status
  show <slug>          one plan, with Done-when progress
  check                validate active plans
  create <title>       new plan directory and file
  archive [--list]     move terminal plans to the archive (--list previews)
EOF
      ;;
    backlog) cat <<'EOF'
Usage: zamm-run.sh backlog <command> [args...]

  add '<sentence>'     capture an idea: the sentence is the headline (all the
                       lens ever shows), the slug is derived, scope defaults
                       to other. If you already know the topic, say so:
                       --scope domain/lobby clusters siblings in the lens and
                       makes --scope filters work; the default stays cheap
                       and uncapped. An idea is progressive disclosure — pipe
                       any depth on stdin, a paragraph or a whole book: plain
                       prose is parked under ## Background (unbounded; +bg in
                       the lens, opened by backlog show), stdin with its own
                       headings is used verbatim. Optional: --scope <tag>,
                       --slug <slug>, --supersedes <id> (re-up: sharpen an
                       existing idea), --importance useful|minor, --durability
                       days..permanent. For other record types (--type
                       tombstone|votes|erasure) the positional is the SLUG,
                       as in memory create.
  list [--all] [--scope <tag>]
                       recompile and print the lens: marked lane first, then
                       every live idea clustered by subpath inside its area
                       (headings carry the counts), dormant collapsed to
                       counts (--all lists dormant ids too). --scope prints a
                       filtered row listing instead — any tag, prefix match,
                       so --scope domain also finds domain/lobby.
  show <slug|id>       one idea in full
  mark <slug|id>       select an idea for implementation: it enters the
                       session digest and stops decaying until promoted,
                       unmarked, or tombstoned
  unmark <slug|id>     deselect (writes the explicit marked: no decision)
  promote <slug|id> ['<plan title>']
                       create the plan (title defaults to the idea headline),
                       retire the idea with a tombstone linking both ways
  check                validate the backlog ledger, write nothing

Read the lens before adding: supersede or vote instead of duplicating.
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
  # Every operational command funnels through here, so this is the one place
  # the canonical roots are proven to be real directories inside the project
  # before anything reads or writes through them.
  zamm_verify_roots "$ROOT" || exit 4
}

# scaffold installs INTO a project that may not have zamm-memory/ yet, so a
# failed lookup falls back to the working directory instead of erroring.
root_or_cwd() { ROOT=$(resolve_root) || ROOT=$PWD; }

# Every command that INTERPRETS ledger data does so with the CURRENT protocol
# semantics; running one against another schema version silently reads old data
# under new rules. The scaffold gate only covers install/upgrade — operational
# commands had no gate at all — so this refuses them centrally when VERSION is
# missing, malformed, or not the supported version, and points at the migration
# guide. `status` is exempt (it REPORTS the mismatch instead of refusing);
# `scaffold` and `help` never reach here. Requires ROOT to be resolved first.
SUPPORTED_VERSION="3"
# Refusal, never a warning: when the toolchain speaks one protocol version and
# the ledger was written under another, nothing downstream can be trusted to
# parse the records under the rules they were written with. What differs per
# case is the REMEDY, and telling someone to migrate when they should update
# the skill (or scaffold) sends them the wrong way — so each state names its
# own fix instead of sharing one generic line.
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATION_DIR="$SKILL_ROOT/references/migrations"

# The remedy for a protocol mismatch, written once because two commands
# report this state. The gate itself points at status ("reports the state
# without operating"), so status is where a blocked developer looks next —
# and the two MUST NOT disagree. They did: the gate said "this project is
# newer, update the skill" while status said "migrate via the matching
# guide", which is the exact backwards move the newer-than-skill case
# exists to prevent.
# Writes to stdout; callers choose the stream and the indent.
version_advice() {
  _v="$1"; _pfx="$2"
  _guide="$MIGRATION_DIR/v1-v2-to-v3-memory.md"
  if [ -z "$_v" ]; then
    printf '%szamm-memory/ exists but carries no VERSION file (partial install, or damage).\n' "$_pfx"
    printf '%sWhat to do:  zamm-run.sh scaffold\n' "$_pfx"
    printf '%s             It stamps a genuinely empty tree and refuses one holding content,\n' "$_pfx"
    printf '%s             which tells you which of the two you have.\n' "$_pfx"
  elif ! printf '%s' "$_v" | grep -q '^[0-9][0-9]*$'; then
    printf '%sThat value is not a version number, so no upgrade path can be chosen for it.\n' "$_pfx"
    printf '%sWhat to do:  inspect zamm-memory/VERSION by hand; a v3 project contains exactly %s.\n' "$_pfx" "$SUPPORTED_VERSION"
  elif [ "$_v" -gt "$SUPPORTED_VERSION" ]; then
    printf '%sThis project is NEWER than your ZAMM skill. Do not migrate the ledger.\n' "$_pfx"
    printf '%sWhat to do:  update the skill itself (git pull in %s), then retry.\n' "$_pfx" "$SKILL_ROOT"
    printf '%s             A teammate migrated and pushed; your install has not caught up.\n' "$_pfx"
  else
    printf '%sWhat to do:  follow the migration guide, which updates VERSION when it completes:\n' "$_pfx"
    if [ -f "$_guide" ]; then
      printf '%s             %s\n' "$_pfx" "$_guide"
    else
      printf '%s             a guide under %s\n' "$_pfx" "$MIGRATION_DIR"
    fi
  fi
}

require_version() {
  _vfile="$ROOT/zamm-memory/VERSION"
  _ver=""
  [ -f "$_vfile" ] && _ver=$(sed -n '1p' "$_vfile" | tr -d '[:space:]')
  [ "$_ver" = "$SUPPORTED_VERSION" ] && return 0

  # 1. Nothing installed. Not a mismatch and not damage: scaffold is the fix.
  if [ ! -d "$ROOT/zamm-memory" ]; then
    echo "zamm: ZAMM is not installed here (no zamm-memory/ directory)." >&2
    echo "  Install it:  zamm-run.sh scaffold" >&2
    exit 5
  fi

  echo "zamm: project protocol version is '${_ver:-missing}', this toolchain speaks '$SUPPORTED_VERSION'." >&2
  echo "  Refusing to operate: records written under another protocol may parse under different rules." >&2

  version_advice "$_ver" "  " >&2
  echo "  ('zamm-run.sh status' reports the state without operating.)" >&2
  exit 5
}

# The stamp the scaffold wrote into the managed block, and the stamp the
# installed skill hashes to right now. Both readers (status, and the drift
# notice on digest) MUST derive these identically, which is why they live
# here once — the same reason zamm-skill-stamp.sh exists at all.
rendered_stamp() {
  sed -n 's/.*SKILL-BLOCK:zamm:BEGIN version=\([^ ]*\).*/\1/p' \
    "$ROOT/AGENTS.md" 2>/dev/null | head -1
}
installed_stamp() {
  [ -f "$INTERNAL/zamm-skill-stamp.sh" ] || return 0
  sh "$INTERNAL/zamm-skill-stamp.sh" 2>/dev/null || true
}

# Session start runs `memory digest` and nothing else, so this is the only
# place a skill update can be noticed without the agent going looking for it.
# It is a NOTICE, not a refusal: a moved stamp means the rendered instructions
# are stale, not that the ledger parses differently — the protocol version is
# what governs that, and it refuses. The stamp hashes every skill file, so a
# comment edit moves it; refusing here would break the project on a doc-only
# update. Goes to stderr so the digest on stdout stays clean and pipeable.
warn_if_surfaces_stale() {
  _rs=$(rendered_stamp)
  [ -n "$_rs" ] || return 0
  _is=$(installed_stamp)
  [ -n "$_is" ] || return 0
  [ "$_rs" != "$_is" ] || return 0
  echo "zamm: the ZAMM skill has changed since this project was scaffolded" >&2
  echo "  rendered surfaces: $_rs, installed skill: $_is" >&2
  echo "  refresh them (and tell the human) before relying on the rendered protocol:" >&2
  echo "    zamm-run.sh scaffold" >&2
}

# ---------------- built-in read-only views ----------------

digest_field() { sed -n '1s/.*[( ]'"$1"'=\([0-9][0-9]*\).*/\1/p' "$DIGEST" 2>/dev/null; }

# A field from the compiler's machine-readable state sidecar (one "key<TAB>val"
# per line). This is the authority for counts — reverse-parsing the rendered
# digest double-counted contested guardrails (Digest + reconciliation).
state_field() {
  [ -f "$STATE" ] || return 0
  awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$STATE"
}

# The compiler stamps the same generation token into the digest and the state
# sidecar. The two are renamed separately, so a compile interrupted between
# the renames leaves a mismatched pair; consuming the sidecar against a digest
# from a different compile would e.g. let memory list serve records the
# published digest never surfaced. Sidecar consumers verify the pair and treat
# a mismatch (or a pre-generation artifact with no token) as "recompile".
# ONE definition of the pairing rule, for both artifact/sidecar pairs
# (digest+state.tsv, backlog lens+backlog-state.tsv): the generation token
# stamped into both by the same compile must match, or the pair is torn.
pair_coherent() {
  _pc_sg=$(awk -F"$(printf '\t')" '$1 == "generation" { print $2; exit }' "$2" 2>/dev/null) || return 1
  _pc_ag=$(sed -n 's/^<!-- zamm-generation: \(.*\) -->$/\1/p' "$1" 2>/dev/null | tail -1)
  [ -n "$_pc_sg" ] && [ "$_pc_sg" = "$_pc_ag" ]
}

state_coherent() { pair_coherent "$DIGEST" "$STATE"; }

print_status() {
  DIGEST="$ROOT/zamm-memory/.compiled/memory.md"
  STATE="$ROOT/zamm-memory/.compiled/state.tsv"
  version=$(sed -n '1p' "$ROOT/zamm-memory/VERSION" 2>/dev/null | tr -d '[:space:]')
  stamp=$(rendered_stamp)

  printf 'ZAMM      version %s   root %s\n' "${version:-unknown}" "$ROOT"
  # status is the one operational command exempt from the version gate: it
  # REPORTS a mismatch (so an unmigrated project can still be inspected) where
  # every other command refuses. Make the mismatch loud.
  #
  # A project with no zamm-memory/ at all is NOT a mismatch: there is nothing
  # to migrate and scaffold is exactly the fix, so saying "migrate, and
  # scaffold cannot help" sends a first-time user the wrong way — and
  # contradicts the version gate every other command prints.
  if [ ! -d "$ROOT/zamm-memory" ]; then
    printf '          ZAMM is not installed here (no zamm-memory/ directory)\n'
    printf '          install it: zamm-run.sh scaffold\n'
    # Stop here. Every section below reads a tree that does not exist, and
    # reporting a missing plan root as "structural damage" of an empty
    # project is the same absent-vs-unreadable confusion (G3) one level up:
    # nothing is damaged, nothing was ever installed.
    exit 0
  fi
  if [ "${version:-}" != "$SUPPORTED_VERSION" ]; then
    printf '          PROTOCOL MISMATCH: project is %s, toolchain speaks %s -- other commands will refuse\n' \
      "${version:-missing}" "$SUPPORTED_VERSION"
    version_advice "${version:-}" "          "
  fi
  # Recompute the SAME content stamp scaffold wrote, so a skill tree edited
  # since the last scaffold (git checkout included) reads STALE.
  current=$(installed_stamp)
  if [ -z "$stamp" ]; then
    printf '          rendered surfaces: none found (run: zamm-run.sh scaffold)\n'
  elif [ -n "$current" ] && [ "$stamp" != "$current" ]; then
    printf '          rendered surfaces: %s -- STALE, skill is %s\n' "$stamp" "$current"
    printf '          run: zamm-run.sh scaffold\n'
  else
    printf '          rendered surfaces: %s\n' "$stamp"
  fi
  # A zamm-memory rule in .cursorignore is the one project-local
  # misconfiguration that breaks ZAMM from the outside: the Cursor Agent
  # Sandbox maps matched paths to EPERM, and every checked enumeration then
  # fails closed (G3) with a generic "unreadable" message that points nowhere
  # near this file. Scaffold reclaims the rules IT wrote; a hand-added one is
  # the user's, so this is a warning, not a deletion — and not an exit code:
  # outside the sandbox the same file is harmless.
  if [ -f "$ROOT/.cursorignore" ]; then
    _cig=$(awk '{ l = $0; sub(/^[ \t]+/, "", l)
                  if (l == "" || l ~ /^#/) next
                  if (l ~ /zamm-memory/) printf "          %s\n", l }' \
             "$ROOT/.cursorignore")
    if [ -n "$_cig" ]; then
      printf '          WARNING: .cursorignore lists zamm-memory path(s):\n'
      printf '%s\n' "$_cig"
      printf '          In the Cursor sandbox those read as EPERM and ZAMM commands\n'
      printf '          fail closed. Move them to .cursorindexingignore (hidden from\n'
      printf '          search, still readable), or re-run: zamm-run.sh scaffold\n'
    fi
  fi
  echo

  if [ ! -f "$DIGEST" ]; then
    echo 'Ledger    no compiled digest'
    echo '          run: zamm-run.sh memory digest'
  else
    # files/live/quarantined come from the compiler's own digest header (a
    # structured line it emits, not reverse-parsed prose), so they are reliable
    # with or without the sidecar.
    nrec=$(digest_field files)
    [ "$nrec" = "1" ] && recword="record" || recword="records"
    printf 'Ledger    %s %s, %s live, %s quarantined\n' \
      "$nrec" "$recword" "$(digest_field live)" "$(digest_field quarantined)"
    dormant=$(sed -n 's/^Dormant (.*): //p' "$DIGEST" | head -1)
    [ -n "$dormant" ] && printf '          dormant: %s\n' "$dormant"
    unlisted=$(sed -n 's/^Unlisted live (.*): //p' "$DIGEST" | head -1)
    [ -n "$unlisted" ] && printf '          unlisted (below budget): %s\n' "$unlisted"
    # guardrail/contested/other counts are graph facts the compiler records in
    # the sidecar. There is deliberately NO Markdown fallback: reverse-parsing
    # the digest double-counted contested guardrails and reconciliation groups
    # (the bug the sidecar exists to fix), so a stale/absent sidecar reports
    # "recompile" rather than a plausible-but-wrong number.
    if state_coherent; then
      printf '          guardrails: %s/15\n' "$(state_field guardrails)"
      other=$(state_field other)
      { [ -n "$other" ] && [ "$other" != "0" ]; } && printf '          other backlog: %s/5\n' "$other"
      contested=$(state_field contested)
      { [ -n "$contested" ] && [ "$contested" -gt 0 ]; } &&
        printf '          RECONCILIATION PENDING: %s group(s)\n' "$contested"
      # Divergence check: sidecar count vs the ledger on disk. A record file
      # that VANISHED since the compile (hand-moved back to a draft, say)
      # leaves nothing newer than the digest, so the mtime staleness check
      # below cannot see it — the count comparison can.
      # Checked, not `| wc -l` over a silenced find: a find that cannot
      # descend the tree must fail loudly, never read as a lower count.
      if ! _odl=$(find "$ROOT/zamm-memory/knowledge" -type f -name '*.md'); then
        echo 'zamm: cannot enumerate the ledger (unreadable, not empty).' >&2
        exit 4
      fi
      ondisk=$(printf '%s\n' "$_odl" | grep -c . || true)
      sfiles=$(state_field files)
      if [ -n "$sfiles" ] && [ "${ondisk:-0}" -ne "$sfiles" ]; then
        printf '          STALE: %s record file(s) on disk but the last compile saw %s\n' "$ondisk" "$sfiles"
        echo '          run: zamm-run.sh memory digest'
      fi
    else
      echo '          (guardrail/reconciliation counts unavailable: run zamm-run.sh memory digest)'
    fi
    # The digest embeds active plans as well as knowledge records, so a plan
    # edited after the last compile makes it stale too — watch both trees.
    # archive/knowledge is IN the scan: the compiler parses archived headers
    # for type and supersedes edges, so an edited archived record makes the
    # digest just as stale as an edited live one. (Optional tree — a missing
    # operand would make find fail and read as unreadable.)
    _nwtrees="$ROOT/zamm-memory/knowledge"
    [ -d "$ROOT/zamm-memory/archive/knowledge" ] &&
      _nwtrees="$_nwtrees $ROOT/zamm-memory/archive/knowledge"
    # shellcheck disable=SC2086 -- deliberate word splitting over fixed paths
    if ! _nwl=$(find $_nwtrees -type f -name '*.md' -newer "$DIGEST"); then
      echo 'zamm: cannot enumerate the ledger or plan tree (unreadable, not empty).' >&2
      exit 4
    fi
    # Plans are scanned at the depth the digest actually compiles from — the
    # same -mindepth 2 -maxdepth 2 '*.plan.md' the plan manifest uses. A full
    # -depth walk here descended into <plan>/workdir/, which the digest never
    # reads: a scratch note under workdir then reported the digest STALE when
    # recompiling could not change a byte of it, and an unreadable workdir
    # (the Cursor sandbox maps ignored paths to EPERM) failed the whole
    # command closed. Matching the compiler's own depth fixes both.
    if ! _nwp=$(find "$ROOT/zamm-memory/active/plans" \
                  -mindepth 2 -maxdepth 2 -name '*.plan.md' -newer "$DIGEST"); then
      echo 'zamm: cannot enumerate the ledger or plan tree (unreadable, not empty).' >&2
      exit 4
    fi
    newer=$(printf '%s\n%s\n' "$_nwl" "$_nwp" | grep -c . || true)
    if [ "${newer:-0}" -gt 0 ]; then
      printf '          STALE: %s file(s) newer than the digest\n' "$newer"
      echo '          run: zamm-run.sh memory digest'
    fi
    # The inert probe is a compiler run over the whole graph, archived
    # headers included: silencing it turned "the ledger could not be read"
    # into "nothing to archive", which is exactly the state that must NOT
    # look healthy. rc 4 (unreadable) refuses like every other enumeration
    # failure here; any other failure is reported instead of swallowed.
    _irc=0
    _il=$(sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --list-inert 2>/dev/null) || _irc=$?
    if [ "$_irc" -ge 4 ]; then
      echo '          ERROR: the ledger could not be read (unreadable, not empty)' >&2
      echo '          run: zamm-run.sh memory check' >&2
      exit 4
    fi
    if [ "$_irc" -ne 0 ]; then
      printf '          inert-chain scan unavailable (compiler rc=%s); run: zamm-run.sh memory check\n' "$_irc"
    else
      ninert=$(printf '%s\n' "$_il" | grep -c . || true)
      [ "${ninert:-0}" -gt 0 ] &&
        printf '          %s in fully-retired chains (zamm-run.sh memory archive)\n' "$ninert"
    fi
  fi
  # A hand-composed draft is invisible to check and the digest, so status is
  # where it surfaces. It is counted, not rated: `memory create` writes
  # complete records, so a draft is a deliberate two-step composition rather
  # than a record left to rot, and an age threshold only invented a policy
  # nobody asked for (at the cost of the toolchain's only non-POSIX stat).
  ndrafts=0
  dlist=$(list_drafts_checked) || exit 4
  if [ -n "$dlist" ]; then
    ndrafts=$(printf '%s\n' "$dlist" | grep -c . || true)
    printf '          drafts: %s unpublished (zamm-run.sh memory drafts)\n' "$ndrafts"
  fi
  nrec=$(count_recovery_files) || exit 4
  [ "${nrec:-0}" -gt 0 ] &&
    printf '          RECOVERY FILES: %s left by an interrupted publish (zamm-run.sh memory drafts)\n' "$nrec"
  echo

  # ---- backlog (optional tree; absence is data, not a gap to report) ----
  if [ -d "$ROOT/zamm-memory/backlog" ]; then
    _blens="$ROOT/zamm-memory/.compiled/backlog.md"
    _bstate="$ROOT/zamm-memory/.compiled/backlog-state.tsv"
    if [ ! -f "$_blens" ]; then
      printf 'Backlog   lens not yet compiled\n'
      printf '          run: zamm-run.sh memory digest\n'
    elif ! pair_coherent "$_blens" "$_bstate" ||
         ! _bvals=$(awk -F"$(printf '\t')" '
             $1 == "live"   { l = $2 }
             $1 == "hot"    { h = $2 }
             $1 == "marked" { m = $2 }
             END { print l "\t" h "\t" m }
           ' "$_bstate" 2>/dev/null); then
      # same coherence rule as the knowledge sidecar (pair_coherent): the
      # lens and its state are two renames, so a crash between them — or a
      # deleted sidecar, before OR between these reads — leaves a torn pair.
      # Report and name the remedy; a bare read here once aborted status
      # mid-output under set -e with no diagnostic at all, and the single
      # guarded read closes the check-then-read window a per-key read left.
      printf 'Backlog   lens/state pair incoherent (interrupted compile, or a deleted sidecar)\n'
      printf '          run: zamm-run.sh memory digest\n'
    else
      _btab=$(printf '\t')
      _blive=${_bvals%%"$_btab"*}
      _bmark=${_bvals##*"$_btab"}
      _bhot=${_bvals#*"$_btab"}; _bhot=${_bhot%"$_btab"*}
      printf 'Backlog   %s live ideas, %s hot, %s marked\n' \
        "${_blive:-?}" "${_bhot:-?}" "${_bmark:-?}"
      # same watch as the digest: idea files newer than the lens read STALE,
      # and an unreadable backlog tree fails closed (G3)
      if ! _bnw=$(find "$ROOT/zamm-memory/backlog" -type f -name '*.md' -newer "$_blens"); then
        echo 'zamm: cannot enumerate the backlog tree (unreadable, not empty).' >&2
        exit 4
      fi
      _bnewer=$(printf '%s\n' "$_bnw" | grep -c . || true)
      if [ "${_bnewer:-0}" -gt 0 ]; then
        printf '          STALE: %s file(s) newer than the lens\n' "$_bnewer"
        echo '          run: zamm-run.sh memory digest'
      fi
    fi
    echo
  fi

  # Plans enumerate through the checked manifest, never a glob: a status that
  # reported "none active" over an unreadable tree would hide the failure.
  pmf=$(mktemp "${TMPDIR:-/tmp}/zamm-status-pmf.XXXXXX")
  if ! sh "$INTERNAL/zamm-plan-manifest.sh" --project-root "$ROOT" > "$pmf"; then
    rm -f "$pmf"
    echo 'Plans     ERROR: cannot enumerate the plan tree (unreadable, not empty)'
    exit 4
  fi
  tab=$(printf '\t')
  # a missing plan root is structural damage (scaffold always creates both),
  # never a healthy zero-plan project
  if grep -q "^MISSING${tab}" "$pmf"; then
    grep "^MISSING${tab}" "$pmf" | while IFS="$tab" read -r _ mroot; do
      printf 'Plans     ERROR: plan root missing: %s -- structural damage, not an empty project\n' "${mroot#"$ROOT/"}"
    done
    echo '          restore it (zamm-run.sh scaffold recreates the directory), then investigate'
    rm -f "$pmf"
    exit 4
  fi
  stlist=""
  while IFS= read -r pd; do
    [ -n "$pd" ] || continue
    pf=$(awk -F"$tab" -v d="$pd/" '$1 == "PLANFILE" && index($2, d) == 1 { print $2; exit }' "$pmf")
    [ -n "$pf" ] || continue
    s=$(sed -n 's/^Status:[[:space:]]*//p' "$pf" | head -1 | awk '{print $1}')
    stlist="$stlist$s
"
  done <<EOF
$(awk -F"$tab" '$1 == "PLANDIR" { print $2 }' "$pmf")
EOF
  total=0; terminal=0; summary=""
  for st in Draft Implementing Review Done Abandoned; do
    n=$(printf '%s' "$stlist" | grep -c "^$st\$" || true)
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
  nanom=$(awk -F"$tab" '$1 ~ /^(SYMLINK|NOTDIR|UNREADABLE|DUP|DEBRIS)$/ { n++ } END { print n + 0 }' "$pmf")
  [ "$nanom" -gt 0 ] &&
    printf '          INVALID ENTRIES: %s (zamm-run.sh plan check)\n' "$nanom"
  narch=$(awk -F"$tab" '$1 == "ARCHDIR" { n++ } END { print n + 0 }' "$pmf")
  printf '          archived: %s\n' "$narch"
  rm -f "$pmf"
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
  STATE="$ROOT/zamm-memory/.compiled/state.tsv"
  # Default view is what is actually influencing the agent: the records the
  # digest SELECTED. Those ids come from the compiler's state sidecar, not from
  # grepping the rendered digest — the old grep also scooped up any record id
  # that appeared in the appended Plans tail (e.g. inside a plan title), so a
  # live-but-unlisted record named in a plan leaked into the default list.
  # --all adds the unlisted and dormant tail.
  filter=""
  if [ "$show_all" -eq 0 ]; then
    # The default view is exactly the digest-selected records, which the
    # compiler records in the sidecar. There is NO Markdown fallback: grepping
    # the digest also scooped up ids embedded in the appended Plans tail (a
    # record named in a plan title leaked into the list), so a missing sidecar
    # asks for a recompile rather than returning a wrong set.
    [ -f "$STATE" ] || die "no state sidecar yet; run: zamm-run.sh memory digest (or use --all)"
    state_coherent ||
      die "digest and state sidecar are from different compiles (interrupted compile?); run: zamm-run.sh memory digest (or use --all)"
    filter=$(awk -F'\t' '$1=="select"{print $2}' "$STATE" | sort -u)
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

# <slug|id> -> exactly one draft path on stdout. Zero or multiple matches
# Checked enumeration of *.md.draft files. A find that cannot descend the
# tree must fail loudly (status 4), never read as "no drafts" — the same
# unreadable-vs-empty rule the ledger and plan manifests follow. Runs inside
# $(...); callers MUST check the status.
list_drafts_checked() {
  # Absent is data (references/invariants.md, G3): a project that has never
  # been scaffolded has no zamm-memory/ at all, and that is not an unreadable
  # tree. Testing the ROOT of the tree rather than knowledge/ is what keeps
  # the guarantee intact — a zamm-memory/ that exists but cannot be entered
  # still falls through to the checked find below and fails loudly.
  [ -e "$ROOT/zamm-memory" ] || return 0
  # find SUCCEEDS while silently skipping a symlinked directory, so a
  # checked exit status alone still reads a hidden year directory as "no
  # drafts" — the position check has to come first.
  zamm_verify_no_symlinks "$ROOT" || return 4
  find "$ROOT/zamm-memory/knowledge" -type f -name '*.md.draft' || {
    echo "zamm: cannot enumerate drafts under zamm-memory/knowledge (unreadable, not empty)." >&2
    return 4
  }
}

# A record being written lives at .<id>.md.pending.XXXXXX until it validates
# (see references/invariants.md, G1). A crash leaves one behind. It matches no
# other enumeration, so without this it would sit in the tree unmentioned.
list_recovery_files() {
  _rf=$(find_recovery_files) || return 4
  [ -n "$_rf" ] || return 0
  echo
  echo "Leftover temporary files from an interrupted record write:"
  printf '%s\n' "$_rf" | sort | while IFS= read -r f; do
    [ -n "$f" ] && echo "  ${f#"$ROOT/"}"
  done
  echo "  They are not part of the ledger; delete them."
}

count_recovery_files() {
  _rf=$(find_recovery_files) || return 4
  printf '%s\n' "$_rf" | grep -c . || true
}

find_recovery_files() {
  # Absent is data (G3), same rule as list_drafts_checked: no zamm-memory/
  # means nothing was ever written here, not a tree we failed to read.
  [ -e "$ROOT/zamm-memory" ] || return 0
  zamm_verify_no_symlinks "$ROOT" || return 4
  # backlog add composes through the same pending-file protocol, so its
  # crashes leave the same debris; the tree is optional and absent is data
  _rftrees="$ROOT/zamm-memory/knowledge"
  [ -d "$ROOT/zamm-memory/backlog" ] &&
    _rftrees="$_rftrees $ROOT/zamm-memory/backlog"
  # shellcheck disable=SC2086 -- deliberate word splitting over fixed paths
  find $_rftrees -type f -name '.*.md.pending.*' || {
    echo "zamm: cannot enumerate the record trees (unreadable, not empty)." >&2
    return 4
  }
}

# report on stderr and return non-zero (1: no/ambiguous match; 4: the draft
# tree could not be read). Runs inside $(...), so its exits stop only the
# subshell -- callers MUST `|| exit $?`.
resolve_one_draft() {
  needle="$1"
  all=$(list_drafts_checked) || return 4
  drafts=$(printf '%s\n' "$all" |
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      b=$(basename "$f" .md.draft)
      s=$(printf '%s' "$b" | sed 's/^[0-9-]\{11\}//; s/-[a-z0-9]\{5\}$//')
      if [ "$b" = "$needle" ] || [ "$s" = "$needle" ]; then printf '%s\n' "$f"; fi
    done)
  n=$(printf '%s\n' "$drafts" | grep -c . || true)
  if [ "${n:-0}" -eq 0 ]; then
    echo "zamm: no draft matches \"$needle\" (looked for <id>.md.draft)" >&2
    return 1
  fi
  if [ "$n" -gt 1 ]; then
    echo "zamm: \"$needle\" matches $n drafts:" >&2
    printf '%s\n' "$drafts" | while IFS= read -r f; do
      [ -n "$f" ] && echo "  $(basename "$f" .md.draft)" >&2
    done
    echo "  Use the full id to pick one." >&2
    return 1
  fi
  printf '%s\n' "$drafts"
}

# memory drafts: the only view of unpublished <id>.md.draft files, which are
# deliberately invisible to check and the digest.
memory_drafts() {
  case "${1-}" in -h|--help)
    echo "Usage: zamm-run.sh memory drafts"
    echo "  List unpublished drafts (<id>.md.draft)."
    exit 0 ;;
  esac
  [ $# -eq 0 ] || die "memory drafts takes no arguments (got: $*)"
  dlist=$(list_drafts_checked) || exit 4
  dlist=$(printf '%s' "$dlist" | sort)
  if [ -z "$dlist" ]; then
    echo "No drafts."
    list_recovery_files
    exit 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "$(basename "$f" .md.draft)"
  done <<EOF
$dlist
EOF
  echo "Publish one with 'memory publish <id>', or drop it with 'memory discard <id>'."
  list_recovery_files
  exit 0
}

# memory discard <slug|id>: show, then delete, an unpublished draft. The rm
# target always ends in .md.draft, so a published record is out of reach.
memory_discard() {
  case "${1-}" in -h|--help)
    echo "Usage: zamm-run.sh memory discard <slug|id>"
    echo "  Show and delete an unpublished draft (<id>.md.draft)."
    echo "  Published records are never touched; supersede those instead."
    exit 0 ;;
  esac
  [ $# -ge 1 ] || die "memory discard: need a draft slug or id"
  [ $# -le 1 ] || die "memory discard: too many arguments (one slug or id)"
  draft=$(resolve_one_draft "$1") || exit $?
  echo "Discarding ${draft#"$ROOT/"}:"
  sed 's/^/  /' "$draft"
  rm -f "$draft"
  echo "Discarded."
  exit 0
}

# memory publish <slug|id>: land a hand-composed draft (<id>.md.draft) in the
# ledger. `memory create` writes complete records in one step and needs none
# of this; a draft is simply a record someone chose to compose over several
# edits, and publishing it is the same atomic claim create uses (G1): copy the
# draft to a private temp, validate THAT, and hard-link it into place. The
# bytes that are validated are the bytes that land, so there is nothing to
# roll back and no lock to take.
memory_publish() {
  case "${1-}" in -h|--help)
    echo "Usage: zamm-run.sh memory publish <slug|id>"
    echo "  Validate a draft (<id>.md.draft) and land it in the ledger."
    exit 0 ;;
  esac
  [ $# -ge 1 ] || die "memory publish: need a draft slug or id"
  [ $# -le 1 ] || die "memory publish: too many arguments (one slug or id)"
  draft=$(resolve_one_draft "$1") || exit $?
  final="${draft%.draft}"
  [ -e "$final" ] && die "a record already exists at ${final#"$ROOT/"} (draft not published)"

  . "$INTERNAL/zamm-validate.sh"
  pubdir=${draft%/*}
  pubbase=$(basename "$final")
  work=$(mktemp "$pubdir/.$pubbase.pending.XXXXXX") ||
    die "memory publish: could not create a temporary file beside the draft"
  trap 'rm -f "$work"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # -p keeps the draft's own mode; this copy becomes the record
  cp -p "$draft" "$work" || die "memory publish: could not copy the draft"

  disp=${pubdir#"$ROOT/zamm-memory/"}
  zamm_validate_candidate "$ROOT" "$INTERNAL" "$work" "$disp" || {
    echo "      The draft is untouched; fix it and publish again." >&2
    exit 1
  }

  # Atomic no-clobber claim of the final name.
  ln "$work" "$final" 2>/dev/null ||
    die "a record appeared at ${final#"$ROOT/"} while publishing; nothing was published"
  rm -f "$work"
  trap - EXIT HUP INT TERM
  rm -f "$draft"

  # The digest is derived and disposable (G2): a failed rebuild is reported,
  # never a reason to unpublish a valid record.
  crc=0
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" >/dev/null || crc=$?
  if [ "$crc" -eq 2 ]; then
    # informational: the record is in, but the refreshed digest carries
    # damage from OTHER records. Silence here left the caller believing the
    # ledger was clean.
    echo "zamm: published, but the digest is degraded by unrelated pre-existing problems;" >&2
    echo "      run 'zamm-run.sh memory check' to see them." >&2
  elif [ "$crc" -ne 0 ]; then
    echo "zamm: the record was published, but the digest could not be rebuilt (rc=$crc);" >&2
    echo "      run 'zamm-run.sh memory digest' to refresh it." >&2
  fi
  echo "Published: ${final#"$ROOT/"}"
  exit 0
}

# <slug|id> -> exactly one path, or list candidates and exit non-zero.
# The enumeration is CHECKED: a tree that cannot be read is an error, never
# "no match" (references/invariants.md, G3).
resolve_record() {
  needle="$1"
  rtree="${2:-knowledge}"
  zamm_verify_no_symlinks "$ROOT" || exit 4
  rtrees="$ROOT/zamm-memory/$rtree"
  [ -d "$ROOT/zamm-memory/archive/$rtree" ] &&
    rtrees="$rtrees $ROOT/zamm-memory/archive/$rtree"
  # shellcheck disable=SC2086
  all=$(find $rtrees -type f -name '*.md') || {
    echo "zamm: cannot enumerate the ledger (unreadable, not empty)." >&2
    exit 4
  }
  matches=$(printf '%s\n' "$all" |
    while IFS= read -r f; do
      [ -n "$f" ] || continue
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
    if [ "$rtree" = "backlog" ]; then
      echo "  try: zamm-run.sh backlog list --all" >&2
    else
      echo "  try: zamm-run.sh memory list --all" >&2
    fi
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
  # Candidates come from the checked manifest, like every other consumer of
  # "which plans exist": a silenced find reported "no plan matches" for a
  # tree nobody could read, and it happily displayed content reached through
  # a symlinked plan directory — which the manifest refuses to follow.
  _psmf=$(mktemp "${TMPDIR:-/tmp}/zamm-plan-show-mf.XXXXXX")
  if ! sh "$INTERNAL/zamm-plan-manifest.sh" --project-root "$ROOT" > "$_psmf"; then
    rm -f "$_psmf"
    echo "zamm: cannot enumerate the plan tree (unreadable, not empty)." >&2
    exit 4
  fi
  _pstab=$(printf '\t')
  if grep -q "^MISSING${_pstab}" "$_psmf"; then
    rm -f "$_psmf"
    echo "zamm: a plan root is missing (structural damage, not an empty project)." >&2
    echo "  restore it ('zamm-run.sh scaffold' recreates the directory), then investigate." >&2
    exit 4
  fi
  all=$(awk -F"$_pstab" '$1 == "PLANFILE" || $1 == "ARCHFILE" { print $2 }' "$_psmf")
  rm -f "$_psmf"

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
  # The id must be unique across BOTH trees: an archived plan keeps its slug
  # resolvable (votes records, digest history), so a fresh active plan reusing
  # it would make every by-slug reference ambiguous.
  adir="$ROOT/zamm-memory/archive/plans/$today-$slug"
  [ -e "$dir" ] || [ -L "$dir" ] && die "plan already exists: ${dir#"$ROOT/"}"
  { [ -e "$adir" ] || [ -L "$adir" ]; } &&
    die "plan id is already archived: ${adir#"$ROOT/"} (pick a different title)"
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
  # ZAMM_PLAN_ORIGIN (backlog promote only) renders the provenance line INTO
  # the plan while it is still in the private temp tree — so the published
  # directory carries its origin from birth, and an interrupted promote is
  # decidable on retry (guarantee 2). Stamping after the rename left a
  # window where the partial plan was indistinguishable from a stranger's.
  ZAMM_PLAN_TITLE="$title" ZAMM_PLAN_ORIGIN="${ZAMM_PLAN_ORIGIN:-}" awk -v today="$today" '
    $0 == "# <Plan title>"             { print "# " ENVIRON["ZAMM_PLAN_TITLE"]; next }
    $0 == "Last updated: <YYYY-MM-DD>" {
      print "Last updated: " today
      if (ENVIRON["ZAMM_PLAN_ORIGIN"] != "")
        print "Origin-idea: " ENVIRON["ZAMM_PLAN_ORIGIN"]
      next
    }
    { print }
  ' "$template" > "$pf"

  # validate the rendered result BEFORE anything lands in active/plans/
  [ -s "$pf" ] || die "plan create: rendered an empty plan file"
  grep -q '^Status: Draft' "$pf" ||
    die "plan create: rendered plan is missing 'Status: Draft'"
  if grep -q '<Plan title>' "$pf"; then
    die "plan create: title placeholder was not substituted"
  fi
  if [ -n "${ZAMM_PLAN_ORIGIN:-}" ]; then
    grep -q "^Origin-idea: ${ZAMM_PLAN_ORIGIN}\$" "$pf" ||
      die "plan create: the origin line was not rendered (template shape changed?)"
  fi

  # Publish the complete tree with ONE rename. No lock: two agents creating
  # the same plan slug on the same day is the only race here, and POSIX `mv`
  # onto a destination that appeared meanwhile moves the source INSIDE it
  # rather than failing — so instead of excluding the race we detect losing
  # it. The winner's directory is complete and correct; the loser removes its
  # own nested tree and says so. rename(2) still makes the finished tree
  # appear all at once, so a compile never sees an empty plan directory.
  { [ -e "$dir" ] || [ -L "$dir" ]; } &&
    die "plan already exists: ${dir#"$ROOT/"}"
  mv "$tmp" "$dir"
  # Losing the race has an exact signature: our whole tree is now sitting
  # INSIDE the winner's directory under its own temp name. Testing for the
  # plan file instead would not work — the winner wrote one with the same
  # name — so key on the nested temp directory itself.
  if [ -d "$dir/${tmp##*/}" ]; then
    rm -rf "$dir/${tmp##*/}"
    trap - EXIT HUP INT TERM
    die "plan already exists: ${dir#"$ROOT/"} (created concurrently)"
  fi
  if [ ! -f "$dir/$today-$slug.plan.md" ]; then
    trap - EXIT HUP INT TERM
    die "plan create: the rendered tree did not land at ${dir#"$ROOT/"}"
  fi
  trap - EXIT HUP INT TERM

  echo "${dir#"$ROOT/"}/$today-$slug.plan.md"
  echo "Created. Fill Scope and Done-when, then set Status: Implementing." >&2
}

# ---------------- backlog ----------------
# Ideas are ordinary records in zamm-memory/backlog/ — same schema, same
# immutability, compiled by the same compiler into the pulled lens
# .compiled/backlog.md. These verbs are thin sugar over that machinery; the
# capture path (add) is deliberately the cheapest write in the toolchain.

require_backlog_tree() {
  [ -d "$ROOT/zamm-memory/backlog" ] ||
    die "no backlog tree at zamm-memory/backlog ('backlog add' creates it)"
}

# the record-name grammar in ONE place for the shell: YYYY-MM-DD-<slug>-<sfx>
id_to_slug() {
  _its=$1
  _its=${_its#??????????-}
  printf '%s\n' "${_its%-?????}"
}

backlog_check() {
  case "${1-}" in -h|--help) group_usage backlog 0 ;; esac
  [ $# -eq 0 ] || die "backlog check takes no arguments (got: $*)"
  # Absent is data: a project that never captured an idea has nothing to
  # check, which is not the same as a tree that cannot be read.
  if [ ! -d "$ROOT/zamm-memory/backlog" ]; then
    echo "ZAMM backlog: no backlog tree; nothing to check. ('backlog add' creates it.)"
    exit 0
  fi
  exec sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog --check
}

backlog_list() {
  case "${1-}" in -h|--help) group_usage backlog 0 ;; esac
  _bl_all=0; _bl_scope=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) _bl_all=1; shift ;;
      --scope)
        [ $# -ge 2 ] || die "backlog list: --scope requires an area or area/subpath"
        [ -n "$2" ] || die "backlog list: --scope requires a non-empty value"
        _bl_scope="$2"; shift 2 ;;
      --scope=*)
        _bl_scope="${1#--scope=}"
        [ -n "$_bl_scope" ] || die "backlog list: --scope= requires a non-empty value"
        shift ;;
      *) die "backlog list: unknown argument: $1" ;;
    esac
  done
  if [ ! -d "$ROOT/zamm-memory/backlog" ]; then
    echo "ZAMM backlog: empty - no zamm-memory/backlog/ tree yet ('backlog add' creates it)."
    exit 0
  fi
  # like memory digest: recompile, print the artifact, propagate the code —
  # a degraded lens (2) is still printed, a refusal or unreadable tree is not
  rc=0
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog >/dev/null || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    exit "$rc"
  fi
  if [ -n "$_bl_scope" ]; then
    # the query surface: a filtered ROW listing, mirroring memory list
    # --scope exactly (any tag, prefix semantics, secondary doors count).
    # The unfiltered lens stays the one pulled digest. Default view is the
    # lens contents (non-dormant); --all adds the dormant tail.
    _bl_tab=$(printf '\t')
    _bl_filter=""
    if [ "$_bl_all" -eq 0 ]; then
      _bl_state="$ROOT/zamm-memory/.compiled/backlog-state.tsv"
      pair_coherent "$ROOT/zamm-memory/.compiled/backlog.md" "$_bl_state" ||
        die "lens and state sidecar are from different compiles; run: zamm-run.sh memory digest (or use --all)"
      _bl_filter=$(awk -F"$_bl_tab" '$1 == "select" { print $2 }' "$_bl_state" | sort -u)
    fi
    sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog --list-live |
    while IFS="$_bl_tab" read -r _bl_id _bl_primary _bl_alltags _bl_hl; do
      [ -n "$_bl_id" ] || continue
      if [ "$_bl_all" -eq 0 ]; then
        printf '%s\n' "$_bl_filter" | grep -qx "$_bl_id" || continue
      fi
      _bl_matched=0
      _bl_oldifs=$IFS; IFS=,
      for _bl_tag in $_bl_alltags; do
        case "$_bl_tag" in "$_bl_scope"|"$_bl_scope"/*) _bl_matched=1; break ;; esac
      done
      IFS=$_bl_oldifs
      [ "$_bl_matched" -eq 1 ] || continue
      printf '%-22s %-34s %s\n' "$_bl_primary" "$(id_to_slug "$_bl_id")" \
        "$(printf '%s' "$_bl_hl" | cut -c1-72)"
    done
    exit "$rc"
  fi
  cat "$ROOT/zamm-memory/.compiled/backlog.md"
  if [ "$_bl_all" -eq 1 ]; then
    # dormant ids = live rows the lens did not select. Two invocations of
    # the same toolchain; a write between them is ordinary eventual
    # consistency (each side is a truthful reading of some real state).
    _bl_tab=$(printf '\t')
    sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog --list-live |
      awk -F"$_bl_tab" -v statef="$ROOT/zamm-memory/.compiled/backlog-state.tsv" '
        BEGIN {
          while ((getline line < statef) > 0) {
            n = split(line, f, "\t")
            if (n >= 2 && f[1] == "select") sel[f[2]] = 1
          }
          close(statef)
        }
        !($1 in sel) {
          if (!hdr) {
            print ""
            print "Dormant ideas (cooled below the floor; supersede or vote to re-up):"
            hdr = 1
          }
          print "- " $1 ": " $4
        }
      '
  fi
  exit "$rc"
}

backlog_show() {
  case "${1-}" in -h|--help) group_usage backlog 0 ;; esac
  [ $# -ge 1 ] || die "backlog show: need a slug or record id"
  [ $# -le 1 ] || die "backlog show: too many arguments (one slug or id)"
  require_backlog_tree
  path=$(resolve_record "$1" backlog)
  rel="${path#"$ROOT/"}"
  case "$rel" in
    */archive/backlog/*) echo "# $rel  (ARCHIVED - fully-retired chain)" ;;
    *) echo "# $rel" ;;
  esac
  echo
  cat "$path"
}

# Resolve a needle (full id or bare slug) against the LIVE backlog heads and
# print the matching --list-live row. Superseded, tombstoned and quarantined
# ideas deliberately do not resolve: marking or promoting a non-head would
# fork the chain behind the operator's back. Runs inside $(...) — callers
# MUST check the status. Return codes are TYPED — a single boolean here once
# let promote conflate three distinct states into a false "retired" verdict
# (round-3 review): 0 = exactly one live match (row on stdout), 1 = no live
# match, 2 = ambiguous (listing on stderr), 4 = the backlog could not be
# enumerated or compiled (fail closed, G3).
resolve_live_idea() {
  _rl_needle="$1"
  _rl_tab=$(printf '\t')
  _rl_rows=$(sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog --list-live) || {
    echo "zamm: the backlog did not compile; cannot resolve \"$_rl_needle\"." >&2
    return 4
  }
  _rl_m=$(printf '%s\n' "$_rl_rows" | awk -F"$_rl_tab" -v n="$_rl_needle" '
    {
      id = $1
      # id = YYYY-MM-DD-<slug>-<suffix>: slug is chars 12 .. length-6
      s = (length(id) > 17) ? substr(id, 12, length(id) - 17) : ""
      if (id == n || s == n) print
    }')
  _rl_n=$(printf '%s\n' "$_rl_m" | grep -c . || true)
  if [ "${_rl_n:-0}" -eq 0 ]; then
    echo "zamm: no live idea matches \"$_rl_needle\"" >&2
    echo "  try: zamm-run.sh backlog list --all (a superseded or retired idea does not resolve here)" >&2
    return 1
  fi
  if [ "$_rl_n" -gt 1 ]; then
    echo "zamm: \"$_rl_needle\" matches $_rl_n live ideas:" >&2
    printf '%s\n' "$_rl_m" | while IFS="$_rl_tab" read -r _rid _ _ _; do
      [ -n "$_rid" ] && echo "  $_rid" >&2
    done
    echo "  Use the full id to pick one." >&2
    return 2
  fi
  printf '%s\n' "$_rl_m"
}

# one frontmatter value, read from the frontmatter block ONLY — a body line
# that happens to start with "scope:" must not be mistaken for the key
fm_field() {
  awk -v k="$2" '
    NR == 1 { if ($0 == "---") { infm = 1; next } else exit }
    infm && $0 == "---" { exit }
    infm && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      print v
      exit
    }
  ' "$1"
}

# the record body: everything after the closing ---, leading blanks dropped
fm_body() {
  awk '
    c >= 2 { if (!started && $0 == "") next; started = 1; print; next }
    $0 == "---" { c++ }
  ' "$1"
}

backlog_markctl() {
  _mk_action="$1"; shift
  case "${1-}" in -h|--help) group_usage backlog 0 ;; esac
  [ $# -ge 1 ] || die "backlog $_mk_action: need a slug or record id"
  [ $# -le 1 ] || die "backlog $_mk_action: too many arguments (one slug or id)"
  require_backlog_tree
  _mk_tab=$(printf '\t')
  _mk_row=$(resolve_live_idea "$1") || {
    _mk_rc=$?
    # ambiguity and no-match are both operator errors (exit 1, diagnostics
    # already printed); an unreadable tree keeps its G3 code
    [ "$_mk_rc" -eq 4 ] && exit 4
    exit 1
  }
  _mk_id=${_mk_row%%"$_mk_tab"*}
  # effective marked state comes from the compiled lens, never from the head
  # file alone: the lane is inherited through the chain (see effmark in
  # zamm-compile.sh), so the head may carry no marked: key and still be in it
  rc=0
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog >/dev/null || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    die "backlog $_mk_action: the backlog did not compile (rc=$rc)"
  fi
  _mk_date=$(awk -F"$_mk_tab" -v id="$_mk_id" \
    '$1 == "mselect" && $3 == id { print $2; exit }' \
    "$ROOT/zamm-memory/.compiled/backlog-state.tsv")
  if [ "$_mk_action" = "mark" ] && [ -n "$_mk_date" ]; then
    die "backlog mark: $_mk_id is already marked (since $_mk_date)"
  fi
  if [ "$_mk_action" = "unmark" ] && [ -z "$_mk_date" ]; then
    die "backlog unmark: $_mk_id is not marked"
  fi
  _mk_path=$(resolve_record "$_mk_id" backlog)
  _mk_scope=$(fm_field "$_mk_path" scope)
  _mk_imp=$(fm_field "$_mk_path" importance)
  _mk_dur=$(fm_field "$_mk_path" durability)
  _mk_slug=$(id_to_slug "$_mk_id")
  if [ "$_mk_action" = "mark" ]; then
    _mk_val=${ZAMM_TODAY:-$(date +%Y-%m-%d)}
  else
    _mk_val="no"
  fi
  # the marking decision is an ordinary superseding record: same body, the
  # marked: key toggled — so G1 and candidate validation apply unchanged,
  # and the decision is greppable history like everything else
  fm_body "$_mk_path" | sh "$INTERNAL/zamm-new-memory.sh" \
    --project-root "$ROOT" --tree backlog \
    --scope "$_mk_scope" \
    --importance "${_mk_imp:-useful}" --durability "${_mk_dur:-months}" \
    --supersedes "$_mk_id" --marked "$_mk_val" "$_mk_slug" >/dev/null ||
    die "backlog $_mk_action: could not write the superseding record"
  if [ "$_mk_action" = "mark" ]; then
    echo "Marked for implementation ($_mk_val): $_mk_id"
    echo "  It now appears in the session digest and stops decaying until"
    echo "  promoted, unmarked, or tombstoned."
  else
    echo "Unmarked: $_mk_id"
  fi
}

backlog_promote() {
  case "${1-}" in -h|--help) group_usage backlog 0 ;; esac
  [ $# -ge 1 ] || die "backlog promote: need a slug or record id (plus an optional plan title)"
  require_backlog_tree
  _bp_needle="$1"; shift
  _bp_tab=$(printf '\t')

  # ONE resolve, diagnostics captured; its TYPED return code separates the
  # states a single boolean once conflated into a false "retired" verdict:
  # ambiguity and unreadability refuse here, before any authority decision.
  _bp_err=$(mktemp "${TMPDIR:-/tmp}/zamm-promote-err.XXXXXX") ||
    die "backlog promote: could not create a scratch file"
  _bp_rrc=0
  _bp_row=$(resolve_live_idea "$_bp_needle" 2>"$_bp_err") || _bp_rrc=$?
  if [ "$_bp_rrc" -eq 4 ] || [ "$_bp_rrc" -eq 2 ]; then
    cat "$_bp_err" >&2
    rm -f "$_bp_err"
    exit "$([ "$_bp_rrc" -eq 4 ] && echo 4 || echo 1)"
  fi
  _bp_id=""
  [ "$_bp_rrc" -eq 0 ] && _bp_id=${_bp_row%%"$_bp_tab"*}

  # The graph, from the same compile authority: promote reasons about
  # ancestry over the applied supersede edges — a slug is not proof of
  # identity, and the retry-time head is not the promote-time head.
  _bp_graph=$(mktemp "${TMPDIR:-/tmp}/zamm-promote-graph.XXXXXX") ||
    { rm -f "$_bp_err"; die "backlog promote: could not create a scratch file"; }
  if ! sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog --list-graph > "$_bp_graph"; then
    rm -f "$_bp_err" "$_bp_graph"
    die "backlog promote: the backlog graph could not be read (unreadable, not empty)"
  fi

  # The origin scan is MUTATION AUTHORITY: promote tombstones an idea based
  # on what it saw here, so an incomplete view must refuse before anything
  # is created (G3). The manifest exits 0 while representing damage as data
  # rows, so refuse on any row OUTSIDE the known-good vocabulary — an
  # ALLOWLIST, because a blocklist of anomaly tags fails open the day the
  # manifest grows a new one (round-3 review finding).
  _bp_pmf=$(mktemp "${TMPDIR:-/tmp}/zamm-promote-mf.XXXXXX") ||
    { rm -f "$_bp_err" "$_bp_graph"; die "backlog promote: could not create a scratch file"; }
  if ! sh "$INTERNAL/zamm-plan-manifest.sh" --project-root "$ROOT" > "$_bp_pmf"; then
    rm -f "$_bp_err" "$_bp_graph" "$_bp_pmf"
    die "backlog promote: cannot enumerate the plan tree (unreadable, not empty)"
  fi
  _bp_bad=$(awk -F"$_bp_tab" '
    $1 != "PLANDIR" && $1 != "PLANFILE" && $1 != "SUBPLAN" &&
    $1 != "ARCHDIR" && $1 != "ARCHFILE" {
      print "  " $1 ": " $2
    }' "$_bp_pmf")
  if [ -n "$_bp_bad" ]; then
    rm -f "$_bp_err" "$_bp_graph" "$_bp_pmf"
    echo "zamm: backlog promote: the plan tree is damaged; refusing to create or retire anything:" >&2
    printf '%s\n' "$_bp_bad" >&2
    echo "  Repair the tree (zamm-run.sh plan check names the fixes), then rerun." >&2
    exit 4
  fi

  # Origin-idea lines from ACTIVE and ARCHIVED plans in one awk pass — an
  # archived promoted plan is the normal end state and must keep the replay
  # convergent; sed-per-file forked one pipeline per plan forever.
  _bp_org=$(mktemp "${TMPDIR:-/tmp}/zamm-promote-org.XXXXXX") ||
    { rm -f "$_bp_err" "$_bp_graph" "$_bp_pmf"; die "backlog promote: could not create a scratch file"; }
  _bp_pfl=$(awk -F"$_bp_tab" '$1 == "PLANFILE" || $1 == "ARCHFILE" { print $2 }' "$_bp_pmf")
  if [ -n "$_bp_pfl" ]; then
    # one awk over every plan file (an empty list must not reach xargs: some
    # xargs run the command once anyway, and awk with no files reads stdin)
    printf '%s\n' "$_bp_pfl" | tr '\n' '\0' |
      xargs -0 awk 'sub(/^Origin-idea: /, "") { print FILENAME "\t" $0; nextfile }' > "$_bp_org" 2>/dev/null || true
  fi
  rm -f "$_bp_pmf"

  # The verdict: all graph reasoning in one place, over compiler-owned data.
  #   RESUME <plan> <head>  an origin plan exists whose origin is an ancestor
  #                         of a live head - the crash leg; finish the tombstone
  #   DONE <plan>           the origin chain is fully retired - replay no-op
  #   CREATE                no related origin plan; make a fresh one
  #   AMBIGPLAN/AMBIGHEAD   more than one candidate; the operator must pick
  #   SUPERSEDED <head>     the needle names a dead record whose family has a
  #                         live head under another name
  #   RETIRED <id>          the needle names a retired chain with no plan link
  #   NOMATCH               the needle names nothing in the tree
  _bp_verdict=$(awk -F"$_bp_tab" -v needle="$_bp_needle" -v headid="$_bp_id" '
    function ancof(h, o,   qh, qt, q, cur, m, tg, t, seen) {
      # is o an ancestor of h (h included) over applied edges?
      if (h == o) return 1
      qh = 1; qt = 1; q[1] = h
      while (qh <= qt) {
        cur = q[qh++]
        if (cur in seen) continue
        seen[cur] = 1
        if (cur == o) return 1
        if (cur in asup) {
          m = split(asup[cur], tg, ",")
          for (t = 1; t <= m; t++) if (tg[t] != "") q[++qt] = tg[t]
        }
      }
      return 0
    }
    FNR == NR {
      ids[++n] = $1; grp[$1] = $2; live[$1] = $3
      if ($5 != "-" && $5 != "") asup[$1] = $5
      next
    }
    { if (!($2 in op)) { op[$2] = $1 } else { op[$2] = op[$2] "\t" $1 } }
    END {
      if (headid != "") {
        np = 0
        for (o in op) if (ancof(headid, o)) plans[++np] = op[o]
        if (np == 0) { print "CREATE"; exit }
        if (np == 1 && index(plans[1], "\t") == 0) { print "RESUME\t" plans[1] "\t" headid; exit }
        printf "AMBIGPLAN"
        for (i = 1; i <= np; i++) printf "\t%s", plans[i]
        print ""
        exit
      }
      ni = 0
      for (i = 1; i <= n; i++) {
        id = ids[i]
        s = (length(id) > 17) ? substr(id, 12, length(id) - 17) : ""
        if (id == needle || s == needle) { nid[++ni] = id; ngrp[grp[id]] = 1 }
      }
      if (ni == 0) { print "NOMATCH"; exit }
      nres = 0; ndone = 0
      for (o in op) {
        if (!(grp[o] in ngrp)) continue
        if (index(op[o], "\t") > 0) { printf "AMBIGPLAN\t%s\n", op[o]; exit }
        nh = 0
        for (i = 1; i <= n; i++)
          if (live[ids[i]] == 1 && ancof(ids[i], o)) hh[++nh] = ids[i]
        if (nh == 0) { ndone++; doneplan = op[o] }
        else if (nh == 1) { nres++; resplan = op[o]; reshead = hh[1] }
        else {
          printf "AMBIGHEAD"
          for (i = 1; i <= nh; i++) printf "\t%s", hh[i]
          print ""
          exit
        }
      }
      if (nres > 1) { print "AMBIGPLAN"; exit }
      if (nres == 1) { print "RESUME\t" resplan "\t" reshead; exit }
      if (ndone > 0) { print "DONE\t" doneplan; exit }
      # no plan is linked to this family: say what the needle actually is
      for (i = 1; i <= n; i++) {
        id = ids[i]
        if (live[id] == 1 && (grp[id] in ngrp)) { print "SUPERSEDED\t" id; exit }
      }
      print "RETIRED\t" nid[1]
    }
  ' "$_bp_graph" "$_bp_org")
  rm -f "$_bp_graph" "$_bp_org"

  _bp_kind=${_bp_verdict%%"$_bp_tab"*}
  _bp_rest=${_bp_verdict#*"$_bp_tab"}
  case "$_bp_kind" in
    DONE)
      _bp_pdir=$(dirname "$_bp_rest")
      rm -f "$_bp_err"
      echo "Already promoted: ${_bp_pdir#"$ROOT/"} carries this origin and the chain is retired."
      echo "Nothing to do."
      exit 0
      ;;
    RESUME)
      _bp_pf=${_bp_rest%%"$_bp_tab"*}
      _bp_rid=${_bp_rest##*"$_bp_tab"}
      _bp_pdir=$(dirname "$_bp_pf")
      _bp_pdirname=$(basename "$_bp_pdir")
      rm -f "$_bp_err"
      printf 'Promoted to plan %s.\n' "$_bp_pdirname" | sh "$INTERNAL/zamm-new-memory.sh" \
        --project-root "$ROOT" --tree backlog --type tombstone \
        --supersedes "$_bp_rid" "$(id_to_slug "$_bp_rid")" >/dev/null ||
        die "backlog promote: could not write the tombstone"
      echo "Resumed an interrupted promote: ${_bp_pdir#"$ROOT/"} already existed;"
      echo "the tombstone retiring $_bp_rid is now written."
      exit 0
      ;;
    AMBIGPLAN)
      rm -f "$_bp_err"
      echo "zamm: backlog promote: more than one plan claims this idea family:" >&2
      printf '%s\n' "$_bp_rest" | tr "$_bp_tab" '\n' | while IFS= read -r _bp_p; do
        [ -n "$_bp_p" ] && echo "  ${_bp_p#"$ROOT/"}" >&2
      done
      echo "  Untangle by hand (each plan names its Origin-idea); nothing was changed." >&2
      exit 1
      ;;
    AMBIGHEAD)
      rm -f "$_bp_err"
      echo "zamm: backlog promote: the origin plan matches more than one live fork:" >&2
      printf '%s\n' "$_bp_rest" | tr "$_bp_tab" '\n' | sed 's/^/  /' >&2
      echo "  Promote the fork you mean by its full id; nothing was changed." >&2
      exit 1
      ;;
    SUPERSEDED)
      rm -f "$_bp_err"
      echo "zamm: \"$_bp_needle\" names a superseded record; the idea lives on as:" >&2
      echo "  $_bp_rest" >&2
      echo "  Promote that id (or backlog show it first)." >&2
      exit 1
      ;;
    RETIRED)
      rm -f "$_bp_err"
      echo "zamm: \"$_bp_needle\" matches a retired idea, not a live one." >&2
      echo "  Its chain records what happened: zamm-run.sh backlog show $_bp_rest" >&2
      exit 1
      ;;
    NOMATCH)
      cat "$_bp_err" >&2
      rm -f "$_bp_err"
      exit 1
      ;;
  esac
  rm -f "$_bp_err"
  # every non-CREATE verdict exited inside the case; anything else here with
  # no resolved head would promote nothing into a plan named after nothing
  if [ "$_bp_kind" != "CREATE" ] || [ -z "$_bp_id" ]; then
    die "backlog promote: internal error: unexpected verdict \"$_bp_verdict\""
  fi

  # CREATE: a fresh promote for the resolved live head
  _bp_hl=${_bp_row##*"$_bp_tab"}
  if [ $# -gt 0 ]; then
    _bp_title="$*"
  else
    _bp_title=$_bp_hl
  fi

  _bp_pf_rel=$(ZAMM_PLAN_ORIGIN="$_bp_id" plan_create "$_bp_title") ||
    die "backlog promote: plan creation failed"
  _bp_pdir_rel=${_bp_pf_rel%/*}
  _bp_pdirname=${_bp_pdir_rel##*/}

  printf 'Promoted to plan %s.\n' "$_bp_pdirname" | sh "$INTERNAL/zamm-new-memory.sh" \
    --project-root "$ROOT" --tree backlog --type tombstone \
    --supersedes "$_bp_id" "$(id_to_slug "$_bp_id")" >/dev/null || {
    echo "zamm: the plan was created but the tombstone was not written." >&2
    echo "  Rerun 'backlog promote $_bp_id' to finish (it will recognize the plan)." >&2
    exit 1
  }
  echo "Promoted: $_bp_id"
  echo "  plan: $_bp_pdir_rel (Origin-idea recorded)"
  echo "  the idea is retired in the backlog (tombstone names the plan)"
}

backlog_add() {
  case "${1-}" in -h|--help) group_usage backlog 0 ;; esac
  _ba_scope=""; _ba_slug=""; _ba_type="memory"; _ba_pos=""
  _ba_fwd=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope) [ $# -ge 2 ] || die "backlog add: --scope requires a value"; _ba_scope="$2"; shift 2 ;;
      --slug)  [ $# -ge 2 ] || die "backlog add: --slug requires a value"; _ba_slug="$2"; shift 2 ;;
      --type)  [ $# -ge 2 ] || die "backlog add: --type requires a value"; _ba_type="$2"; shift 2 ;;
      --supersedes|--importance|--durability|--date|--marked|--up|--down|--erases)
        [ $# -ge 2 ] || die "backlog add: $1 requires a value"
        # these values are charset-limited downstream (ids, dates, keywords);
        # refusing whitespace here keeps the accumulated list word-splittable
        case "$2" in
          *[!A-Za-z0-9,-]*) die "backlog add: $1 value contains characters the record contract refuses" ;;
        esac
        _ba_fwd="$_ba_fwd $1 $2"
        shift 2
        ;;
      --no-validate) _ba_fwd="$_ba_fwd --no-validate"; shift ;;
      -*) die "backlog add: unknown option: $1" ;;
      *)
        [ -z "$_ba_pos" ] || die "backlog add: more than one positional argument (quote the sentence)"
        _ba_pos="$1"; shift
        ;;
    esac
  done

  if [ "$_ba_type" != "memory" ]; then
    # tombstone/votes/erasure mirror memory create: the positional is the SLUG
    [ -n "$_ba_pos" ] || die "backlog add: --type $_ba_type needs a <topic-slug>"
    # shellcheck disable=SC2086 -- forwarded flags are whitespace-refusing by construction
    sh "$INTERNAL/zamm-new-memory.sh" --project-root "$ROOT" --tree backlog \
      --type "$_ba_type" ${_ba_scope:+--scope "$_ba_scope"} $_ba_fwd "$_ba_pos"
    return
  fi

  # the capture contract: one quoted sentence is a complete invocation
  [ -n "$_ba_pos" ] || die "backlog add: need the idea as one quoted sentence (e.g. backlog add 'We could ...')"
  if [ -z "$_ba_slug" ]; then
    _ba_slug=$(printf '%s' "$_ba_pos" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' |
      sed 's/^-*//; s/-*$//' | cut -c1-40 | sed 's/-*$//')
    [ -n "$_ba_slug" ] || die "backlog add: the sentence produced an empty slug; pass --slug"
  fi
  _ba_body="$_ba_pos"
  if [ ! -t 0 ]; then
    # Piped stdin is the idea's depth. An idea is progressive disclosure:
    # the sentence is the headline (all the lens ever shows), and anything
    # more — a paragraph or a whole book — lives under ## Background, which
    # the record contract leaves unbounded (only the digest block is
    # capped). Plain prose is therefore parked under ## Background
    # automatically; stdin that carries its own headings is an author-
    # structured body and passes through verbatim.
    _ba_extra=$(cat)
    if [ -n "$(printf '%s' "$_ba_extra" | tr -d '[:space:]')" ]; then
      if printf '%s\n' "$_ba_extra" | grep -q '^#'; then
        _ba_body="$_ba_body

$_ba_extra"
      else
        _ba_body="$_ba_body

## Background

$_ba_extra"
      fi
    fi
  fi
  # shellcheck disable=SC2086 -- forwarded flags are whitespace-refusing by construction
  printf '%s\n' "$_ba_body" | sh "$INTERNAL/zamm-new-memory.sh" \
    --project-root "$ROOT" --tree backlog \
    --scope "${_ba_scope:-other}" $_ba_fwd "$_ba_slug"
}

run_check_all() {
  crc=0; prc=0; xrc=0; brc=0
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --check || crc=$?
  # the backlog tree is optional (absence is data); when present it is
  # checked with the same rigor as the knowledge ledger
  if [ -d "$ROOT/zamm-memory/backlog" ]; then
    sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog --check || brc=$?
  fi
  sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" || prc=$?
  # cross-object reconciliation runs last: it assumes each side is individually
  # well-formed and only checks that plans and their votes records agree.
  sh "$INTERNAL/zamm-crosscheck.sh" --project-root "$ROOT" || xrc=$?
  # An enumeration failure (4) outranks a validation failure (1): "could not
  # read" must never be flattened into "checked and found problems".
  rc=0
  for c in $crc $brc $prc $xrc; do
    [ "$c" -eq 0 ] && continue
    [ "$c" -ge 2 ] && rc=4
    [ "$rc" -eq 0 ] && rc=1
  done
  exit "$rc"
}

# true if -h/--help appears anywhere in the args. Help is read-only and must
# never be blocked by the version gate (or interpreted as data, e.g. a title).
wants_help() {
  for _a in "$@"; do
    case "$_a" in -h|--help) return 0 ;; esac
  done
  return 1
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
        *)            group_usage memory 0 ;;  # incl. list/show/publish/drafts/discard (built-in)
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
    backlog) group_usage backlog 0 ;;           # every verb is a built-in
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
    # Help is read-only: route it before the version gate or the built-ins, so
    # `memory <verb> --help` works on a project of any (or no) protocol version.
    wants_help "$@" && do_help memory "$verb"
    case "$verb" in
      digest)
        # --help must reach the user, not the /dev/null the compile output goes to
        case "${1-}" in
          -h|--help) exec sh "$INTERNAL/zamm-compile.sh" --help ;;
        esac
        require_root; require_version
        # Propagate the compiler's exit code instead of flattening it. set -e
        # would otherwise abort here before the digest is printed: a degraded
        # publish (exit 2) still produced a digest and must be shown AND
        # signalled; a refusal (3) or unreadable ledger (4) produced none.
        rc=0
        sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" "$@" >/dev/null || rc=$?
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
          cat "$ROOT/zamm-memory/.compiled/memory.md"
          # after the digest, so it is the last thing on the way out, and on
          # stderr so it never lands inside piped digest content
          warn_if_surfaces_stale
        fi
        exit "$rc"
        ;;
      list)    require_root; require_version; memory_list "$@"; exit 0 ;;
      show)    require_root; require_version; memory_show "$@"; exit 0 ;;
      publish) require_root; require_version; memory_publish "$@"; exit 0 ;;
      drafts)  require_root; require_version; memory_drafts "$@"; exit 0 ;;
      discard) require_root; require_version; memory_discard "$@"; exit 0 ;;
      check)   TARGET="zamm-compile.sh"; set -- --check "$@" ;;
      create)  TARGET="zamm-new-memory.sh" ;;
      archive) TARGET="zamm-memory-archive.sh" ;;
      help|--help|-h) group_usage memory 0 ;;
      *) unknown "memory $verb" ;;
    esac
    require_root; require_version
    ;;

  backlog)
    [ $# -gt 0 ] || group_usage backlog 0
    verb="$1"; shift
    # Help is read-only: route it before the version gate or the built-ins.
    wants_help "$@" && do_help backlog "$verb"
    case "$verb" in
      add)     require_root; require_version; backlog_add "$@"; exit 0 ;;
      list)    require_root; require_version; backlog_list "$@"; exit 0 ;;
      show)    require_root; require_version; backlog_show "$@"; exit 0 ;;
      mark)    require_root; require_version; backlog_markctl mark "$@"; exit 0 ;;
      unmark)  require_root; require_version; backlog_markctl unmark "$@"; exit 0 ;;
      promote) require_root; require_version; backlog_promote "$@"; exit 0 ;;
      check)   require_root; require_version; backlog_check "$@"; exit 0 ;;
      help|--help|-h) group_usage backlog 0 ;;
      *) unknown "backlog $verb" ;;
    esac
    ;;

  plan)
    [ $# -gt 0 ] || group_usage plan 0
    verb="$1"; shift
    # Help is read-only: route it before the version gate or the built-ins.
    wants_help "$@" && do_help plan "$verb"
    case "$verb" in
      list)   TARGET="zamm-status.sh"; INTERP="bash" ;;
      show)   require_root; require_version; plan_show "$@"; exit 0 ;;
      create) require_root; require_version; plan_create "$@"; exit 0 ;;
      check)  TARGET="zamm-plan-check.sh" ;;
      archive)
        case "${1-}" in -h|--help) exec bash "$INTERNAL/zamm-archive.sh" --help ;; esac
        require_root; require_version
        # --list / --dry-run: a read-only preview of archive-ready plans. No
        # validation gate and no move — safe to run any time.
        case "${1-}" in
          --list|--dry-run)
            exec bash "$INTERNAL/zamm-archive.sh" --project-root "$ROOT"
            ;;
        esac
        # The default MOVES. A plan that fails validation must not become
        # archived history: this is what stops a Done plan with empty approval
        # fields.
        sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" >/dev/null || {
          echo "zamm: plan check failed; refusing to archive." >&2
          sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" >/dev/null 2>&1 || true
          sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" 2>&1 >/dev/null | sed 's/^/  /' >&2
          exit 1
        }
        # A plan is archived only when its own state AND its ledger side
        # effects agree: a mismatch between Memory-upvotes/downvotes and the
        # votes record must not be laundered into history by archiving.
        sh "$INTERNAL/zamm-crosscheck.sh" --project-root "$ROOT" >/dev/null 2>&1 || {
          echo "zamm: plan/ledger cross-check failed; refusing to archive." >&2
          sh "$INTERNAL/zamm-crosscheck.sh" --project-root "$ROOT" 2>&1 >/dev/null | sed 's/^/  /' >&2
          exit 1
        }
        exec bash "$INTERNAL/zamm-archive.sh" --project-root "$ROOT" --archive "$@"
        ;;
      help|--help|-h) group_usage plan 0 ;;
      *) unknown "plan $verb" ;;
    esac
    require_root; require_version
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
    require_root; require_version; run_check_all ;;

  *) unknown "$cmd" ;;
esac

[ -f "$INTERNAL/$TARGET" ] || die "missing script: $INTERNAL/$TARGET"

# exec, not a subshell: the child's exit code is this command's exit code.
# zamm-compile.sh exit 3 ("records exist but none survived; refusing to
# publish") is load-bearing and must not be flattened to 1.
exec "$INTERP" "$INTERNAL/$TARGET" --project-root "$ROOT" "$@"
