#!/usr/bin/env bash
set -euo pipefail

# ZAMM self-test:
# - Scaffold a fresh temp project.
# - Verify overwrite-templates mode refreshes template files.
# - Run validate + janitor-check.
# - Verify plan template and wellbeing report.
#
# Usage:
#   bash self-test.sh [--keep-temp]

usage() {
  echo "Usage: self-test.sh [--keep-temp]"
  echo ""
  echo "  --keep-temp   Keep temp project directory for inspection"
  exit 1
}

KEEP_TEMP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-temp)
      KEEP_TEMP=1
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TODAY_YYYY_MM=$(date +%Y-%m)
TODAY=$(date +%Y-%m-%d)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/zamm-self-test.XXXXXX")

cleanup() {
  if [ "$KEEP_TEMP" -eq 0 ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

echo "ZAMM self-test"
echo "Temp project: $TMP_ROOT"
echo ""

echo "[1/6] scaffold"
bash "$SCRIPT_DIR/scaffold.sh" --project-root "$TMP_ROOT" >/dev/null

echo "[2/6] scaffold --overwrite-templates refreshes templates"
STATE_TEMPLATE_FILE="$TMP_ROOT/zamm-memory/active/workstreams/_TEMPLATE/STATE.md"
AGENTS_FILE="$TMP_ROOT/AGENTS.md"
printf '%s\n' "BROKEN TEMPLATE CONTENT" > "$STATE_TEMPLATE_FILE"
printf '%s\n' "BROKEN AGENTS CONTENT" > "$AGENTS_FILE"
bash "$SCRIPT_DIR/scaffold.sh" --project-root "$TMP_ROOT" --overwrite-templates >/dev/null
if ! grep -q "^# Initiative: <slug>" "$STATE_TEMPLATE_FILE"; then
  echo "ERROR: --overwrite-templates did not refresh STATE template"
  exit 1
fi
if ! grep -q "^# AGENTS.md — ZAMM Agent Protocol" "$AGENTS_FILE"; then
  echo "ERROR: --overwrite-templates did not refresh AGENTS.md"
  exit 1
fi

echo "[3/6] validate"
bash "$SCRIPT_DIR/validate.sh" --project-root "$TMP_ROOT" >/dev/null

echo "[4/6] janitor-check --quiet"
if bash "$SCRIPT_DIR/janitor-check.sh" --project-root "$TMP_ROOT" --quiet; then
  :
else
  janitor_exit=$?
  echo "ERROR: janitor-check returned $janitor_exit on a fresh scaffold (expected 0)"
  exit 1
fi

echo "[5/6] verify _PLAN_TEMPLATE.plan.md exists and has required fields"
TEMPLATE_FILE="$TMP_ROOT/zamm-memory/active/workstreams/_TEMPLATE/plans/_PLAN_TEMPLATE.plan.md"
if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "ERROR: plan template not found: $TEMPLATE_FILE"
  exit 1
fi
for field in \
  "Workstream:" \
  "Status: Draft" \
  "## Done-when" \
  "## Learnings" \
  "## Why / rationale" \
  "## Risks" \
  "## Loose ends" \
  "Done-approved-by:" \
  "Done-approved-at:" \
  "Done-approval-evidence:"; do
  if ! grep -q "$field" "$TEMPLATE_FILE"; then
    echo "ERROR: plan template missing field: $field"
    exit 1
  fi
done

echo "[6/6] wellbeing-report"
bash "$SCRIPT_DIR/wellbeing-report.sh" --project-root "$TMP_ROOT" >/dev/null

echo ""
echo "PASS: self-test completed successfully."
if [ "$KEEP_TEMP" -eq 1 ]; then
  echo "Kept temp project at: $TMP_ROOT"
fi
