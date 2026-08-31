#!/usr/bin/env bash
set -euo pipefail

# ZAMM scaffold — creates the /zamm-memory/ directory tree and runtime protocol files.
# Run from the target project root. Idempotent, and always re-renders the
# scaffold-managed runtime surfaces (they are generated and version-stamped, so
# refreshing them is what scaffold means).
# Usage: bash zamm-scaffold.sh [--project-root <path>]

usage() {
  echo "Usage: zamm-scaffold.sh [--project-root <path>]"
  echo ""
  echo "  --project-root   Optional explicit repository root (default: current directory)"
  exit "${1:-1}"
}

PROJECT_ROOT_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      if [ $# -lt 2 ]; then
        echo "ERROR: --project-root requires a path"
        exit 1
      fi
      PROJECT_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "ERROR: unknown argument: $1"
      usage
      ;;
  esac
done

if [ -n "$PROJECT_ROOT_OVERRIDE" ]; then
  if [ ! -d "$PROJECT_ROOT_OVERRIDE" ]; then
    echo "ERROR: --project-root path does not exist: $PROJECT_ROOT_OVERRIDE"
    exit 1
  fi
  PROJECT_ROOT=$(cd "$PROJECT_ROOT_OVERRIDE" && pwd)
else
  PROJECT_ROOT="$PWD"
fi

# Refuse to scaffold through a symlinked canonical component: ensure_dir's
# mkdir -p silently accepts a pre-existing symlink-to-directory, so running
# scaffold on a poisoned tree would neither detect nor repair it. Genuinely
# missing components are fine — creating them is scaffold's job.
. "$(cd "$(dirname "$0")" && pwd)/zamm-paths.sh"
zamm_verify_roots "$PROJECT_ROOT" || exit 4

# ZAMM_TODAY pins the clock (YYYY-MM-DD). Test-only: this date is stamped
# into the managed-block markers, so golden comparisons of rendered surfaces
# need it fixed. Unset in normal use.
TODAY=${ZAMM_TODAY:-$(date +%Y-%m-%d)}
SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCAFFOLD_DIR="$SKILL_DIR/references/scaffold"
PLAN_TEMPLATE="$SKILL_DIR/references/templates/plan.template.md"
VERSION_TEMPLATE="$SCAFFOLD_DIR/version.template"
VERSION_FILE="$PROJECT_ROOT/zamm-memory/VERSION"
CURRENT_ZAMM_VERSION="3"
ZAMM_AGENTS_BEGIN_MARKER_REGEX="^<!-- SKILL-BLOCK:zamm:BEGIN"
ZAMM_AGENTS_END_MARKER="<!-- SKILL-BLOCK:zamm:END -->"
# .cursorignore uses gitignore syntax, so its markers are # comments
ZAMM_IGNORE_BEGIN_MARKER_REGEX="^# SKILL-BLOCK:zamm:BEGIN"
ZAMM_IGNORE_END_MARKER="# SKILL-BLOCK:zamm:END"
ZAMM_BLOCK_VERSION="local"

display_runtime_path() {
  local path="$1"
  case "$path" in
    "$PROJECT_ROOT")
      printf '<project-root>'
      ;;
    "$PROJECT_ROOT"/*)
      printf '<project-root>%s' "${path#"$PROJECT_ROOT"}"
      ;;
    "$HOME")
      printf '~'
      ;;
    "$HOME"/*)
      printf '~%s' "${path#"$HOME"}"
      ;;
    *)
      printf '%s' "$path"
      ;;
  esac
}

RESOLVED_ZAMM_SKILL="$(display_runtime_path "$SKILL_DIR")"

if [ ! -d "$SCAFFOLD_DIR" ]; then
  echo "ERROR: missing scaffold directory: $SCAFFOLD_DIR"
  exit 1
fi

# Drift stamp. Content-derived over the scaffold sources, templates and the
# scaffold script (see scripts/internal/zamm-skill-stamp.sh), NOT the git short SHA: a
# SHA is identical for a clean checkout and one with uncommitted edits, so a
# dirty skill would stamp "current" while its rendered protocol had changed.
# status recomputes the same value to detect drift, so the two must agree.
STAMP_SCRIPT="$SKILL_DIR/scripts/internal/zamm-skill-stamp.sh"
if [ -f "$STAMP_SCRIPT" ]; then
  ZAMM_BLOCK_VERSION="$(sh "$STAMP_SCRIPT")"
fi
ZAMM_AGENTS_BEGIN_MARKER="<!-- SKILL-BLOCK:zamm:BEGIN version=${ZAMM_BLOCK_VERSION} date=${TODAY} -->"
ZAMM_IGNORE_BEGIN_MARKER="# SKILL-BLOCK:zamm:BEGIN version=${ZAMM_BLOCK_VERSION} date=${TODAY}"

read_zamm_version() {
  if [ -f "$VERSION_FILE" ]; then
    sed -n '1p' "$VERSION_FILE" | tr -d '[:space:]'
  fi
}

# Does the project already hold ZAMM content (records, plans, tier cards)?
# .gitkeep placeholders and the VERSION file itself do not count.
zamm_tree_has_content() {
  [ -d "$PROJECT_ROOT/zamm-memory" ] || return 1
  find "$PROJECT_ROOT/zamm-memory" -type f \
    ! -name '.gitkeep' ! -name 'VERSION' 2>/dev/null | grep -q .
}

# Version gating is a strict state machine, not an inference. Deciding
# "probably mid-migration" from an empty tier directory silently relabelled a
# v2 project as v3 without running the migration or asking anyone; a wrong
# guess here stamps an unmigrated (or half-migrated, or corrupted) tree as
# valid v3, and every later tool trusts that stamp.
require_v3_or_fresh() {
  local current_version
  current_version="$(read_zamm_version)"

  # 1. Already v3: normal idempotent re-scaffold.
  if [ "$current_version" = "$CURRENT_ZAMM_VERSION" ]; then
    rmdir "$PROJECT_ROOT/zamm-memory/active/knowledge" 2>/dev/null || true
    return 0
  fi

  # 2. A VERSION exists and is not 3: refuse, whatever else is on disk.
  if [ -n "$current_version" ]; then
    echo "ERROR: zamm-memory/VERSION is '${current_version}', expected '${CURRENT_ZAMM_VERSION}'."
    echo "       The scaffold will not upgrade a versioned project in place."
    echo "       Run the migration guide first:"
    echo "       $SKILL_DIR/references/migrations/v1-v2-to-v3-memory.md"
    exit 1
  fi

  # 3. No VERSION but ZAMM content exists: unknown state, needs a human.
  if zamm_tree_has_content; then
    echo "ERROR: zamm-memory/ holds content but has no VERSION file."
    echo "       Refusing to stamp an unknown tree as v${CURRENT_ZAMM_VERSION}."
    if ls "$PROJECT_ROOT/zamm-memory/active/knowledge/"*.md >/dev/null 2>&1; then
      echo "       Pre-v3 tier card files are present under zamm-memory/active/knowledge/."
    fi
    echo "       Diagnose the tree, then either run the migration guide:"
    echo "       $SKILL_DIR/references/migrations/v1-v2-to-v3-memory.md"
    echo "       or write the correct version to zamm-memory/VERSION by hand."
    exit 1
  fi

  # 4. No VERSION, no content: genuine fresh install.
  rmdir "$PROJECT_ROOT/zamm-memory/active/knowledge" 2>/dev/null || true
}

echo "ZAMM: scaffolding in ${PROJECT_ROOT}"
require_v3_or_fresh

write_if_new() {
  local path="$1"
  local content="$2"
  if [ -f "$path" ]; then
    echo "  exists: $path"
  else
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    echo "  created: $path"
  fi
}

# Managed runtime surfaces are always re-rendered: they are generated and
# version-stamped, so keeping a stale local copy served no one. (User-owned
# files like .gitignore go through ensure_line / the managed-block writer,
# which never clobber content the scaffold does not own.)
write_template_file() {
  local path="$1"
  local content="$2"
  local verb="created"
  [ -f "$path" ] && verb="refreshed"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  echo "  $verb: $path"
}

ensure_file_exists() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  if [ ! -f "$path" ]; then
    : > "$path"
    echo "  created: $path"
  fi
}

copy_mode() {
  local src="$1" dst="$2" mode
  mode="$(stat -f '%Lp' "$src" 2>/dev/null || stat -c '%a' "$src" 2>/dev/null || echo '')"
  if [ -n "$mode" ]; then
    chmod "$mode" "$dst" 2>/dev/null || true
  fi
}

# Append a line to a config file the project also owns (.gitignore etc).
# A file whose last byte is not a newline would otherwise glue our rule onto
# the user's last rule, destroying both ("dist/" + our line = one bad rule).
# Existing files are rewritten via temp + rename so a crash mid-write cannot
# leave the user with a truncated .gitignore.
ensure_line() {
  local path="$1"
  local line="$2"
  local tmp
  if [ -f "$path" ] && grep -Fqx "$line" "$path"; then
    echo "  exists: $path ($line)"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  if [ ! -f "$path" ]; then
    printf '%s\n' "$line" > "$path"   # new file: honours umask, nothing to clobber
    echo "  created: $path ($line)"
    return 0
  fi
  tmp="$(mktemp "${path}.zamm.XXXXXX")"
  cat "$path" > "$tmp"
  # command substitution strips trailing newlines: empty result = file already
  # ends in a newline, non-empty = last byte is real content
  if [ -s "$tmp" ] && [ -n "$(tail -c1 "$tmp")" ]; then
    printf '\n' >> "$tmp"
    echo "  note: $path had no trailing newline; added one before appending"
  fi
  printf '%s\n' "$line" >> "$tmp"
  copy_mode "$path" "$tmp"
  mv "$tmp" "$path"
  echo "  appended: $path ($line)"
}

# A begin marker with no matching end marker used to delete everything from
# the marker to end-of-file — silently destroying whatever the user wrote
# after it. Structure is validated first and anything unexpected refuses:
# never "repair" a malformed block by dropping an unbounded tail.
assert_managed_block_wellformed() {
  local path="$1" begin_regex="$2" end_marker="$3" begin_marker="$4"
  local nbegin nend

  nbegin="$(grep -Ec "$begin_regex" "$path" || true)"
  nend="$(grep -Fxc "$end_marker" "$path" || true)"

  if [ "$nbegin" -eq 0 ] && [ "$nend" -eq 0 ]; then
    return 0   # no block yet
  fi
  if [ "$nbegin" -eq 1 ] && [ "$nend" -eq 1 ]; then
    # both present exactly once: the end must follow the begin
    if awk -v b="$begin_regex" -v e="$end_marker" '
        $0 ~ b { bl = NR }
        $0 == e { el = NR }
        END { exit (bl != "" && el != "" && el > bl) ? 0 : 1 }' "$path"; then
      return 0
    fi
    echo "ERROR: $path has a ZAMM end marker before its begin marker."
  elif [ "$nbegin" -gt 1 ] || [ "$nend" -gt 1 ]; then
    echo "ERROR: $path has ${nbegin} ZAMM begin and ${nend} end markers (expected one pair)."
  elif [ "$nbegin" -eq 1 ]; then
    echo "ERROR: $path has a ZAMM begin marker with no end marker."
  else
    echo "ERROR: $path has a ZAMM end marker with no begin marker."
  fi
  # Both markers come from the CALLER. Hardcoding the AGENTS.md HTML-comment
  # form here told a user with a damaged .cursorignore to write a marker this
  # script can never match (its regex is ^# SKILL-BLOCK:zamm:BEGIN), and an
  # HTML comment in a gitignore-syntax file is a live pattern, not a comment.
  echo "       Refusing to edit: repairing this automatically would mean deleting"
  echo "       content the scaffold does not own. Fix the markers by hand, or"
  echo "       delete the ZAMM block entirely and re-run. Expected markers:"
  echo "         begin: ${begin_marker}"
  echo "         end:   ${end_marker}"
  echo "       (the version= and date= values are not checked)"
  exit 1
}

# Rules THIS skill wrote into .cursorignore before the sandbox EPERM hazard
# was understood: the whole-file era (up to v3's first release) shipped them
# as the entire file, and the managed-block era shipped them inside the block.
# A re-scaffold removes them wherever they sit, because they are ZAMM's own
# past output — reclaiming it is not editing the user's rules, git still has
# them, and leaving them behind means the prescribed remedy ("re-run
# scaffold") reports success while the sandbox failure it fixes persists.
#
# Exact whole-line matches only. A user rule that merely resembles one of
# these (zamm-memory/archive/**/*.bak, say) is theirs and stays.
ZAMM_LEGACY_IGNORE_RULES="zamm-memory/archive/**
zamm-memory/active/plans/**/workdir/**
zamm-memory/archive/plans/**/workdir/**"

strip_legacy_ignore_lines() {
  local path="$1"
  [ -f "$path" ] || return 0
  local filtered_file notices_file rule

  # Sibling temps for the same reason as upsert_managed_block_at_end: the
  # final mv is an atomic rename only within one filesystem.
  filtered_file="$(mktemp "${path}.zamm.XXXXXX")"
  notices_file="$(mktemp "${path}.zamm.XXXXXX")"
  # The rule list reaches awk through the ENVIRONMENT, not -v: a -v value
  # containing a real newline is rejected outright by BSD awk ("newline in
  # string"), and this list is one rule per line.
  if ! ZAMM_LEGACY_RULES="$ZAMM_LEGACY_IGNORE_RULES" awk \
    -v begin_regex="$ZAMM_IGNORE_BEGIN_MARKER_REGEX" \
    -v end_marker="$ZAMM_IGNORE_END_MARKER" \
    -v filtered="$filtered_file" \
    -v notices="$notices_file" '
    BEGIN {
      n = split(ENVIRON["ZAMM_LEGACY_RULES"], r, "\n")
      for (i = 1; i <= n; i++) legacy[r[i]] = 1
      in_block = 0
    }
    {
      if (in_block == 0 && ($0 ~ begin_regex)) {
        in_block = 1
      } else if (in_block == 1 && ($0 == end_marker)) {
        in_block = 0
      } else if (in_block == 0 && ($0 in legacy)) {
        # Outside the block only: what is inside is replaced wholesale by the
        # upsert that follows, and reporting it as "removed" would announce a
        # deletion the user never had a say in.
        print $0 > notices
        next
      }
      print > filtered
    }
  ' "$path"; then
    rm -f "$filtered_file" "$notices_file"
    echo "ERROR: could not read $path to check it for legacy ZAMM rules."
    exit 1
  fi

  if [ -s "$notices_file" ]; then
    while IFS= read -r rule; do
      [ -n "$rule" ] || continue
      echo "  removed: $path: $rule (legacy ZAMM rule, now in .cursorindexingignore)"
    done < "$notices_file"
    copy_mode "$path" "$filtered_file"
    mv "$filtered_file" "$path"
  else
    rm -f "$filtered_file"      # nothing to reclaim: do not even touch mtime
  fi
  rm -f "$notices_file"
}

upsert_managed_block_at_end() {
  local path="$1"
  local begin_marker="$2"
  local begin_marker_regex="$3"
  local end_marker="$4"
  local content="$5"
  local had_existing_block=0
  local filtered_file

  ensure_file_exists "$path"
  assert_managed_block_wellformed "$path" "$begin_marker_regex" "$end_marker" "$begin_marker"

  if grep -Eq "$begin_marker_regex" "$path"; then
    had_existing_block=1
  fi

  # Create the temp file ADJACENT to the target, not under $TMPDIR: the final
  # `mv` is an atomic rename only within one filesystem, and /tmp is frequently
  # a different mount than the repo (so mv there becomes copy-then-delete, a
  # window where a reader sees a truncated file). The sibling temp shares the
  # target's filesystem.
  filtered_file="$(mktemp "${path}.zamm.XXXXXX")"
  awk \
    -v begin_regex="$begin_marker_regex" \
    -v end_marker="$end_marker" '
    BEGIN { in_block = 0 }
    {
      if (in_block == 0 && ($0 ~ begin_regex)) {
        in_block = 1
        next
      }
      if (in_block == 1 && ($0 == end_marker)) {
        in_block = 0
        next
      }
      if (in_block == 0) {
        print
      }
    }
  ' "$path" > "$filtered_file"

  # assemble the whole file privately, then publish with one rename
  if [ -s "$filtered_file" ] && [ -n "$(tail -c1 "$filtered_file")" ]; then
    printf '\n' >> "$filtered_file"        # no trailing newline: do not glue
  fi
  if [ -s "$filtered_file" ] && [ -n "$(tail -n1 "$filtered_file")" ]; then
    printf '\n' >> "$filtered_file"        # blank line before the block
  fi
  printf '%s\n' "$begin_marker" >> "$filtered_file"
  printf '%s\n' "$content" >> "$filtered_file"
  printf '%s\n' "$end_marker" >> "$filtered_file"
  copy_mode "$path" "$filtered_file"
  mv "$filtered_file" "$path"

  if [ "$had_existing_block" -eq 1 ]; then
    echo "  updated: $path (ZAMM managed block)"
  else
    echo "  appended: $path (ZAMM managed block)"
  fi
}

ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
  if [ ! -f "$dir/.gitkeep" ] && [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
    touch "$dir/.gitkeep"
  fi
}

render_template_file() {
  local source_file="$1"
  if [ ! -f "$source_file" ]; then
    echo "ERROR: missing scaffold template file: $source_file"
    exit 1
  fi
  sed "s/__TODAY__/${TODAY}/g" "$source_file"
}

render_runtime_surface_content() {
  local content="$1"
  # Expand only the FIRST <zamm-skill> token — the definition line in
  # "## Script Path Resolution". Later occurrences stay literal and read as
  # the alias defined there; repeating the full path ~12x costs every agent
  # ~300 tokens per session for zero information.
  content="${content/<zamm-skill>/$RESOLVED_ZAMM_SKILL}"
  printf '%s' "$content"
}

write_current_zamm_version() {
  local content

  if [ -f "$VERSION_TEMPLATE" ]; then
    content="$(render_template_file "$VERSION_TEMPLATE")"
  else
    content="$CURRENT_ZAMM_VERSION"
  fi

  mkdir -p "$(dirname "$VERSION_FILE")"
  # temp + atomic rename: every other command gates on this file, so a crash
  # mid-write must never leave a half-written (unparseable) VERSION behind
  local tmp
  tmp="$(mktemp "$(dirname "$VERSION_FILE")/.VERSION.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$VERSION_FILE"
  echo "  version: $VERSION_FILE -> $CURRENT_ZAMM_VERSION"
}

# --- Ledger + plan roots ---
ensure_dir "$PROJECT_ROOT/zamm-memory/knowledge"
ensure_dir "$PROJECT_ROOT/zamm-memory/backlog"
ensure_dir "$PROJECT_ROOT/zamm-memory/active/plans"
ensure_dir "$PROJECT_ROOT/zamm-memory/archive/plans"
ensure_dir "$PROJECT_ROOT/zamm-memory/archive/knowledge/initializations"

# --- Git hygiene for the ledger ---
ensure_line "$PROJECT_ROOT/.gitignore" "zamm-memory/.compiled/"
ensure_line "$PROJECT_ROOT/.gitattributes" "zamm-memory/**/*.md text eol=lf"

