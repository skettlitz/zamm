#!/bin/sh
# ZAMM plan manifest — the one checked enumeration of the plan trees. Every
# consumer of "which plans exist" (plan check, the digest plans tail, status,
# archive, cross-check) reads this instead of running its own glob or find:
# a private glob over an unreadable directory expands to nothing and turns
# "I could not read the plans" into "there are no plans", and a `[ -d ]` test
# follows symlinks into content the tree never contained.
#
# Usage: zamm-plan-manifest.sh [--project-root <path>]
#
# Output: sorted TAB-separated lines on stdout.
#   PLANDIR\t<abs dir>      regular directory directly under active/plans
#   PLANFILE\t<abs file>    readable main-candidate plan file in a PLANDIR
#                           (maxdepth 1, *.plan.md, not *.subplan-*)
#   SUBPLAN\t<abs file>     readable *.subplan-*.plan.md file in a PLANDIR
#   ARCHDIR\t<abs dir>      regular directory directly under archive/plans
#   ARCHFILE\t<abs file>    readable main-candidate plan file in an ARCHDIR
#   SYMLINK\t<abs path>     symlinked entry (either tree, any depth scanned);
#                           never followed, never read
#   NOTDIR\t<abs path>      non-directory entry directly under a tree, or a
#                           directory posing as a *.plan.md file
#   UNREADABLE\t<abs file>  plan file that exists but cannot be opened
#   DUP\t<slug>\t<active dir>\t<archive dir>   same plan id in both trees
#
# Hidden entries (leading dot) are ignored. An absent tree is a legal empty
# tree (no lines, exit 0). An EXISTING tree that cannot be enumerated is
# exit 4: unreadable, not empty — the failure a glob would silently eat.

set -eu
LC_ALL=C
export LC_ALL

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
      echo "Usage: zamm-plan-manifest.sh [--project-root <path>]"
      echo "  Emit the checked, tagged enumeration of active and archived plans."
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ACTIVE="$PROJECT_ROOT/zamm-memory/active/plans"
ARCHIVE="$PROJECT_ROOT/zamm-memory/archive/plans"

T_ENT=$(mktemp "${TMPDIR:-/tmp}/zamm-plan-mf-ent.XXXXXX")
T_PF=$(mktemp "${TMPDIR:-/tmp}/zamm-plan-mf-pf.XXXXXX")
T_OUT=$(mktemp "${TMPDIR:-/tmp}/zamm-plan-mf-out.XXXXXX")
trap 'rm -f "$T_ENT" "$T_PF" "$T_OUT" "$T_OUT.dup"' EXIT HUP INT TERM

fail_unreadable() {
  echo "ERROR: could not enumerate the plan tree (a directory could not be read)." >&2
  echo "       The plan tree is unreadable, not empty." >&2
  exit 4
}

# emit_tree <tree root> <dir tag> <file tag>
emit_tree() {
  tree="$1"; dtag="$2"; ftag="$3"
  # a symlinked tree root would route every "plan" through content outside the
  # memory tree; refuse to follow it
  if [ -L "$tree" ]; then
    printf 'SYMLINK\t%s\n' "$tree" >> "$T_OUT"
    return 0
  fi
  [ -d "$tree" ] || return 0
  # Two checked stages, mirroring the ledger manifest: find exits non-zero
  # when it cannot descend a directory, and each stage writes a file whose
  # exit status is inspected — piping straight to a reader would report only
  # the reader's status. find does not follow symlinks, so a symlinked dir is
  # listed at depth 1 and its contents are never enumerated.
  find "$tree" -mindepth 1 -maxdepth 1 -print > "$T_ENT" || fail_unreadable
  find "$tree" -mindepth 2 -maxdepth 2 -name '*.plan.md' -print > "$T_PF" || fail_unreadable
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    base=${e##*/}
    case "$base" in .*) continue ;; esac
    if [ -L "$e" ]; then
      printf 'SYMLINK\t%s\n' "$e" >> "$T_OUT"
    elif [ -d "$e" ]; then
      printf '%s\t%s\n' "$dtag" "$e" >> "$T_OUT"
    else
      printf 'NOTDIR\t%s\n' "$e" >> "$T_OUT"
    fi
  done < "$T_ENT"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base=${f##*/}
    case "$base" in .*) continue ;; esac
    if [ -L "$f" ]; then
      printf 'SYMLINK\t%s\n' "$f" >> "$T_OUT"
    elif [ -d "$f" ]; then
      printf 'NOTDIR\t%s\n' "$f" >> "$T_OUT"
    elif [ ! -r "$f" ]; then
      printf 'UNREADABLE\t%s\n' "$f" >> "$T_OUT"
    else
      case "$base" in
        *.subplan-*) printf 'SUBPLAN\t%s\n' "$f" >> "$T_OUT" ;;
        *)           printf '%s\t%s\n' "$ftag" "$f" >> "$T_OUT" ;;
      esac
    fi
  done < "$T_PF"
}

: > "$T_OUT"
emit_tree "$ACTIVE" PLANDIR PLANFILE
emit_tree "$ARCHIVE" ARCHDIR ARCHFILE

# duplicate plan identity across the two trees: the same slug active AND
# archived makes every by-slug reference (votes records, plan create, archive
# moves) ambiguous
awk -F'\t' '
  $1 == "PLANDIR" { n = split($2, p, "/"); act[p[n]] = $2 }
  $1 == "ARCHDIR" { n = split($2, p, "/"); if (p[n] in act) printf "DUP\t%s\t%s\t%s\n", p[n], act[p[n]], $2 }
' "$T_OUT" >> "$T_OUT.dup" || fail_unreadable
cat "$T_OUT.dup" >> "$T_OUT" && rm -f "$T_OUT.dup"

sort "$T_OUT" || fail_unreadable
