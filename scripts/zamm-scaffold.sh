#!/usr/bin/env bash
set -euo pipefail

# ZAMM scaffold — creates the /zamm-memory/ directory tree and runtime protocol files.
# Run from the target project root. Idempotent by default.
# Usage: bash zamm-scaffold.sh [--project-root <path>] [--overwrite-templates]

usage() {
  echo "Usage: zamm-scaffold.sh [--project-root <path>] [--overwrite-templates]"
  echo ""
  echo "  --project-root   Optional explicit repository root (default: current directory)"
  echo "  --overwrite-templates"
  echo "                   Re-render every scaffold-managed runtime file from the"
  echo "                   installed skill: overwrites .cursor/rules/zamm.mdc and"
  echo "                   .cursorignore if present (default: existing files are kept)."
  echo "                   The AGENTS.md managed block is re-rendered either way."
  exit 1
}

PROJECT_ROOT_OVERRIDE=""
OVERWRITE_TEMPLATES=0
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
    --overwrite-templates)
      OVERWRITE_TEMPLATES=1
      shift
      ;;
    -h|--help)
      usage
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

TODAY=$(date +%Y-%m-%d)
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCAFFOLD_DIR="$SKILL_DIR/references/scaffold"
PLAN_TEMPLATE="$SKILL_DIR/references/templates/plan.template.md"
VERSION_TEMPLATE="$SCAFFOLD_DIR/version.template"
VERSION_FILE="$PROJECT_ROOT/zamm-memory/VERSION"
CURRENT_ZAMM_VERSION="3"
ZAMM_AGENTS_BEGIN_MARKER_REGEX="^<!-- SKILL-BLOCK:zamm:BEGIN"
ZAMM_AGENTS_END_MARKER="<!-- SKILL-BLOCK:zamm:END -->"
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

if version_sha="$(git -C "$SKILL_DIR" rev-parse --short HEAD 2>/dev/null)"; then
  ZAMM_BLOCK_VERSION="git:${version_sha}"
fi
ZAMM_AGENTS_BEGIN_MARKER="<!-- SKILL-BLOCK:zamm:BEGIN version=${ZAMM_BLOCK_VERSION} date=${TODAY} -->"

read_zamm_version() {
  if [ -f "$VERSION_FILE" ]; then
    sed -n '1p' "$VERSION_FILE" | tr -d '[:space:]'
  fi
}

# Refuse to scaffold while pre-v3 tier card files still exist; card conversion
# needs agent judgment and is covered by the migration guide instead. A stale
# pre-v3 VERSION with no tier files left means the migration guide is mid-run
# (tier files deleted, finalization pending) — proceed and overwrite VERSION.
require_v3_or_fresh() {
  local current_version
  current_version="$(read_zamm_version)"
  if [ "$current_version" = "$CURRENT_ZAMM_VERSION" ]; then
    return 0
  fi
  if ls "$PROJECT_ROOT/zamm-memory/active/knowledge/"*.md >/dev/null 2>&1; then
    echo "ERROR: pre-v3 tier card files exist under zamm-memory/active/knowledge/ (VERSION='${current_version:-missing}')."
    echo "       Run the migration guide first:"
    echo "       $SKILL_DIR/references/migrations/v1-v2-to-v3-memory.md"
    exit 1
  fi
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

write_template_file() {
  local path="$1"
  local content="$2"

  if [ "$OVERWRITE_TEMPLATES" -eq 1 ] && [ -f "$path" ]; then
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    echo "  overwritten: $path"
  else
    write_if_new "$path" "$content"
  fi
}

ensure_file_exists() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  if [ ! -f "$path" ]; then
    : > "$path"
    echo "  created: $path"
  fi
}

ensure_line() {
  local path="$1"
  local line="$2"
  if [ -f "$path" ] && grep -Fqx "$line" "$path"; then
    echo "  exists: $path ($line)"
  else
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$line" >> "$path"
    echo "  appended: $path ($line)"
  fi
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

  if grep -Eq "$begin_marker_regex" "$path"; then
    had_existing_block=1
  fi

  filtered_file="$(mktemp)"
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

  cat "$filtered_file" > "$path"
  rm -f "$filtered_file"

  if [ -s "$path" ] && [ -n "$(tail -n1 "$path")" ]; then
    printf '\n' >> "$path"
  fi
  printf '%s\n' "$begin_marker" >> "$path"
  printf '%s\n' "$content" >> "$path"
  printf '%s\n' "$end_marker" >> "$path"

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
  printf '%s\n' "$content" > "$VERSION_FILE"
  echo "  version: $VERSION_FILE -> $CURRENT_ZAMM_VERSION"
}

