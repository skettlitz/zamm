#!/bin/sh
# ZAMM new-memory — creates a ledger record with a collision-safe name
# (YYYY-MM-DD-<slug>-<5 random chars>.md) and a frontmatter skeleton.
# By default it writes an <id>.md.draft the compiler ignores; the caller fills
# the body, then `memory publish <id>` validates and lands it. Prints the draft
# path. --immediate skips the draft and writes the final .md at once.
#
# Usage: zamm-new-memory.sh [--project-root <path>] [--type memory|tombstone|votes]
#                           [--scope <tag[, tag2[, tag3]]>] [--supersedes <id[,id...]>]
#                           [--importance guardrail|useful|minor]
#                           [--durability days|weeks|months|years|permanent]
#                           [--plan <plan-dir-slug>] [--date YYYY-MM-DD]
#                           [--immediate] <topic-slug>
#
# --scope takes 1-3 comma-separated area tags from the fixed set (domain,
# contracts, conventions, internals, quality, tooling, ops, meta; or other
# alone). The first tag may carry a /subpath; secondary tags are bare areas.
# --importance/--durability rate the record at write time (defaults:
# useful/months); ranking decays over the durability horizon.
# --date backdates the record (filename date, created:, and year directory
# all follow it); intended for v1/v2 migration, where records carry the
# original card's last-updated date. Default is today.

set -eu
LC_ALL=C
export LC_ALL

PROJECT_ROOT="$PWD"
RTYPE="memory"
SCOPE=""
SUPERSEDES=""
IMPORTANCE="useful"
DURABILITY="months"
PLAN=""
RDATE=""
SLUG=""
IMMEDIATE=0

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
    --scope)      need_val "$@"; SCOPE="$2"; shift 2 ;;
    --supersedes) need_val "$@"; SUPERSEDES="$2"; shift 2 ;;
    --importance) need_val "$@"; IMPORTANCE="$2"; shift 2 ;;
    --durability) need_val "$@"; DURABILITY="$2"; shift 2 ;;
    --plan)       need_val "$@"; PLAN="$2"; shift 2 ;;
    --date)       need_val "$@"; RDATE="$2"; shift 2 ;;
    # --immediate writes the final <id>.md straight away (the old behaviour),
    # for migration tooling and scripted creation. The default writes an
    # <id>.md.draft the compiler ignores, so a half-filled record never appears
    # in the ledger between creation and `memory publish`.
    --immediate)  IMMEDIATE=1; shift ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
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
  memory|tombstone|votes) ;;
  *)
    echo "ERROR: --type must be memory, tombstone, or votes" >&2
    exit 1
    ;;
esac

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

RECDATE=$(date +%Y-%m-%d)
if [ -n "$RDATE" ]; then
  case "$RDATE" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) RECDATE="$RDATE" ;;
    *)
      echo "ERROR: --date must be YYYY-MM-DD: $RDATE" >&2
      exit 1
      ;;
  esac
  # digit shape is not enough: the compiler requires a real calendar date, so
  # a backdated migration record must not be able to create 2026-02-30
  Y=${RECDATE%%-*}; MD=${RECDATE#*-}; M=${MD%%-*}; D=${MD#*-}
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
    echo "ERROR: --date is not a real calendar date: $RDATE" >&2
    exit 1
  fi
fi
YEAR=${RECDATE%%-*}
DIR="$PROJECT_ROOT/zamm-memory/knowledge/$YEAR"
mkdir -p "$DIR"

FILE=""
tries=0
while [ "$tries" -lt 5 ]; do
  # 5 chars from a 30-symbol alphabet: lowercase Crockford base32 minus the
  # visually ambiguous 0 1 i l o u (30 symbols, not 32)
  SUFFIX=$(LC_ALL=C tr -dc '23456789abcdefghjkmnpqrstvwxyz' < /dev/urandom \
    | dd bs=1 count=5 2>/dev/null)
  CANDIDATE="$DIR/$RECDATE-$SLUG-$SUFFIX.md"
  if [ ! -e "$CANDIDATE" ]; then
    FILE="$CANDIDATE"
    break
  fi
  tries=$((tries + 1))
done
if [ -z "$FILE" ]; then
  echo "ERROR: could not find a free filename (urandom unavailable?)" >&2
  exit 1
fi

# Build the skeleton in a private temp file, then publish it with one atomic
# rename — a concurrent compile must never read a half-written frontmatter.
WORK="$DIR/.zamm-new.$$-$SUFFIX"
{
  echo "---"
  echo "type: $RTYPE"
  if [ -n "$SCOPE" ]; then echo "scope: $SCOPE"; fi
  if [ -n "$SUPERSEDES" ]; then echo "supersedes: $SUPERSEDES"; fi
  if [ "$RTYPE" = "memory" ]; then
    echo "importance: $IMPORTANCE"
    echo "durability: $DURABILITY"
  fi
  if [ -n "$PLAN" ]; then echo "plan: $PLAN"; fi
  if [ "$RTYPE" = "votes" ]; then
    echo "up:"
    echo "down:"
  fi
  echo "created: $RECDATE"
  echo "schema: 3"
  echo "---"
} > "$WORK"

if [ "$RTYPE" = "votes" ]; then
  echo "note: fill up:/down: in the created file (at least one must be non-empty; zamm-compile.sh --check rejects a votes record with both empty)" >&2
fi

if [ "$IMMEDIATE" -eq 1 ]; then
  # Old behaviour: the final record lands immediately (migration/scripted use).
  mv "$WORK" "$FILE"
  echo "$FILE"
else
  # Default: land as <id>.md.draft. The compiler globs *.md, so a .md.draft is
  # invisible to the ledger — a record composed over several edits never shows
  # up half-finished. `memory publish` validates it and renames it into place.
  DRAFT="$FILE.draft"
  mv "$WORK" "$DRAFT"
  echo "Draft created (NOT yet in the ledger). Fill in the body, then run:" >&2
  echo "  zamm-run.sh memory publish $RECDATE-$SLUG-$SUFFIX" >&2
  echo "$DRAFT"
fi