# --- Cursor ignore rules ---
# Managed block, not whole-file ownership: the previous model left the user
# choosing between "no ZAMM rules at all" (normal run kept their file
# untouched) and "your rules deleted" (--overwrite-templates replaced it).
#
# The split is load-bearing, and it is one-sided: the Cursor Agent Sandbox
# maps every .cursorignore-matched path to EPERM, so a zamm-memory rule there
# makes a checked find(1) fail closed (invariants G3) and breaks the command
# that walks that tree. ZAMM therefore writes NO rules into .cursorignore at
# all — only the note explaining why — and hides retired trees and plan
# scratch via .cursorindexingignore, which excludes from the index without
# denying reads. Both files still get a managed block: the note has to live
# somewhere a reader looks, and the block is also what lets a re-scaffold
# reclaim the rules older versions of this skill wrote (see
# strip_legacy_ignore_lines).
#
# A missing template is a hard error, not a silent skip: half of this split
# applied (archive out of .cursorignore, nothing hiding it from the index, or
# worse, the reverse) is exactly the state that must not look healthy. Same
# rule as the protocol fragments below.
for surface in cursorignore cursorindexingignore; do
  ignore_src="$SCAFFOLD_DIR/$surface"
  if [ ! -f "$ignore_src" ]; then
    echo "ERROR: missing scaffold template file: $ignore_src"
    exit 1
  fi
  # Assign first, then pass: the exit status of a command substitution in
  # ARGUMENT position is discarded, so an unreadable template would have
  # rendered an empty managed block while scaffold reported success. As an
  # assignment, set -e sees the failure.
  ignore_content="$(cat "$ignore_src")"
  if [ "$surface" = "cursorignore" ]; then
    strip_legacy_ignore_lines "$PROJECT_ROOT/.cursorignore"
  fi
  upsert_managed_block_at_end \
    "$PROJECT_ROOT/.$surface" \
    "$ZAMM_IGNORE_BEGIN_MARKER" \
    "$ZAMM_IGNORE_BEGIN_MARKER_REGEX" \
    "$ZAMM_IGNORE_END_MARKER" \
    "$ignore_content"
