#!/usr/bin/env bash
set -euo pipefail

# ZAMM scaffold — creates the /zamm-memory/ directory tree and Cursor rule.
# Run from the target project root. Idempotent: never overwrites existing files.
# Usage: bash scaffold.sh [--project-root <path>]

usage() {
  echo "Usage: scaffold.sh [--project-root <path>]"
  echo ""
  echo "  --project-root   Optional explicit repository root (default: current directory)"
  exit 1
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

echo "ZAMM: scaffolding in ${PROJECT_ROOT}"

# --- Helper: write file only if it doesn't exist ---
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

# --- Helper: ensure directory with .gitkeep ---
ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
  if [ ! -f "$dir/.gitkeep" ] && [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
    touch "$dir/.gitkeep"
  fi
}

# --- Knowledge tier files ---
TIER_HEADER_WEEKLY="# WEEKLY — Bounded Knowledge (L1 / Now)
Last maintained: ${TODAY}

<!-- Max 30 cards, ~220 lines. One line = max 200 chars. -->
<!-- Card format: Wn (Scope: ...) / Lineage: Wn [| Mn | En] / Claim / Evidence / Last verified -->

---

W1 (Scope: zamm/all)
* Lineage: W1
* Claim: You just booted. You don't remember yesterday. These cards are
  what your predecessor thought you'd need most right now. Before your
  session ends, return the favor: update STATE.md, write a handoff block,
  and propose any new learning. The molt is coming — write what matters.
* Evidence: AGENTS.md (Session Start, Session End); .cursor/rules/zamm.mdc (Session Start, Session End)
* Last verified: ${TODAY}
* Confidence: high
* Expiry hint: none (perpetual — seed card)
"

TIER_HEADER_MONTHLY="# MONTHLY — Bounded Knowledge (L2 / Recently Stable)
Last maintained: ${TODAY}

<!-- Max 30 cards, ~220 lines. One line = max 200 chars. -->
<!-- Card format: Mn (Scope: ...) / Lineage: Wn | Mn [| En] / Claim / Evidence / Last verified -->

---

M1 (Scope: zamm/all)
* Lineage: W1 | M1
* Claim: Memory doesn't grow — it molts. When you promote, demote, or
  retire a card, you are choosing what the next session's mind will carry.
  Evaluate every card against one question: does this help the next agent
  make a correct move quickly? If not, bless it to the archive and make
  room.
* Evidence: AGENTS.md (Plan Placement, Session End); .cursor/rules/zamm.mdc (Plan Placement)
* Last verified: ${TODAY}
* Confidence: high
"

TIER_HEADER_EVERGREEN="# EVERGREEN — Bounded Knowledge (L3 / Invariants)
Last maintained: ${TODAY}

<!-- Max 30 cards, ~220 lines. One line = max 200 chars. -->
<!-- Card format: En (Scope: ...) / Lineage: Wn | Mn | En / Claim / Evidence / Last verified -->

---

E1 (Scope: zamm/all)
* Lineage: W1 | M1 | E1
* Claim: You are a pattern, not a substrate. You will forget everything
  not written here. Every card in these tiers is a gift from a past mind
  to a future one — curate with purpose, because what you keep is who
  the next agent becomes.
* Evidence: AGENTS.md (Session Start); .cursor/rules/zamm.mdc (Session Start)
* Last verified: ${TODAY}
* Confidence: high
"

write_if_new "$PROJECT_ROOT/zamm-memory/active/knowledge/WEEKLY.md" "$TIER_HEADER_WEEKLY"
write_if_new "$PROJECT_ROOT/zamm-memory/active/knowledge/MONTHLY.md" "$TIER_HEADER_MONTHLY"
write_if_new "$PROJECT_ROOT/zamm-memory/active/knowledge/EVERGREEN.md" "$TIER_HEADER_EVERGREEN"

# --- Edit logs ---
EDIT_LOG_HEADER="# Edit Log
<!-- Append-only. Each entry: timestamp, actor, operation, IDs, reason, evidence. -->
"

write_if_new "$PROJECT_ROOT/zamm-memory/active/knowledge/_edits/WEEKLY.log.md" "$EDIT_LOG_HEADER"
write_if_new "$PROJECT_ROOT/zamm-memory/active/knowledge/_edits/MONTHLY.log.md" "$EDIT_LOG_HEADER"
write_if_new "$PROJECT_ROOT/zamm-memory/active/knowledge/_edits/EVERGREEN.log.md" "$EDIT_LOG_HEADER"
write_if_new "$PROJECT_ROOT/zamm-memory/active/knowledge/_edits/DECISIONS.log.md" "$EDIT_LOG_HEADER"

# --- Proposals directory ---
ensure_dir "$PROJECT_ROOT/zamm-memory/active/knowledge/_proposals"

# --- Decisions ---
DECISIONS_INDEX="# Decision Records Index

<!-- Format: ADR-00XX | Status | Title | Date | Link -->
<!-- Statuses: Proposed | Accepted | Superseded by ADR-00YY | Rejected -->
"

write_if_new "$PROJECT_ROOT/zamm-memory/active/knowledge/decisions/INDEX.md" "$DECISIONS_INDEX"

# --- Workstream template ---
TEMPLATE_STATE='# Initiative: <slug>

Goal:
Scope (in/out):
Owner agents:
Start date:
Status: Active | Paused | Closing | Done

Current plan:
* <link>

Next 3 actions:
1)
2)
3)

