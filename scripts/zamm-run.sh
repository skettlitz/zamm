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
  status               health overview: ledger, backlog, journal, plans, drift
  check                validate everything (memory + backlog + journal + plans)
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

Journal
  journal add '<sentence>'
                       record an episode; one sentence is enough
  journal list [--all] [--scope <tag>] [--cue <slug>] [--since <date>]
                       the timeline lens, newest first (--all: dormant too;
                       filters print a row listing)
  journal show <slug>  one record in full
  journal search <predicates> [--text <pattern>] [--files]
                       structured query: --class --scope --cue --kind
                       --covers --agent --user --axis --since --until
  journal stats [--axis <name>] [<predicates>]
                       coverage-honest aggregates for the human
  journal export [<predicates>]
                       the versioned TSV seam for applications
  journal digest <YYYY[-MM]> [--detail ...] [--stats ...] [--elevations ...]
                       the compiled period view (never stored)
  journal elevate <kind> <YYYY[-MM]>
                       summarize a completed period; body on stdin
  journal review [--headlines] [--cue <slug>] [--scope <tag>] [--period <p>] [--pass <kind>]
                       read what triage has not covered yet
  journal settle [--through <date>] [--pass <kind>]
                       claim triage coverage with a watermark record
  journal check        validate the journal ledger

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
    journal) cat <<'EOF'
Usage: zamm-run.sh journal <command> [args...]

  add '<sentence>'     record an episode: the sentence is the headline, the
                       slug is derived, scope defaults to other, durability
                       to weeks; time/agent/user are stamped (ZAMM_AGENT,
                       the git identity). Pipe any depth on stdin (plain
                       prose parks under ## Background). Optional: --scope
                       <tag>, --cue <slug> (shipped cues: side-quest,
                       exceptional-occurrence, non-action, cross-plan-
                       context, blind-spot), --salience 1..10, --axis
                       name=value (repeatable; 0..10 unsigned or -5..+5
                       always signed), --x key=value (repeatable, lands as
                       x-key:), --agent/--user, --slug, --supersedes <id>,
                       --importance useful|minor, --durability. For --type
                       tombstone|erasure the positional is the SLUG.
  list [--all] [--scope <tag>] [--cue <slug>] [--since <date>]
                       recompile and print the timeline lens: months newest
                       first, dormant entries collapsed to counts (--all
                       lists them). A filter prints a row listing instead.
  show <slug|id>       one record in full
  search <predicates> [--text <pattern>] [--files]
                       rows matching every predicate, newest first (--files
                       prints paths for piping). Predicates: --class
                       entry|elevation|watermark, --scope, --cue, --kind,
                       --covers <period> (prefix), --agent, --user, --axis
                       name[(=|<|>)value], --since/--until; a leading !
                       negates. The same grammar drives export, stats and
                       digest.
  stats [--axis <name>] [<predicates>]
                       overview: every axis with type and coverage, per-cue
                       and per-agent/user counts; --axis <name> drills into
                       per-month nearest-rank quartiles (plus neg/zero/pos
                       for a bipolar axis). Entries only unless --class.
  export [<predicates>]
                       the read API for applications: a version line, a
                       column-name row, one TSV row per record (readers map
                       by name; columns only append within v1).
  digest <YYYY[-MM]> [--detail headlines|blocks|full] [--stats none|summary|full]
         [--elevations all|only|none] [<predicates>]
                       the compiled period view on stdout, never stored: a
                       month = stats + elevations + entries; a year = the
                       digest of digests (per-month rows, monthly
                       elevations with headline fallback, the yearly one).
                       A skill style is a saved flag combination.
  elevate <kind> <YYYY[-MM]>
                       summarize a COMPLETED period into a stored record
                       (type: digest), body on stdin: line one is all the
                       year view shows of the period, the block is what
                       the month view shows. Kinds monthly and yearly ship,
                       the set is open. The record names the entries it
                       saw and is its own coverage. Optional --scope,
                       --slug, --axis, --x.
  review [--headlines] [--cue <slug>] [--scope <tag>] [--period <p>] [--pass <kind>]
                       the reading surface for judgment digestion:
                       undigested entries oldest first (headlines only above
                       50); --period reads a whole calendar span; --cue and
                       --scope are reading aids, never coverage units.
  settle [--through <date>] [--pass <kind>]
                       claim triage coverage: writes a watermark naming the
                       entries it covers (today, or a partial boundary with
                       --through; refuses a non-advancing or future date,
                       and refuses while the journal is degraded). Headline
                       on stdin says what came of the review.
  check                validate the journal ledger, write nothing

Episodes, not facts: a durable rule found here is distilled into a knowledge
record, an implied action into a backlog idea; the journal keeps the trace.
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

  # ---- journal (optional tree; absence is data, not a gap to report) ----
  if [ -d "$ROOT/zamm-memory/journal" ]; then
    _jlens="$ROOT/zamm-memory/.compiled/journal.md"
    _jstate="$ROOT/zamm-memory/.compiled/journal-state.tsv"
    if [ ! -f "$_jlens" ]; then
      printf 'Journal   lens not yet compiled\n'
      printf '          run: zamm-run.sh memory digest\n'
    elif ! pair_coherent "$_jlens" "$_jstate" ||
         ! _jvals=$(awk -F"$(printf '\t')" '
             $1 == "entries"    { e = $2 }
             $1 == "undigested" { u = $2 }
             $1 == "elevations" { l = $2 }
             $1 == "watermark" && $2 == "triage" { w = $3 }
             END { print e "\t" u "\t" l "\t" w }
           ' "$_jstate" 2>/dev/null); then
      printf 'Journal   lens/state pair incoherent (interrupted compile, or a deleted sidecar)\n'
      printf '          run: zamm-run.sh memory digest\n'
    else
      _jtab=$(printf '\t')
      _jent=${_jvals%%"$_jtab"*}; _jrest=${_jvals#*"$_jtab"}
      _jund=${_jrest%%"$_jtab"*}; _jrest=${_jrest#*"$_jtab"}
      _jelv=${_jrest%%"$_jtab"*}; _jwm=${_jrest#*"$_jtab"}
      if [ -n "$_jwm" ]; then _jcov="reviewed through $_jwm"; else _jcov="never reviewed"; fi
      printf 'Journal   %s entries, %s undigested (%s), %s elevations\n' \
        "${_jent:-?}" "${_jund:-?}" "$_jcov" "${_jelv:-?}"
      awk -F"$_jtab" '
        $1 == "due_triage" { printf "          triage due: %s undigested, oldest %s (zamm-run.sh journal review)\n", $2, $3 }
        $1 == "due_elev"   { printf "          %s elevation due for %s (zamm-run.sh journal elevate %s %s)\n", $2, $3, $2, $3 }
      ' "$_jstate"
      if ! _jnw=$(find "$ROOT/zamm-memory/journal" -type f -name '*.md' -newer "$_jlens"); then
        echo 'zamm: cannot enumerate the journal tree (unreadable, not empty).' >&2
        exit 4
      fi
      _jnewer=$(printf '%s\n' "$_jnw" | grep -c . || true)
      if [ "${_jnewer:-0}" -gt 0 ]; then
        printf '          STALE: %s file(s) newer than the lens\n' "$_jnewer"
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
  [ -d "$ROOT/zamm-memory/journal" ] &&
    _rftrees="$_rftrees $ROOT/zamm-memory/journal"
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
    case "$rtree" in
      backlog) echo "  try: zamm-run.sh backlog list --all" >&2 ;;
      journal) echo "  try: zamm-run.sh journal list --all" >&2 ;;
      *)       echo "  try: zamm-run.sh memory list --all" >&2 ;;
    esac
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
    { sub(/\r$/, "") }
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
# is the frontmatter key PRESENT (even with an empty value)? An exact claim
# that named nothing is not the same as a record carrying no claim at all.
fm_has() {
  awk -v k="$2" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 == "---") { infm = 1; next } else exit }
    infm && $0 == "---" { exit }
    infm {
      p = index($0, ":")
      if (p > 1) {
        key = substr($0, 1, p - 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        if (key == k) { found = 1; exit }
      }
    }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# The compiler trims the key and strips a carriage return before deciding
# what a frontmatter line says; these read the same files, so they follow
# the same rules. Two parsers with different ideas of `covered :` or of a
# CRLF file is a divergence that only shows up as missing output.
fm_field() {
  awk -v k="$2" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 == "---") { infm = 1; next } else exit }
    infm && $0 == "---" { exit }
    infm {
      p = index($0, ":")
      if (p > 1) {
        key = substr($0, 1, p - 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        if (key == k) {
          v = substr($0, p + 1)
          sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
          print v
          exit
        }
      }
    }
  ' "$1"
}

# The record body: everything after the closing ---, leading blanks dropped.
# Line endings are normalized first, like the two key readers above and like
# the compiler: without it a CRLF record never matched its own closing fence,
# so the body read as EMPTY - a digest rendered an elevation heading with no
# summary under it, and `backlog mark` refused to copy a body it could not
# find. Records are written LF (.gitattributes says so), but one arriving
# from a Windows checkout still has to read.
fm_body() {
  awk '
    { sub(/\r$/, "") }
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

# ---------------- journal ----------------
# Episodes are ordinary records in zamm-memory/journal/ — same schema, same
# immutability, compiled by the same compiler into the timeline lens
# .compiled/journal.md. Three record classes share the tree: ENTRIES
# (type: memory), ELEVATIONS (type: digest — stored digests of a period)
# and WATERMARKS (type: memory + reviewed-through: — triage coverage
# claims). Digestion is a trichotomy: compiled views (`journal digest`,
# never stored), triage (`review`/`settle` behind a max-of-dates
# watermark) and elevation (`journal elevate`). Capture is as cheap as
# `backlog add`; the session digest carries one Journal: line only when
# digestion is due. Every read below is pulled.

JOURNAL_REVIEW_MAX=50   # review switches to headlines above this many entries
JOURNAL_RC=0
JOURNAL_TIME=""
JOURNAL_AGENT=""
JOURNAL_USER=""
JOURNAL_EXPORT_HEADER="# zamm-journal-export v1"
# the treeless answer to `journal export`: an empty seam is still a
# well-formed one. Must match the compiler row byte for byte (the suite
# compares both against one constant).
JOURNAL_EXPORT_COLUMNS="id	class	created	time	agent	user	cue	kind	covers	pass	reviewed-through	scope	salience	state	reviewed	bg	axes	headline	passes"
# Nearest-rank quartiles over a gv[group, i] array, spliced into every awk
# program here that reports them. Nearest rank is a golden-stability
# contract (deterministic, awk-portable, no interpolation), and the sidecar
# rows, journal stats and journal digest must never disagree about the same
# data - so the definition lives here once, matching the compiler side.
JOURNAL_AWK_QUARTILES='
    function nrank(n, p,   r) { r = int(p * n); if (r < p * n) r++; if (r < 1) r = 1; return r }
    function isort(g, n,   i, j, t) {
      for (i = 2; i <= n; i++) { t = gv[g, i]; j = i - 1
        while (j >= 1 && gv[g, j] > t) { gv[g, j + 1] = gv[g, j]; j-- }
        gv[g, j + 1] = t }
    }
'

require_journal_tree() {
  [ -d "$ROOT/zamm-memory/journal" ] ||
    die "no journal tree at zamm-memory/journal ('journal add' creates it)"
}

# Coverage-writing verbs (settle, elevate) refuse while the journal is
# degraded. A quarantined record is one NOBODY could review, and a claim
# written now covers it by date the moment it is repaired - it drops behind
# the watermark, or inside an elevated period, having never been read, and
# no rerun takes that back (guarantee 2). Capture is untouched: `journal
# add` never refuses, and reads only report the degradation.
require_clean_journal() {
  [ "$JOURNAL_RC" -eq 2 ] || return 0
  echo "zamm: journal $1: the journal is degraded - some records could not be read." >&2
  echo "      Refusing to write coverage over them: once they are repaired they would" >&2
  echo "      fall behind this claim by date, unreviewed, and no rerun can undo that." >&2
  echo "      Fix them first:  zamm-run.sh journal check" >&2
  exit 2
}

journal_today() { printf '%s\n' "${ZAMM_TODAY:-$(date +%Y-%m-%d)}"; }

# string comparison without relying on a non-POSIX `[ a \> b ]`
str_gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a "" > b "") }'; }