done

# --- AGENTS.md + Cursor rule (composed from canonical fragments) ---
# The always-on surfaces carry the compact ROUTER, not the full protocol:
# ~54KB of manual on two alwaysApply surfaces taxed every session for text
# that is only needed at decision points. The router states what ZAMM is,
# how to compile context, who owns memory and plans, and when to load the
# full protocol body (which stays in this skill, read on demand).
AGENTS_HEADER="$SCAFFOLD_DIR/agents-header.template.md"
RULE_HEADER="$SCAFFOLD_DIR/rule-header.mdc"
PROTOCOL_BODY="$SCAFFOLD_DIR/protocol-body.template.md"
PROTOCOL_ROUTER="$SCAFFOLD_DIR/protocol-router.template.md"

if [ -f "$AGENTS_HEADER" ] && [ -f "$RULE_HEADER" ] && [ -f "$PROTOCOL_ROUTER" ] && [ -f "$PROTOCOL_BODY" ]; then
  RAW_AGENTS_CONTENT="$(cat "$AGENTS_HEADER"; printf '\n'; cat "$PROTOCOL_ROUTER")"
  RAW_RULE_CONTENT="$(cat "$RULE_HEADER"; printf '\n'; cat "$PROTOCOL_ROUTER")"
  AGENTS_CONTENT="$(render_runtime_surface_content "$RAW_AGENTS_CONTENT")"
  RULE_CONTENT="$(render_runtime_surface_content "$RAW_RULE_CONTENT")"
  upsert_managed_block_at_end \
    "$PROJECT_ROOT/AGENTS.md" \
    "$ZAMM_AGENTS_BEGIN_MARKER" \
    "$ZAMM_AGENTS_BEGIN_MARKER_REGEX" \
    "$ZAMM_AGENTS_END_MARKER" \
    "$AGENTS_CONTENT"
  write_template_file "$PROJECT_ROOT/.cursor/rules/zamm.mdc" "$RULE_CONTENT"
