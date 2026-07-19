#!/bin/sh
# ZAMM new-memory — creates a ledger record file with a collision-safe name
# (YYYY-MM-DD-<slug>-<5 random base32 chars>.md) and a frontmatter skeleton.
# Prints the created file path; the caller fills the body afterwards
# (and up:/down: lists for votes records).
#
# Usage: zamm-new-memory.sh [--project-root <path>] [--type memory|tombstone|votes]
#                           [--scope <tag[, tag2[, tag3]]>] [--supersedes <id[,id...]>]
#                           [--importance guardrail|useful|minor]
#                           [--durability days|weeks|months|years|permanent]
#                           [--plan <plan-dir-slug>] [--date YYYY-MM-DD] <topic-slug>
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
    --type)       RTYPE="$2"; shift 2 ;;
    --scope)      SCOPE="$2"; shift 2 ;;
    --supersedes) SUPERSEDES="$2"; shift 2 ;;
    --importance) IMPORTANCE="$2"; shift 2 ;;
    --durability) DURABILITY="$2"; shift 2 ;;
    --plan)       PLAN="$2"; shift 2 ;;
    --date)       RDATE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
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

# scope: 1-3 area tags from the fixed set; subpath on the first tag only;
# other must stand alone (same contract zamm-compile.sh --check enforces)
if [ -n "$SCOPE" ]; then
  VALID_AREAS=" domain contracts conventions internals quality tooling ops meta "
  NTAGS=0
  SEEN=" "
  OLD_IFS=$IFS
  IFS=', '
  set -f
  for TAG in $SCOPE; do
    [ -z "$TAG" ] && continue
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
  done
  set +f
  IFS=$OLD_IFS
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
fi
YEAR=${RECDATE%%-*}
DIR="$PROJECT_ROOT/zamm-memory/knowledge/$YEAR"
mkdir -p "$DIR"

FILE=""
tries=0
while [ "$tries" -lt 5 ]; do
  # 5 chars from lowercase Crockford base32 (no 0 1 i l o u)
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
} > "$FILE"

if [ "$RTYPE" = "votes" ]; then
  echo "note: fill up:/down: in the created file (at least one must be non-empty; zamm-compile.sh --check rejects a votes record with both empty)" >&2
fi
echo "$FILE"
