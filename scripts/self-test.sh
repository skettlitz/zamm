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

echo "[4/5] new-plan (flags-first)"
bash "$SCRIPT_DIR/new-plan.sh" \
  --project-root "$TMP_ROOT" \
  "init-${TODAY_YYYY_MM}-self-test" \
  "smoke-plan" >/dev/null

echo "[5/5] wellbeing-report"
bash "$SCRIPT_DIR/wellbeing-report.sh" --project-root "$TMP_ROOT" >/dev/null

echo ""
echo "PASS: self-test completed successfully."
if [ "$KEEP_TEMP" -eq 1 ]; then
  echo "Kept temp project at: $TMP_ROOT"
fi