# a calendar period: YYYY or YYYY-MM with a real month
valid_period() {
  case "$1" in
    [0-9][0-9][0-9][0-9]) return 0 ;;
    [0-9][0-9][0-9][0-9]-0[1-9]|[0-9][0-9][0-9][0-9]-1[0-2]) return 0 ;;
  esac
  return 1
}

# recompile the lens; a degraded lens (2) is still published and read,
# anything else non-zero refuses (unreadable tree, nothing survived)
journal_compile() {
  JOURNAL_RC=0
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree journal >/dev/null || JOURNAL_RC=$?
  if [ "$JOURNAL_RC" -ne 0 ] && [ "$JOURNAL_RC" -ne 2 ]; then
    exit "$JOURNAL_RC"
  fi
}

# The export stream into a scratch file (a pipeline would mask an unreadable
# tree as an empty stream, G3). Prints "<rc><TAB><path>": the compile status
# travels WITH the data, so a read can propagate a degraded tree (exit 2)
# instead of handing an application a silently short dataset under exit 0.
# Runs inside $(...): callers MUST `|| exit $?`.
journal_export_tmp() {
  _je_tmp=$(mktemp "${TMPDIR:-/tmp}/zamm-journal-export.XXXXXX") ||
    { echo "zamm: journal: could not create a scratch file" >&2; return 1; }
  _je_rc=0
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree journal --export > "$_je_tmp" 2>/dev/null || _je_rc=$?
  if [ "$_je_rc" -ne 0 ] && [ "$_je_rc" -ne 2 ]; then
    rm -f "$_je_tmp"
    echo "zamm: the journal did not compile (rc=$_je_rc); run: zamm-run.sh journal check" >&2
    return "$_je_rc"
  fi
  printf '%s\t%s\n' "$_je_rc" "$_je_tmp"
}

# Exit a journal read, carrying the compile status. Exit 2 must always pair
# with a visible notice (the taxonomy contract), and for a read that notice
# is what tells a consumer its rows are missing whatever was quarantined.
journal_exit() {
  if [ "${1:-0}" -eq 2 ]; then
    echo "zamm: the journal tree is degraded: the rows above omit quarantined records." >&2
    echo "      Run: zamm-run.sh journal check" >&2
  fi
  exit "${1:-0}"
}

# a record path from its id (year directory = the id's year); archived
# records resolve through the slower checked lookup
journal_record_path() {
  _jrp="$ROOT/zamm-memory/journal/${1%%-*}/$1.md"
  if [ -f "$_jrp" ]; then printf '%s\n' "$_jrp"; else resolve_record "$1" journal; fi
}

# an identity token: lowercase, [a-z0-9.@+-], leading punctuation dropped
journal_token() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9.@+' '-' | sed 's/^[-.@+]*//; s/-*$//'
}

# Provenance stamps for every journal write: time from the clock (ZAMM_TIME
# pins it, test-only), agent from --agent/ZAMM_AGENT, user from
# --user/ZAMM_USER, else the git identity commits already carry (user.name,
# then the email local part) — nothing new is disclosed. Omitted with a
# notice when underivable; validation never refuses an unstamped record.
journal_stamps() {
  # Validated here and passed as SEPARATE quoted arguments below: these
  # values used to be joined into one string that every caller expanded
  # unquoted, so a ZAMM_TIME carrying spaces injected flags of its own and
  # turned an ordinary `journal add` into a coverage claim.
  JOURNAL_TIME=${ZAMM_TIME:-$(date +%H:%M)}
  case "$JOURNAL_TIME" in
    [01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;;
    *) die "journal: ZAMM_TIME must be HH:MM (got: $JOURNAL_TIME)" ;;
  esac
  _js_time=$JOURNAL_TIME
  _js_agent=$(journal_token "${1:-${ZAMM_AGENT:-}}")
  _js_user=${2:-${ZAMM_USER:-}}
  if [ -z "$_js_user" ]; then
    _js_user=$(git config user.name 2>/dev/null || true)
    if [ -z "$_js_user" ]; then
      _js_user=$(git config user.email 2>/dev/null | sed 's/@.*//' || true)
    fi
  fi
  _js_user=$(journal_token "$_js_user")
  if [ -z "$_js_agent" ]; then
    echo "zamm: agent: omitted (pass --agent or set ZAMM_AGENT so the record self-identifies)" >&2
  fi
  if [ -z "$_js_user" ]; then
    echo "zamm: user: omitted (no git identity; pass --user or set ZAMM_USER)" >&2
  fi
  JOURNAL_AGENT=$_js_agent
  JOURNAL_USER=$_js_user
}

# ---- one predicate grammar, shared by search, export, stats and digest ----
# --class entry|elevation|watermark, --scope <tag> (prefix match, any tag),
# --cue, --kind, --covers <period> (prefix on the calendar grammar, so
# --covers 2026 finds the monthlies and the yearly), --agent, --user,
# --axis name[(=|>|<)value], --since/--until YYYY[-MM[-DD]]. A leading !
# negates one value; a repeated key ORs its positive values. Accumulated as
# key<TAB>value lines and handed to awk through the environment (a -v value
# must not carry a newline on BSD awk).
JP=""
JP_TAB=$(printf '\t')
JP_NL='
'
# An axis predicate is `name` (rated at all) or `name(=|<|>)<integer>`. The
# operand must be a real integer: awk coerces anything else to 0, so an
# unvalidated `--axis mood=garbage` silently became `mood == 0` and returned
# rows nobody asked for. One operator only, and it splits where jp_filter
# splits (the first of = < >).
jp_axis_ok() {
  case "$1" in
    *=*)   _jan=${1%%=*};   _jav=${1#*=} ;;
    *'<'*) _jan=${1%%'<'*}; _jav=${1#*'<'} ;;
    *'>'*) _jan=${1%%'>'*}; _jav=${1#*'>'} ;;
    *)     _jan=$1;         _jav="" ;;
  esac
  case "$_jan" in ''|*[!a-z0-9-]*|-*|*-) return 1 ;; esac
  case "$1" in
    *=*|*'<'*|*'>'*)
      case "${_jav#[+-]}" in ''|*[!0-9]*) return 1 ;; esac
      ;;
  esac
  return 0
}

jp_add() {
  _jpk="$1"; _jpv="$2"; _jpwho="$3"
  case "$_jpv" in
    ''|*[![:print:]]*|*"$JP_TAB"*) die "$_jpwho: --$_jpk requires one printable value" ;;
  esac
  _jpbare=${_jpv#!}
  case "$_jpk" in
    coveredby)
      case "$_jpbare" in ''|*[!a-z0-9-]*|-*) die "$_jpwho: --pass must be a kind slug [a-z0-9-] (got: $_jpbare)" ;; esac ;;
    class|sectionclass)
      case "$_jpbare" in entry|elevation|watermark) ;;
        *) die "$_jpwho: --class must be entry, elevation or watermark (got: $_jpbare)" ;;
      esac ;;
    since|until|sectionsince|sectionuntil)
      case "$_jpbare" in
        [0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        *) die "$_jpwho: --$_jpk takes YYYY, YYYY-MM or YYYY-MM-DD (got: $_jpbare)" ;;
      esac ;;
    covers|sectioncovers)
      valid_period "$_jpbare" || die "$_jpwho: --covers takes YYYY or YYYY-MM (got: $_jpbare)" ;;
    axis)
      jp_axis_ok "$_jpbare" ||
        die "$_jpwho: --axis takes <name> or <name>(=|<|>)<integer> (got: $_jpbare)" ;;
  esac
  JP="$JP$_jpk$JP_TAB$_jpv$JP_NL"
}