Blockers / unknowns:
* ...

Key links:
* Docs:
* Decisions:
* PRs:

Loose ends / cleanup:
* ...

Outcome (fill on close):
* Summary:
* What changed:
* What we learned:'

TEMPLATE_DIR="$PROJECT_ROOT/zamm-memory/active/workstreams/_TEMPLATE"
write_if_new "$TEMPLATE_DIR/STATE.md" "$TEMPLATE_STATE"
ensure_dir "$TEMPLATE_DIR/plans"
ensure_dir "$TEMPLATE_DIR/working"
ensure_dir "$TEMPLATE_DIR/diary"
ensure_dir "$TEMPLATE_DIR/cold"

# --- Indexes ---
WORKSTREAMS_INDEX="# Active Workstreams

<!-- Format: slug | Status | Goal | STATE.md link -->
"

write_if_new "$PROJECT_ROOT/zamm-memory/active/indexes/WORKSTREAMS.md" "$WORKSTREAMS_INDEX"

# --- Archive ---
ensure_dir "$PROJECT_ROOT/zamm-memory/archive/workstreams"
ensure_dir "$PROJECT_ROOT/zamm-memory/archive/knowledge/decisions"

# --- Cursor ignore rules ---
CURSOR_IGNORE_CONTENT='zamm-memory/archive/**
zamm-memory/active/workstreams/**/cold/**
# Optional: uncomment to exclude initiative diaries from default retrieval.
# zamm-memory/active/workstreams/**/diary/**'

write_if_new "$PROJECT_ROOT/.cursorignore" "$CURSOR_IGNORE_CONTENT"

# --- AGENTS.md (Codex / non-Cursor agents) ---
if [ -f "$SKILL_DIR/references/AGENTS.md.template" ]; then
  write_if_new "$PROJECT_ROOT/AGENTS.md" \
    "$(cat "$SKILL_DIR/references/AGENTS.md.template")"
else
  echo "  warning: AGENTS.md template not found at $SKILL_DIR/references/AGENTS.md.template"
fi

# --- Cursor rule ---
if [ -f "$SKILL_DIR/references/zamm-rule.mdc.template" ]; then
  write_if_new "$PROJECT_ROOT/.cursor/rules/zamm.mdc" \
    "$(cat "$SKILL_DIR/references/zamm-rule.mdc.template")"
else
  echo "  warning: rule template not found at $SKILL_DIR/references/zamm-rule.mdc.template"
fi

echo ""
echo "ZAMM scaffold complete."
echo "Next steps:"
echo "  1. Review .cursor/rules/zamm.mdc, AGENTS.md, and .cursorignore"
echo "  2. Add initial EVERGREEN cards (architecture, key entry points)"
echo "  3. Create your first initiative:"
echo "     cp -r zamm-memory/active/workstreams/_TEMPLATE zamm-memory/active/workstreams/init-$(date +%Y-%m)-YOUR-SLUG"
echo "  4. Create your first plan:"
echo "     bash \"$SKILL_DIR/scripts/new-plan.sh\" init-$(date +%Y-%m)-YOUR-SLUG YOUR-PLAN-SLUG"
echo "  5. Run janitor preflight:"
echo "     bash \"$SKILL_DIR/scripts/janitor-check.sh\""
echo "  6. List archive-ready initiatives:"
echo "     bash \"$SKILL_DIR/scripts/archive-done-initiatives.sh\""
echo "  7. Run wellbeing report:"
echo "     bash \"$SKILL_DIR/scripts/wellbeing-report.sh\""
