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
# Usage: zamm-new-memory.sh [--project-root <path>] [--type memory|tombstone|votes|erasure]
#                           [--scope <tag[, tag2[, tag3]]>] [--supersedes <id[,id...]>]
#                           [--erases <id[,id...]>] [--up <id[,id...]>] [--down <id[,id...]>]
#                           [--importance guardrail|useful|minor]
#                           [--durability days|weeks|months|years|permanent]
#                           [--plan <plan-dir-slug>] [--date YYYY-MM-DD]
#                           [--edit] [--no-validate] <topic-slug> < body.md
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
SCOPE=""
SUPERSEDES=""
ERASES=""
IMPORTANCE="useful"
DURABILITY="months"
PLAN=""
RDATE=""
SLUG=""
UP=""
DOWN=""
EDIT=0
VALIDATE=1

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
    --erases)     need_val "$@"; ERASES="$2"; shift 2 ;;
    --up)         need_val "$@"; UP="$2"; shift 2 ;;
    --down)       need_val "$@"; DOWN="$2"; shift 2 ;;
    --importance) need_val "$@"; IMPORTANCE="$2"; shift 2 ;;
    --durability) need_val "$@"; DURABILITY="$2"; shift 2 ;;
    --plan)       need_val "$@"; PLAN="$2"; shift 2 ;;
    --date)       need_val "$@"; RDATE="$2"; shift 2 ;;
    --edit)        EDIT=1; shift ;;
    --no-validate) VALIDATE=0; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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
  memory|tombstone|votes|erasure) ;;
  *)
    echo "ERROR: --type must be memory, tombstone, votes, or erasure" >&2
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
  echo "ERROR: zamm-memory/knowledge/$YEAR is a symlink or not a real directory;" >&2
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
  echo "---"
  echo "type: $RTYPE"
  if [ -n "$SCOPE" ]; then echo "scope: $SCOPE"; fi
  if [ -n "$SUPERSEDES" ]; then echo "supersedes: $SUPERSEDES"; fi
  if [ -n "$ERASES" ]; then echo "erases: $ERASES"; fi
  if [ "$RTYPE" = "memory" ]; then
    echo "importance: $IMPORTANCE"
    echo "durability: $DURABILITY"
  fi
  if [ -n "$PLAN" ]; then echo "plan: $PLAN"; fi
  if [ "$RTYPE" = "votes" ]; then
    echo "up:${UP:+ $UP}"
    echo "down:${DOWN:+ $DOWN}"
  fi
  echo "created: $RECDATE"
  echo "schema: 3"
  echo "---"
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
    echo "ERROR: could not create a private temporary file under zamm-memory/knowledge/$YEAR" >&2
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
      "knowledge/$YEAR" || exit 1
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
