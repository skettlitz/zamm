#!/bin/sh
# ZAMM new-memory — writes a ledger record with a collision-safe name
# (YYYY-MM-DD-<slug>-<5 random chars>.md) in one atomic step: the complete
# record is composed in a private temporary file, validated there, and then
# claimed under its final name with a no-clobber hard link. Prints the path.
#
# The body arrives on stdin (or through $EDITOR with --edit); votes records
# take their payload from --up/--down and must have no body. There is no
# draft state: a record is either absent or complete and valid. See
# references/invariants.md.
#
# Usage: zamm-new-memory.sh [--project-root <path>] [--type memory|tombstone|votes|erasure|digest]
#                           [--tree knowledge|backlog|journal]
#                           [--scope <tag[, tag2[, tag3]]>] [--supersedes <id[,id...]>]
#                           [--erases <id[,id...]>] [--up <id[,id...]>] [--down <id[,id...]>]
#                           [--importance guardrail|useful|minor]
#                           [--durability days|weeks|months|years|permanent]
#                           [--plan <plan-dir-slug>] [--marked YYYY-MM-DD|no]
#                           [--date YYYY-MM-DD] [--x <key=value>]...
#                           journal only: [--cue <slug>] [--salience 1..10]
#                           [--axis <name=value>]... [--agent <token>] [--user <token>]
#                           [--time HH:MM] [--digest <kind> --covers <YYYY[-MM]>]
#                           [--reviewed-through YYYY-MM-DD [--pass <kind>]]
#                           [--covered <id[,id...]>]
#                           [--edit] [--no-validate] <topic-slug> < body.md
#
# --tree backlog writes an idea into the backlog ledger (validated against
# the backlog tree, no guardrail importance, no --plan); --marked puts a
# backlog idea into (a date) or out of (no) the marked lane.
# --tree journal writes an episode (type memory), an elevation (--type
# digest with --digest/--covers) or a watermark (--reviewed-through) into
# the journal; no guardrails, no votes, no --plan; durability defaults to
# weeks. --x key=value writes an x-key: line (auto-prefixed, so it can never
# write a policy key); axis values are unipolar 0..10 or bipolar -5..+5
# (always signed).
#
# --scope takes 1-3 comma-separated area tags from the fixed set (domain,
# contracts, conventions, internals, quality, tooling, ops, meta; or other
# alone). The first tag may carry a /subpath; secondary tags are bare areas.
# --importance/--durability rate the record at write time (defaults:
# useful/months); ranking decays over the durability horizon.
# --date backdates the record (filename date, created:, and year directory
# all follow it); intended for v1/v2 migration, where records carry the
# original card's last-updated date. Default is today.
# --no-validate skips the per-record check and the digest rebuild; it exists
# for bulk migration, where validating each record costs a full compile.
# Run `zamm-run.sh check` once at the end instead.

set -eu
LC_ALL=C
export LC_ALL

PROJECT_ROOT="$PWD"
RTYPE="memory"
TREE="knowledge"
SCOPE=""
SUPERSEDES=""
ERASES=""
IMPORTANCE="useful"
DURABILITY="months"
PLAN=""
MARKED=""
RDATE=""
SLUG=""
UP=""
DOWN=""
EDIT=0
VALIDATE=1
DUR_SET=0
CUE=""
SALIENCE=""
AXES=""
XKEYS=""
AGENT=""
USERTOKEN=""
RTIME=""
DIGEST=""
COVERS=""
RTHROUGH=""
PASS=""
COVERED=""
COVERED_SET=0

# need_val <all remaining args>: the option is $1, its value $2. Called before
# consuming a value so a missing one is a controlled error, not a set -u crash.
need_val() {
  if [ "$#" -lt 2 ]; then
    echo "ERROR: $1 requires a value" >&2
    exit 1
  fi
}

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
    # Each value-taking option requires its argument. Without this guard `$2`
    # under `set -u` aborts with a raw "unbound variable" when the option is the
    # last token (e.g. `... create foo --scope`), instead of clear usage text.
    --type)       need_val "$@"; RTYPE="$2"; shift 2 ;;
    --tree)       need_val "$@"; TREE="$2"; shift 2 ;;
    --marked)     need_val "$@"; MARKED="$2"; shift 2 ;;
    --scope)      need_val "$@"; SCOPE="$2"; shift 2 ;;
    --supersedes) need_val "$@"; SUPERSEDES="$2"; shift 2 ;;
    --erases)     need_val "$@"; ERASES="$2"; shift 2 ;;
    --up)         need_val "$@"; UP="$2"; shift 2 ;;
    --down)       need_val "$@"; DOWN="$2"; shift 2 ;;
    --importance) need_val "$@"; IMPORTANCE="$2"; shift 2 ;;
    --durability) need_val "$@"; DURABILITY="$2"; DUR_SET=1; shift 2 ;;
    --cue)        need_val "$@"; CUE="$2"; shift 2 ;;
    --salience)   need_val "$@"; SALIENCE="$2"; shift 2 ;;
    --axis)       need_val "$@"; AXES="$AXES$2
