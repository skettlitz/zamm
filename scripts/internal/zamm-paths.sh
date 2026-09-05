# ZAMM canonical-path verification — shared primitive, sourced
# (`. zamm-paths.sh`) by the dispatcher and by every directly-invocable
# script. Not executable on its own.
#
# The leaf-level symlink discipline (records, plan entries) is
# useless if a CANONICAL ROOT is itself a symlink: `[ -d ]` follows links, so
# a symlinked knowledge/ reads as "the ledger is empty" while the real
# records sit outside the tree, and a symlinked .compiled/ or archive/ routes
# writes outside the repository the caller believes it is operating on. Every
# component of every canonical path must therefore be a real directory that
# physically resolves under the project root.

# zamm_verify_roots <project-root>
# Rejects a symlink (or a non-directory) at any component of the canonical
# memory roots and verifies zamm-memory/ physically resolves under the
# physical project root. Missing components are legal — scaffold creates
# them, and missing-vs-damaged is judged by each consumer (the plan manifest
# reports MISSING roots; the compiler requires knowledge/). Prints ERROR
# lines on stderr and returns 1 on any violation; callers exit 4 (the
# unreadable/untrustworthy taxonomy: refuse to operate, previous digest left
# untouched).
zamm_verify_roots() {
  _zvr_root="$1"
  _zvr_bad=0
  for _zvr_rel in \
    zamm-memory \
    zamm-memory/knowledge \
    zamm-memory/backlog \
    zamm-memory/journal \
    zamm-memory/archive \
    zamm-memory/archive/knowledge \
    zamm-memory/archive/backlog \
    zamm-memory/archive/journal \
    zamm-memory/archive/plans \
    zamm-memory/active \
    zamm-memory/active/plans \
    zamm-memory/.compiled
  do
    _zvr_p="$_zvr_root/$_zvr_rel"
    if [ -L "$_zvr_p" ]; then
      echo "ERROR: $_zvr_rel is a symlink; the memory tree must be real directories (no symlinks)." >&2
      echo "       Refusing to operate: a symlinked root reads or writes outside the project." >&2
      _zvr_bad=1
    elif [ -e "$_zvr_p" ] && [ ! -d "$_zvr_p" ]; then
      echo "ERROR: $_zvr_rel exists but is not a directory; refusing to operate." >&2
      _zvr_bad=1
    fi
  done
  # Belt and braces: even with no symlink at any listed component, verify the
  # tree PHYSICALLY resolves under the physical project root (covers mount
  # tricks and any component this list might miss). pwd -P on both sides keeps
  # a project root that is itself reached through a symlink working (macOS
  # /tmp -> /private/tmp).
  if [ "$_zvr_bad" -eq 0 ] && [ -d "$_zvr_root/zamm-memory" ]; then
    _zvr_pr=$(cd "$_zvr_root" 2>/dev/null && pwd -P) || _zvr_pr=""
    _zvr_pm=$(cd "$_zvr_root/zamm-memory" 2>/dev/null && pwd -P) || _zvr_pm=""
    if [ -z "$_zvr_pr" ] || [ -z "$_zvr_pm" ]; then
      echo "ERROR: the memory tree cannot be entered (unreadable, not empty); refusing to operate." >&2
      _zvr_bad=1
    elif [ "$_zvr_pm" != "$_zvr_pr/zamm-memory" ]; then
      echo "ERROR: zamm-memory does not physically resolve under the project root" >&2
      echo "       ($_zvr_pm vs $_zvr_pr/zamm-memory); refusing to operate." >&2
      _zvr_bad=1
    fi
  fi
  [ "$_zvr_bad" -eq 0 ]
}

# zamm_verify_no_symlinks <project-root>
# The ledger holds real files and real directories, nothing else
# (references/invariants.md, G5). Any symlink under any record tree is
# refused, at any position, whatever it points at.
#
# The reason is self-containment: a ledger has to travel with its repository,
# and a symlink means the knowledge lives somewhere a clone will not have. One
# uniform rule also beats reasoning about which positions are dangerous — the
# previous version judged by position because a `[ -d ]` probe cannot tell a
# dangling directory link from a file link, and a symlinked year directory
# makes every record behind it invisible to `find` (the ledger reads as
# SMALLER rather than unreachable, and a digest published from it silently
# drops records). With every symlink refused, that distinction stops mattering.
#
# Prints ERROR lines on stderr and returns 1 on any violation; callers
# exit 4 (unreadable/untrustworthy: refuse, previous digest untouched).
zamm_verify_no_symlinks() {
  _zvl_root="$1"
  _zvl_bad=0
  for _zvl_tree in "$_zvl_root/zamm-memory/knowledge" \
                   "$_zvl_root/zamm-memory/archive/knowledge" \
                   "$_zvl_root/zamm-memory/backlog" \
                   "$_zvl_root/zamm-memory/archive/backlog" \
                   "$_zvl_root/zamm-memory/journal" \
                   "$_zvl_root/zamm-memory/archive/journal"; do
    [ -d "$_zvl_tree" ] || continue
    if ! _zvl_links=$(find "$_zvl_tree" -type l); then
      echo "ERROR: could not enumerate ${_zvl_tree#"$_zvl_root/"} (unreadable, not empty)." >&2
      _zvl_bad=1
      continue
    fi
    [ -n "$_zvl_links" ] || continue
    while IFS= read -r _zvl_l; do
      [ -n "$_zvl_l" ] || continue
      echo "ERROR: ${_zvl_l#"$_zvl_root/"}: symlink inside the ledger; refusing to operate." >&2
      echo "       The ledger must be self-contained: real files and real" >&2
      echo "       directories only, so it travels with the repository." >&2
      _zvl_bad=1
    done <<EOF
$_zvl_links
EOF
  done
  [ "$_zvl_bad" -eq 0 ]
}
