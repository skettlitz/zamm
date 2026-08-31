#!/bin/sh
# ZAMM candidate validation — sourced by the record writers.
#
# A candidate is judged by ERROR-line DIFF against the same ledger without it:
# an error present in the overlay run but absent from the baseline was
# introduced by the candidate. A whole-ledger pass/fail gate would refuse a
# good record over unrelated pre-existing errors, and grepping stderr for the
# candidate id is unsound in both directions (a diagnostic may name a
# different record, or none at all, and an unrelated id may embed this one).
#
# zamm_validate_candidate <root> <internal-dir> <candidate-file> <display-dir> [tree]
#   0  the candidate introduces no new errors (new warnings are printed)
#   1  it introduces errors, or the check could not run; diagnostics on stderr
# tree (default knowledge) selects which record tree the candidate is judged
# against — a backlog candidate must diff against the backlog ledger, or its
# supersede targets read as dangling and its policy rules never run.

zamm_validate_candidate() {
  _vroot=$1; _vint=$2; _vcand=$3; _vdisp=$4; _vtree=${5:-knowledge}
  _vbase=$(mktemp "${TMPDIR:-/tmp}/zamm-base.XXXXXX") || {
    echo "zamm: could not create a scratch file for validation" >&2
    return 1
  }
  _vover=$(mktemp "${TMPDIR:-/tmp}/zamm-over.XXXXXX") || {
    rm -f "$_vbase"
    echo "zamm: could not create a scratch file for validation" >&2
    return 1
  }

  sh "$_vint/zamm-compile.sh" --project-root "$_vroot" --tree "$_vtree" --check >/dev/null 2>"$_vbase" || true
  _vrc=0
  sh "$_vint/zamm-compile.sh" --project-root "$_vroot" --tree "$_vtree" --check --with-candidate "$_vcand" \
    >/dev/null 2>"$_vover" || _vrc=$?

  # rc > 1 means the check itself could not run (an unreadable tree, say), so
  # the candidate was never actually judged. That is the unreadable case from
  # references/invariants.md: report it and refuse, rather than treat an
  # unread ledger as a clean one.
  if [ "$_vrc" -ne 0 ] && [ "$_vrc" -ne 1 ]; then
    echo "zamm: the ledger could not be validated (check rc=$_vrc); nothing was written." >&2
    sed 's/^/  /' "$_vover" >&2
    rm -f "$_vbase" "$_vover"
    return 1
  fi

  # Diagnostics name the private overlay copy; show the path the record will
  # actually occupy instead.
  _vsed="s|\.compiled/\.overlay\.[^/]*/|$_vdisp/|; s/^/  /"
  _vnew=$(
    { grep '^zamm-compile: ERROR:' "$_vbase" || true; } | sort > "$_vbase.e"
    { grep '^zamm-compile: ERROR:' "$_vover" || true; } | sort > "$_vover.e"
    comm -13 "$_vbase.e" "$_vover.e"
  )
  if [ -n "$_vnew" ]; then
    echo "zamm: the record did not validate; nothing was written. New errors:" >&2
    printf '%s\n' "$_vnew" | sed "$_vsed" >&2
    rm -f "$_vbase" "$_vover" "$_vbase.e" "$_vover.e"
    return 1
  fi

  _vwarn=$(
    { grep '^zamm-compile: WARNING:' "$_vbase" || true; } | sort > "$_vbase.w"
    { grep '^zamm-compile: WARNING:' "$_vover" || true; } | sort > "$_vover.w"
    comm -13 "$_vbase.w" "$_vover.w"
  )
  if [ -n "$_vwarn" ]; then
    echo "zamm: writing with new warning(s):" >&2
    printf '%s\n' "$_vwarn" | sed "$_vsed" >&2
  fi

  rm -f "$_vbase" "$_vover" "$_vbase.e" "$_vover.e" "$_vbase.w" "$_vover.w"
  return 0
}