"; shift 2 ;;
    --x)          need_val "$@"; XKEYS="$XKEYS$2
"; shift 2 ;;
    --agent)      need_val "$@"; AGENT="$2"; shift 2 ;;
    --user)       need_val "$@"; USERTOKEN="$2"; shift 2 ;;
    --time)       need_val "$@"; RTIME="$2"; shift 2 ;;
    --digest)     need_val "$@"; DIGEST="$2"; shift 2 ;;
    --covers)     need_val "$@"; COVERS="$2"; shift 2 ;;
    --reviewed-through) need_val "$@"; RTHROUGH="$2"; shift 2 ;;
    --covered)    need_val "$@"; COVERED="$2"; COVERED_SET=1; shift 2 ;;
    --pass)       need_val "$@"; PASS="$2"; shift 2 ;;
    --plan)       need_val "$@"; PLAN="$2"; shift 2 ;;
    --date)       need_val "$@"; RDATE="$2"; shift 2 ;;
    --edit)        EDIT=1; shift ;;
    --no-validate) VALIDATE=0; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -n "$SLUG" ]; then
        echo "ERROR: multiple slugs given: $SLUG, $1" >&2
        exit 1
      fi
      SLUG="$1"
      shift
      ;;
  esac
done

# Directly invocable, so re-prove the canonical roots are real directories
# inside the project before writing a record through them (G5).
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/zamm-paths.sh"
. "$SCRIPT_DIR/zamm-validate.sh"
zamm_verify_roots "$PROJECT_ROOT" || exit 4

if [ -z "$SLUG" ]; then
  echo "ERROR: missing <topic-slug>" >&2
  exit 1
fi
case "$SLUG" in
  *[!a-z0-9-]*|-*)
    echo "ERROR: slug must be lowercase [a-z0-9-] and not start with '-': $SLUG" >&2
    exit 1
    ;;
  *-|*--*)
    echo "ERROR: slug must not end with '-' or contain '--': $SLUG" >&2
    exit 1
    ;;
esac
if [ "${#SLUG}" -gt 40 ]; then
  echo "ERROR: slug longer than 40 chars: $SLUG" >&2
  exit 1
fi
case "$RTYPE" in
  memory|tombstone|votes|erasure|digest) ;;
  *)
    echo "ERROR: --type must be memory, tombstone, votes, erasure, or (journal only) digest" >&2
    exit 1
    ;;
esac
case "$TREE" in
  knowledge|backlog|journal) ;;
  *)
    echo "ERROR: --tree must be knowledge, backlog or journal" >&2
    exit 1
    ;;
esac
# Journal policy at the CLI, with the compile-side errors as the deep lock:
# type digest (an elevation) exists only there; no guardrails, no votes, no
# plan; durability defaults to weeks (episodes age fast).
if [ "$RTYPE" = "digest" ] && [ "$TREE" != "journal" ]; then
  echo "ERROR: type digest is the journal elevation record; pass --tree journal" >&2
  exit 1
fi
if [ "$TREE" = "journal" ]; then
  if [ "$IMPORTANCE" = "guardrail" ]; then
    echo "ERROR: guardrail importance is not allowed in the journal (distill the rule into a knowledge record instead)" >&2
    exit 1
  fi
  if [ "$RTYPE" = "votes" ]; then
    echo "ERROR: votes records are not allowed in the journal (a timeline has no ranking to vote on)" >&2
    exit 1
  fi
  if [ -n "$PLAN" ]; then
    echo "ERROR: journal records carry no --plan" >&2
    exit 1
  fi
  [ "$DUR_SET" -eq 1 ] || DURABILITY="weeks"
