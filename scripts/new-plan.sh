#!/usr/bin/env bash
set -euo pipefail

# ZAMM new-plan — creates a plan file at the deterministic path enforced by
# the Plan Placement Contract (spec section 6).
#
# Usage:
#   bash new-plan.sh <initiative-slug> <plan-slug> [--subplan <parent-plan-slug>] [--project-root <path>]
#
# Examples:
#   bash new-plan.sh init-2026-02-auth-oidc token-refresh
#   bash new-plan.sh init-2026-02-auth-oidc migrations --subplan token-refresh

usage() {
  echo "Usage: new-plan.sh <initiative-slug> <plan-slug> [--subplan <parent-plan-slug>] [--project-root <path>]"
  echo ""
  echo "  initiative-slug   Name of the workstream directory (e.g. init-2026-02-auth-oidc)"
  echo "  plan-slug         Short name for this plan (e.g. token-refresh)"
  echo "  --subplan <slug>  Make this a subplan of <parent-plan-slug>"
  echo "  --project-root    Optional explicit repository root (default: current directory)"
  exit 1
}
PARENT_SLUG=""
PROJECT_ROOT_OVERRIDE=""
POSITIONALS=()

validate_slug() {
  local label="$1"
  local value="$2"
  if [[ "$value" == *"/"* ]] || [[ "$value" =~ [[:space:]] ]]; then
    echo "ERROR: invalid ${label} '$value' (must not contain '/' or whitespace)"
    exit 1
  fi
}

resolve_explicit_root() {
  local path="$1"
  if [ ! -d "$path" ]; then
    echo "ERROR: --project-root path does not exist: $path"
    exit 1
  fi
  (cd "$path" && pwd)
}

while [ $# -gt 0 ]; do
  case "$1" in
    --subplan)
      if [ $# -lt 2 ]; then
        echo "ERROR: --subplan requires a parent plan slug"
        exit 1
      fi
      PARENT_SLUG="$2"
      shift 2
      ;;
    --project-root)
      if [ $# -lt 2 ]; then
        echo "ERROR: --project-root requires a path"
        exit 1
      fi
      PROJECT_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        POSITIONALS+=("$1")
        shift
      done
      ;;
    -*)
      echo "ERROR: unknown option: $1"
      usage
      ;;
    *)
      POSITIONALS+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONALS[@]}" -ne 2 ]; then
  echo "ERROR: expected exactly 2 positional args: <initiative-slug> <plan-slug>"
  usage
fi

INITIATIVE_SLUG="${POSITIONALS[0]}"
PLAN_SLUG="${POSITIONALS[1]}"

validate_slug "initiative-slug" "$INITIATIVE_SLUG"
validate_slug "plan-slug" "$PLAN_SLUG"

if [ -n "$PARENT_SLUG" ]; then
  validate_slug "parent-plan-slug" "$PARENT_SLUG"
fi

if [ -n "$PROJECT_ROOT_OVERRIDE" ]; then
  PROJECT_ROOT=$(resolve_explicit_root "$PROJECT_ROOT_OVERRIDE")
else
  PROJECT_ROOT="$PWD"
fi

TODAY=$(date +%Y-%m-%d)
WORKSTREAMS="$PROJECT_ROOT/zamm-memory/active/workstreams"
TEMPLATE_DIR="$WORKSTREAMS/_TEMPLATE"
INIT_DIR="$WORKSTREAMS/$INITIATIVE_SLUG"

if [ ! -d "$WORKSTREAMS" ]; then
  echo "ERROR: zamm workspace not found at: $WORKSTREAMS"
  echo "       Run scaffold.sh in repo root or pass --project-root <repo-root>."
  exit 1
fi

# --- Bootstrap initiative from _TEMPLATE if it doesn't exist ---
if [ ! -d "$INIT_DIR" ]; then
  if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "ERROR: neither initiative '$INITIATIVE_SLUG' nor _TEMPLATE exist."
    echo "       Run scaffold.sh first."
    exit 1
  fi
  echo "Initiative '$INITIATIVE_SLUG' does not exist. Creating from _TEMPLATE..."
  cp -r "$TEMPLATE_DIR" "$INIT_DIR"
  echo "  created: $INIT_DIR"
fi

PLANS_DIR="$INIT_DIR/plans"
mkdir -p "$PLANS_DIR"

# --- Build filename ---
if [ -n "$PARENT_SLUG" ]; then
  FILENAME="${TODAY}-${PARENT_SLUG}.subplan-${PLAN_SLUG}.md"
else
  FILENAME="${TODAY}-${PLAN_SLUG}.md"
fi

PLAN_PATH="$PLANS_DIR/$FILENAME"

if [ -f "$PLAN_PATH" ]; then
  echo "Plan already exists: $PLAN_PATH"
  exit 0
fi

# --- Write plan template ---
if [ -n "$PARENT_SLUG" ]; then
  PLAN_TITLE="Subplan: $PLAN_SLUG (parent: $PARENT_SLUG)"
  parent_candidate=$(find "$PLANS_DIR" -maxdepth 1 -type f -name "????-??-??-${PARENT_SLUG}.md" | sort | tail -n 1)
  if [ -n "$parent_candidate" ]; then
    parent_basename=$(basename "$parent_candidate")
    PARENT_LINE="Parent plan: ${parent_basename}"
  else
    PARENT_LINE="Parent plan slug: ${PARENT_SLUG} (unresolved; expected YYYY-MM-DD-${PARENT_SLUG}.md)"
  fi
else
  PLAN_TITLE="Plan: $PLAN_SLUG"
  PARENT_LINE=""
fi

PLAN_CONTENT="# $PLAN_TITLE

Status: Draft

Wellbeing-before:
Complexity-forecast:
Memory-upvotes:
Memory-downvotes:

Scope (in):
Scope (out):
${PARENT_LINE:+${PARENT_LINE}
}
## Done-when

- [ ]

## Approach



## PR list

- (none yet)

## Evidence

-

## Docs impacted

- (none yet)

Wellbeing-after:
Complexity-felt:
Complexity-delta:
"

printf '%s\n' "$PLAN_CONTENT" > "$PLAN_PATH"
echo "Created: $PLAN_PATH"
