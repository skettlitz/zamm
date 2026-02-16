#!/usr/bin/env bash
set -euo pipefail

# ZAMM package script:
# - Creates a clean release archive with git archive.
# - Ensures .git / __MACOSX are absent.
# - Uses SKILL.md frontmatter `name` as top-level folder prefix by default.
#
# Usage:
#   bash package-skill.sh [--ref <git-ref>] [--out-dir <path>] [--prefix <name>]

usage() {
  echo "Usage: package-skill.sh [--ref <git-ref>] [--out-dir <path>] [--prefix <name>]"
  echo ""
  echo "  --ref <git-ref>   Git ref to package (default: HEAD)"
  echo "  --out-dir <path>  Output directory (default: ./dist)"
  echo "  --prefix <name>   Top-level folder name inside archive (default: SKILL name)"
  exit 1
}

REF="HEAD"
OUT_DIR=""
PREFIX=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)
      if [ $# -lt 2 ]; then
        echo "ERROR: --ref requires a value"
        exit 1
      fi
      REF="$2"
      shift 2
      ;;
    --out-dir)
      if [ $# -lt 2 ]; then
        echo "ERROR: --out-dir requires a path"
        exit 1
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    --prefix)
      if [ $# -lt 2 ]; then
        echo "ERROR: --prefix requires a value"
        exit 1
      fi
      PREFIX="$2"
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: repository root is not a git work tree: $REPO_ROOT"
  exit 1
fi

if [ -z "$PREFIX" ]; then
  PREFIX=$(sed -n 's/^name:[[:space:]]*//p' "$REPO_ROOT/SKILL.md" | head -n1 | tr -d '[:space:]')
  if [ -z "$PREFIX" ]; then
    echo "ERROR: could not derive skill name from SKILL.md frontmatter"
    exit 1
  fi
fi

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$REPO_ROOT/dist"
fi

mkdir -p "$OUT_DIR"
DATE_TAG=$(date +%Y%m%d)
ARCHIVE_PATH="$OUT_DIR/${PREFIX}-${DATE_TAG}.tar.gz"

git -C "$REPO_ROOT" archive \
  --format=tar.gz \
  --prefix="${PREFIX}/" \
  --output="$ARCHIVE_PATH" \
  "$REF"

if tar -tzf "$ARCHIVE_PATH" | rg -q '(^|/)(__MACOSX|\.git)(/|$)'; then
  echo "ERROR: archive contains forbidden metadata (__MACOSX or .git)"
  exit 1
fi

if ! tar -tzf "$ARCHIVE_PATH" | head -n1 | rg -q "^${PREFIX}/"; then
  echo "ERROR: archive root prefix mismatch (expected ${PREFIX}/)"
  exit 1
fi

echo "Created archive: $ARCHIVE_PATH"
echo "Root prefix: ${PREFIX}/"
echo "Source ref: $REF"