else
  if [ -n "$CUE$SALIENCE$AXES$AGENT$USERTOKEN$RTIME$DIGEST$COVERS$RTHROUGH$PASS" ]; then
    echo "ERROR: --cue/--salience/--axis/--agent/--user/--time/--digest/--covers/--reviewed-through/--pass are journal keys (--tree journal)" >&2
    exit 1
  fi
fi
# Journal class rules: an ENTRY (memory), an ELEVATION (digest + --digest
# --covers) or a WATERMARK (memory + --reviewed-through); one class per
# record. Every value here becomes a frontmatter line, so each is
# charset-limited: no whitespace or control characters can reach the file.
jslug_ok() { case "$1" in ''|*[!a-z0-9-]*|-*) return 1 ;; esac; return 0; }
jtoken_ok() { case "$1" in ''|*[!A-Za-z0-9._@+-]*|[._@+-]*) return 1 ;; esac; return 0; }
if [ "$RTYPE" = "digest" ]; then
  if [ -z "$DIGEST" ] || [ -z "$COVERS" ]; then
    echo "ERROR: an elevation (type digest) needs both --digest <kind> and --covers <YYYY[-MM]>" >&2
    exit 1
  fi
  if [ -n "$CUE$SALIENCE" ]; then
    echo "ERROR: --cue/--salience are entry keys; an elevation carries --digest instead" >&2
    exit 1
  fi
  if [ -n "$RTHROUGH$PASS" ]; then
    echo "ERROR: --reviewed-through/--pass are watermark keys; a record is exactly one class" >&2
    exit 1
  fi
elif [ -n "$DIGEST$COVERS" ]; then
  echo "ERROR: --digest/--covers belong to --type digest (an elevation record)" >&2
  exit 1
fi
if [ -n "$DIGEST" ] && ! jslug_ok "$DIGEST"; then
  echo "ERROR: --digest must be a kind slug [a-z0-9-]: $DIGEST" >&2
  exit 1
fi
if [ -n "$COVERS" ]; then
  case "$COVERS" in
    [0-9][0-9][0-9][0-9]) ;;
    [0-9][0-9][0-9][0-9]-0[1-9]|[0-9][0-9][0-9][0-9]-1[0-2]) ;;
    *)
      echo "ERROR: --covers must be a calendar period YYYY or YYYY-MM: $COVERS" >&2
      exit 1
      ;;
  esac
fi
if [ -n "$RTHROUGH" ]; then
  if [ "$RTYPE" != "memory" ]; then
    echo "ERROR: --reviewed-through is a watermark key and needs a memory record" >&2
    exit 1
  fi
  if [ -n "$CUE$SALIENCE$AXES" ]; then
    echo "ERROR: --cue/--salience/--axis are entry keys; a watermark claims coverage only" >&2
    exit 1
  fi
  if [ "$PASS" = "triage" ]; then
    echo "ERROR: --pass triage is the default pass; omit it (one spelling per kind)" >&2
    exit 1
  fi
  if [ -n "$PASS" ] && ! jslug_ok "$PASS"; then
    echo "ERROR: --pass must be a kind slug [a-z0-9-]: $PASS" >&2
    exit 1
  fi
elif [ -n "$PASS" ]; then
  echo "ERROR: --pass scopes a watermark and needs --reviewed-through" >&2
  exit 1
fi
# --covered names the entries a watermark actually reviewed: the claim
# identity a date alone cannot carry (an entry merged in later, dated before
# the boundary, was never seen by it).
if [ "$COVERED_SET" -eq 1 ]; then
  if [ -z "$RTHROUGH" ] && [ "$RTYPE" != "digest" ]; then
    echo "ERROR: --covered names what a coverage record saw: it belongs on a watermark (--reviewed-through) or an elevation (--type digest)" >&2
    exit 1
  fi
  case "$COVERED" in
    *[!a-z0-9,-]*)
      echo "ERROR: --covered must be comma-separated record ids [a-z0-9-]" >&2
      exit 1
      ;;
  esac
fi
if [ "$RTYPE" != "memory" ] && [ "$RTYPE" != "digest" ] && [ -n "$CUE$SALIENCE$AXES" ]; then
  echo "ERROR: --cue/--salience/--axis are only meaningful on memory or digest records" >&2
  exit 1
fi
if [ -n "$CUE" ] && ! jslug_ok "$CUE"; then
  echo "ERROR: --cue must be a slug [a-z0-9-]: $CUE" >&2
  exit 1
