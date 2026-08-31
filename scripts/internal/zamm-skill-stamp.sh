#!/bin/sh
# ZAMM skill stamp — a short content hash over the skill's operative inputs:
# the scaffold source fragments, the templates, and ALL the scripts. scaffold
# writes this stamp into the managed-block markers; status recomputes it to
# detect drift. Both MUST derive it identically, so the logic lives here once
# rather than in each caller.
#
# The scripts are hashed too, not only the scaffold sources: an edit to
# zamm-compile.sh or zamm-run.sh changes how the skill behaves even when the
# rendered protocol text is byte-identical, and the drift signal should tell a
# scaffolded project that the skill it installed has moved.
#
# Content-derived even in a git checkout: a `git rev-parse` short SHA is the
# SAME string for a clean tree and a tree with uncommitted edits, so a dirty
# skill would have stamped "current" while its rendered protocol had actually
# changed. Hashing the files (paths included, so adding or renaming a fragment
# moves the stamp) makes an edited tree read STALE until re-scaffolded.
#
# Prints one line: "sha:<12 hex>" normally, or "local" if no hasher exists.
set -eu
LC_ALL=C
export LC_ALL

SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

hasher=""
if command -v shasum >/dev/null 2>&1; then hasher="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then hasher="sha256sum"
elif command -v cksum >/dev/null 2>&1; then hasher="cksum"
else
  echo "local"
  exit 0
fi

# Hash EVERY normative input, not just the scaffold sources: the rendered
# protocol and the operative behaviour are governed by SKILL.md, everything
# under references/ (distillation triggers, complexity animals, initialization,
# migration and eternal-memory doctrine, scaffold fragments, templates), and
# all of scripts/. A change to any of them should read STALE until re-scaffold;
# hashing only references/scaffold + references/templates + scripts left edits
# to SKILL.md and references/distillation-triggers.md invisible to drift.
# Dotfiles are pruned at every depth (files and directories both). The skill
# tracks none of them, but a working copy collects them — .DS_Store above all —
# and hashing those made the stamp differ between the author's tree and a clean
# clone of the SAME commit, so every fresh clone reported STALE surfaces and no
# re-scaffold could ever fix it. Anything normative lives in a non-dot path.
digest=$({
  { [ -f "$SKILL_DIR/SKILL.md" ] && printf '%s\n' "$SKILL_DIR/SKILL.md"; }
  find "$SKILL_DIR/references" "$SKILL_DIR/scripts" \
    -name '.*' -prune -o -type f -print 2>/dev/null
} | LC_ALL=C sort | {
  while IFS= read -r f; do
    printf '%s\n' "${f#"$SKILL_DIR"}"
    cat "$f" 2>/dev/null
  done
} | $hasher | tr -d ' -' | cut -c1-12)

[ -n "$digest" ] || { echo "local"; exit 0; }
printf 'sha:%s\n' "$digest"
