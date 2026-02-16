#!/usr/bin/env bash
set -euo pipefail

# ZAMM self-test:
# - Scaffold a fresh temp project.
# - Run validate + janitor-check.
# - Smoke-test new-plan flag ordering and wellbeing report.
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

echo "[1/5] scaffold"
bash "$SCRIPT_DIR/scaffold.sh" --project-root "$TMP_ROOT" >/dev/null

echo "[2/5] validate"
bash "$SCRIPT_DIR/validate.sh" --project-root "$TMP_ROOT" >/dev/null

echo "[3/5] janitor-check --quiet"
if bash "$SCRIPT_DIR/janitor-check.sh" --project-root "$TMP_ROOT" --quiet; then
  :
else
  janitor_exit=$?
  echo "ERROR: janitor-check returned $janitor_exit on a fresh scaffold (expected 0)"
  exit 1
fi

echo "[4/7] new-plan (flags-first)"
bash "$SCRIPT_DIR/new-plan.sh" \
  --project-root "$TMP_ROOT" \
  "init-${TODAY_YYYY_MM}-self-test" \
  "smoke-plan" >/dev/null

echo "[5/7] verify .plan.md suffix and template fields"
TODAY=$(date +%Y-%m-%d)
PLAN_FILE="$TMP_ROOT/zamm-memory/active/workstreams/init-${TODAY_YYYY_MM}-self-test/plans/${TODAY}-smoke-plan.plan.md"
if [ ! -f "$PLAN_FILE" ]; then
  echo "ERROR: expected plan file not found: $PLAN_FILE"
  exit 1
fi
for field in "Workstream:" "Owner agent:" "Last updated:" "## Why / rationale" "## Risks" "## Loose ends"; do
  if ! grep -q "$field" "$PLAN_FILE"; then
    echo "ERROR: plan template missing field: $field"
    exit 1
  fi
done

echo "[6/7] new-plan subplan (parent warning)"
stderr_output=$(bash "$SCRIPT_DIR/new-plan.sh" \
  --project-root "$TMP_ROOT" \
  "init-${TODAY_YYYY_MM}-self-test" \
  "child-plan" \
  --subplan "nonexistent-parent" 2>&1 1>/dev/null || true)
if echo "$stderr_output" | grep -q "WARNING.*parent plan"; then
  :
else
  echo "ERROR: expected parent-not-found warning on stderr for --subplan with missing parent"
  exit 1
fi

echo "[7/7] wellbeing-report"
bash "$SCRIPT_DIR/wellbeing-report.sh" --project-root "$TMP_ROOT" >/dev/null

echo ""
echo "PASS: self-test completed successfully."
if [ "$KEEP_TEMP" -eq 1 ]; then
  echo "Kept temp project at: $TMP_ROOT"
fi