fi
if [ -n "$SALIENCE" ]; then
  case "$SALIENCE" in
    [1-9]|10) ;;
    *)
      echo "ERROR: --salience must be an integer 1..10: $SALIENCE" >&2
      exit 1
      ;;
  esac
fi
if [ -n "$AGENT" ] && ! jtoken_ok "$AGENT"; then
  echo "ERROR: --agent must be one token [A-Za-z0-9._@+-]: $AGENT" >&2
  exit 1
fi
if [ -n "$USERTOKEN" ] && ! jtoken_ok "$USERTOKEN"; then
  echo "ERROR: --user must be one token [A-Za-z0-9._@+-]: $USERTOKEN" >&2
  exit 1
fi
if [ -n "$RTIME" ]; then
  case "$RTIME" in
    [01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;;
    *)
      echo "ERROR: --time must be HH:MM: $RTIME" >&2
      exit 1
      ;;
  esac
fi
# --axis name=value: the value spelling IS the type (a sign makes it
# bipolar -5..+5, no sign unipolar 0..10); one name per axis, and salience
# keeps its short spelling
AXSEEN=" "
if [ -n "$AXES" ]; then
  while IFS= read -r _ax; do
    [ -n "$_ax" ] || continue
    case "$_ax" in
      *=*) _axn=${_ax%%=*}; _axv=${_ax#*=} ;;
      *)
        echo "ERROR: --axis takes name=value (got: $_ax)" >&2
        exit 1
        ;;
    esac
    if [ "$_axn" = "salience" ]; then
      echo "ERROR: --axis salience is spelled --salience (one name per axis)" >&2
      exit 1
    fi
    if ! jslug_ok "$_axn"; then
      echo "ERROR: axis name must be a slug [a-z0-9-]: $_axn" >&2
      exit 1
    fi
    case "$_axv" in
      [+-][0-5]) [ "$_axv" != "-0" ] || { echo "ERROR: axis $_axn: write +0, not -0" >&2; exit 1; } ;;
      [0-9]|10) ;;
      *)
        echo "ERROR: axis $_axn: value must be unipolar 0..10 (unsigned) or bipolar -5..+5 (always signed): $_axv" >&2
        exit 1
        ;;
    esac
    case "$AXSEEN" in
      *" $_axn "*)
        echo "ERROR: duplicate axis: $_axn" >&2
        exit 1
        ;;
    esac
    AXSEEN="$AXSEEN$_axn "
  done <<EOF
$AXES
EOF
fi
# --x key=value: the experimental namespace, auto-prefixed into x- so the
# escape hatch can never write a policy key; the value is one line
XSEEN=" "
if [ -n "$XKEYS" ]; then
  while IFS= read -r _xk; do
    [ -n "$_xk" ] || continue
    case "$_xk" in
      *=*) _xn=${_xk%%=*}; _xv=${_xk#*=} ;;
      *)
        echo "ERROR: --x takes key=value (got: $_xk)" >&2
        exit 1
        ;;
    esac
    if ! jslug_ok "$_xn"; then
      echo "ERROR: --x key must be a slug [a-z0-9-]: $_xn" >&2
      exit 1
    fi
    case "$_xv" in
      *[![:print:]]*)
        echo "ERROR: --x $_xn: value must be one printable line" >&2
        exit 1
        ;;
    esac
    case "$XSEEN" in
      *" $_xn "*)
        echo "ERROR: duplicate --x key: $_xn" >&2
        exit 1
        ;;
    esac
    XSEEN="$XSEEN$_xn "
  done <<EOF
$XKEYS
EOF
fi
# Per-tree policy, refused at the CLI so the author hears it before composing
# anything; the compile-side errors are the deep lock for hand-written files.
if [ "$TREE" = "backlog" ]; then
  if [ "$IMPORTANCE" = "guardrail" ]; then
    echo "ERROR: guardrail importance is not allowed in the backlog; mark the idea instead (backlog mark)" >&2
    exit 1
  fi
  if [ -n "$PLAN" ]; then
    echo "ERROR: backlog votes are triage votes and carry no --plan" >&2
    exit 1
  fi
fi
if [ -n "$MARKED" ]; then
  if [ "$TREE" != "backlog" ] || [ "$RTYPE" != "memory" ]; then
    echo "ERROR: --marked is only meaningful on a backlog memory record" >&2
    exit 1
  fi
  case "$MARKED" in
    no|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *)
      echo "ERROR: --marked must be a YYYY-MM-DD date or \"no\"" >&2
      exit 1
      ;;
  esac