# 0 when $1 is a predicate flag (consumes $1 $2 into JP), 1 otherwise
jp_flag() {
  case "$1" in
    --class|--scope|--cue|--kind|--covers|--agent|--user|--axis|--since|--until)
      jp_add "${1#--}" "$2" "$3"
      return 0 ;;
  esac
  return 1
}

# filter export rows on stdin by the accumulated predicates; keep=1 passes
# the two header lines through (export), else they are dropped
jp_filter() {
  ZAMM_JP="$JP" awk -F"$JP_TAB" -v keep="${1:-0}" '
    BEGIN {
      np = split(ENVIRON["ZAMM_JP"], pl, "\n")
      for (i = 1; i <= np; i++) {
        if (pl[i] == "") continue
        t = index(pl[i], "\t"); k = substr(pl[i], 1, t - 1); v = substr(pl[i], t + 1)
        if (substr(v, 1, 1) == "!") { v = substr(v, 2); nn[k]++; nv[k, nn[k]] = v }
        else { pn[k]++; pv[k, pn[k]] = v }
        keys[k] = 1
      }
    }
    function trimv(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }
    function axval(name,   n, a, i, p) {
      if (name == "salience") return ($13 == "-") ? "" : $13
      if ($17 == "-") return ""
      n = split($17, a, " ")
      for (i = 1; i <= n; i++) {
        p = index(a[i], "=")
        if (substr(a[i], 1, p - 1) == name) return substr(a[i], p + 1)
      }
      return ""
    }
    function one(k, v,   n, tg, i, t, p, op, name, want, have) {
      # sectionclass is the internal constraint a digest section adds for
      # itself. A separate KEY, because repeated values of one key OR
      # together: adding another `class` would widen the caller predicate
      # instead of narrowing it, and `--class watermark` would list
      # watermarks under Entries.
      if (k == "class" || k == "sectionclass") return ($2 == v)
      if (k == "cue")    return ($7 == v)
      if (k == "kind")   return ($8 == v)
      if (k == "agent")  return ($5 == v)
      if (k == "user")   return ($6 == v)
      # section* keys are the bounds the digest adds for itself, as a
      # separate KEY because
      # repeated values of one key OR together: adding another `since`
      # widened the caller selection instead of narrowing it, so
      # `digest 2026-06 --since 2026-06-15` showed all of June.
      if (k == "since" || k == "sectionsince") return ($3 >= v)
      if (k == "until" || k == "sectionuntil") return (substr($3, 1, length(v)) <= v)
      if (k == "covers" || k == "sectioncovers") return ($9 != "-" && substr($9, 1, length(v)) == v)
      if (k == "coveredby") {
        if ($19 == "-" || $19 == "") return 0
        n = split($19, tg, " ")
        for (i = 1; i <= n; i++) if (tg[i] == v) return 1
        return 0
      }
      if (k == "scope") {
        n = split($12, tg, ",")
        for (i = 1; i <= n; i++) {
          t = trimv(tg[i])
          if (t == v || substr(t, 1, length(v) + 1) == v "/") return 1
        }
        return 0
      }
      if (k == "axis") {
        p = match(v, /[=<>]/)
        if (p == 0) return (axval(v) != "")
        name = substr(v, 1, p - 1); op = substr(v, p, 1); want = substr(v, p + 1) + 0
        have = axval(name)
        if (have == "") return 0
        have = have + 0
        if (op == "=") return (have == want)
        if (op == "<") return (have < want)
        return (have > want)
      }
      return 0
    }
    NR <= 2 { if (keep) print; next }
    {
      ok = 1
      for (k in keys) {
        if (pn[k] > 0) {
          hit = 0
          for (i = 1; i <= pn[k]; i++) if (one(k, pv[k, i])) { hit = 1; break }
          if (!hit) { ok = 0; break }
        }
        for (i = 1; i <= nn[k]; i++) if (one(k, nv[k, i])) { ok = 0; break }
        if (!ok) break
      }
      if (ok) print
    }
  '
}

# the digest block of a record on stdout: mode block (everything above the
# first heading), rest (the block minus its headline paragraph, indented) or
# full (the whole body)
journal_block() {
  fm_body "$1" | awk -v mode="$2" '
    mode == "full" { print; next }
    /^#/ { exit }
    mode == "block" { print; next }
    {
      ln = $0; sub(/^[ \t]+/, "", ln); sub(/[ \t]+$/, "", ln)
      if (!started) { if (ln == "") next; started = 1 }
      if (!paradone) { if (ln == "") paradone = 1; next }
      if (ln != "") print "  " ln
    }
  '
}

# "1 entry" / "2 entries": counts in prose, not bare numbers with a plural
plural() { if [ "$1" -eq 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }

journal_check() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  [ $# -eq 0 ] || die "journal check takes no arguments (got: $*)"
  if [ ! -d "$ROOT/zamm-memory/journal" ]; then
    echo "ZAMM journal: no journal tree; nothing to check. ('journal add' creates it.)"
    exit 0
  fi
  exec sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree journal --check
}

journal_add() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  _ja_scope=""; _ja_slug=""; _ja_type="memory"; _ja_pos=""; _ja_agent=""; _ja_user=""
  # Rotation: each original argument is consumed once; flags that go to
  # the writer are re-appended as REAL arguments, so a --x value may hold
  # spaces without any word-splitting hazard. After the loop "$@" is
  # exactly the forwarded flag list.
  _ja_n=$#
  while [ "$_ja_n" -gt 0 ]; do
    case "$1" in
      --scope) [ $# -ge 2 ] || die "journal add: --scope requires a value"; _ja_scope="$2"; shift 2; _ja_n=$((_ja_n - 2)) ;;
      --slug)  [ $# -ge 2 ] || die "journal add: --slug requires a value"; _ja_slug="$2"; shift 2; _ja_n=$((_ja_n - 2)) ;;
      --type)  [ $# -ge 2 ] || die "journal add: --type requires a value"; _ja_type="$2"; shift 2; _ja_n=$((_ja_n - 2)) ;;
      --agent) [ $# -ge 2 ] || die "journal add: --agent requires a value"; _ja_agent="$2"; shift 2; _ja_n=$((_ja_n - 2)) ;;
      --user)  [ $# -ge 2 ] || die "journal add: --user requires a value"; _ja_user="$2"; shift 2; _ja_n=$((_ja_n - 2)) ;;
      --cue|--salience|--supersedes|--importance|--durability|--erases|--date|--axis|--x)
        [ $# -ge 2 ] || die "journal add: $1 requires a value"
        set -- "$@" "$1" "$2"; shift 2; _ja_n=$((_ja_n - 2)) ;;
      --no-validate) set -- "$@" "$1"; shift; _ja_n=$((_ja_n - 1)) ;;
      -*) die "journal add: unknown option: $1" ;;
      *)
        [ -z "$_ja_pos" ] || die "journal add: more than one positional argument (quote the sentence)"
        _ja_pos="$1"; shift; _ja_n=$((_ja_n - 1)) ;;
    esac
  done
  _ja_today=$(journal_today)
  if [ "$_ja_type" != "memory" ]; then
    # tombstone/erasure mirror memory create: the positional is the SLUG
    [ -n "$_ja_pos" ] || die "journal add: --type $_ja_type needs a <topic-slug>"
    journal_stamps "$_ja_agent" "$_ja_user"
    # shellcheck disable=SC2086 -- each stamp is one validated word
    sh "$INTERNAL/zamm-new-memory.sh" --project-root "$ROOT" --tree journal \
      --type "$_ja_type" ${_ja_scope:+--scope "$_ja_scope"} --date "$_ja_today" \
      --time "$JOURNAL_TIME" ${JOURNAL_AGENT:+--agent "$JOURNAL_AGENT"} ${JOURNAL_USER:+--user "$JOURNAL_USER"} \
      "$@" "$_ja_pos"
    return
  fi
  # the capture contract: one quoted sentence is a complete invocation
  [ -n "$_ja_pos" ] || die "journal add: need the episode as one quoted sentence (e.g. journal add 'CI was red four hours; upstream outage, nothing local.')"
  if [ -z "$_ja_slug" ]; then
    _ja_slug=$(printf '%s' "$_ja_pos" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' |
      sed 's/^-*//; s/-*$//' | cut -c1-40 | sed 's/-*$//')
    [ -n "$_ja_slug" ] || die "journal add: the sentence produced an empty slug; pass --slug"
  fi
  _ja_body="$_ja_pos"
  if [ ! -t 0 ]; then
    # progressive disclosure, exactly as backlog add: the sentence is the
    # headline, piped depth parks under ## Background unless it carries
    # its own headings
    _ja_extra=$(cat)
    if [ -n "$(printf '%s' "$_ja_extra" | tr -d '[:space:]')" ]; then
      if printf '%s\n' "$_ja_extra" | grep -q '^#'; then
        _ja_body="$_ja_body

$_ja_extra"
      else
        _ja_body="$_ja_body

## Background

$_ja_extra"
      fi
    fi
  fi
  journal_stamps "$_ja_agent" "$_ja_user"
  # shellcheck disable=SC2086 -- each stamp is one validated word
  printf '%s\n' "$_ja_body" | sh "$INTERNAL/zamm-new-memory.sh" \
    --project-root "$ROOT" --tree journal \
    --scope "${_ja_scope:-other}" --date "$_ja_today" \
    --time "$JOURNAL_TIME" ${JOURNAL_AGENT:+--agent "$JOURNAL_AGENT"} ${JOURNAL_USER:+--user "$JOURNAL_USER"} \
    "$@" "$_ja_slug"
}

