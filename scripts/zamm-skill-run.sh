#!/usr/bin/env bash
set -euo pipefail

# The ZAMM family's skill entry point: every skill of the family ships this
# file under this name, so installing or updating any of them reads the same:
#
#   bash <skill-dir>/scripts/zamm-skill-run.sh [--project-root <path>] scaffold [flags]
#
# Commands: scaffold. Work with the skill itself goes through its own
# surfaces (for zamm, zamm-run.sh), not through this script.

SKILL_NAME="zamm"
HERE="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: zamm-skill-run.sh [--project-root <path>] <command> [args...]"
  echo ""
  echo "  scaffold   install or update ${SKILL_NAME}'s agent-instruction surfaces"
  echo "             (zamm-skill-run.sh scaffold --help lists its flags)"
  exit "${1:-1}"
}

ROOT_ARGS=()
if [ $# -ge 1 ] && [ "$1" = "--project-root" ]; then
  if [ $# -lt 2 ]; then
    echo "ERROR: --project-root requires a path" >&2
    exit 1
  fi
  ROOT_ARGS=(--project-root "$2")
  shift 2
fi

[ $# -ge 1 ] || usage
cmd="$1"
shift
case "$cmd" in
  scaffold)
    exec bash "$HERE/zamm-run.sh" scaffold ${ROOT_ARGS[@]+"${ROOT_ARGS[@]}"} "$@"
    ;;
  -h|--help|help)
    usage 0
    ;;
  *)
    echo "ERROR: unknown command: $cmd" >&2
    usage
    ;;
esac