fi

# Values that become frontmatter lines are DATA, never structure. A newline in
# --supersedes or --plan would break out of its `key: value` line and forge
# further keys (e.g. seed-up:, which the compiler honors as vote weight) while
# still passing --check — a CLI authority forge. Reject anything outside the
# record-id / slug charset, which excludes every control character.
case "$SUPERSEDES" in
  *[!a-z0-9,\ -]*)
    echo "ERROR: --supersedes must be comma-separated record ids [a-z0-9-]" >&2
    exit 1
    ;;
esac
case "$ERASES" in
  *[!a-z0-9,\ -]*)
    echo "ERROR: --erases must be comma-separated record ids [a-z0-9-]" >&2
    exit 1
    ;;
esac
case "$UP$DOWN" in
  *[!a-z0-9,\ -]*)
    echo "ERROR: --up/--down must be comma-separated record ids [a-z0-9-]" >&2
    exit 1
    ;;
esac
if [ -n "$UP$DOWN" ] && [ "$RTYPE" != "votes" ]; then
  echo "ERROR: --up/--down are only meaningful on --type votes" >&2
  exit 1
fi
case "$PLAN" in
  *[!a-z0-9-]*)
    echo "ERROR: --plan must be a plan-directory slug [a-z0-9-]" >&2
    exit 1
    ;;
esac
case "$IMPORTANCE" in
  guardrail|useful|minor) ;;
  *)
    echo "ERROR: --importance must be guardrail, useful, or minor" >&2
    exit 1
    ;;
esac
case "$DURABILITY" in
  days|weeks|months|years|permanent) ;;
  *)
    echo "ERROR: --durability must be days, weeks, months, years, or permanent" >&2
    exit 1
    ;;
esac

# a memory record without scope: is quarantined by the compiler, and the area
# is known at creation time — emitting a skeleton that cannot compile only
# defers the error. The empty body is the one documented fill-me-in exception.
if [ "$RTYPE" = "erasure" ] && [ -z "$ERASES" ]; then
  echo "ERROR: --erases is required for erasure records (the record ids to redact)" >&2
  exit 1
fi
if [ -n "$ERASES" ] && [ "$RTYPE" != "erasure" ]; then
  echo "ERROR: --erases is only meaningful on --type erasure" >&2
  exit 1
fi
if [ "$RTYPE" = "memory" ] && [ -z "$SCOPE" ]; then
  echo "ERROR: --scope is required for memory records (1-3 tags from: domain" >&2
  echo "       contracts conventions internals quality tooling ops meta; or other alone)" >&2
  exit 1
fi

# scope: 1-3 area tags from the fixed set; subpath on the first tag only;
# other must stand alone (same contract zamm-compile.sh --check enforces)
if [ -n "$SCOPE" ]; then
  VALID_AREAS=" domain contracts conventions internals quality tooling ops meta "
  NTAGS=0
  SEEN=" "
  NORMSCOPE=""
  # Split on commas preserving EMPTY fields, then trim each. The old
  # `IFS=', '; for TAG in $SCOPE` collapsed adjacent separators, so a scope like
  # "domain,,quality" silently dropped the empty middle and the generator wrote
  # a record the compiler then rejected — a create must not produce a record its
  # own checker refuses. An empty component is now a generator error too.
  SCOPE_REST="$SCOPE"
  while : ; do
    case "$SCOPE_REST" in
      *,*) TAG="${SCOPE_REST%%,*}"; SCOPE_REST="${SCOPE_REST#*,}"; MORE=1 ;;
      *)   TAG="$SCOPE_REST"; MORE=0 ;;
    esac
    # POSIX whitespace trim, no subshell
    TAG="${TAG#"${TAG%%[![:space:]]*}"}"
    TAG="${TAG%"${TAG##*[![:space:]]}"}"
    if [ -z "$TAG" ]; then
      echo "ERROR: scope has an empty component (adjacent, leading or trailing comma): $SCOPE" >&2
      exit 1
    fi
    NTAGS=$((NTAGS + 1))
    case "$TAG" in
      *[!a-z0-9/-]*|/*|*/)
        echo "ERROR: scope tag must be <area>[/<subpath>] in lowercase [a-z0-9-]: $TAG" >&2
        exit 1
        ;;
    esac
    AREA=${TAG%%/*}
    case "$VALID_AREAS" in
      *" $AREA "*) ;;
      *)
        if [ "$AREA" != "other" ]; then
          echo "ERROR: unknown scope area \"$AREA\" (fixed set:${VALID_AREAS}or other alone)" >&2
          exit 1
        fi
        ;;
    esac
    if [ "$NTAGS" -gt 1 ]; then
      case "$TAG" in
        */*)
          echo "ERROR: secondary scope tag must be a bare area (subpath on the first tag only): $TAG" >&2
          exit 1
          ;;
      esac
    fi
    case "$SEEN" in
      *" $AREA "*)
        echo "ERROR: duplicate scope area: $AREA" >&2
        exit 1
        ;;
    esac
    SEEN="$SEEN$AREA "
    NORMSCOPE="$NORMSCOPE${NORMSCOPE:+, }$TAG"
    [ "$MORE" -eq 0 ] && break
  done
  # Write the NORMALIZED scope (trimmed tags, rejoined), not the raw argument.
  # The per-tag validation ran on trimmed tags, so a leading/embedded newline or
  # stray whitespace in the raw --scope value would otherwise pass validation
  # and then be written verbatim into the record, which the compiler rejects.
  SCOPE="$NORMSCOPE"
  if [ "$NTAGS" -gt 3 ]; then
    echo "ERROR: scope has $NTAGS tags (max 3)" >&2
    exit 1
  fi
  case "$SEEN" in
    *" other "*)
      if [ "$NTAGS" -gt 1 ] || [ "$SCOPE" != "other" ]; then
        echo "ERROR: other must be the sole scope tag, without subpath" >&2
        exit 1
      fi
      ;;
  esac