else
  # VERSION must not be stamped by an install that could not render the
  # protocol: a project marked v3 whose runtime surfaces are missing looks
  # migrated to every later tool while carrying no operating instructions.
  # PROTOCOL_BODY is required too, although not rendered: the router points
  # agents at it, so an install without it routes to nothing.
  [ -f "$AGENTS_HEADER" ] || echo "ERROR: missing template fragment: $AGENTS_HEADER"
  [ -f "$RULE_HEADER" ] || echo "ERROR: missing template fragment: $RULE_HEADER"
  [ -f "$PROTOCOL_ROUTER" ] || echo "ERROR: missing template fragment: $PROTOCOL_ROUTER"
  [ -f "$PROTOCOL_BODY" ] || echo "ERROR: missing template fragment: $PROTOCOL_BODY"
  echo "       The skill install is incomplete; VERSION was not written."
  exit 1
fi

write_current_zamm_version

echo ""
echo "ZAMM scaffold complete."
echo "Next steps (commands are safe from any cwd):"
echo "  1. Review .cursor/rules/zamm.mdc, AGENTS.md, .cursorignore, .cursorindexingignore, .gitignore, .gitattributes"
echo "  2. Compile the (empty) digest and confirm the toolchain works:"
echo "     bash \"$SKILL_DIR/scripts/zamm-run.sh\" --project-root \"$PROJECT_ROOT\" memory digest"
echo "  3. If the digest reports no live records, ask whether to run"
echo "     \"$SKILL_DIR/references/initialization/existing-project.md\""
# a lone single quote is easier to name than to escape inside these echoes
SQ="'"
echo "  4. Create memory records (one step; the body arrives on stdin):"
echo "     bash \"$SKILL_DIR/scripts/zamm-run.sh\" --project-root \"$PROJECT_ROOT\" memory create --scope ${SQ}<area[/subpath][, area2]>${SQ} <topic-slug> <<${SQ}EOF${SQ}"
echo "     <the record body>"
echo "     EOF"
echo "  5. Create your first plan with the official command (no manual mkdir/cp):"
echo "     bash \"$SKILL_DIR/scripts/zamm-run.sh\" --project-root \"$PROJECT_ROOT\" plan create '<plan title>'"
echo "  6. Check current plan status buckets anytime:"
echo "     bash \"$SKILL_DIR/scripts/zamm-run.sh\" --project-root \"$PROJECT_ROOT\" plan list"
echo "  7. Archive finished plan directories when ready (--list to preview):"
echo "     bash \"$SKILL_DIR/scripts/zamm-run.sh\" --project-root \"$PROJECT_ROOT\" plan archive"
