# ZAMM publication mutex — shared primitives, sourced (`. zamm-lock.sh`) by
# the compiler and by the publish transaction. Not executable on its own.
#
# Caller contract: set LOCK_DIR and REAPER_DIR before calling. The lock is a
# portable mkdir mutex; the pid file inside it names the owner. A lock left
# behind by a killed process is reaped once its recorded owner pid is gone —
# but ONLY under a second mutex, revalidating the SAME owner while holding
# it. Unserialized reaping raced: two contenders could both authorize removal
# of one stale lock, and the slower rm then destroyed the lock the faster
# contender had already reacquired, putting two publishers back in flight.
# Soundness of the revalidation: a new owner can only appear after the stale
# directory is removed, and removal happens only inside the reaper mutex — so
# while the pid file still names the same dead owner, nobody live holds the
# lock (a fresh owner that has not yet written its pid file reads as a
# changed/empty pid and is left alone).

# a pid is alive if we can signal it OR ps still lists it (kill -0 fails with
# EPERM on a live process owned by someone else, which must not read as dead)
zamm_pid_alive() { kill -0 "$1" 2>/dev/null || ps -p "$1" >/dev/null 2>&1; }

# Acquire the lock for this process (pid file = $$). Blocks up to ~60s, then
# prints the timeout message and returns 1 with nothing held.
zamm_lock_acquire() {
  _tries=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    _lpid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ -n "$_lpid" ] && ! zamm_pid_alive "$_lpid"; then
      if mkdir "$REAPER_DIR" 2>/dev/null; then
        _lpid2=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
        if [ "$_lpid2" = "$_lpid" ] && ! zamm_pid_alive "$_lpid2"; then
          rm -rf "$LOCK_DIR"
        fi
        rmdir "$REAPER_DIR" 2>/dev/null || true
      fi
    fi
    _tries=$((_tries + 1))
    if [ "$_tries" -gt 600 ]; then
      echo "ERROR: another compile has held the ledger lock for over 60s ($LOCK_DIR)." >&2
      echo "       If no zamm process is running, remove that directory (and any" >&2
      echo "       leftover $REAPER_DIR) and retry. Previous digest left untouched." >&2
      return 1
    fi
    sleep 0.1
  done
  echo "$$" > "$LOCK_DIR/pid"
  return 0
}

# Release ONLY while the pid file still names this process: should the lock
# ever be lost to another owner, releasing must not destroy the new owner's
# mutual exclusion. Always returns 0 (safe in traps under set -e).
zamm_lock_release() {
  if [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$LOCK_DIR"
  fi
  return 0
}