# --- Ledger + plan roots ---
ensure_dir "$PROJECT_ROOT/zamm-memory/knowledge"
ensure_dir "$PROJECT_ROOT/zamm-memory/active/plans"
ensure_dir "$PROJECT_ROOT/zamm-memory/archive/plans"
ensure_dir "$PROJECT_ROOT/zamm-memory/archive/knowledge/initializations"

# --- Git hygiene for the ledger ---
ensure_line "$PROJECT_ROOT/.gitignore" "zamm-memory/.compiled/"
ensure_line "$PROJECT_ROOT/.gitattributes" "zamm-memory/**/*.md text eol=lf"

# --- Cursor ignore rules ---
if [ -f "$SCAFFOLD_DIR/cursorignore" ]; then
  write_template_file "$PROJECT_ROOT/.cursorignore" "$(cat "$SCAFFOLD_DIR/cursorignore")"
fi

# --- AGENTS.md + Cursor rule (composed from canonical fragments) ---
AGENTS_HEADER="$SCAFFOLD_DIR/agents-header.template.md"
RULE_HEADER="$SCAFFOLD_DIR/rule-header.mdc"
PROTOCOL_BODY="$SCAFFOLD_DIR/protocol-body.template.md"

if [ -f "$AGENTS_HEADER" ] && [ -f "$RULE_HEADER" ] && [ -f "$PROTOCOL_BODY" ]; then
  RAW_AGENTS_CONTENT="$(cat "$AGENTS_HEADER"; printf '\n'; cat "$PROTOCOL_BODY")"
  RAW_RULE_CONTENT="$(cat "$RULE_HEADER"; printf '\n'; cat "$PROTOCOL_BODY")"
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
  [ -f "$AGENTS_HEADER" ] || echo "  warning: missing template fragment: $AGENTS_HEADER"
  [ -f "$RULE_HEADER" ] || echo "  warning: missing template fragment: $RULE_HEADER"
  [ -f "$PROTOCOL_BODY" ] || echo "  warning: missing template fragment: $PROTOCOL_BODY"
fi

write_current_zamm_version

echo ""
echo "ZAMM scaffold complete."
echo "Next steps (commands are safe from any cwd):"
echo "  1. Review .cursor/rules/zamm.mdc, AGENTS.md, .cursorignore, .gitignore, .gitattributes"
echo "  2. Compile the (empty) digest and confirm the toolchain works:"
echo "     bash \"$SKILL_DIR/scripts/zamm-compile.sh\" --project-root \"$PROJECT_ROOT\""
echo "  3. If the digest reports no live records, ask whether to run"
echo "     \"$SKILL_DIR/references/initialization/existing-project.md\""
echo "  4. Create memory records with:"
echo "     bash \"$SKILL_DIR/scripts/zamm-new-memory.sh\" --project-root \"$PROJECT_ROOT\" --scope '<area[/subpath][, area2]>' <topic-slug>"
echo "  5. Create your first plan directory and plan file:"
echo "     PLAN_SLUG=\"$(date +%Y-%m-%d)-YOUR-PLAN-SLUG\""
echo "     mkdir -p \"$PROJECT_ROOT/zamm-memory/active/plans/\$PLAN_SLUG/workdir\""
if [ -f "$PLAN_TEMPLATE" ]; then
  echo "     cp \"$PLAN_TEMPLATE\" \"$PROJECT_ROOT/zamm-memory/active/plans/\$PLAN_SLUG/\$PLAN_SLUG.plan.md\""
else
  echo "     (plan template missing at $PLAN_TEMPLATE; create the .plan.md file manually)"
fi
echo "  6. Check current plan status buckets anytime:"
echo "     bash \"$SKILL_DIR/scripts/zamm-status.sh\" --project-root \"$PROJECT_ROOT\""
echo "  7. Archive finished plan directories when ready:"
echo "     bash \"$SKILL_DIR/scripts/zamm-archive.sh\" --project-root \"$PROJECT_ROOT\""