journal_list() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  _jl_all=0; _jl_scope=""; _jl_cue=""; _jl_since=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) _jl_all=1; shift ;;
      --scope) [ $# -ge 2 ] || die "journal list: --scope requires an area or area/subpath"; _jl_scope="$2"; shift 2 ;;
      --cue)   [ $# -ge 2 ] || die "journal list: --cue requires a slug"; _jl_cue="$2"; shift 2 ;;
      --since) [ $# -ge 2 ] || die "journal list: --since requires YYYY[-MM[-DD]]"; _jl_since="$2"; shift 2 ;;
      *) die "journal list: unknown argument: $1" ;;
    esac
  done
  if [ ! -d "$ROOT/zamm-memory/journal" ]; then
    echo "ZAMM journal: empty - no zamm-memory/journal/ tree yet ('journal add' creates it)."
    exit 0
  fi
  journal_compile
  if [ -n "$_jl_scope$_jl_cue$_jl_since" ]; then
    # the query surface: a filtered ROW listing, entries only, dormant
    # excluded unless --all (the unfiltered lens stays the one pulled read)
    JP=""
    jp_add class entry "journal list"
    [ -z "$_jl_scope" ] || jp_add scope "$_jl_scope" "journal list"
    [ -z "$_jl_cue" ] || jp_add cue "$_jl_cue" "journal list"
    [ -z "$_jl_since" ] || jp_add since "$_jl_since" "journal list"
    _jl_x=$(journal_export_tmp) || exit $?
    _jl_x=${_jl_x#*"$JP_TAB"}
    jp_filter 0 < "$_jl_x" |
    while IFS="$JP_TAB" read -r _id _cls _cr _tm _ag _us _cue _kd _cv _ps _rt _sc _sal _st _rv _bg _ax _hl _pss; do
      [ -n "$_id" ] || continue
      if [ "$_jl_all" -eq 0 ] && [ "$_st" = "dormant" ]; then continue; fi
      printf '%s  %-22s %s [%s]\n' "$_cr" "$_sc" "$(printf '%s' "$_hl" | cut -c1-60)" "$_id"
    done
    rm -f "$_jl_x"
    journal_exit "$JOURNAL_RC"
  fi
  cat "$ROOT/zamm-memory/.compiled/journal.md"
  if [ "$_jl_all" -eq 1 ]; then
    JP=""
    jp_add class entry "journal list"
    _jl_x=$(journal_export_tmp) || exit $?
    _jl_x=${_jl_x#*"$JP_TAB"}
    jp_filter 0 < "$_jl_x" | awk -F"$JP_TAB" '
      $14 == "dormant" {
        if (!hdr) { print ""; print "Dormant entries (decayed below the floor; still the record of what happened):"; hdr = 1 }
        print "- " $3 "  " $18 " [" $1 "]"
      }'
    rm -f "$_jl_x"
  fi
  # the lens itself carries the ## Degraded section, so the status alone
  # is the signal here
  exit "$JOURNAL_RC"
}

journal_show() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  [ $# -ge 1 ] || die "journal show: need a slug or record id"
  [ $# -le 1 ] || die "journal show: too many arguments (one slug or id)"
  require_journal_tree
  path=$(resolve_record "$1" journal)
  rel="${path#"$ROOT/"}"
  case "$rel" in
    */archive/journal/*) echo "# $rel  (ARCHIVED - fully-retired chain)" ;;
    *) echo "# $rel" ;;
  esac
  echo
  cat "$path"
}

journal_export() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  JP=""
  while [ $# -gt 0 ]; do
    if jp_flag "$1" "${2-}" "journal export"; then shift 2; continue; fi
    die "journal export: unknown argument: $1 (predicates: --class --scope --cue --kind --covers --agent --user --axis --since --until)"
  done
  if [ ! -d "$ROOT/zamm-memory/journal" ]; then
    # absence is data: an empty seam is still a well-formed seam
    printf '%s\n%s\n' "$JOURNAL_EXPORT_HEADER" "$JOURNAL_EXPORT_COLUMNS"
    exit 0
  fi
  _jx=$(journal_export_tmp) || exit $?
  _jxrc=${_jx%%"$JP_TAB"*}; _jx=${_jx#*"$JP_TAB"}
  jp_filter 1 < "$_jx"
  rm -f "$_jx"
  journal_exit "$_jxrc"
}

journal_search() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  JP=""; _jse_text=""; _jse_files=0
  while [ $# -gt 0 ]; do
    if jp_flag "$1" "${2-}" "journal search"; then shift 2; continue; fi
    case "$1" in
      --text)  [ $# -ge 2 ] || die "journal search: --text requires a pattern"; _jse_text="$2"; shift 2 ;;
      --files) _jse_files=1; shift ;;
      *) die "journal search: unknown argument: $1 (predicates: --class --scope --cue --kind --covers --agent --user --axis --since --until; plus --text <pattern>, --files)" ;;
    esac
  done
  if [ ! -d "$ROOT/zamm-memory/journal" ]; then
    echo "ZAMM journal: empty - nothing to search ('journal add' creates the tree)." >&2
    exit 0
  fi
  # A pattern grep cannot compile exits 2, exactly as an unreadable file
  # does. Validating it once here against empty input separates the two, so
  # a later 2 can only be the file - and a typo refuses instead of reading
  # as an honest "no matches".
  if [ -n "$_jse_text" ]; then
    if printf '' | grep -q -e "$_jse_text" 2>/dev/null; then :; else
      _jse_grc=$?
      [ "$_jse_grc" -le 1 ] ||
        die "journal search: --text is not a valid pattern: $_jse_text"
    fi
  fi
  # no journal_compile here: the export IS a full parse of the tree, and
  # this verb reads neither the lens nor the sidecar - compiling first
  # parsed everything twice for no observable effect
  _jx=$(journal_export_tmp) || exit $?
  _jxrc=${_jx%%"$JP_TAB"*}; _jx=${_jx#*"$JP_TAB"}
  # the rows land in a file, so the loop runs in THIS shell: an unreadable
  # record has to be able to exit 4 (G3), which it cannot do from the
  # subshell a pipeline would put it in
  _jse_rows=$(mktemp "${TMPDIR:-/tmp}/zamm-journal-search.XXXXXX") ||
    die "journal search: could not create a scratch file"
  jp_filter 0 < "$_jx" > "$_jse_rows"
  rm -f "$_jx"
  while IFS="$JP_TAB" read -r _id _cls _cr _tm _ag _us _cue _kd _cv _ps _rt _sc _sal _st _rv _bg _ax _hl _pss; do
    [ -n "$_id" ] || continue
    _p=$(journal_record_path "$_id") || continue
    if [ -n "$_jse_text" ]; then
      if grep -q -e "$_jse_text" "$_p" 2>/dev/null; then :; else
        _jse_grc=$?
        if [ "$_jse_grc" -gt 1 ]; then
          rm -f "$_jse_rows"
          echo "zamm: journal search: cannot read ${_p#"$ROOT/"} (unreadable, not empty)." >&2
          exit 4
        fi
        continue
      fi
    fi
    if [ "$_jse_files" -eq 1 ]; then
      echo "${_p#"$ROOT/"}"
    else
      printf '%s  %s\n' "$_id" "$_hl"
    fi
  done < "$_jse_rows"
  rm -f "$_jse_rows"
  journal_exit "$_jxrc"
}

journal_stats() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  JP=""; _jst_axis=""; _jst_class=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --axis)
        # a bare name drills into that axis; with an operator it is the
        # shared predicate (rows rating the axis a certain way)
        [ $# -ge 2 ] || die "journal stats: --axis requires an axis name"
        case "$2" in
          *[=\<\>]*) jp_add axis "$2" "journal stats" ;;
          *) [ -z "$_jst_axis" ] || die "journal stats: one --axis to drill into"; _jst_axis="$2" ;;
        esac
        shift 2 ;;
      --class) _jst_class=1; jp_flag "$1" "${2-}" "journal stats"; shift 2 ;;
      *)
        if jp_flag "$1" "${2-}" "journal stats"; then shift 2; continue; fi
        die "journal stats: unknown argument: $1" ;;
    esac
  done
  # entries only by default: a month's digest must never double-count the
  # month it summarizes (--class elevation inspects them deliberately)
  [ "$_jst_class" -eq 1 ] || jp_add class entry "journal stats"
  if [ ! -d "$ROOT/zamm-memory/journal" ]; then
    echo "ZAMM journal: empty - no entries to count ('journal add' creates the tree)."
    exit 0
  fi
  # as in search: the export is the parse, and stats reads no sidecar
  _jx=$(journal_export_tmp) || exit $?
  _jxrc=${_jx%%"$JP_TAB"*}; _jx=${_jx#*"$JP_TAB"}
  jp_filter 0 < "$_jx" | awk -F"$JP_TAB" -v drill="$_jst_axis" "$JOURNAL_AWK_QUARTILES"'
    function axtype(v) { return (v ~ /^[+-]/) ? "bipolar" : "unipolar" }
    function seen(arr, ord, k, cnt) { if (!(k in arr)) { arr[k] = 0; ord[++cnt[0]] = k }; arr[k]++ }
    function rate(name, v,   ty, mo, g) {
      ty = axtype(v)
      if (!((name SUBSEP ty) in atn)) { atn[name SUBSEP ty] = 0; aord[++na] = name SUBSEP ty }
      atn[name SUBSEP ty]++
      if (drill != "" && name == drill) {
        mo = substr($3, 1, 7)
        g = mo SUBSEP ty
        if (!(g in gn)) { gn[g] = 0; gord[++ng] = g; tyseen[ty] = 1 }
        gv[g, ++gn[g]] = v + 0
        if (v + 0 < 0) neg[g]++; else if (v + 0 == 0) zero[g]++; else pos[g]++
      }
    }
    {
      n++
      mo = substr($3, 1, 7)
      if (!(mo in mn)) { mn[mo] = 0; mord[++nmo] = mo }
      mn[mo]++
      if (lo == "" || $3 < lo) lo = $3
      if (hi == "" || $3 > hi) hi = $3
      seen(cues, cord, $7, cc); seen(agents, agord, $5, ac); seen(users, uord, $6, uc)
      if ($13 != "-") rate("salience", $13)
      if ($17 != "-") {
        k = split($17, ax, " ")
        for (i = 1; i <= k; i++) { p = index(ax[i], "="); rate(substr(ax[i], 1, p - 1), substr(ax[i], p + 1)) }
      }
    }
    END {
      if (n == 0) { print "# ZAMM journal stats: no matching entries"; exit 0 }
      if (drill == "") {
        printf "# ZAMM journal stats: %d entries, %s through %s\n\n", n, substr(lo, 1, 7), substr(hi, 1, 7)
        print "axes (coverage = rated/entries; a sparse axis is never over-read):"
        if (na == 0) print "  (none rated)"
        for (i = 1; i <= na; i++) {
          split(aord[i], ap, SUBSEP)
          printf "  %-24s %-9s %d/%d rated (%d%%)\n", ap[1], ap[2], atn[aord[i]], n, int(100 * atn[aord[i]] / n + 0.5)
        }
        s = ""; for (i = 1; i <= cc[0]; i++) s = s ((i > 1) ? ", " : "") ((cord[i] == "-") ? "(none)" : cord[i]) " " cues[cord[i]]
        print "cues: " s
        s = ""; for (i = 1; i <= ac[0]; i++) s = s ((i > 1) ? ", " : "") ((agord[i] == "-") ? "(unstamped)" : agord[i]) " " agents[agord[i]]
        print "agents: " s
        s = ""; for (i = 1; i <= uc[0]; i++) s = s ((i > 1) ? ", " : "") ((uord[i] == "-") ? "(unstamped)" : uord[i]) " " users[uord[i]]
        print "users: " s
        s = ""; for (i = 1; i <= nmo; i++) s = s ((i > 1) ? ", " : "") mord[i] " " mn[mord[i]]
        print "months: " s
        exit 0
      }
      nty = 0; for (t in tyseen) nty++
      if (nty == 0) { printf "# axis %s: no entry rates it (%d entries)\n", drill, n; exit 0 }
      if (nty > 1) print "note: " drill " mixes signed and unsigned values across records (probable spelling drift); split by type"
      for (tt = 1; tt <= 2; tt++) {
        ty = (tt == 1) ? "unipolar" : "bipolar"
        if (!(ty in tyseen)) continue
        printf "# axis %s (%s %s), %s through %s\n\n", drill, ty, (ty == "bipolar") ? "-5..+5" : "0..10", substr(lo, 1, 7), substr(hi, 1, 7)
        if (ty == "bipolar") print "month     n  rated  p25  med  p75   neg  zero  pos"
        else print "month     n  rated  p25  med  p75"
        rated = 0
        for (i = 1; i <= nmo; i++) {
          mo = mord[i]; g = mo SUBSEP ty
          if (!(g in gn)) continue
          isort(g, gn[g]); rated += gn[g]
          if (ty == "bipolar")
            printf "%s %3d %6d  %+3d  %+3d  %+3d  %4d  %4d %4d\n", mo, mn[mo], gn[g], gv[g, nrank(gn[g], 0.25)], gv[g, nrank(gn[g], 0.5)], gv[g, nrank(gn[g], 0.75)], neg[g] + 0, zero[g] + 0, pos[g] + 0
          else
            printf "%s %3d %6d  %3d  %3d  %3d\n", mo, mn[mo], gn[g], gv[g, nrank(gn[g], 0.25)], gv[g, nrank(gn[g], 0.5)], gv[g, nrank(gn[g], 0.75)]
        }
        printf "\ncoverage: %d/%d entries rate this axis (%d%%)\n", rated, n, int(100 * rated / n + 0.5)
        if (tt == 1 && ("bipolar" in tyseen)) print ""
      }
    }
  '
  rm -f "$_jx"
  journal_exit "$_jxrc"
}

journal_review() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  _jr_head=0; _jr_cue=""; _jr_scope=""; _jr_period=""; _jr_pass=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --headlines) _jr_head=1; shift ;;
      --cue)    [ $# -ge 2 ] || die "journal review: --cue requires a slug"; _jr_cue="$2"; shift 2 ;;
      --scope)  [ $# -ge 2 ] || die "journal review: --scope requires an area or area/subpath"; _jr_scope="$2"; shift 2 ;;
      --period) [ $# -ge 2 ] || die "journal review: --period requires YYYY or YYYY-MM"; _jr_period="$2"; shift 2 ;;
      --pass)   [ $# -ge 2 ] || die "journal review: --pass requires a kind"; _jr_pass="$2"; shift 2 ;;
      *) die "journal review: unknown argument: $1" ;;
    esac
  done
  if [ -n "$_jr_period" ]; then
    valid_period "$_jr_period" || die "journal review: --period must be YYYY or YYYY-MM: $_jr_period"
    [ -z "$_jr_pass" ] || die "journal review: --period reads a calendar span, --pass an undigested set; pick one"
  fi
  if [ ! -d "$ROOT/zamm-memory/journal" ]; then
    echo "ZAMM journal: empty - nothing to review ('journal add' creates the tree)."
    exit 0
  fi
  journal_compile
  _jr_state="$ROOT/zamm-memory/.compiled/journal-state.tsv"
  _jr_wm=$(awk -F"$JP_TAB" -v p="${_jr_pass:-triage}" '$1 == "watermark" && $2 == p { print $3; exit }' "$_jr_state")
  # WHICH rows is the shared predicate grammar, exactly as in search,
  # export, stats and digest: undigested is `since <watermark>` (the
  # inclusive boundary), a period is the since/until bracket, and the two
  # reading aids are the ordinary --cue/--scope predicates. The awk below
  # only builds the sort key.
  JP=""
  jp_add class entry "journal review"
  if [ -n "$_jr_period" ]; then
    jp_add since "$_jr_period" "journal review"
    jp_add until "$_jr_period" "journal review"
  else
    # undigested is what no claim of this pass has NAMED - not a date range.
    # An entry written or merged after a claim, dated before its boundary,
    # is uncovered however old it looks.
    jp_add coveredby "!${_jr_pass:-triage}" "journal review"
  fi
  [ -z "$_jr_cue" ] || jp_add cue "$_jr_cue" "journal review"
  [ -z "$_jr_scope" ] || jp_add scope "$_jr_scope" "journal review"
  _jx=$(journal_export_tmp) || exit $?
  _jxrc=${_jx%%"$JP_TAB"*}; _jx=${_jx#*"$JP_TAB"}
  # oldest first; within a day salience first, then time, then id
  # the salience travels as its own field: deriving it back from the padded
  # sort key meant $((10 - 09)), and a leading zero is an octal literal in
  # shell arithmetic - salience 1 and 2 aborted the read mid-record
  _jr_rows=$(jp_filter 0 < "$_jx" | awk -F"$JP_TAB" '
    { s = ($13 == "-") ? 0 : $13 + 0; printf "%s\t%02d\t%s\t%s\t%s\t%s\n", $3, 10 - s, ($4 == "-") ? "~" : $4, $13, $1, $18 }
  ' | sort)
  rm -f "$_jx"
  _jr_n=$(printf '%s\n' "$_jr_rows" | grep -c . || true)
  # Entries dated ON the watermark stay listed by construction: the boundary
  # is inclusive so same-day work is never silently skipped, which means a
  # claim dated D cannot cover the entries of D. Say so, or the reader sees
  # a settle that reported them covered and a review that still lists them.
  _jr_same=0
  if [ -z "$_jr_period" ] && [ -n "$_jr_wm" ]; then
    _jr_same=$(printf '%s\n' "$_jr_rows" |
      awk -F"$JP_TAB" -v w="$_jr_wm" '$1 == w { n++ } END { print n + 0 }')
  fi
  _jr_what="$(plural "$_jr_n" entry entries)"
  if [ -n "$_jr_period" ]; then
    echo "# Journal review: $_jr_what in $_jr_period (a calendar span; watermark-independent)"
  elif [ -n "$_jr_wm" ]; then
    echo "# Journal review: $_jr_what undigested (${_jr_pass:-triage} reviewed through $_jr_wm; coverage is by record, not by date)"
  else
    echo "# Journal review: $_jr_what undigested (${_jr_pass:-triage} never settled)"
  fi
  [ "${_jr_same:-0}" -eq 0 ] ||
    echo "# $(plural "$_jr_same" "entry is" "entries are") dated on the watermark itself ($_jr_wm) and unnamed by the claim - still yours to read."
  [ -z "$_jr_cue" ] || echo "# cue filter: $_jr_cue - a reading aid, never a coverage unit (a settle after this pass alone would overclaim)"
  [ -z "$_jr_scope" ] || echo "# scope filter: $_jr_scope - a reading aid, never a coverage unit"
  if [ "${_jr_n:-0}" -eq 0 ]; then
    echo "(nothing to review)"
    journal_exit "$_jxrc"
  fi
  if [ "$_jr_head" -eq 0 ] && [ "$_jr_n" -gt "$JOURNAL_REVIEW_MAX" ]; then
    _jr_head=1
    echo "zamm: $_jr_n entries exceed JOURNAL_REVIEW_MAX=$JOURNAL_REVIEW_MAX; headlines only (journal show <id> opens one; settle --through <date> chunks the backlog)" >&2
  fi
  echo
  printf '%s\n' "$_jr_rows" | while IFS="$JP_TAB" read -r _d _rk _t _s _id _hl; do
    [ -n "$_id" ] || continue
    if [ "$_jr_head" -eq 1 ]; then
      printf -- '- %s  %s [%s]\n' "$_d" "$_hl" "$_id"
    else
      _p=$(journal_record_path "$_id") || continue
      echo "## $_id"
      _meta="$_d"
      [ "$_t" = "~" ] || _meta="$_meta $_t"
      _c=$(fm_field "$_p" cue); [ -z "$_c" ] || _meta="$_meta  cue: $_c"
      _sc=$(fm_field "$_p" scope); [ -z "$_sc" ] || _meta="$_meta  scope: $_sc"
      [ "$_s" = "-" ] || _meta="$_meta  salience: $_s"
      printf '%s\n' "$_meta"
      echo
      fm_body "$_p"
      echo
    fi
  done
  if [ -z "$_jr_period" ]; then
    echo
    echo "When done: distill patterns into knowledge records and implied actions into"
    echo "backlog ideas, then claim the coverage: zamm-run.sh journal settle${_jr_pass:+ --pass $_jr_pass} [--through <date>]"
  fi
  journal_exit "$_jxrc"
}

journal_settle() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  _jt_through=""; _jt_pass=""; _jt_agent=""; _jt_user=""
  _jt_n=$#
  while [ "$_jt_n" -gt 0 ]; do
    case "$1" in
      --through) [ $# -ge 2 ] || die "journal settle: --through requires a date"; _jt_through="$2"; shift 2; _jt_n=$((_jt_n - 2)) ;;
      --pass)    [ $# -ge 2 ] || die "journal settle: --pass requires a kind"; _jt_pass="$2"; shift 2; _jt_n=$((_jt_n - 2)) ;;
      --agent)   [ $# -ge 2 ] || die "journal settle: --agent requires a value"; _jt_agent="$2"; shift 2; _jt_n=$((_jt_n - 2)) ;;
      --user)    [ $# -ge 2 ] || die "journal settle: --user requires a value"; _jt_user="$2"; shift 2; _jt_n=$((_jt_n - 2)) ;;
      --x) [ $# -ge 2 ] || die "journal settle: --x requires key=value"; set -- "$@" "$1" "$2"; shift 2; _jt_n=$((_jt_n - 2)) ;;
      --no-validate) set -- "$@" "$1"; shift; _jt_n=$((_jt_n - 1)) ;;
      *) die "journal settle: unknown argument: $1" ;;
    esac
  done
  require_journal_tree
  journal_compile
  require_clean_journal settle
  _jt_today=$(journal_today)
  _jt_through=${_jt_through:-$_jt_today}
  valid_ymd "$_jt_through" || die "journal settle: --through must be a real YYYY-MM-DD date: $_jt_through"
  if str_gt "$_jt_through" "$_jt_today"; then
    die "journal settle: refusing the future date $_jt_through (an overclaim by construction; today is $_jt_today)"
  fi
  _jt_state="$ROOT/zamm-memory/.compiled/journal-state.tsv"
  _jt_cur=$(awk -F"$JP_TAB" -v p="${_jt_pass:-triage}" '$1 == "watermark" && $2 == p { print $3; exit }' "$_jt_state")
  if [ -n "$_jt_cur" ] && ! str_gt "$_jt_through" "$_jt_cur"; then
    die "journal settle: $_jt_through is not beyond the current ${_jt_pass:-triage} watermark $_jt_cur (a claim adding no coverage is a mistake, not a no-op)"
  fi
  # what this claim covers: entries from the standing claim (inclusive) up
  # to the new boundary (inclusive) - the headline narrates the maintenance
  _jx=$(journal_export_tmp) || exit $?
  _jxrc=${_jx%%"$JP_TAB"*}; _jx=${_jx#*"$JP_TAB"}
  # The claim NAMES the entries it covers. A date cannot carry that: an
  # entry written or merged later, dated before the boundary, existed for
  # nobody to review, and a date-only claim would retire it unread. Entries
  # dated exactly on the boundary are excluded, as before - this claim is
  # written today and cannot have seen the rest of today.
  _jt_out=$(awk -F"$JP_TAB" -v p="${_jt_pass:-triage}" -v thr="$_jt_through" '
    function covered(   n, tg, i) {
      if ($19 == "-" || $19 == "") return 0
      n = split($19, tg, " ")
      for (i = 1; i <= n; i++) if (tg[i] == p) return 1
      return 0
    }
    NR > 2 && $2 == "entry" && !covered() {
      if ($3 < thr) { ids = ids ((ids == "") ? "" : ",") $1; n++ }
      else if ($3 == thr) same++
    }
    END { printf "%d\t%d\t%s\n", n + 0, same + 0, ids }' "$_jx")
  rm -f "$_jx"
  _jt_cnt=${_jt_out%%"$JP_TAB"*}
  _jt_rest=${_jt_out#*"$JP_TAB"}
  _jt_same=${_jt_rest%%"$JP_TAB"*}
  _jt_ids=${_jt_rest#*"$JP_TAB"}
  _jt_body=""
  if [ ! -t 0 ]; then _jt_body=$(cat); fi
  if [ -z "$(printf '%s' "$_jt_body" | tr -d '[:space:]')" ]; then
    _jt_body="Reviewed $_jt_cnt entries through $_jt_through${_jt_pass:+ (pass $_jt_pass)}."
    if [ "${_jt_same:-0}" -gt 0 ]; then
      _jt_body="$_jt_body Not named: $(plural "$_jt_same" entry entries) dated $_jt_through."
    fi
  fi
  _jt_slug=$(printf '%s' "${_jt_pass:+$_jt_pass-}reviewed-through-$_jt_through" | cut -c1-40 | sed 's/-*$//')
  journal_stamps "$_jt_agent" "$_jt_user"
  # shellcheck disable=SC2086 -- each stamp is one validated word
  _jt_path=$(printf '%s\n' "$_jt_body" | sh "$INTERNAL/zamm-new-memory.sh" \
    --project-root "$ROOT" --tree journal --scope other \
    --reviewed-through "$_jt_through" ${_jt_pass:+--pass "$_jt_pass"} \
    --covered "$_jt_ids" \
    --date "$_jt_today" \
    --time "$JOURNAL_TIME" ${JOURNAL_AGENT:+--agent "$JOURNAL_AGENT"} ${JOURNAL_USER:+--user "$JOURNAL_USER"} \
    "$@" "$_jt_slug") ||
    die "journal settle: could not write the watermark"
  echo "Settled: ${_jt_pass:-triage} reviewed through $_jt_through ($_jt_cnt entries covered)."
  echo "  ${_jt_path#"$ROOT/"}"
  if [ "${_jt_same:-0}" -gt 0 ]; then
    echo "  Not named by this claim: $(plural "$_jt_same" entry entries) dated $_jt_through,"
    echo "  written after it. Those stay in the review set and clear on the next settle;"
    echo "  the digest does not nag meanwhile."
  fi
}

journal_elevate() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  [ $# -ge 2 ] || die "journal elevate: need <kind> <YYYY[-MM]> (the elevation body on stdin)"
  _je_kind="$1"; _je_period="$2"; shift 2
  case "$_je_kind" in
    ''|*[!a-z0-9-]*|-*) die "journal elevate: kind must be a slug [a-z0-9-]: $_je_kind" ;;
  esac
  valid_period "$_je_period" || die "journal elevate: period must be YYYY or YYYY-MM: $_je_period"
  _je_today=$(journal_today)
  # The period must be OVER. An elevation is a stored digest of a period,
  # and the year view renders it INSTEAD of that period's entries - so one
  # written mid-period hides every entry the period gains afterwards, with
  # nothing falling due to correct it. For a period still running, the
  # compiled view (journal digest <period>) is the live answer and is always
  # current; elevation is for the settled narrative.
  if ! str_gt "$(printf '%s' "$_je_today" | cut -c1-"${#_je_period}")" "$_je_period"; then
    die "journal elevate: $_je_period is not over yet (today is $_je_today); elevate a completed period, or read the live view with: zamm-run.sh journal digest $_je_period"
  fi
  _je_scope=""; _je_slug=""; _je_agent=""; _je_user=""; _je_sup=0
  _je_n=$#
  while [ "$_je_n" -gt 0 ]; do
    case "$1" in
      --scope) [ $# -ge 2 ] || die "journal elevate: --scope requires a value"; _je_scope="$2"; shift 2; _je_n=$((_je_n - 2)) ;;
      --slug)  [ $# -ge 2 ] || die "journal elevate: --slug requires a value"; _je_slug="$2"; shift 2; _je_n=$((_je_n - 2)) ;;
      --agent) [ $# -ge 2 ] || die "journal elevate: --agent requires a value"; _je_agent="$2"; shift 2; _je_n=$((_je_n - 2)) ;;
      --user)  [ $# -ge 2 ] || die "journal elevate: --user requires a value"; _je_user="$2"; shift 2; _je_n=$((_je_n - 2)) ;;
      --supersedes)
        [ $# -ge 2 ] || die "journal elevate: --supersedes requires a record id"
        _je_sup=1; set -- "$@" "$1" "$2"; shift 2; _je_n=$((_je_n - 2)) ;;
      --importance|--durability|--axis|--x)
        [ $# -ge 2 ] || die "journal elevate: $1 requires a value"
        set -- "$@" "$1" "$2"; shift 2; _je_n=$((_je_n - 2)) ;;
      --no-validate) set -- "$@" "$1"; shift; _je_n=$((_je_n - 1)) ;;
      *) die "journal elevate: unknown argument: $1" ;;
    esac
  done
  if [ -t 0 ]; then
    die "journal elevate: the elevation body arrives on stdin (line one: the period in one sentence, as the year view shows it; then the block the month view shows; optional ## Background)"
  fi
  _je_body=$(cat)
  [ -n "$(printf '%s' "$_je_body" | tr -d '[:space:]')" ] || die "journal elevate: the body on stdin is empty"
  # A correction SUPERSEDES; a second bare elevation of the same period is a
  # competing claim, and which one the views show then rests on a tiebreak
  # over random id suffixes. Say so before writing, and name the id.
  if [ -d "$ROOT/zamm-memory/journal" ]; then
    journal_compile
    require_clean_journal elevate
    _je_prior=""
    [ "$_je_sup" -eq 1 ] || _je_prior=$(awk -F"$JP_TAB" -v k="$_je_kind" -v p="$_je_period" \
      '$1 == "elev" && $2 == k && $3 == p { print $4; exit }' \
      "$ROOT/zamm-memory/.compiled/journal-state.tsv" 2>/dev/null || true)
    if [ -n "$_je_prior" ]; then
      echo "zamm: an elevation for $_je_kind $_je_period already exists:" >&2
      echo "        $_je_prior" >&2
      echo "      Writing another without --supersedes leaves two competing claims for one" >&2
      echo "      period. To correct the existing one instead, rerun with:" >&2
      echo "        --supersedes $_je_prior" >&2
    fi
  fi
  [ -n "$_je_slug" ] || _je_slug="$_je_kind-$_je_period"
  # The elevation NAMES the entries of the period it saw, the same claim
  # identity a watermark carries: an entry merged in afterwards, dated
  # inside the period, was never part of this narrative, and the year view
  # would otherwise render this record in its place forever.
  _je_ids=""
  if [ -d "$ROOT/zamm-memory/journal" ]; then
    _jex=$(journal_export_tmp) || exit $?
    _jex=${_jex#*"$JP_TAB"}
    _je_ids=$(awk -F"$JP_TAB" -v per="$_je_period" '
      NR > 2 && $2 == "entry" && substr($3, 1, length(per)) == per {
        ids = ids ((ids == "") ? "" : ",") $1
      }
      END { print ids }' "$_jex")
    rm -f "$_jex"
  fi
  journal_stamps "$_je_agent" "$_je_user"
  # durability years by default: an elevation never decays in the compiler
  # anyway, and it is the most durable output the journal produces
  # shellcheck disable=SC2086 -- each stamp is one validated word
  _je_path=$(printf '%s\n' "$_je_body" | sh "$INTERNAL/zamm-new-memory.sh" \
    --project-root "$ROOT" --tree journal --type digest \
    --digest "$_je_kind" --covers "$_je_period" --scope "${_je_scope:-other}" \
    --covered "$_je_ids" \
    --durability years --date "$_je_today" \
    --time "$JOURNAL_TIME" ${JOURNAL_AGENT:+--agent "$JOURNAL_AGENT"} ${JOURNAL_USER:+--user "$JOURNAL_USER"} \
    "$@" "$_je_slug") ||
    die "journal elevate: could not write the elevation"
  echo "Elevated: $_je_kind $_je_period"
  echo "  ${_je_path#"$ROOT/"} (the record is the coverage; no settle for elevations)"
}

# journal digest <YYYY[-MM]>: the compiled period view, the PRIMARY digest -
# automatic, composable, never stored. The period shape selects the base
# settings: a month renders stats + elevations + entries; a year is the
# digest of digests (per-month rows + monthly elevations with headline
# fallback + the yearly elevation). A style is a saved invocation of the
# flags below; there is no registry.
journal_digest() {
  case "${1-}" in -h|--help) group_usage journal 0 ;; esac
  JP=""; _jd_period=""; _jd_detail=""; _jd_stats="summary"; _jd_elev="all"
  while [ $# -gt 0 ]; do
    case "$1" in
      --detail) [ $# -ge 2 ] || die "journal digest: --detail requires headlines|blocks|full"; _jd_detail="$2"; shift 2 ;;
      --stats)  [ $# -ge 2 ] || die "journal digest: --stats requires none|summary|full"; _jd_stats="$2"; shift 2 ;;
      --elevations) [ $# -ge 2 ] || die "journal digest: --elevations requires all|only|none"; _jd_elev="$2"; shift 2 ;;
      --class) jp_flag "$1" "${2-}" "journal digest"; shift 2 ;;
      -*)
        if jp_flag "$1" "${2-}" "journal digest"; then shift 2; continue; fi
        die "journal digest: unknown argument: $1" ;;
      *)
        [ -z "$_jd_period" ] || die "journal digest: one period (YYYY or YYYY-MM)"
        _jd_period="$1"; shift ;;
    esac
  done
  [ -n "$_jd_period" ] || die "journal digest: need a period, YYYY or YYYY-MM"
  valid_period "$_jd_period" || die "journal digest: period must be YYYY or YYYY-MM: $_jd_period"
  case "$_jd_detail" in ''|headlines|blocks|full) ;; *) die "journal digest: --detail must be headlines, blocks or full" ;; esac
  case "$_jd_stats" in none|summary|full) ;; *) die "journal digest: --stats must be none, summary or full" ;; esac
  case "$_jd_elev" in all|only|none) ;; *) die "journal digest: --elevations must be all, only or none" ;; esac
  if [ ! -d "$ROOT/zamm-memory/journal" ]; then
    echo "# Journal digest $_jd_period: no journal tree ('journal add' creates it)"
    exit 0
  fi
  journal_compile
  _jd_state="$ROOT/zamm-memory/.compiled/journal-state.tsv"
  # The caller predicates are the base for BOTH selections; entries and
  # elevations then add only what their own section needs. Selecting
  # elevations straight from the sidecar ignored the grammar entirely, so
  # `--kind monthly` narrowed the entries and left every elevation in - a
  # saved style could not be trusted to mean one thing.
  _jd_jpuser="$JP"
  jp_add sectionclass entry "journal digest"
  jp_add sectionsince "$_jd_period" "journal digest"
  jp_add sectionuntil "$_jd_period" "journal digest"
  _jx=$(journal_export_tmp) || exit $?
  _jdxrc=${_jx%%"$JP_TAB"*}; _jx=${_jx#*"$JP_TAB"}
  _jd_rows=$(mktemp "${TMPDIR:-/tmp}/zamm-journal-digest.XXXXXX") || die "journal digest: could not create a scratch file"
  jp_filter 0 < "$_jx" > "$_jd_rows"
  _jd_n=$(grep -c . "$_jd_rows" || true)
  # Effectiveness is the sidecar (one elevation per kind and period); WHICH
  # of those to render is the predicate set. A caller asking for a class
  # other than elevation has asked for no elevations at all.
  JP="$_jd_jpuser"
  jp_add sectionclass elevation "journal digest"
  jp_add sectioncovers "$_jd_period" "journal digest"
  _jd_esel=$(jp_filter 0 < "$_jx" | cut -f1)
  rm -f "$_jx"
  # ENVIRON, never -v: BSD awk refuses a -v value holding a real newline
  _jd_elevs=$(ZAMM_JD_SEL="$_jd_esel" awk -F"$JP_TAB" -v per="$_jd_period" '
    BEGIN {
      n = split(ENVIRON["ZAMM_JD_SEL"], a, "\n")
      for (i = 1; i <= n; i++) if (a[i] != "") keep[a[i]] = 1
    }
    $1 == "elev" && substr($3, 1, length(per)) == per && ($4 in keep) { print $2 "\t" $3 "\t" $4 }
  ' "$_jd_state" | sort -t "$JP_TAB" -k2,2r -k1,1)
  _jd_ne=$(printf '%s\n' "$_jd_elevs" | grep -c . || true)
  if [ "${#_jd_period}" -eq 7 ]; then
    [ -n "$_jd_detail" ] || _jd_detail="blocks"
    echo "# Journal digest $_jd_period ($(plural "$_jd_n" entry entries), $(plural "$_jd_ne" elevation elevations); compiled view, not stored)"
  else
    [ -n "$_jd_detail" ] || _jd_detail="headlines"
    _jd_ny=$(printf '%s\n' "$_jd_elevs" | awk -F"$JP_TAB" -v per="$_jd_period" '$2 == per { n++ } END { print n + 0 }')
    _jd_nm=$((_jd_ne - _jd_ny))
    echo "# Journal digest $_jd_period ($(plural "$_jd_n" entry entries), $(plural "$_jd_nm" "monthly-grain elevation" "monthly-grain elevations"), $(plural "$_jd_ny" "yearly elevation" "yearly elevations"); the digest of digests, compiled, not stored)"
  fi
  if [ "$_jd_stats" != "none" ] && [ "$_jd_n" -gt 0 ]; then
    echo
    echo "## Stats"
    awk -F"$JP_TAB" -v year="$([ "${#_jd_period}" -eq 4 ] && echo 1 || echo 0)" "$JOURNAL_AWK_QUARTILES"'
      # keyed by name AND type: one name carrying both spellings is two
      # scales, and averaging them reported a bipolar median under a
      # unipolar label
      function rate(name, v,   ty, g) {
        ty = (v ~ /^[+-]/) ? "bipolar" : "unipolar"
        g = name SUBSEP ty
        if (!(g in gn)) { gn[g] = 0; gord[++ng] = g; gnm[g] = name; gty[g] = ty }
        gv[g, ++gn[g]] = v + 0
      }
      {
        n++
        mo = substr($3, 1, 7)
        if (!(mo in mn)) { mn[mo] = 0; mord[++nmo] = mo }
        mn[mo]++
        c = $7; if (!(c in cues)) { cues[c] = 0; cord[++nc] = c }; cues[c]++
        if ($13 != "-") rate("salience", $13)
        if ($17 != "-") { k = split($17, ax, " "); for (i = 1; i <= k; i++) { p = index(ax[i], "="); rate(substr(ax[i], 1, p - 1), substr(ax[i], p + 1)) } }
      }
      END {
        if (year) { s = ""; for (i = nmo; i >= 1; i--) s = s ((i < nmo) ? ", " : "") mord[i] " " mn[mord[i]]; print "entries by month: " s }
        s = ""; for (i = 1; i <= nc; i++) s = s ((i > 1) ? ", " : "") ((cord[i] == "-") ? "(none)" : cord[i]) " " cues[cord[i]]
        print "cues: " s
        for (i = 1; i <= ng; i++) {
          g = gord[i]; isort(g, gn[g])
          fmt = (gty[g] == "bipolar") ? "%+d" : "%d"
          printf "axis %s (%s): %d/%d rated, median " fmt ", p25 " fmt ", p75 " fmt "\n", gnm[g], gty[g], gn[g], n, gv[g, nrank(gn[g], 0.5)], gv[g, nrank(gn[g], 0.25)], gv[g, nrank(gn[g], 0.75)]
        }
      }
    ' "$_jd_rows"
    if [ "$_jd_stats" = "full" ]; then
      echo
      echo "month x cue x axis (n, p25, median, p75; nearest rank):"
      # over the SELECTED rows, not the sidecar: the sidecar aggregates the
      # whole tree, so a filtered view was printing detail for the very
      # records its own summary excluded
      awk -F"$JP_TAB" "$JOURNAL_AWK_QUARTILES"'
        function add(mo, cu, nm, v,   g) {
          g = mo SUBSEP cu SUBSEP nm SUBSEP ((v ~ /^[+-]/) ? "bipolar" : "unipolar")
          if (!(g in gn)) { gn[g] = 0; gord[++ng] = g }
          gv[g, ++gn[g]] = v + 0
        }
        {
          mo = substr($3, 1, 7); cu = $7
          if ($13 != "-") add(mo, cu, "salience", $13)
          if ($17 != "-") {
            k = split($17, ax, " ")
            for (i = 1; i <= k; i++) { p = index(ax[i], "="); add(mo, cu, substr(ax[i], 1, p - 1), substr(ax[i], p + 1)) }
          }
        }
        END {
          for (i = 1; i <= ng; i++) {
            g = gord[i]; isort(g, gn[g]); split(g, f, SUBSEP)
            fmt = (f[4] == "bipolar") ? "%+d" : "%d"
            printf("  %s  %-24s %-20s %-9s %3d  " fmt " " fmt " " fmt "\n", f[1], f[2], f[3], f[4], gn[g], gv[g, nrank(gn[g], 0.25)], gv[g, nrank(gn[g], 0.5)], gv[g, nrank(gn[g], 0.75)])
          }
        }
      ' "$_jd_rows" | sort -k1,1r -k2,2 -k3,3
    fi
  fi
  # render one elevation at the requested detail: the year view at
  # headlines detail shows an elevation's headline only, otherwise the
  # digest block; full prints the whole body
  jd_render_elev() {
    _p=$(journal_record_path "$3") || return 0
    echo
    echo "### $1 $2 [$3]"
    if [ "$_jd_detail" = "full" ]; then journal_block "$_p" full
    elif [ "${#_jd_period}" -eq 4 ] && [ "$_jd_detail" = "headlines" ]; then journal_block "$_p" block | awk 'NF { print; exit }'
    else journal_block "$_p" block; fi
  }
  if [ "$_jd_elev" != "none" ]; then
    awk -F"$JP_TAB" -v per="$_jd_period" '
      $1 == "elev_competing" && substr($3, 1, length(per)) == per {
        printf "note: %s %s has %d live elevations; showing %s - supersede one to decide it\n", $2, $3, $4, $5
      }' "$_jd_state"
  fi
  if [ "$_jd_elev" != "none" ] && [ "$_jd_ne" -gt 0 ]; then
    if [ "${#_jd_period}" -eq 7 ] || [ "$_jd_elev" = "only" ]; then
      # every selected elevation, newest period first - the whole answer
      # when the caller asked for only these
      echo
      echo "## Elevations"
      printf '%s\n' "$_jd_elevs" | while IFS="$JP_TAB" read -r _k _c _id; do
        [ -n "$_id" ] || continue
        jd_render_elev "$_k" "$_c" "$_id"
      done
    elif [ "$_jd_ny" -gt 0 ]; then
      echo
      echo "## Yearly elevation"
      printf '%s\n' "$_jd_elevs" | while IFS="$JP_TAB" read -r _k _c _id; do
        [ -n "$_id" ] && [ "$_c" = "$_jd_period" ] || continue
        jd_render_elev "$_k" "$_c" "$_id"
      done
    fi
  fi
  if [ "$_jd_elev" != "only" ]; then
    echo
    if [ "${#_jd_period}" -eq 7 ]; then
      echo "## Entries"
      if [ "$_jd_n" -eq 0 ]; then echo "(no entries)"; fi
      while IFS="$JP_TAB" read -r _id _cls _cr _tm _ag _us _cue _kd _cv _ps _rt _sc _sal _st _rv _bg _ax _hl _pss; do
        [ -n "$_id" ] || continue
        _tag=""
        [ "$_cue" = "-" ] || _tag=" ($_cue)"
        case "$_jd_detail" in
          headlines) printf -- '- %s  %s%s [%s]\n' "${_cr#*-*-}" "$_hl" "$_tag" "$_id" ;;
          blocks)
            printf -- '- %s  %s%s [%s]\n' "${_cr#*-*-}" "$_hl" "$_tag" "$_id"
            _p=$(journal_record_path "$_id") || continue
            journal_block "$_p" rest ;;
          full)
            printf '### %s  %s%s [%s]\n' "$_cr" "$_hl" "$_tag" "$_id"
            _p=$(journal_record_path "$_id") || continue
            journal_block "$_p" full
            echo ;;
        esac
      done < "$_jd_rows"
    else
      # the year view reads the grain below: an elevated month shows its
      # elevation, an unelevated month falls back to entry headlines
      echo "## Months"
      # every month that has entries or a month-grain elevation, newest first
      { awk -F"$JP_TAB" '{ print substr($3, 1, 7) }' "$_jd_rows"
        printf '%s\n' "$_jd_elevs" | awk -F"$JP_TAB" 'length($2) == 7 { print $2 }'; } | sort -ur | while IFS= read -r _mo; do
        [ -n "$_mo" ] || continue
        _mel=$(printf '%s\n' "$_jd_elevs" | awk -F"$JP_TAB" -v m="$_mo" '$2 == m { print }')
        echo
        if [ -n "$_mel" ] && [ "$_jd_elev" != "none" ]; then
          echo "### $_mo (elevated)"
          printf '%s\n' "$_mel" | while IFS="$JP_TAB" read -r _k _c _id; do
            [ -n "$_id" ] || continue
            jd_render_elev "$_k" "$_c" "$_id"
            # entries this elevation never saw are listed under it: the
            # year view renders the elevation INSTEAD of the month, so
            # anything outside its coverage would vanish from this view
            # WHICH entries an elevation missed is the compiler's answer,
            # read from the sidecar. Re-deriving it here meant a second
            # frontmatter parser with its own rules about carriage returns
            # and spacing - and the two disagreeing is exactly how an
            # uncovered entry went missing from this view again.
            _munc=$(awk -F"$JP_TAB" -v k="$_k" -v c="$_c" \
              '$1 == "elev_uncovered" && $2 == k && $3 == c { print $4 }' "$_jd_state")
            [ -n "$_munc" ] || continue
            ZAMM_JD_UNC="$_munc" awk -F"$JP_TAB" '
              BEGIN {
                n = split(ENVIRON["ZAMM_JD_UNC"], a, "\n")
                for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1
              }
              ($1 in want) {
                if (!hdr) { print ""; print "  Not covered by this elevation:"; hdr = 1 }
                print "  - " substr($3, 9, 2) "  " $18 " [" $1 "]"
              }' "$_jd_rows"
          done
        else
          echo "### $_mo (unelevated: entry headlines)"
          awk -F"$JP_TAB" -v m="$_mo" 'substr($3, 1, 7) == m { print "- " substr($3, 9, 2) "  " $18 " [" $1 "]" }' "$_jd_rows"
        fi
      done
    fi
  fi
  rm -f "$_jd_rows"
  journal_exit "$_jdxrc"
}

run_check_all() {
  crc=0; prc=0; xrc=0; brc=0; jrc=0
  sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --check || crc=$?
  # the backlog and journal trees are optional (absence is data); when
  # present each is checked with the same rigor as the knowledge ledger
  if [ -d "$ROOT/zamm-memory/backlog" ]; then
    sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree backlog --check || brc=$?
  fi
  if [ -d "$ROOT/zamm-memory/journal" ]; then
    sh "$INTERNAL/zamm-compile.sh" --project-root "$ROOT" --tree journal --check || jrc=$?
  fi
  sh "$INTERNAL/zamm-plan-check.sh" --project-root "$ROOT" || prc=$?
  # cross-object reconciliation runs last: it assumes each side is individually
  # well-formed and only checks that plans and their votes records agree.
  sh "$INTERNAL/zamm-crosscheck.sh" --project-root "$ROOT" || xrc=$?
  # An enumeration failure (4) outranks a validation failure (1): "could not
  # read" must never be flattened into "checked and found problems".
  rc=0
  for c in $crc $brc $jrc $prc $xrc; do
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
    journal) group_usage journal 0 ;;           # every verb is a built-in
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

  journal)
    [ $# -gt 0 ] || group_usage journal 0
    verb="$1"; shift
    # Help is read-only: route it before the version gate or the built-ins.
    wants_help "$@" && do_help journal "$verb"
    case "$verb" in
      add)     require_root; require_version; journal_add "$@"; exit 0 ;;
      list)    require_root; require_version; journal_list "$@"; exit 0 ;;
      show)    require_root; require_version; journal_show "$@"; exit 0 ;;
      search)  require_root; require_version; journal_search "$@"; exit 0 ;;
      stats)   require_root; require_version; journal_stats "$@"; exit 0 ;;
      export)  require_root; require_version; journal_export "$@"; exit 0 ;;
      digest)  require_root; require_version; journal_digest "$@"; exit 0 ;;
      elevate) require_root; require_version; journal_elevate "$@"; exit 0 ;;
      review)  require_root; require_version; journal_review "$@"; exit 0 ;;
      settle)  require_root; require_version; journal_settle "$@"; exit 0 ;;
      check)   require_root; require_version; journal_check "$@"; exit 0 ;;
      help|--help|-h) group_usage journal 0 ;;
      *) unknown "journal $verb" ;;
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