fi

# 0 if $1 is a real Gregorian date; digit shape is not enough, the compiler
# requires a real calendar date, so a backdated record must not be able to
# create 2026-02-30 and a watermark cannot claim one
real_date() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  Y=${1%%-*}; MD=${1#*-}; M=${MD%%-*}; D=${MD#*-}
  # strip ONE leading zero for base-10 arithmetic (fields are 2-digit, so a
  # single strip is enough); "00" -> "0", not "" — stripping twice emptied a
  # zero field and the `[` error below did not abort under set -e, so a
  # zero-month date wrote an invalid ledger file.
  Y=${Y#0}; Y=${Y#0}; Y=${Y#0}; M=${M#0}; D=${D#0}
  : "${M:=0}" "${D:=0}" "${Y:=0}"
  DIM=31
  case "$M" in
    4|6|9|11) DIM=30 ;;
    2)
      DIM=28
      if [ $((Y % 4)) -eq 0 ] && { [ $((Y % 100)) -ne 0 ] || [ $((Y % 400)) -eq 0 ]; }; then
        DIM=29
      fi
      ;;
  esac
  if [ "$M" -lt 1 ] || [ "$M" -gt 12 ] || [ "$D" -lt 1 ] || [ "$D" -gt "$DIM" ]; then
    return 1
  fi
  return 0
}
RECDATE=$(date +%Y-%m-%d)
if [ -n "$RDATE" ]; then
  real_date "$RDATE" || {
    echo "ERROR: --date must be a real YYYY-MM-DD calendar date: $RDATE" >&2
    exit 1
  }
  RECDATE="$RDATE"
fi
if [ -n "$RTHROUGH" ]; then
  real_date "$RTHROUGH" || {
    echo "ERROR: --reviewed-through must be a real YYYY-MM-DD calendar date: $RTHROUGH" >&2
    exit 1
  }
fi
YEAR=${RECDATE%%-*}
DIR="$PROJECT_ROOT/zamm-memory/$TREE/$YEAR"
# The year directory is a DYNAMIC path component the canonical-root check
# cannot list: a symlinked knowledge/<year> would route the new record
# outside the project — and hide it from every enumeration, which never
# follows symlinked directories. Check the whole ledger first (a sibling
# year hidden that way makes any id-collision probe unsound), then this
# year's own directory: mkdir -p silently accepts an existing
# symlink-to-directory, and FAILS on a dangling one, so tolerate its status
# and judge by what is actually there.
zamm_verify_no_symlinks "$PROJECT_ROOT" || exit 4
mkdir -p "$DIR" 2>/dev/null || true
if [ -L "$DIR" ] || [ ! -d "$DIR" ]; then
  echo "ERROR: zamm-memory/$TREE/$YEAR is a symlink or not a real directory;" >&2
  echo "       refusing to write a record through it (no symlinks in the ledger)." >&2
  exit 4
