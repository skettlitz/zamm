#!/usr/bin/env bash
set -euo pipefail

# ZAMM scaffold — creates the /zamm-memory/ directory tree and runtime protocol files.
# Run from the target project root. Idempotent by default.
# Usage: bash scaffold.sh [--project-root <path>] [--overwrite-templates]

usage() {
  echo "Usage: scaffold.sh [--project-root <path>] [--overwrite-templates]"
  echo ""
  echo "  --project-root   Optional explicit repository root (default: current directory)"
  echo "  --overwrite-templates"
  echo "                   Overwrite scaffold-managed runtime protocol files if they exist"
  echo "                   (AGENTS.md, .cursor/rules/zamm.mdc)"
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
PLAN_TEMPLATE="$SKILL_DIR/references/templates/plan-template.plan.template.md"

if [ ! -d "$SCAFFOLD_DIR" ]; then
  echo "ERROR: missing scaffold directory: $SCAFFOLD_DIR"
  exit 1
fi

echo "ZAMM: scaffolding in ${PROJECT_ROOT}"

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

write_from_template_if_new() {
  local dest_path="$1"
  local source_path="$2"
  local content
  content="$(render_template_file "$source_path")"
  write_if_new "$dest_path" "$content"
}

# --- Knowledge tier files ---
write_from_template_if_new \
  "$PROJECT_ROOT/zamm-memory/active/knowledge/WEEKLY.md" \
  "$SCAFFOLD_DIR/knowledge-weekly.template.md"
write_from_template_if_new \
  "$PROJECT_ROOT/zamm-memory/active/knowledge/MONTHLY.md" \
  "$SCAFFOLD_DIR/knowledge-monthly.template.md"
write_from_template_if_new \
  "$PROJECT_ROOT/zamm-memory/active/knowledge/EVERGREEN.md" \
  "$SCAFFOLD_DIR/knowledge-evergreen.template.md"

# --- Plan roots ---
ensure_dir "$PROJECT_ROOT/zamm-memory/active/plans"
ensure_dir "$PROJECT_ROOT/zamm-memory/archive/plans"

# --- Cursor ignore rules ---
write_from_template_if_new \
  "$PROJECT_ROOT/.cursorignore" \
  "$SCAFFOLD_DIR/cursorignore"

# --- AGENTS.md + Cursor rule (composed from canonical fragments) ---
AGENTS_HEADER="$SCAFFOLD_DIR/agents-header.template.md"
RULE_HEADER="$SCAFFOLD_DIR/rule-header.mdc"
PROTOCOL_BODY="$SCAFFOLD_DIR/protocol-body.template.md"

if [ -f "$AGENTS_HEADER" ] && [ -f "$RULE_HEADER" ] && [ -f "$PROTOCOL_BODY" ]; then
  AGENTS_CONTENT="$(cat "$AGENTS_HEADER"; printf '\n'; cat "$PROTOCOL_BODY")"
  RULE_CONTENT="$(cat "$RULE_HEADER"; printf '\n'; cat "$PROTOCOL_BODY")"
  write_template_file "$PROJECT_ROOT/AGENTS.md" "$AGENTS_CONTENT"
  write_template_file "$PROJECT_ROOT/.cursor/rules/zamm.mdc" "$RULE_CONTENT"
else
  [ -f "$AGENTS_HEADER" ] || echo "  warning: missing template fragment: $AGENTS_HEADER"
  [ -f "$RULE_HEADER" ] || echo "  warning: missing template fragment: $RULE_HEADER"
  [ -f "$PROTOCOL_BODY" ] || echo "  warning: missing template fragment: $PROTOCOL_BODY"
fi

echo ""
echo "ZAMM scaffold complete."
echo "Next steps:"
echo "  1. Review .cursor/rules/zamm.mdc, AGENTS.md, and .cursorignore"
echo "  2. Add initial EVERGREEN cards (architecture, key entry points)"
echo "  3. Create your first plan directory and plan file:"
echo "     PLAN_SLUG=\"$(date +%Y-%m-%d)-YOUR-PLAN-SLUG\""
echo "     mkdir -p zamm-memory/active/plans/\$PLAN_SLUG/workdir"
if [ -f "$PLAN_TEMPLATE" ]; then
  echo "     cp \"$PLAN_TEMPLATE\" zamm-memory/active/plans/\$PLAN_SLUG/\$PLAN_SLUG.plan.md"
else
  echo "     (plan template missing at $PLAN_TEMPLATE; create the .plan.md file manually)"
fi
echo "  4. Check current plan status buckets anytime:"
echo "     bash \"$SKILL_DIR/scripts/zamm-status.sh\""
echo "  5. Archive finished plan directories when ready:"
echo "     bash \"$SKILL_DIR/scripts/archive-done-initiatives.sh\""