fi

# ------------------------------------------------------------------ write
# One atomic claim (references/invariants.md, G1): compose the complete
# record in a private temporary file, validate it THERE, then claim its final
# name with an atomic no-clobber hard link. The record therefore never exists
# on disk in a mutable, half-valid state, and the bytes that are validated are
# the exact bytes that land — link() publishes the inode we just checked.
#
# There is no lock and no rollback because neither has anything to protect: a
# failure leaves one temporary file, and a concurrent creator is writing a
# different filename.

BODY=""
if [ "$RTYPE" = "votes" ]; then
  # a votes record must have an EMPTY body; up:/down: are the payload
  if [ "$EDIT" -eq 1 ]; then
    echo "ERROR: --edit is meaningless for a votes record (its body must stay empty)" >&2
    exit 1
  fi
  if [ -z "$UP" ] && [ -z "$DOWN" ]; then
    echo "ERROR: a votes record needs --up and/or --down (comma-separated record ids)" >&2
    exit 1
  fi
elif [ "$EDIT" -eq 1 ]; then
  : # body comes from the editor, below
else
  if [ -t 0 ]; then
    echo "ERROR: no record body on stdin." >&2
    echo "       Pipe the body in:  ... memory create --scope internals my-slug <<'EOF'" >&2
    echo "                          Headline sentence." >&2
    echo "                          EOF" >&2
    echo "       or compose it in an editor with --edit." >&2
    exit 1
  fi
  BODY=$(cat)
  if [ -z "$(printf '%s' "$BODY" | tr -d '[:space:]')" ]; then
    echo "ERROR: the record body on stdin is empty; a $RTYPE record needs one." >&2
    exit 1
  fi
fi

emit_frontmatter() {
  # printf, never echo: a POSIX /bin/sh (dash, which is what CI runs) makes
  # `echo` expand backslash escapes, so a value holding \n breaks out of its
  # own `key: value` line and forges further frontmatter. That turned the
  # deliberately unrefusable capture path into a way to write a coverage
  # claim - the x- namespace exists precisely so an escape hatch can never
  # write a policy key. The format string is fixed here; values are data.
  fm() { printf '%s\n' "$*"; }
  fm "---"
  fm "type: $RTYPE"
  if [ -n "$SCOPE" ]; then fm "scope: $SCOPE"; fi
  if [ -n "$SUPERSEDES" ]; then fm "supersedes: $SUPERSEDES"; fi
  if [ -n "$ERASES" ]; then fm "erases: $ERASES"; fi
  if [ "$RTYPE" = "memory" ] || [ "$RTYPE" = "digest" ]; then
    fm "importance: $IMPORTANCE"
    fm "durability: $DURABILITY"
  fi
  if [ -n "$MARKED" ]; then fm "marked: $MARKED"; fi
  if [ -n "$PLAN" ]; then fm "plan: $PLAN"; fi
  if [ "$RTYPE" = "votes" ]; then
    fm "up:${UP:+ $UP}"
    fm "down:${DOWN:+ $DOWN}"
  fi
  fm "created: $RECDATE"
  if [ -n "$RTIME" ]; then fm "time: $RTIME"; fi
  if [ -n "$AGENT" ]; then fm "agent: $AGENT"; fi
  if [ -n "$USERTOKEN" ]; then fm "user: $USERTOKEN"; fi
  if [ -n "$CUE" ]; then fm "cue: $CUE"; fi
  if [ -n "$SALIENCE" ]; then fm "salience: $SALIENCE"; fi
  if [ -n "$AXES" ]; then
    printf '%s' "$AXES" | while IFS= read -r _ax; do
      [ -n "$_ax" ] && fm "axis-${_ax%%=*}: ${_ax#*=}"
    done
  fi
  if [ -n "$DIGEST" ]; then fm "digest: $DIGEST"; fi
  if [ -n "$COVERS" ]; then fm "covers: $COVERS"; fi
  if [ -n "$RTHROUGH" ]; then fm "reviewed-through: $RTHROUGH"; fi
  if [ -n "$PASS" ]; then fm "pass: $PASS"; fi
  # present-but-empty is meaningful: a claim that named NOTHING is still an
  # exact claim, and must not read as the blunt date-only form
  if [ "$COVERED_SET" -eq 1 ]; then fm "covered:${COVERED:+ $COVERED}"; fi
  if [ -n "$XKEYS" ]; then
    printf '%s' "$XKEYS" | while IFS= read -r _xk; do
      [ -n "$_xk" ] && fm "x-${_xk%%=*}: ${_xk#*=}"
    done
  fi
  fm "schema: 3"
  fm "---"
}

# mktemp creates 0600; this file BECOMES the record, so give it the mode a
# plain redirection would have (0666 masked by the caller's umask).
apply_record_mode() {
  _um=$(umask)
  chmod "$(printf '%o' "$(( 0666 & ~0$_um ))")" "$1" 2>/dev/null ||
    chmod 644 "$1" 2>/dev/null || true
}

WORK=""
cleanup() { [ -z "$WORK" ] || rm -f "$WORK"; return 0; }
trap 'cleanup' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

FILE=""
tries=0
while [ "$tries" -lt 5 ]; do
  tries=$((tries + 1))
  # 5 chars from a 30-symbol alphabet: lowercase Crockford base32 minus the
  # visually ambiguous 0 1 i l o u (30 symbols, not 32)
  SUFFIX=$(LC_ALL=C tr -dc '23456789abcdefghjkmnpqrstvwxyz' < /dev/urandom \
    | dd bs=1 count=5 2>/dev/null)
  # a short dd read (interrupted or starved urandom) yields a suffix the id
  # grammar rejects; retry instead of minting a malformed id
  [ "${#SUFFIX}" -eq 5 ] || continue
  BASE="$RECDATE-$SLUG-$SUFFIX"

  # The temp is named for the id it will become: the compiler derives the
  # candidate id from this filename when validating the overlay. It matches
  # neither *.md nor *.md.draft, so no enumeration ever sees it.
  cleanup
  WORK=$(mktemp "$DIR/.$BASE.md.pending.XXXXXX") || {
    echo "ERROR: could not create a private temporary file under zamm-memory/$TREE/$YEAR" >&2
    exit 1
  }
  apply_record_mode "$WORK"

  if [ "$EDIT" -eq 1 ]; then
    { emit_frontmatter; echo; echo "<!-- write the record body here, then save and quit -->"; } > "$WORK"
    ED=${VISUAL:-${EDITOR:-}}
    [ -n "$ED" ] || { echo "ERROR: --edit needs \$EDITOR or \$VISUAL to be set" >&2; exit 1; }
    "$ED" "$WORK" || { echo "ERROR: the editor exited nonzero; nothing was written" >&2; exit 1; }
  elif [ "$RTYPE" = "votes" ]; then
    emit_frontmatter > "$WORK"
  else
    { emit_frontmatter; echo; printf '%s\n' "$BODY"; } > "$WORK"
  fi

  if [ "$VALIDATE" -eq 1 ]; then
    zamm_validate_candidate "$PROJECT_ROOT" "$SCRIPT_DIR" "$WORK" \
      "$TREE/$YEAR" "$TREE" || exit 1
  fi

  # Atomic no-clobber claim: link() fails with EEXIST when the name is taken,
  # so the reservation cannot race. A collision is a fresh suffix, not damage.
  if ln "$WORK" "$DIR/$BASE.md" 2>/dev/null; then
    FILE="$DIR/$BASE.md"
    break
  fi
done
cleanup
WORK=""
trap - EXIT HUP INT TERM

if [ -z "$FILE" ]; then
  echo "ERROR: could not claim a free record id after 5 tries (urandom unavailable, or persistent id collisions?)" >&2
  exit 1
fi

if [ "$RTYPE" = "erasure" ]; then
  echo "note: now delete the erased record file(s); the erasure record keeps them out of the digest" >&2
fi

# Refresh the digest so the new record is visible immediately. The digest is
# derived and disposable (G2), so a failure here is reported, not fatal: the
# record is already in the ledger and the next compile picks it up.
if [ "$VALIDATE" -eq 1 ]; then
  crc=0
  sh "$SCRIPT_DIR/zamm-compile.sh" --project-root "$PROJECT_ROOT" >/dev/null 2>&1 || crc=$?
  if [ "$crc" -eq 2 ]; then
    echo "note: the record was written, but the digest is degraded by unrelated" >&2
    echo "      pre-existing problems; run 'zamm-run.sh memory check' to see them." >&2
  elif [ "$crc" -ne 0 ]; then
    echo "note: the record was written, but the digest could not be rebuilt (rc=$crc);" >&2
    echo "      run 'zamm-run.sh memory digest' to refresh it." >&2
  fi
fi

echo "$FILE"
