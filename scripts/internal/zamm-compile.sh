#!/bin/sh
# ZAMM compile — builds the gitignored memory digest from the append-only
# knowledge ledger. Deterministic, read-only over the ledger, safe to rerun.
# POSIX sh + POSIX awk only: runs on stock macOS, Linux, and git-bash.
#
# Usage: zamm-compile.sh [--project-root <path>] [--tree knowledge|backlog|journal] [--check]
#   --tree        which record tree to compile (default: knowledge). The
#                 backlog tree compiles into the pulled lens
#                 .compiled/backlog.md instead of the session digest, with
#                 backlog policy (uncapped headline listing, no guardrails,
#                 plan-less votes, marked lane) — see the lens switches below.
#                 The journal tree compiles into the timeline lens
#                 .compiled/journal.md with journal policy (three record
#                 classes: entries, elevations, watermarks; no votes, no
#                 guardrails, no marked lane; journal-only keys).
#   --export      journal only: print the versioned TSV export seam
#                 (# zamm-journal-export v1, a column-name row, one row per
#                 unretired record, newest first). Read-only.
#   --check       validate ledger records (naming, schema, references) and exit
#                 non-zero on violations; writes no digest.
#   --list-live   print "id<TAB>primary-scope<TAB>all-tags<TAB>headline" for
#                 every live memory record, dormant ones included. all-tags is
#                 the comma-joined scope list (primary + secondaries).
#                 Read-only.
#   --list-inert  print the path of every record in a supersede component with
#                 no live memory record and no live votes record. Read-only;
#                 these are the records memory archive may move.

set -eu
LC_ALL=C
export LC_ALL

PROJECT_ROOT="$PWD"
CHECK=0
LIST_INERT=0
LIST_LIVE=0
LIST_VOTES=0
LIST_GRAPH=0
EXPORT=0
CANDIDATE=""
TREE="knowledge"
while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      if [ $# -lt 2 ] || [ ! -d "$2" ]; then
        echo "ERROR: --project-root requires an existing path" >&2
        exit 1
      fi
      PROJECT_ROOT=$(cd "$2" && pwd)
      shift 2
      ;;
    --tree)
      case "${2-}" in
        knowledge|backlog|journal) TREE="$2" ;;
        *)
          echo "ERROR: --tree must be knowledge, backlog or journal" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --check)
      CHECK=1
      shift
      ;;
    --with-candidate)
      if [ $# -lt 2 ] || [ ! -f "$2" ]; then
        echo "ERROR: --with-candidate requires an existing draft file" >&2
        exit 1
      fi
      CANDIDATE="$2"
      shift 2
      ;;
    --list-inert)
      LIST_INERT=1
      shift
      ;;
    --list-live)
      LIST_LIVE=1
      shift
      ;;
    --list-graph)
      LIST_GRAPH=1
      shift
      ;;
    --list-votes)
      LIST_VOTES=1
      shift
      ;;
    --export)
      EXPORT=1
      shift
      ;;
    -h|--help)
      echo "Usage: zamm-compile.sh [--project-root <path>] [--tree knowledge|backlog|journal] [--check [--with-candidate <draft>]] [--list-live] [--list-inert] [--list-votes] [--list-graph] [--export]"
      echo "  --with-candidate validates the ledger AS IF the named .md.draft were"
      echo "  published, without renaming anything into the live namespace."
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# One compiler, two trees: the knowledge tree renders the pushed session
# digest, the backlog tree renders the pulled lens. Everything below the
# rendering policy — enumeration, the G1-G5 discipline, parsing, validation,
# the supersede graph, votes, decay — is deliberately shared; the tree only
# chooses roots, output names, and the lens policy switches inside the awk.
KNOWLEDGE_DIR="$PROJECT_ROOT/zamm-memory/$TREE"
OUT_DIR="$PROJECT_ROOT/zamm-memory/.compiled"
if [ "$TREE" = "backlog" ]; then
  OUT_FILE="$OUT_DIR/backlog.md"
elif [ "$TREE" = "journal" ]; then
  OUT_FILE="$OUT_DIR/journal.md"
else
  OUT_FILE="$OUT_DIR/memory.md"
fi
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# ZAMM_PLAN_MANIFEST overrides the plan-manifest path (test-only DI seam,
# like ZAMM_TODAY).
PLAN_MANIFEST="${ZAMM_PLAN_MANIFEST:-$SCRIPT_DIR/zamm-plan-manifest.sh}"
# ZAMM_TODAY pins the clock (YYYY-MM-DD). Test-only: scoring decays over
# dates, so golden digests need a fixed today. Unset in normal use.
TODAY=${ZAMM_TODAY:-$(date +%Y-%m-%d)}

# Defense in depth: this script is directly invocable, so it re-proves the
# canonical roots are real directories inside the project (the dispatcher
# already did for its own callers). A symlinked knowledge/ otherwise reads as
# "the ledger is empty" and a symlinked .compiled/ redirects the digest write.
. "$SCRIPT_DIR/zamm-paths.sh"
zamm_verify_roots "$PROJECT_ROOT" || exit 4

if [ ! -d "$KNOWLEDGE_DIR" ]; then
  if [ "$TREE" = "backlog" ]; then
    echo "ERROR: missing $KNOWLEDGE_DIR (backlog add creates it, or re-run zamm-scaffold.sh)" >&2
  elif [ "$TREE" = "journal" ]; then
    echo "ERROR: missing $KNOWLEDGE_DIR (journal add creates it, or re-run zamm-scaffold.sh)" >&2
  else
    echo "ERROR: missing $KNOWLEDGE_DIR (run zamm-scaffold.sh first)" >&2
  fi
  exit 1
fi

if [ -n "$CANDIDATE" ] && [ "$CHECK" -ne 1 ]; then
  echo "ERROR: --with-candidate is only meaningful with --check" >&2
  exit 1
fi
if [ "$EXPORT" -eq 1 ] && [ "$TREE" != "journal" ]; then
  echo "ERROR: --export is a journal surface (pass --tree journal)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Candidate overlay: the draft is validated under its FINAL id by staging a
# private copy named <id>.md and enumerating that copy with the manifest. The
# live namespace never contains the candidate, so no concurrent reader can
# observe an unvalidated record, and no rollback of a rejected candidate is
# ever needed (there is nothing to roll back).
OVERLAY_DIR=""
OVERLAY_COPY=""
if [ -n "$CANDIDATE" ]; then
  cb=$(basename "$CANDIDATE")
  case "$cb" in
    *.md.draft) cid="${cb%.md.draft}" ;;
    # A record being written by zamm-new-memory.sh lives at
    # .<id>.md.pending.XXXXXX until it validates. That name matches neither
    # *.md (ledger enumeration) nor *.md.draft, so an in-flight record is
    # invisible to every other reader.
    .*.md.pending.*) cid="${cb%.md.pending.*}"; cid="${cid#.}" ;;
    *)
      echo "ERROR: --with-candidate expects a <id>.md.draft or .<id>.md.pending.* file (got: $cb)" >&2
      exit 1
      ;;
  esac
  OVERLAY_DIR=$(mktemp -d "$OUT_DIR/.overlay.XXXXXX") || {
    echo "ERROR: could not create the candidate overlay directory" >&2
    exit 1
  }
  OVERLAY_COPY="$OVERLAY_DIR/$cid.md"
  cp "$CANDIDATE" "$OVERLAY_COPY" || {
    echo "ERROR: could not stage the candidate for validation" >&2
    rm -rf "$OVERLAY_DIR"
    exit 1
  }
fi

# Per-process temp files: concurrent compiles must never share a path, or one
# process renames another's half-written file (digest truncated to a stub).
# The whole digest is built privately, then published with a single mv.
if command -v mktemp >/dev/null 2>&1; then
  TMP_FILE=$(mktemp "$OUT_DIR/memory.md.XXXXXX")
else
  TMP_FILE="$OUT_DIR/memory.md.tmp.$$"
  : > "$TMP_FILE"
fi
PLANS_TMP="$TMP_FILE.plans"
MF_FILES="$TMP_FILE.mf"
MF_LINKS="$TMP_FILE.ml"
MF_ARCH="$TMP_FILE.ma"
MANIFEST="$TMP_FILE.manifest"
# Machine-readable compilation state, published beside memory.md. status and
# `memory list` read THIS rather than reverse-parsing the rendered Markdown —
# grepping the digest counted a contested guardrail twice (once in the Digest,
# once under reconciliation) and mistook a record id embedded in a plan title
# for a selected record.
if [ "$TREE" = "backlog" ]; then
  STATE_FILE="$OUT_DIR/backlog-state.tsv"
elif [ "$TREE" = "journal" ]; then
  STATE_FILE="$OUT_DIR/journal-state.tsv"
else
  STATE_FILE="$OUT_DIR/state.tsv"
fi
STATE_TMP="$TMP_FILE.state"
# Cleanup releases the lock ONLY while its pid file still names this process:
# should the lock ever be lost to another owner, exiting must not destroy the
# new owner's mutual exclusion.
# set +e first: a failing rm (an unwritable directory, say) must never abort
# the trap before the lock is released — a leaked lock stalls every later
# compile and publish for a 60s timeout apiece.
trap 'set +e; rm -f "$TMP_FILE" "$PLANS_TMP" "$MF_FILES" "$MF_LINKS" "$MF_ARCH" "$MANIFEST" "$STATE_TMP" "$TMP_FILE.pmf"; [ -n "$OVERLAY_DIR" ] && rm -rf "$OVERLAY_DIR"; :' EXIT HUP INT TERM

# No lock. The digest is derived, gitignored and regenerable, so it is never
# protected — only recomputed (references/invariants.md, G2). Each compile
# enumerates the ledger into a private manifest and renames its private result
# into place; the rename is atomic, so a reader sees one coherent digest or
# the other, never a torn one. Two concurrent compiles both publish a truthful
# reading of some real ledger state and the last one wins, which may leave the
# digest one record behind until the next compile. That is ordinary staleness
# under eventual consistency, not damage: `memory digest` fixes it.

# Enumerate the ledger into a manifest, checking every step. A find that cannot
# descend a directory (permissions, a vanished path, an I/O fault) exits
# non-zero; piping it straight into `sort` masks that, because a pipeline
# reports the LAST command's status and POSIX sh has no pipefail — so a partial
# read would publish as if the unread records did not exist, turning "I could
# not read the ledger" into "these records are gone". Each stage writes a file
# whose exit status is checked; any failure leaves the previous digest
# untouched and exits 4 (unreadable, not empty — distinct from the exit-3
# "readable but nothing survived" case).
ARCHIVE_KNOWLEDGE="$PROJECT_ROOT/zamm-memory/archive/$TREE"
enum_ok=1
find "$KNOWLEDGE_DIR" -type f -name '*.md' > "$MF_FILES" || enum_ok=0
# Symlinks are invisible to `-type f`, so a symlink under either tree would
# be silently skipped (unscanned, uncounted). Register them ALL explicitly —
# files and directories, no name filter — so the compiler REJECTS them: the
# ledger holds real files only, no symlinks (they invite loops and path
# escapes and hide records from --check).
find "$KNOWLEDGE_DIR" -type l > "$MF_LINKS" || enum_ok=0
if [ -d "$ARCHIVE_KNOWLEDGE" ]; then
  find "$ARCHIVE_KNOWLEDGE" -type l >> "$MF_LINKS" || enum_ok=0
fi
# shun.md was the pre-erasure-record redaction list. Silently ignoring one
# left behind would resurrect exactly the content it was written to suppress,
# so its presence — as a file, a directory, a symlink, anything — refuses the
# compile until it is migrated. Testing the PATH (not a find over the tree)
# is what makes every file type equal here: the old parser only ever saw
# regular files, so a directory named shun.md silently emptied the set.
#
# This runs BEFORE the general symlink refusal below: a shun.md symlink is a
# symlink, but the migration instructions are the more useful diagnostic.
if [ -e "$KNOWLEDGE_DIR/shun.md" ] || [ -L "$KNOWLEDGE_DIR/shun.md" ]; then
  echo "ERROR: zamm-memory/$TREE/shun.md exists; this toolchain redacts through erasure RECORDS." >&2
  echo "       Refusing to compile: ignoring it would resurrect the content it suppresses." >&2
  echo "       Migrate: for each id listed there, create a record with" >&2
  echo "         type: erasure, erases: <id>, and the reason in the body" >&2
  echo "       (zamm-run.sh memory create --type erasure --erases <id> <slug>), then delete shun.md." >&2
  echo "       See references/migrations/ for the full procedure." >&2
  exit 4
fi
# No symlink may sit anywhere under either knowledge tree: one behind a
# directory position hides every record under it from the enumeration above
# (find never follows it), and one at a record position points at content a
# clone will not have. Fatal, like an unreadable tree: previous digest left
# untouched.
zamm_verify_no_symlinks "$PROJECT_ROOT" || exit 4

# Archived ids, filename only. A record moved out by `memory archive` must still
# resolve as a known-inert reference target rather than reading as a dangling
# supersedes:, so its NAME is registered without parsing content.
if [ -d "$ARCHIVE_KNOWLEDGE" ]; then
  find "$ARCHIVE_KNOWLEDGE" -type f -name '*.md' > "$MF_ARCH" || enum_ok=0
else
  : > "$MF_ARCH"
fi
if ! {
  cat "$MF_FILES"
  # the staged candidate joins the enumeration under its final id, as if it
  # were already published (see the overlay block above)
  if [ -n "$OVERLAY_COPY" ]; then printf '%s\n' "$OVERLAY_COPY"; fi
  sed 's/^/SYMLINK\t/' "$MF_LINKS"
  sed 's/^/ARCHIVED\t/' "$MF_ARCH"
} | sort > "$MANIFEST"; then
  enum_ok=0
fi
if [ "$enum_ok" -ne 1 ]; then
  echo "ERROR: could not enumerate the ledger (a directory or file could not be read)." >&2
  echo "       The ledger is unreadable, not empty; previous digest left untouched." >&2
  exit 4
fi

set +e
awk \
  -v today="$TODAY" -v check="$CHECK" -v listinert="$LIST_INERT" -v listlive="$LIST_LIVE" -v listvotes="$LIST_VOTES" -v listgraph="$LIST_GRAPH" -v export="$EXPORT" -v root="$PROJECT_ROOT/" -v statefile="$STATE_TMP" -v lens="$TREE" '
BEGIN {
  DIGEST_MAX = 75       # full digest blocks (actionable: headline + elaboration)
  HEADLINE_MAX = 150    # headline-only reminders (topic exists; open if relevant)
                        # ~same space as 100 full entries, ~2.25x coverage
  GROUP_PENALTY = 0.25  # subtracted from log(score) per seat already taken
                        # from the same area: diversity pressure, not a quota
  TAG_COST = 0.25       # subtracted from log(score) per scope tag beyond the
                        # first: extra tags buy selection doors, not free rank
  VOTE_WEIGHT = 0.5     # score magnitude of one vote (before recency decay);
                        # votes demote or promote, they must not single-handedly
                        # delist a fresh useful record (base weight 1.0)
  FLOOR = 0.05          # scores below this are dormant: counted, not listed.
                        # Live guardrails never go dormant: `!` is a safety
                        # contract, retired only by supersession or tombstone
  OTHER_MAX = 5         # --check fails when live other records exceed this
  GUARDRAIL_MAX = 15    # guardrails enter the Digest layer before DIGEST_MAX
                        # and never decay, so they are the one unbounded part
                        # of an otherwise bounded surface: warn, do not fail
  CHAINDEPTH_MAX = 2    # supersede hops that earn durability credit. Ten
                        # rewrites of a churning statement must not outrank
                        # knowledge that was simply right the first time
  SEED_MAX = 10000      # ceiling on a migration vote seed: enough to carry
                        # real pre-migration popularity, low enough that a
                        # forged seed cannot pin a record atop the ranking
  HOT = 0.5             # backlog lens only: score at or above this reads as a
                        # hot idea (a fresh useful-rated idea within roughly
                        # one half-life, or anything recently voted up)
  MARKED_MAX = 7        # backlog lens only: soft cap on the marked lane. A
                        # marked idea is pushed into every session digest and
                        # never decays, so inflation must nag — warn, do not
                        # fail, the guardrail-cap rationale. Deliberately
                        # tighter than GUARDRAIL_MAX.
  JOURNAL_REVIEW_COUNT = 25   # journal only: triage is due at this many
                              # undigested entries ...
  JOURNAL_REVIEW_AGE = 60     # ... or when the oldest undigested entry is
                              # older than this many days
  JOURNAL_LAPSE = 3           # journal only: an elevation practice lapses
                              # when the due period is more than this many
                              # grains (of the kind: months, years) beyond
                              # the newest elevated one - the line goes
                              # silent instead of nagging a dropped habit

  VALID_AREAS = " domain contracts conventions internals quality tooling ops meta "
  # every key the compiler acts on; anything else is a typo until proven
  # otherwise (x- prefix reserved for deliberate extensions). `marked` is
  # meaningful only in the backlog tree, but it belongs in this list for BOTH
  # trees: its knowledge-side rejection below is a policy error naming the
  # remedy, not an unknown-key typo warning.
  KNOWN_KEYS = " type scope supersedes erases created schema plan up down importance durability seed-up seed-dn migrated-from marked cue salience time agent user reviewed-through pass digest covers covered "
  # the journal-only keys (plus the axis- prefix family): refused in every
  # other tree as a policy error, validated per class inside the journal
  JOURNAL_KEYS = " cue salience time agent user reviewed-through pass digest covers covered "
  nelev = 0; nwm = 0; nwmpass = 0; nkinds = 0; nundig = 0; ndue = 0; jnm = 0; jng = 0
  nrec = 0; nerr = 0; nsort = 0; nother = 0
  nfiles = 0; nbad = 0; ndup = 0; nwarn = 0
}

# ---- input: one record file path per line ----
{
  if (index($0, "SYMLINK\t") == 1) {
    sp = substr($0, 9)
    ns = split(sp, spp, "/")
    # Fatal, not a skip: a symlinked record is a record we did NOT read, and
    # nothing distinguishes a symlinked erasure record from any other. Once
    # erasure lives in records, skipping one can silently un-redact, so the
    # ledger is treated as unreadable rather than smaller — the same rule as
    # an unreadable record file or archived header.
    err(relpath(sp) ": symlinked record files are not allowed in the ledger (no symlinks); the ledger is unreadable, not empty")
    fatalrc = 4
    exit 4
  }
  if (index($0, "ARCHIVED\t") == 1) {
    apath = substr($0, 10)
    n = split(apath, pp, "/")
    aid = pp[n]; sub(/\.md$/, "", aid)
    archived[aid] = 1
    read_archived_header(apath, aid)
    next
  }
  path = $0
  n = split(path, pp, "/")
  base = pp[n]
  read_record(path, base)
}

# Frontmatter-only read of an archived record: its id, type and supersedes
# edges keep their place in the graph as an INERT node (grouping, conflict
# detection, lineage) while its content, votes and durability stay out of the
# ranking and the digest. An UNREADABLE archived file is fatal, like an
# unreadable archived record: its type and supersedes edges are validation
# authority (an unread type silently waives the type-transition checks, and
# lost edges split reconciliation groups), so a failing read WOULD widen
# validity if compilation continued.
function read_archived_header(path, aid,   line, state, firstline, pos, key, val) {
  if ((getline line < path) < 0) {
    close(path)
    err(relpath(path) ": cannot read archived record header (permission denied or I/O error); the ledger is unreadable, not empty")
    fatalrc = 4
    exit 4
  }
  close(path)
  state = 0; firstline = 1
  while ((getline line < path) > 0) {
    sub(/\r$/, "", line)
    if (firstline) {
      firstline = 0
      if (line == "---") { state = 1; continue }
      break
    }
    if (state == 1) {
      if (line == "---") break
      pos = index(line, ":")
      if (pos > 1) {
        key = trim(substr(line, 1, pos - 1))
        val = trim(substr(line, pos + 1))
        if      (key == "type")       atype[aid] = val
        else if (key == "supersedes") asupinert[aid] = val
        # erases: travels with the record, so a redaction survives the move
        else if (key == "erases")     aerases[aid] = val
      }
    }
  }
  close(path)
}

function read_record(path, base,   id, line, state, firstline, fmclosed, pos, key, val, lc, q, n2, ydir, t, a, hasother, fdate, frest, fsuf, fslug, axn) {
  id = base
  sub(/\.md$/, "", id)
  nfiles++
  delete seenkey

  # lint: exact filename contract YYYY-MM-DD-<slug>-<suffix>.md
  if (base !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z0-9][a-z0-9-]*\.md$/)
    rerr(id, path ": filename violates YYYY-MM-DD-slug-suffix.md lowercase [a-z0-9-] rule")
  else if (base !~ /-[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]\.md$/)
    rerr(id, path ": filename missing the 5-char uniqueness suffix before .md")
  else {
    fdate = substr(id, 1, 10)
    frest = substr(id, 12)                    # <slug>-<suffix>
    fsuf = substr(frest, length(frest) - 4)   # last 5 chars
    fslug = substr(frest, 1, length(frest) - 6)
    if (!validdate(fdate))
      rerr(id, path ": filename date is not a real calendar date: " fdate)
    # the uniqueness alphabet drops 0 1 i l o u (visually ambiguous), so a
    # suffix outside it was not produced by zamm-new-memory.sh
    if (fsuf ~ /[01ilou]/)
      rerr(id, path ": suffix \"" fsuf "\" uses characters outside the uniqueness alphabet 23456789abcdefghjkmnpqrstvwxyz")
    if (fslug == "")
      rerr(id, path ": filename has no slug between the date and the suffix")
    else if (length(fslug) > 40)
      rerr(id, path ": slug is " length(fslug) " chars (max 40): " fslug)
    else if (fslug ~ /^-/ || fslug ~ /-$/ || fslug ~ /--/)
      rerr(id, path ": slug \"" fslug "\" has a leading, trailing or doubled hyphen")
  }
  # Case-fold collision means two DIFFERENT names that a case-insensitive
  # filesystem cannot keep apart. Two identical basenames in different year
  # directories are not that — they are a duplicate id, reported just below,
  # and calling them a case-fold collision only adds a misleading second
  # diagnostic to the one the user has to act on.
  lc = tolower(base)
  if ((lc in casemap) && casemap[lc] != path && casebase[lc] != base)
    rerr(id, path ": case-fold collision with " casemap[lc])
  casemap[lc] = path
  casebase[lc] = base
  if (id in filepath) {
    err(path ": duplicate record id " id)
    dupfile[++ndup] = path
    return
  }

  filepath[id] = path
  order[++nrec] = id
  rtype[id] = "memory"

  # An unreadable file is FATAL, not a quarantine. A quarantine assumes we
  # know what the record was: we do not. An unreadable ERASURE record would
  # silently stop redacting, which is precisely the resurrection the old
  # unreadable-shun.md guard existed to prevent — and nothing can tell an
  # unreadable erasure record from any other unreadable file. Same rule as
  # the archived headers and the ledger enumeration: a failing READ must
  # never widen validity. (The while(>0) form below cannot tell an open
  # error (getline -1) from a clean empty file (0), so probe once up front,
  # then reopen for the real read.)
  if ((getline line < path) < 0) {
    close(path)
    err(relpath(path) ": cannot read record file (permission denied or I/O error); the ledger is unreadable, not empty")
    fatalrc = 4
    exit 4
  }
  close(path)

  state = 0; firstline = 1; fmclosed = 0
  while ((getline line < path) > 0) {
    sub(/\r$/, "", line)
    if (firstline) {
      firstline = 0
      if (line == "---") { state = 1; continue }
      state = 2  # no frontmatter: whole file is body (weak schema)
    }
    if (state == 1) {
      if (line == "---") { state = 2; fmclosed = 1; continue }
      pos = index(line, ":")
      if (pos > 1) {
        key = trim(substr(line, 1, pos - 1))
        val = trim(substr(line, pos + 1))
        # last-wins on a repeated key silently changes what a record means
        # (two importance: lines = two different rankings, one invisible)
        if (key in seenkey) rerr(id, path ": duplicate frontmatter key \"" key "\"")
        seenkey[key] = 1
        if (index(KNOWN_KEYS, " " key " ") == 0 && key !~ /^x-/ && key !~ /^axis-/)
          warn(path ": unknown frontmatter key \"" key "\" (ignored; use x- prefix for extensions)")
        # jkeys doubles as the set membership test and the first-seen key
        # named in the misfile diagnostic
        if (index(JOURNAL_KEYS, " " key " ") > 0 || key ~ /^axis-/) {
          if (!(id in jkeys)) jkeys[id] = key
        }
        if      (key == "type")       rtype[id] = val
        else if (key == "scope")      rscope[id] = val
        else if (key == "supersedes") rsup[id] = val
        else if (key == "erases")     rerases[id] = val
        else if (key == "created")    rcreated[id] = val
        else if (key == "schema")     rschema[id] = val
        else if (key == "plan")       rplan[id] = val
        else if (key == "up")         rup[id] = val
        else if (key == "down")       rdown[id] = val
        else if (key == "importance") rimp[id] = val
        else if (key == "durability") rdur[id] = val
        else if (key == "seed-up")    rseedup[id] = val
        else if (key == "seed-dn")    rseeddn[id] = val
        else if (key == "migrated-from") rmigfrom[id] = val
        else if (key == "marked")     { rmarked[id] = val; hasmark[id] = 1 }
        else if (key == "cue")        rcue[id] = val
        else if (key == "salience")   rsal[id] = val
        else if (key == "time")       rtime[id] = val
        else if (key == "agent")      ragent[id] = val
        else if (key == "user")       ruser[id] = val
        else if (key == "reviewed-through") { rrt[id] = val; haswm[id] = 1 }
        else if (key == "pass")       rpass[id] = val
        else if (key == "covered")    { rcovd[id] = val; hascovd[id] = 1 }
        else if (key == "digest")     rdig[id] = val
        else if (key == "covers")     rcov[id] = val
        else if (key ~ /^axis-/) {
          axn = substr(key, 6)
          naxis[id]++
          axlist[id, naxis[id]] = axn
          raxis[id, axn] = val
        }
        # unknown keys are ignored on purpose
      }
      continue
    }
    if (state == 2) rbody[id] = rbody[id] line "\n"
  }
  close(path)

  # ---- record contract; any violation quarantines the record (see rerr) ----
  if (fmclosed == 0) {
    if (state == 1) rerr(id, path ": frontmatter not closed (missing second ---)")
    else rerr(id, path ": missing frontmatter block")
  }
  if (rcreated[id] == "")
    rerr(id, path ": missing created:")
  else if (!validdate(rcreated[id]))
    rerr(id, path ": created: is not a real YYYY-MM-DD date: " rcreated[id])
  else if (id ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/ && rcreated[id] != substr(id, 1, 10))
    rerr(id, path ": created: " rcreated[id] " does not match filename date " substr(id, 1, 10))
  n2 = split(path, q, "/")
  if (n2 >= 2) {
    ydir = q[n2 - 1]
    if (ydir ~ /^[0-9][0-9][0-9][0-9]$/ && ydir != substr(id, 1, 4))
      rerr(id, path ": year directory " ydir " does not match filename year " substr(id, 1, 4))
  }
  if (rschema[id] == "")
    rerr(id, path ": missing schema:")
  else if (rschema[id] != "3")
    rerr(id, path ": unsupported schema: " rschema[id])
  # type: digest is the journal elevation record: a stored digest of a
  # period. It is legal ONLY in the journal tree - older toolchains never
  # enumerate that tree, so the new-type quarantine hazard (which is about
  # trees they SCAN) does not arise there; every other tree refuses it.
  if (rtype[id] == "digest" && lens != "journal")
    rerr(id, path ": type: digest is the journal elevation record type; the " lens " tree has no elevations")
  else if (rtype[id] != "memory" && rtype[id] != "tombstone" && rtype[id] != "votes" &&
      rtype[id] != "erasure" && rtype[id] != "digest")
    rerr(id, path ": unknown type \"" rtype[id] "\"")
  if (rtype[id] == "memory" || rtype[id] == "digest") {
    parsetags(id)
    if (rscope[id] == "") rerr(id, path ": memory record missing scope:")
    else if (tagn[id] == 0)
      rerr(id, path ": scope: \"" rscope[id] "\" yields no tags")
    else {
      if (emptytag[id])
        rerr(id, path ": scope: \"" rscope[id] "\" has an empty tag component")
      if (tagn[id] > 3)
        rerr(id, path ": scope has " tagn[id] " tags (max 3)")
      hasother = 0
      for (t = 1; t <= tagn[id]; t++) {
        a = areaof(tagsc[id, t])
        if (a == "other") hasother = 1
        else if (index(VALID_AREAS, " " a " ") == 0)
          rerr(id, path ": unknown scope area \"" a "\" (fixed set: domain contracts conventions internals quality tooling ops meta; or other alone)")
        if (t > 1 && index(tagsc[id, t], "/") > 0)
          rerr(id, path ": secondary scope tag \"" tagsc[id, t] "\" carries a subpath (bare areas only)")
        if ((a in dupechk) && dupechk[a] == id)
          rerr(id, path ": duplicate scope area \"" a "\"")
        dupechk[a] = id
      }
      if (hasother && (tagn[id] > 1 || index(pscope[id], "/") > 0))
        rerr(id, path ": other must be the sole scope tag, without subpath")
    }
    if (rimp[id] == "") rerr(id, path ": memory record missing importance: (the ranking depends on it)")
    if (rdur[id] == "") rerr(id, path ": memory record missing durability: (the ranking depends on it)")
    # Backlog policy: no guardrails. A guardrail rating has exactly one
    # power — unbudgeted admission into the pushed digest — and the backlog
    # is a pulled lens, so the rating would be a lie that old habits might
    # later honor. The marked lane is the sanctioned way an idea reaches the
    # session digest.
    if (lens == "backlog" && rimp[id] == "guardrail")
      rerr(id, path ": guardrail importance is not allowed in the backlog (mark the idea instead: backlog mark)")
    # Journal policy: no guardrails either - there is no pushed surface to
    # guard; an episode that turned out to be a standing rule is distilled
    # into a knowledge record at triage.
    if (lens == "journal" && rimp[id] == "guardrail")
      rerr(id, path ": guardrail importance is not allowed in the journal (distill the rule into a knowledge record instead)")
    if (rbody[id] !~ /[^ \t\n]/) rerr(id, path ": memory record has empty body")
    else if (headline(id) == "")
      rerr(id, path ": missing headline (body starts with a heading)")
    else {
      # Headline length (~300 chars) is a soft authoring guide, not a hard
      # --check fail — prefer a complete trigger over mid-thought truncation.
      # Digest-block size stays hard-capped (attention budget).
      if (blockl[id] > 12)
        rerr(id, path ": digest block exceeds 12 lines; move detail under ## Background")
      if (blockc[id] > 1200)
        rerr(id, path ": digest block exceeds 1200 chars; move detail under ## Background")
    }
  }
  if (rtype[id] == "tombstone") {
    if (rsup[id] == "") rerr(id, path ": tombstone without supersedes target")
    # a tombstone retires knowledge; without a reason nobody can tell later
    # whether it was wrong, obsolete, or removed by mistake
    if (rbody[id] !~ /[^ \t\n]/) rerr(id, path ": tombstone has no body (the retirement reason is required)")
  }
  if (rtype[id] == "erasure") {
    # An erasure record is the ledger recording its own redaction: it names
    # the ids whose content must never be compiled again, and it carries the
    # reason. Unlike the old shun.md list it is an ordinary record, so it
    # rides the same enumeration, symlink refusal and unreadable handling as
    # everything else — and it is auditable (who erased what, when, why).
    if (rerases[id] == "") rerr(id, path ": erasure record missing erases: (the ids it redacts)")
    if (rbody[id] !~ /[^ \t\n]/) rerr(id, path ": erasure record has no body (the erasure reason is required)")
    # it acts through erases:, never through the supersede graph
    if (rsup[id] != "") rerr(id, path ": erasure record must not carry supersedes: (use erases:)")
    en = split(rerases[id], eg, ",")
    delete seenerase
    for (e = 1; e <= en; e++) {
      etgt = trim(eg[e])
      if (etgt == "") continue
      if (etgt == id) rerr(id, path ": erasure record erases itself")
      else if (etgt in seenerase) rerr(id, path ": duplicate erases target " etgt)
      seenerase[etgt] = 1
    }
  }
  if (rtype[id] == "votes") {
    # Journal policy: no votes at all. A timeline has no hot-to-cold order
    # to vote on; digestion is the only consumer of an episode.
    if (lens == "journal") rerr(id, path ": votes records are not allowed in the journal (a timeline has no ranking to vote on)")
    # plan: is a per-tree policy. Knowledge votes come from plan close-outs,
    # so a plan-less votes record there is an orphan minting rank for nothing.
    # Backlog votes are TRIAGE — they rate ideas, no plan exists — so the
    # same key is refused there; the relaxation must not leak either way.
    if (lens == "backlog") {
      if (rplan[id] != "") rerr(id, path ": backlog votes are triage votes and carry no plan: (remove the key)")
    }
    else if (rplan[id] == "") rerr(id, path ": votes record missing plan:")
    # plan: is consumed downstream as a plan DIRECTORY slug (the cross-check
    # resolves it under active/plans and archive/plans), so it must be a bare
    # slug — never a path. "plan: .." or "plan: ../../knowledge" would resolve
    # to a real directory and launder an orphan votes record past the check.
    else if (rplan[id] !~ /^[a-z0-9][a-z0-9-]*$/)
      rerr(id, path ": plan: must be a plan directory slug [a-z0-9-] (got \"" rplan[id] "\")")
    if (rup[id] == "" && rdown[id] == "") rerr(id, path ": votes record with neither up: nor down:")
    if (rbody[id] ~ /[^ \t\n]/) rerr(id, path ": votes record must have an empty body (the up:/down: lists are the payload)")
    # A target repeated within up: (or down:), or listed in BOTH up: and down:,
    # forges vote weight (three "up: X" once counted as +3). Each list is a
    # SET of targets; a repeat or an up/down contradiction quarantines the
    # whole record so no forged weight reaches the ranking.
    check_vote_lists(id, path)
  }
  if (rimp[id] != "" && rimp[id] !~ /^(guardrail|useful|minor)$/)
    rerr(id, path ": unknown importance \"" rimp[id] "\" (guardrail|useful|minor)")
  if (rdur[id] != "" && rdur[id] !~ /^(days|weeks|months|years|permanent)$/)
    rerr(id, path ": unknown durability \"" rdur[id] "\" (days|weeks|months|years|permanent)")
  # marked: is the backlog selection lane — a date (the day first marked) or
  # the explicit deselection `no`. It has no meaning on knowledge records or
  # on non-memory types, and an unparseable value must not silently read as
  # unmarked (that would drop an idea out of the pushed lane, the exact
  # silent-loss the lane exists to prevent).
  if (id in hasmark) {
    if (lens != "backlog")
      rerr(id, path ": marked: is a backlog key; a " lens " record cannot sit in the marked lane")
    else if (rtype[id] != "memory")
      rerr(id, path ": marked: is only meaningful on a memory record (this is a " rtype[id] ")")
    else if (rmarked[id] != "no" && !validdate(rmarked[id]))
      rerr(id, path ": marked: must be a real YYYY-MM-DD date or \"no\" (got \"" rmarked[id] "\")")
  }
  # Journal keys are refused outside the journal whatever the record type
  # (a journal-only key on a knowledge record is a misfile, not a typo).
  if ((id in jkeys) && lens != "journal")
    rerr(id, path ": " jkeys[id] ": is a journal key; the " lens " tree has no journal classes (write it with journal add)")
  # Inside the journal every record is validated as a class, whether or not
  # it carries a journal key: a bare type: digest carries none at all, and
  # gating on the keys let it pass the contract and reach the export as an
  # elevation with no kind and no period.
  if (lens == "journal") check_journal(id, path)
  # seed-up/seed-dn carry pre-migration vote counts and feed the ranking
  # directly; they are meaningful ONLY on a migration record. Requiring
  # migrated-from: closes a hand-authored forge (a record with seed-up: 50 but
  # no migration provenance would otherwise inflate its own rank and pass --check).
  if ((rseedup[id] != "" || rseeddn[id] != "") && rmigfrom[id] == "")
    rerr(id, path ": seed-up/seed-dn are migration seeds and require migrated-from:")
  # A seed feeds the ranking as a raw vote count, so an unbounded or negative
  # value forges rank: seed-up: 999999999 pins a record at the top forever, and
  # seed-dn is SUBTRACTED, so a negative seed-dn would ADD score. Constrain both
  # to plain non-negative integers within a sane ceiling.
  if (rseedup[id] != "" && !validseed(rseedup[id]))
    rerr(id, path ": seed-up must be a non-negative integer <= " SEED_MAX " (got \"" rseedup[id] "\")")
  if (rseeddn[id] != "" && !validseed(rseeddn[id]))
    rerr(id, path ": seed-dn must be a non-negative integer <= " SEED_MAX " (got \"" rseeddn[id] "\")")
  # migrated-from names the migration provenance; require an id/path-like token
  # (no spaces or control chars, non-empty) rather than accepting any free text.
  # Mixed case is allowed: it points at a FOREIGN system id (a v1/v2 card like
  # "B3"), which need not follow the v3 lowercase record-id convention.
  if (rmigfrom[id] != "" && rmigfrom[id] !~ /^[A-Za-z0-9][A-Za-z0-9._\/-]*$/)
    rerr(id, path ": migrated-from must be a provenance token [A-Za-z0-9._/-] (got \"" rmigfrom[id] "\")")

  if (rcreated[id] == "" && id ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/)
    rcreated[id] = substr(id, 1, 10)
}

# ---- helpers ----
function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }

# Machine-readable compilation state, written beside memory.md. Downstream
# commands (status, memory list) read THIS instead of grepping the rendered
# digest. select rows are the record ids the digest actually surfaced (Digest
# blocks + Headlines), i.e. what memory list should show by default. Guardrail
# and contested counts come from the graph, not from counting rendered lines.
function emit_state(   i, j, id, k, pm, cu, mk, mp, g, gp, n, nm2, fs) {
  if (statefile == "") return
  printf "files\t%d\n", nfiles > statefile
  printf "parsed\t%d\n", nrec - nbad > statefile
  printf "live\t%d\n", nlive > statefile
  printf "quarantined\t%d\n", nquar > statefile
  printf "dangling\t%d\n", ndangling > statefile
  printf "dupvotes\t%d\n", ndupvote > statefile
  printf "badvoterefs\t%d\n", nbadvoteref > statefile
  printf "badcover\t%d\n", nbadcover > statefile
  printf "guardrails\t%d\n", nguard > statefile
  printf "contested\t%d\n", ngroups > statefile
  printf "other\t%d\n", nother > statefile
  printf "dormant\t%d\n", ndorm > statefile
  printf "unlisted\t%d\n", nunlist > statefile
  if (lens == "backlog") {
    printf "hot\t%d\n", nhot > statefile
    printf "marked\t%d\n", nmarked > statefile
    # single authority for the cap: the digest compile prints its section
    # nag from this row instead of re-owning the MARKED_MAX constant
    if (nmarked > MARKED_MAX) printf "marked_over\t%d\n", nmarked > statefile
  }
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in printed) print "select\t" id > statefile
  }
  # Journal rows: coverage (the effective watermark per pass), the
  # effective elevations, what is due (consumed by the digest compile for
  # its one Journal: line, in FIXED order: triage first, then the built-in
  # kinds in ship order), and the instrument - per calendar month x cue
  # entry counts and per month x cue x axis nearest-rank quartiles, over
  # ENTRIES only (a digest of a month must not double-count its month) and
  # over created: dates, never liveness (decay must not rewrite what a
  # finished month says). Row kinds are tagged and additive; readers skip
  # unknown kinds.
  if (lens == "journal") {
    printf "entries\t%d\n", nlive > statefile
    printf "undigested\t%d\n", nundig > statefile
    printf "oldest_undigested\t%s\n", dv(oldest) > statefile
    printf "clearable\t%d\n", nclear > statefile
    printf "elevations\t%d\n", nelev > statefile
    printf "watermarks\t%d\n", nwm > statefile
    for (i = 1; i <= nwmpass; i++)
      printf "watermark\t%s\t%s\t%s\n", wmpass[i], wmmax[wmpass[i]], wmid[wmpass[i]] > statefile
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if ((id in elive) && effel[rdig[id] SUBSEP rcov[id]] == id)
        printf "elev\t%s\t%s\t%s\n", rdig[id], rcov[id], id > statefile
    }
    if (duetri) printf "due_triage\t%d\t%s\n", nundig, oldest > statefile
    for (i = 1; i <= ndue; i++) printf "due_elev\t%s\t%s\n", duekind[i], dueper[i] > statefile
    for (i = 1; i <= nek; i++) {
      if (ecount[eorder[i]] < 2) continue
      printf "elev_competing\t%s\t%s\t%d\t%s\n", ekind[eorder[i]], eper[eorder[i]], ecount[eorder[i]], effel[eorder[i]] > statefile
    }
    for (i = 1; i <= nek; i++) {
      if (!(eorder[i] in stale)) continue
      printf "elev_stale\t%s\t%s\t%d\t%s\n", ekind[eorder[i]], eper[eorder[i]], stale[eorder[i]], effel[eorder[i]] > statefile
      # the entries that elevation never saw, by id: the renderer must not
      # re-derive coverage from the record - two parsers disagreeing about
      # one frontmatter line is how an uncovered entry goes missing again
      for (j = 1; j <= uncn[eorder[i]]; j++)
        printf "elev_uncovered\t%s\t%s\t%s\n", ekind[eorder[i]], eper[eorder[i]], unc[eorder[i], j] > statefile
    }
    for (i = 1; i <= nsort; i++) {
      id = sorted[i]
      pm = substr(rcreated[id], 1, 7); cu = (rcue[id] == "") ? "-" : rcue[id]
      mk = pm SUBSEP cu
      if (!(mk in mcount)) morder[++jnm] = mk
      mcount[mk]++
      if (rsal[id] != "") jgadd(pm, cu, "salience", "unipolar", rsal[id] + 0)
      for (k = 1; k <= naxis[id]; k++) {
        nm2 = axlist[id, k]
        if ((id SUBSEP nm2) in axtype) jgadd(pm, cu, nm2, axtype[id, nm2], raxis[id, nm2] + 0)
      }
    }
    for (i = 1; i <= jnm; i++) {
      split(morder[i], mp, SUBSEP)
      printf "month\t%s\t%s\t%d\n", mp[1], mp[2], mcount[morder[i]] > statefile
    }
    for (i = 1; i <= jng; i++) {
      g = gorder[i]; n = gn[g]
      jsortvals(g, n)
      split(g, gp, SUBSEP)
      fs = (gp[4] == "bipolar") ? "%+d" : "%d"
      fs = "axis\t%s\t%s\t%s\t%s\t%d\t" fs "\t" fs "\t" fs "\n"
      printf(fs, gp[1], gp[2], gp[3], gp[4], n, gv[g, nrank(n, 0.25)], gv[g, nrank(n, 0.5)], gv[g, nrank(n, 0.75)]) > statefile
    }
  }
  # The marked rows feed the digest compile, which renders the ## Marked
  # backlog section from this sidecar. mark-date first so a plain sort
  # yields oldest-first; the headline is TAB-sanitized because record
  # content must never smuggle a column separator into a TSV surface (the
  # norm_list rule).
  if (lens == "backlog") {
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if (!(id in markedof)) continue
      mh = headline(id)
      gsub(/\t/, " ", mh)
      printf "mselect\t%s\t%s\t%s\n", markedof[id], id, mh > statefile
    }
  }
  close(statefile)
}

# The ## Degraded section: quarantined records, dangling supersedes targets,
# duplicate active votes records, invalid vote references. Rendered on the
# normal digest path AND on the zero-live path — a ledger holding only (say) a
# votes record with a ghost target must still read as degraded, not as a
# clean uninitialized ledger.
function emit_degraded(   i, id) {
  if (nquar == 0 && ndangling == 0 && ndupvote == 0 && nbadvoteref == 0 && nbadcover == 0) return
  print "## Degraded (ledger integrity problems - see below)"
  print ""
  if (nquar > 0) {
    print "Quarantined records - failed the record contract and were excluded from"
    print "liveness, supersession, votes and ranking. Fix them and recompile; run"
    print "--check for the full error list."
    print ""
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if (!(id in bad)) continue
      print "- " relpath(badmsg[id])
    }
    for (i = 1; i <= ndup; i++)
      print "- " relpath(dupfile[i]) ": duplicate record id"
    print ""
  }
  if (ndangling > 0) {
    print "Dangling references - these records are LIVE, but name a supersedes:"
    print "target that does not exist in the ledger, so that edge was dropped."
    print "A missing target is usually a typo or a not-yet-committed record."
    print ""
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if (!(id in hasdangling)) continue
      print "- " id ": supersedes target not found: " danglingtgt[id]
    }
    print ""
  }
  if (ndupvote > 0) {
    print "Duplicate vote records - more than one active votes record names the"
    print "same plan. Only the newest is counted; supersede the stale ones."
    print ""
    for (i = 1; i <= ndupvote; i++)
      print "- " dupvoteplan[i] ": " nplanvotes[dupvoteplan[i]] " active votes records (counted: " canonvote[dupvoteplan[i]] ")"
    print ""
  }
  if (nbadcover > 0) {
    print "Void coverage claims - a watermark or elevation names records it could"
    print "not have reviewed, so it covers NOTHING and its entries stay undigested."
    print ""
    for (i = 1; i <= nbadcover; i++)
      print "- " badcover[i]
    print ""
  }
  if (nbadvoteref > 0) {
    print "Invalid vote references - a votes record names a target that does not"
    print "exist or is not a memory record; that vote was dropped."
    print ""
    for (i = 1; i <= nbadvoteref; i++)
      print "- " badvoteref[i]
    print ""
  }
}

# a comma-separated id list, re-emitted with each element trimmed and empties
# dropped: "a,<TAB>b , ,c" -> "a,b,c". Used wherever a raw frontmatter list
# would leak interior whitespace into a machine-readable (TSV) surface.
function norm_list(s,   n, av, t, tgt, out) {
  n = split(s, av, ",")
  out = ""
  for (t = 1; t <= n; t++) {
    tgt = trim(av[t])
    if (tgt == "") continue
    # an interior tab cannot appear in a valid id, but a malformed element
    # (already degraded as a bad vote reference) must still not be able to
    # smuggle a column separator into the TSV
    gsub(/\t/, " ", tgt)
    out = out (out == "" ? "" : ",") tgt
  }
  return out
}

# a migration seed is a plain non-negative integer within a ceiling: no sign,
# no decimal, no exponent (all of which awk would coerce into a usable number)
function validseed(v) {
  if (v !~ /^[0-9]+$/) return 0
  return (v + 0 <= SEED_MAX)
}

# votes hygiene: up: and down: are each a SET of record ids. A target repeated
# within a list, or present in both lists, is a contradiction that inflates or
# cancels vote weight, so it quarantines the record. vu/vd are function-local
# (fresh per call) so one record cannot leak targets into the next.
function check_vote_lists(id, path,   m, av, t, tgt, vu, vd) {
  m = split(rup[id], av, ",")
  for (t = 1; t <= m; t++) {
    tgt = trim(av[t]); if (tgt == "") continue
    if (tgt in vu) rerr(id, path ": duplicate up: vote target " tgt)
    vu[tgt] = 1
  }
  m = split(rdown[id], av, ",")
  for (t = 1; t <= m; t++) {
    tgt = trim(av[t]); if (tgt == "") continue
    if (tgt in vd) rerr(id, path ": duplicate down: vote target " tgt)
    vd[tgt] = 1
    if (tgt in vu) rerr(id, path ": vote target " tgt " is in both up: and down:")
  }
}

# ---- journal class rules ----
# Three record classes share the journal tree: an ENTRY (type: memory), an
# ELEVATION (type: digest + digest:/covers:) and a WATERMARK (type: memory +
# reviewed-through: [+ pass:]). A record is exactly one class, and every
# journal key resolves by VALUE, never by graph, so validation is per
# record with no registry anywhere.
function jslug(v) { return (v ~ /^[a-z0-9][a-z0-9-]*$/) }
# the journal class of a record, for diagnostics
function jclass(x) {
  if (rtype[x] == "digest") return "an elevation"
  if (x in haswm) return "a watermark"
  return "an entry"
}
# a calendar period: YYYY or YYYY-MM with a real month
function jperiod(v,   m) {
  if (v ~ /^[0-9][0-9][0-9][0-9]$/) return 1
  if (v !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]$/) return 0
  m = substr(v, 6, 2) + 0
  return (m >= 1 && m <= 12)
}
# An axis value is self-describing by its spelling: a sign makes it
# bipolar (-5..+5, +0 included, -0 refused), no sign makes it unipolar
# (0..10). Two types, no registry, so validation stays per record.
function jaxtype(v) {
  if (v ~ /^[+-][0-5]$/) return (v == "-0") ? "" : "bipolar"
  if (v ~ /^([0-9]|10)$/) return "unipolar"
  return ""
}
function check_journal(id, path,   isel, iswm, k, nm2, v, ty, cn, ci, cvg, cvt, pstart) {
  isel = (rtype[id] == "digest")
  iswm = (id in haswm)
  if (rtype[id] != "memory" && rtype[id] != "digest") {
    # a tombstone or erasure may carry provenance (time/agent/user), nothing else
    if (rcue[id] != "" || rsal[id] != "" || naxis[id] > 0 || rdig[id] != "" || rcov[id] != "" || iswm || rpass[id] != "")
      rerr(id, path ": cue/salience/axis-*/digest/covers/reviewed-through/pass are only meaningful on memory or digest records (this is a " rtype[id] ")")
  }
  if (isel) {
    if (rdig[id] == "" || rcov[id] == "")
      rerr(id, path ": an elevation (type: digest) needs both digest: <kind> and covers: <YYYY[-MM]>")
    if (rcue[id] != "" || rsal[id] != "")
      rerr(id, path ": cue:/salience: are entry keys; an elevation carries digest: instead")
    if (iswm || rpass[id] != "")
      rerr(id, path ": reviewed-through:/pass: are watermark keys; a record is exactly one class")
  } else if (rdig[id] != "" || rcov[id] != "") {
    rerr(id, path ": digest:/covers: belong to type: digest (an elevation record)")
  }
  if (rdig[id] != "" && !jslug(rdig[id])) rerr(id, path ": digest: must be a kind slug [a-z0-9-] (got \"" rdig[id] "\")")
  if (rcov[id] != "" && !jperiod(rcov[id])) rerr(id, path ": covers: must be a calendar period YYYY or YYYY-MM (got \"" rcov[id] "\")")
  # ... and an elevation cannot summarize a period that has not begun. The
  # runner is stricter (the period must be COMPLETE); this is the floor a
  # hand-written record cannot fall through.
  else if (rcov[id] != "" && validdate(rcreated[id])) {
    pstart = (length(rcov[id]) == 4) ? rcov[id] "-01-01" : rcov[id] "-01"
    if (pstart > rcreated[id])
      rerr(id, path ": covers: " rcov[id] " begins after the record date " rcreated[id] " (an elevation cannot summarize a period that has not started)")
  }
  if (iswm) {
    if (!validdate(rrt[id])) rerr(id, path ": reviewed-through: must be a real YYYY-MM-DD date (got \"" rrt[id] "\")")
    # A claim cannot reach past the day it was written. settle refuses a
    # future date at the CLI; this is the deep lock for a hand-written or
    # merged record, which is committed repository content like any other -
    # without it, one line claims coverage of every entry there will ever be.
    else if (validdate(rcreated[id]) && rrt[id] > rcreated[id])
      rerr(id, path ": reviewed-through: " rrt[id] " is later than the record date " rcreated[id] " (a claim cannot cover what did not exist when it was made)")
    if (rcue[id] != "" || rsal[id] != "" || naxis[id] > 0)
      rerr(id, path ": cue:/salience:/axis-* are entry keys; a watermark claims coverage only")
    if (rpass[id] == "triage") rerr(id, path ": pass: triage is the default pass; omit the key (one spelling per kind)")
    else if (rpass[id] != "" && !jslug(rpass[id])) rerr(id, path ": pass: must be a kind slug [a-z0-9-] (got \"" rpass[id] "\")")
  } else if (rpass[id] != "") {
    rerr(id, path ": pass: scopes a watermark and needs reviewed-through:")
  }
  # covered: is the claim IDENTITY - the entries a watermark actually saw.
  # A date alone cannot say that: an entry written or merged later, dated
  # before the boundary, was never reviewed by it (see the coverage pass).
  if (id in hascovd) {
    if (!iswm && !isel) rerr(id, path ": covered: names what a coverage record saw and belongs on a watermark or an elevation")
    else {
      cn = split(rcovd[id], cvg, ",")
      for (ci = 1; ci <= cn; ci++) {
        cvt = trim(cvg[ci])
        if (cvt == "") continue
        if (cvt !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z0-9][a-z0-9-]*$/)
          rerr(id, path ": covered: \"" cvt "\" is not a record id")
        else if (cvt == id)
          rerr(id, path ": covered: names the watermark itself")
      }
    }
  }
  if (rcue[id] != "" && !jslug(rcue[id])) rerr(id, path ": cue: must be a slug [a-z0-9-] (got \"" rcue[id] "\")")
  if (rsal[id] != "" && rsal[id] !~ /^([1-9]|10)$/) rerr(id, path ": salience: must be an integer 1..10 (got \"" rsal[id] "\")")
  for (k = 1; k <= naxis[id]; k++) {
    nm2 = axlist[id, k]; v = raxis[id, nm2]
    if (nm2 == "salience") rerr(id, path ": axis-salience: is spelled salience: (one name per axis)")
    else if (!jslug(nm2)) rerr(id, path ": axis name must be a slug [a-z0-9-] (got \"axis-" nm2 "\")")
    ty = jaxtype(v)
    if (ty == "") rerr(id, path ": axis-" nm2 ": must be unipolar 0..10 (unsigned) or bipolar -5..+5 (always signed, +0 not -0); got \"" v "\"")
    else axtype[id, nm2] = ty
  }
  if (rtime[id] != "" && rtime[id] !~ /^([01][0-9]|2[0-3]):[0-5][0-9]$/) rerr(id, path ": time: must be HH:MM (got \"" rtime[id] "\")")
  if (ragent[id] != "" && ragent[id] !~ /^[A-Za-z0-9][A-Za-z0-9._@+-]*$/) rerr(id, path ": agent: must be one token [A-Za-z0-9._@+-] (got \"" ragent[id] "\")")
  if (ruser[id] != "" && ruser[id] !~ /^[A-Za-z0-9][A-Za-z0-9._@+-]*$/) rerr(id, path ": user: must be one token [A-Za-z0-9._@+-] (got \"" ruser[id] "\")")
}

# The "<period> (<kinds>)" list a journal lens header renders, newest
# period first. skip[] holds periods already shown elsewhere (pass the empty
# noskip array when nothing is skipped); arrays are by reference in awk, so
# one definition serves both header lines.
function jlabels(map, skip,   k, n, i, j, arr, s) {
  n = 0
  for (k in map) {
    if (k in skip) continue
    j = ++n
    while (j > 1 && arr[j - 1] < k) { arr[j] = arr[j - 1]; j-- }
    arr[j] = k
  }
  if (n == 0) return ""
  s = ""
  for (i = 1; i <= n; i++) s = s ((i > 1) ? ", " : "") arr[i] " (" map[arr[i]] ")"
  return s
}

# A covered id has to name a real journal ENTRY of this tree that the claim
# could actually have seen. Syntax alone let a claim name a QUARANTINED
# record - one nobody could read, so one nobody reviewed - and absorb it
# silently the moment it was repaired, with no rerun to recover it. An
# erased or archived id is a known-inert node and still counts: it existed.
# Archived ONLY when no live copy exists, though - the condition every other
# pass uses. An interrupted archive leaves both, and taking the archived
# exemption first meant a claim could name a live entry dated after its own
# boundary and pass: the entry was retired unread, check was clean, and
# review reported nothing outstanding.
function cover_ok(claim, cvt, period, bound,   c) {
  if ((cvt in erased) || ((cvt in archived) && !(cvt in filepath))) return 1
  if (!(cvt in filepath)) {
    bad_cover(claim ": covered: names " cvt ", which is not in this journal")
    return 0
  }
  if (cvt in bad) {
    bad_cover(claim ": covered: names " cvt ", which is quarantined - nobody could have reviewed it")
    return 0
  }
  if (rtype[cvt] != "memory" || (cvt in haswm)) {
    bad_cover(claim ": covered: names " cvt ", which is not an entry")
    return 0
  }
  c = rcreated[cvt]
  if (period != "" && substr(c, 1, length(period)) != period) {
    bad_cover(claim ": covered: names " cvt " (" c "), outside the period " period)
    return 0
  }
  if (bound != "" && c >= bound) {
    bad_cover(claim ": covered: names " cvt " (" c "), which is not before the claim boundary " bound)
    return 0
  }
  return 1
}

# A claim whose coverage list does not hold up carries NO coverage at all -
# fail closed on authority, which here means fail open on the entries: they
# stay undigested until someone reviews them for real.
function cover_list_ok(claim, list, period, bound,   n, g, i, t, ok) {
  ok = 1
  n = split(list, g, ",")
  for (i = 1; i <= n; i++) {
    t = trim(g[i])
    if (t == "") continue
    if (!cover_ok(claim, t, period, bound)) ok = 0
  }
  return ok
}

function bad_cover(msg) {
  err(msg)
  badcover[++nbadcover] = msg
}

# Every coverage pass that covers this entry, space separated: named by a
# claim of that pass, or falling under a date-only claim of it.
function jpasses(id,   s, i2, p) {
  s = ""
  for (i2 = 1; i2 <= nwmpass; i2++) {
    p = wmpass[i2]
    if (((p SUBSEP id) in cov) || ((p in dateonly) && rcreated[id] < dateonly[p]))
      s = s ((s == "") ? "" : " ") p
  }
  return s
}

# grains between two periods of one kind: months for YYYY-MM, years for YYYY
function grain_dist(a, b,   ya, yb, ma, mb) {
  ya = substr(a, 1, 4) + 0; yb = substr(b, 1, 4) + 0
  if (length(a) == 7 && length(b) == 7) {
    ma = substr(a, 6, 2) + 0; mb = substr(b, 6, 2) + 0
    return (yb * 12 + mb) - (ya * 12 + ma)
  }
  return yb - ya
}

# nearest-rank percentile index over n sorted values: deterministic,
# awk-portable, no interpolation, so goldens stay byte-stable across awks
function nrank(n, p,   r) {
  r = int(p * n)
  if (r < p * n) r++
  if (r < 1) r = 1
  return r
}

# month x cue x axis groups for the sidecar aggregates (entries only)
function jgadd(pm, cu, nm2, ty, v,   g) {
  g = pm SUBSEP cu SUBSEP nm2 SUBSEP ty
  if (!(g in gn)) { gorder[++jng] = g; gn[g] = 0 }
  gv[g, ++gn[g]] = v
}
# insertion sort of one group: a group is one month, one cue, one axis
function jsortvals(g, n,   i, j, t) {
  for (i = 2; i <= n; i++) {
    t = gv[g, i]; j = i - 1
    while (j >= 1 && gv[g, j] > t) { gv[g, j + 1] = gv[g, j]; j-- }
    gv[g, j + 1] = t
  }
}

# timeline order: created desc, then time desc (an entry without time: sorts
# last within its day), then id desc - the ONLY place time: is consulted
function jcmp(a, b) {
  if (jkey[a] != jkey[b]) return (jkey[a] > jkey[b]) ? -1 : 1
  return 0
}
function jsift(lo, hi,   root, child, tmp) {
  root = lo
  while (root * 2 <= hi) {
    child = root * 2
    if (child < hi && jcmp(jarr[child], jarr[child + 1]) < 0) child++
    if (jcmp(jarr[root], jarr[child]) < 0) {
      tmp = jarr[root]; jarr[root] = jarr[child]; jarr[child] = tmp
      root = child
    } else return
  }
}
function jheapsort(n,   i, tmp) {
  for (i = int(n / 2); i >= 1; i--) jsift(i, n)
  for (i = n; i > 1; i--) {
    tmp = jarr[1]; jarr[1] = jarr[i]; jarr[i] = tmp
    jsift(1, i - 1)
  }
}
function dv(v) { return (v == "") ? "-" : v }

# The export seam: the sanctioned read API for applications. A version line,
# a column-name row (readers map by NAME and ignore unknown columns; within
# v1 columns only append), then one TAB row per unretired record, newest
# first. Same enumeration every other read sees (G3).
function jexport(   i, id, n, cls, ax, k, hl, st, rv, sc2) {
  print "# zamm-journal-export v1"
  print "id\tclass\tcreated\ttime\tagent\tuser\tcue\tkind\tcovers\tpass\treviewed-through\tscope\tsalience\tstate\treviewed\tbg\taxes\theadline\tpasses"
  n = 0
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if ((id in live) || (id in elive) || (id in wmlive)) {
      jarr[++n] = id
      jkey[id] = rcreated[id] "\t" rtime[id] "\t" id
    }
  }
  jheapsort(n)
  for (i = 1; i <= n; i++) {
    id = jarr[i]
    cls = (id in elive) ? "elevation" : ((id in wmlive) ? "watermark" : "entry")
    ax = ""
    for (k = 1; k <= naxis[id]; k++) ax = ax ((ax == "") ? "" : " ") axlist[id, k] "=" raxis[id, axlist[id, k]]
    hl = headline(id); gsub(/\t/, " ", hl)
    sc2 = rscope[id]; gsub(/\t/, " ", sc2)
    st = (cls == "entry" && (id in dormant)) ? "dormant" : "live"
    rv = (cls == "entry") ? ((id in reviewed) ? "yes" : "no") : "-"
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, cls, rcreated[id], dv(rtime[id]), dv(ragent[id]), dv(ruser[id]), dv(rcue[id]), dv(rdig[id]), dv(rcov[id]), (cls == "watermark" ? (rpass[id] == "" ? "triage" : rpass[id]) : "-"), dv(rrt[id]), dv(sc2), dv(rsal[id]), st, rv, ((id in hasbg) ? "yes" : "no"), dv(ax), hl, ((cls == "entry") ? dv(passesof[id]) : "-")
  }
}

# absolute paths cost context in an always-on surface; show them repo-relative
function relpath(s) { if (root != "" && index(s, root) == 1) return substr(s, length(root) + 1); return s }

# real Gregorian date, not just the digit shape: 2026-99-99 and 2026-02-30
# are rejected, leap years respected
function validdate(d,   y, mo, dy, dim) {
  if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
  y = substr(d, 1, 4) + 0; mo = substr(d, 6, 2) + 0; dy = substr(d, 9, 2) + 0
  if (mo < 1 || mo > 12 || dy < 1) return 0
  if (mo == 4 || mo == 6 || mo == 9 || mo == 11) dim = 30
  else if (mo == 2) dim = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
  else dim = 31
  return (dy <= dim)
}

# warnings name a likely mistake without quarantining the record: an unknown
# key is usually a typo, but guessing wrong must not cost the whole record
function warn(msg) { print "zamm-compile: WARNING: " msg | "cat 1>&2"; nwarn++ }

function err(msg) { print "zamm-compile: ERROR: " msg | "cat 1>&2"; nerr++ }

# Record-scoped error: quarantines the record. A record that fails the
# contract is dropped from liveness, supersession, votes and ranking — but it
# must never take a valid record down with it, so its supersedes: edges are
# ignored rather than applied (fail open on content, fail closed on
# authority). --check still fails; normal compile publishes the rest and
# lists the casualties under ## Degraded.
function rerr(id, msg) {
  err(msg)
  if (!(id in bad)) { bad[id] = 1; nbad++; badmsg[id] = msg }
}

# APPROXIMATE day index: every month is treated as 31 days and every year as
# 372 (12 x 31). This is deterministic and dependency-free, and only ever feeds
# a DIFFERENCE of two dates that drives an exponential decay weight — so an
# error of a few days near month boundaries shifts a score imperceptibly and
# never changes a ranking tier. It is NOT a real calendar day count; do not use
# it anywhere exactness matters (validdate() enforces real calendar dates).
function daynum(d) {
  if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 0
  return substr(d, 1, 4) * 372 + substr(d, 6, 2) * 31 + substr(d, 9, 2) + 0
}

# EXACT days between two calendar dates (the standard days-from-civil
# algorithm). daynum() above is a deliberate approximation feeding a decay
# WEIGHT, where a few days near a month boundary are invisible; a policy
# BOUNDARY cannot use it. Under daynum, "older than 60 days" fired on day 60
# for a 31st-of-January entry and would wait past day 62 for a March one.
function civildays(d,   y, m, dd, era, yoe, doy, doe) {
  if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 0
  y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
  if (m <= 2) y--
  era = int(y / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

# recency weight, half-life ~90 days
function agew(d,   a) {
  if (d == "") return 0.25
  a = tdn - daynum(d)
  if (a < 0) a = 0
  return exp(-0.0077 * a)
}

# ---- conflict grouping: union-find over ALL supersede edges ----
# First-parent chain walking only models a single lineage, so a successor
# branching off the second lineage of a reconciliation merge was never seen
# as competing with the merge head. Connected components over the undirected
# edge set group every related record regardless of which parent came first.
# Component label = lexicographically smallest id (deterministic, and since
# ids lead with the creation date it is normally the original record).
function uf_find(x,   r, p) {
  r = x
  while ((r in ufp) && ufp[r] != r) r = ufp[r]
  while ((x in ufp) && ufp[x] != x) { p = ufp[x]; ufp[x] = r; x = p }
  return r
}

function uf_union(a, b,   ra, rb) {
  if (!(a in ufp)) ufp[a] = a
  if (!(b in ufp)) ufp[b] = b
  ra = uf_find(a); rb = uf_find(b)
  if (ra == rb) return
  if (ra < rb) ufp[rb] = ra; else ufp[ra] = rb
}

function group(id) { return (id in ufp) ? uf_find(id) : id }

# cycle detection over the supersede DAG. A cycle makes liveness meaningless —
# every record in it supersedes the next — so every member must be quarantined,
# not just the node where the loop happened to close.
#
# Tarjan strongly-connected components, iterative. The previous single early
# -return DFS quarantined only the FIRST cycle it closed and left stale grey
# state behind, so a second, disjoint cycle reachable through a shared node
# went undetected — its records were silently applied and could kill a valid
# neighbour (exit 0, no degradation shown). SCC decomposition finds ALL cycles
# regardless of overlap or discovery order; a component is cyclic when it has
# more than one node, or one node with a self-edge. Iterative (explicit stacks)
# because a recursive walk in awk also risks blowing the interpreter stack on a
# long valid chain.

# cycle-candidate adjacency: the supersede targets of every non-quarantined
# record, filtered exactly as liveness will filter them (existing, non-erased,
# non-bad). Built once so Tarjan and any re-run read the same graph.
function build_adj(   i, id, m, tg, t, v, c) {
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if ((id in erased) || (id in bad)) continue
    adjn[id] = 0
    if (rsup[id] == "") continue
    m = split(rsup[id], tg, ",")
    c = 0
    for (t = 1; t <= m; t++) {
      v = trim(tg[t])
      if (v == "" || !(v in filepath) || (v in erased) || (v in bad)) continue
      adj[id, ++c] = v
    }
    adjn[id] = c
  }
}

# quarantine every member of an SCC that represents a cycle (size > 1, or a
# lone node that supersedes itself). A self-supersession is already caught in
# pass 1a, but checking here keeps SCC handling self-contained.
function scc_close(u, sp,   k, w, size, selfloop, t) {
  size = 0
  # pop the component stack down to and including u
  while (1) {
    w = tstk[tsp--]; ton[w] = 0
    comp[++size] = w
    if (w == u) break
  }
  selfloop = 0
  for (t = 1; t <= adjn[u]; t++) if (adj[u, t] == u) selfloop = 1
  if (size > 1 || selfloop) {
    for (k = 1; k <= size; k++)
      rerr(comp[k], filepath[comp[k]] ": supersede cycle member (strongly-connected component of " size ")")
  }
}

function tarjan(   i, id, u, ci, v, par) {
  build_adj()
  tj_idx = 0    # next DFS index to hand out
  tsp = 0       # component-stack pointer (tstk / ton)
  wsp = 0       # work-stack pointer (wnode / wci): the explicit call stack
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if ((id in erased) || (id in bad)) continue
    if (id in tindex) continue
    wsp = 1; wnode[1] = id; wci[1] = 0
    while (wsp > 0) {
      u = wnode[wsp]
      ci = wci[wsp]
      if (ci == 0) {
        tj_idx++
        tindex[u] = tj_idx
        tlow[u] = tj_idx
        tsp++; tstk[tsp] = u; ton[u] = 1
      }
      if (ci < adjn[u]) {
        wci[wsp] = ci + 1
        v = adj[u, ci + 1]
        if (!(v in tindex)) {
          wsp++; wnode[wsp] = v; wci[wsp] = 0        # descend
        } else if (ton[v] && tindex[v] < tlow[u]) {
          tlow[u] = tindex[v]                        # back/cross edge on stack
        }
      } else {
        if (tlow[u] == tindex[u]) scc_close(u)       # u roots an SCC
        wsp--                                        # return from u
        if (wsp > 0) {
          par = wnode[wsp]
          if (tlow[u] < tlow[par]) tlow[par] = tlow[u]
        }
      }
    }
  }
}

# durability credit: only single-target supersessions count — a hop that
# merged several heads (reconciliation) was forced by concurrency and proves
# nothing about the statement having survived repeated updates
function chaindepth(id,   r, hops, d) {
  r = id; hops = 0; d = 0
  while ((r in parent) && hops < 200) {
    if (nsup[r] == 1) d++
    r = parent[r]; hops++
  }
  # capped: lineage length is weak evidence of truth — a supersede may be a
  # confirmation, a small refresh, or a full correction of something wrong.
  # Uncapped it compounds with inherited ancestor votes, so the statements
  # revised most often (the least settled) would rank highest.
  return (d > CHAINDEPTH_MAX) ? CHAINDEPTH_MAX : d
}

# author-rated base weight; guardrails are rare, load-bearing rules
function ibase(v) {
  if (v == "guardrail") return 3
  if (v == "minor")     return 0.3
  return 1
}

# durability = author-rated shelf life; it IS the decay half-life (days)
function halflife(v) {
  if (v == "days")      return 7
  if (v == "weeks")     return 30
  if (v == "years")     return 365
  if (v == "permanent") return 0
  return 91
}

function decayw(id,   h, a) {
  h = halflife(rdur[id])
  if (h == 0) return 1
  a = tdn - daynum(rcreated[id])
  if (a < 0) a = 0
  return exp(-0.693147 * a / h)
}

# scope = 1-3 ordered area tags; the first (primary) may carry /subpath and is
# where the record displays, secondaries are bare areas (selection doors only)
function parsetags(id,   m, tv, t, tag) {
  tagn[id] = 0; pscope[id] = ""; parea[id] = ""; emptytag[id] = 0
  if (rscope[id] == "") return
  m = split(rscope[id], tv, ",")
  for (t = 1; t <= m; t++) {
    tag = trim(tv[t])
    # an empty component ("a,,b" or a bare ",") silently dropped a tag and
    # could yield zero tags from a non-empty scope: line
    if (tag == "") { emptytag[id] = 1; continue }
    tagsc[id, ++tagn[id]] = tag
  }
  if (tagn[id] == 0) return
  pscope[id] = tagsc[id, 1]
  parea[id] = areaof(pscope[id])
}

function areaof(tag,   p) {
  p = index(tag, "/")
  if (p > 0) return substr(tag, 1, p - 1)
  return tag
}

# diversity domain of a record for display/dormant grouping = primary area
function area(id) { return parea[id] }

# selection enters through the least-crowded of the tag areas
function mintaken(id,   t, v, mn) {
  if (tagn[id] == 0) return ntaken[""]
  mn = -1
  for (t = 1; t <= tagn[id]; t++) {
    v = ntaken[areaof(tagsc[id, t])]
    if (mn < 0 || v < mn) mn = v
  }
  return mn
}

# fractional seat attribution: a k-tag record occupies 1/k of a seat per area
function takeseats(id,   t) {
  if (tagn[id] == 0) { ntaken[""]++; return }
  for (t = 1; t <= tagn[id]; t++)
    ntaken[areaof(tagsc[id, t])] += 1 / tagn[id]
}

# parsimony cost: each tag beyond the first costs rank
function tagcost(id) { return (tagn[id] > 1) ? TAG_COST * (tagn[id] - 1) : 0 }

# votes attach to the exact record voted on; totals aggregate over a record
# and ALL records it (transitively) supersedes, never sideways — so a vote on
# one fork head cannot bleed to a competing head
# A bad vote reference (missing or wrong-typed target) drops just that vote —
# co-listed valid votes still count — but it is a global graph defect, so like a
# dangling supersedes it is surfaced under ## Degraded and forces a degraded
# (exit 2) publish rather than a healthy-looking exit 0. --check already fails
# on it via err(); this makes normal compile agree about ledger health.
function bad_voteref(msg) {
  err(msg)
  badvoteref[++nbadvoteref] = msg
}

function addvotes(voter, list, sign, w,   m, t, tgt, av) {
  if (list == "") return
  m = split(list, av, ",")
  for (t = 1; t <= m; t++) {
    tgt = trim(av[t])
    if (tgt == "") continue
    # erased or archived target = known inert node: no vote, no error -
    # archived only when no live copy exists, or a vote on a record caught
    # mid-archive silently vanished from the ranking instead of counting
    if ((tgt in erased) || ((tgt in archived) && !(tgt in filepath))) continue
    if (!(tgt in filepath)) { bad_voteref(voter ": vote target not found: " tgt); continue }
    if (tgt in bad) continue
    # votes rate knowledge, so only memory records can be voted on: a vote on
    # a tombstone or on another votes record carries no meaning and would
    # silently vanish from the ranking. Bad target is a degradation (surfaced,
    # not silently dropped) but does not quarantine the record.
    if (rtype[tgt] != "memory") {
      bad_voteref(voter ": vote target " tgt " is a " rtype[tgt] " record; only memory records can be voted on")
      continue
    }
    if (sign > 0) { vup_id[tgt]++; vsc_id[tgt] += w }
    else          { vdn_id[tgt]++; vsc_id[tgt] -= w }
  }
}

# Enqueue the applied supersede targets of cur onto q; returns the new tail
# index. ONE definition of the edge expansion every ancestor walk uses
# (chainagg, effmark collection, effmark dominance) — three hand-copied
# loops once began to drift, and walks that traverse different graphs are
# exactly how lane resolution goes silently wrong.
function pushsups(q, qt, cur,   m, tg, t, tgt) {
  if (asup[cur] != "") {
    m = split(asup[cur], tg, ",")
    for (t = 1; t <= m; t++) {
      tgt = trim(tg[t])
      if (tgt != "") q[++qt] = tgt
    }
  }
  return qt
}

# DAG walk over the ancestor set: which 1 = up count, 2 = down count, 3 = score.
# Walks asup[] (the APPLIED edges) only, so votes aggregate across exactly the
# lineage that liveness recognises — never through a quarantined or dangling
# ancestor (that would let an invalid record lend its votes to a valid head).
# The visited set (vseen/epoch) makes each node contribute once, which both
# handles diamonds and bounds the walk by the ledger size, so there is no
# arbitrary node cap to silently truncate a long ancestry.
function chainagg(id, which,   q, qh, qt, cur, tot) {
  epoch++
  tot = 0; qh = 1; qt = 1; q[1] = id
  while (qh <= qt) {
    cur = q[qh++]
    if (vseen[cur] == epoch) continue
    vseen[cur] = epoch
    if (which == 1)      tot += vup_id[cur]
    else if (which == 2) tot += vdn_id[cur]
    else                 tot += vsc_id[cur]
    qt = pushsups(q, qt, cur)
  }
  return tot
}

# The dead lanes: a tombstone kills the marked: key of every record BEHIND
# it — its victims and their entire ancestor cones — as a property of the
# NODES, not of the path a later walk happens to take. The earlier path-based
# wall held only when a revival superseded the tombstone record itself;
# superseding the dead CONTENT record directly (the natural gesture — it is
# the record that carries the content) sidestepped the wall and inherited the
# dead mark (round-3 review finding, reproduced). One multi-source BFS per
# compile, seeded with every tombstone applied-edge target.
function build_tombkill(   i, id, qh, qt, m, tg, t, tgt, cur) {
  qh = 1; qt = 0
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if ((id in erased) || (id in bad)) continue
    if (rtype[id] != "tombstone" || asup[id] == "") continue
    m = split(asup[id], tg, ",")
    for (t = 1; t <= m; t++) {
      tgt = trim(tg[t])
      if (tgt != "" && !(tgt in tombkilled)) { tombkilled[tgt] = 1; tkq[++qt] = tgt }
    }
  }
  while (qh <= qt) {
    cur = tkq[qh++]
    if (asup[cur] == "") continue
    m = split(asup[cur], tg, ",")
    for (t = 1; t <= m; t++) {
      tgt = trim(tg[t])
      if (tgt != "" && !(tgt in tombkilled)) { tombkilled[tgt] = 1; tkq[++qt] = tgt }
    }
  }
}

# Effective marked state of a backlog head, resolved by GRAPH PRECEDENCE:
# a decision made on a descendant record overrides every decision on its
# ancestors, because superseding IS the act of revising — id order proves
# nothing (same-day ids differ only by a random suffix, so a lexical
# "newest id wins" let a mark resurface after a same-day unmark). The
# marked: key on the head itself outranks everything; otherwise the
# UNDOMINATED decision nodes — those no other decision node can reach along
# applied supersede edges — form the frontier, and only genuinely
# incomparable fork decisions fall back to the deterministic id tiebreak.
# Tombstone-killed decisions (build_tombkill) contribute nothing, so a
# revival starts outside the lane whichever record it supersedes. Dominance
# itself is PURE ANCESTRY with no tombstone wall: a wall there severed real
# descent and handed comparable decisions to the suffix tiebreak — the
# pathology this function exists to prevent (round-3 review finding,
# reproduced). Returns the marked date, or "" when the decision is "no" or
# none exists — a superseding record that OMITS the key inherits the lane.
# Walks asup[] only, like the vote aggregation, so a quarantined ancestor
# cannot decide.
function effmark(id,   q, qh, qt, cur, nm, i2, best) {
  if (id in hasmark) return mkval(id)
  # collect the reachable, still-living decision nodes
  mkepoch++
  nm = 0; qh = 1; qt = 1; q[1] = id
  while (qh <= qt) {
    cur = q[qh++]
    if (mkseen[cur] == mkepoch) continue
    mkseen[cur] = mkepoch
    if ((cur in hasmark) && !(cur in tombkilled)) mkm[++nm] = cur
    qt = pushsups(q, qt, cur)
  }
  if (nm == 0) return ""
  # dominance: ONE walk seeded from the applied targets of every decision
  # node; any decision node it reaches was revised by a descendant and is
  # overridden. (Only mkm members are ever read back from mkdom, and each is
  # reset first, so writes to other ids are inert.)
  mkepoch++
  qh = 1; qt = 0
  for (i2 = 1; i2 <= nm; i2++) {
    mkdom[mkm[i2]] = 0
    qt = pushsups(q, qt, mkm[i2])
  }
  while (qh <= qt) {
    cur = q[qh++]
    if (mkseen[cur] == mkepoch) continue
    mkseen[cur] = mkepoch
    if (cur in hasmark) mkdom[cur] = 1
    qt = pushsups(q, qt, cur)
  }
  best = ""
  for (i2 = 1; i2 <= nm; i2++)
    if (!mkdom[mkm[i2]] && mkm[i2] > best) best = mkm[i2]
  return mkval(best)
}

function mkval(x) { return (rmarked[x] == "no") ? "" : rmarked[x] }

# ranking: score desc, then id desc (newer/later name wins ties) — deterministic
# total order: score desc, then id desc (newer/later name wins ties).
# <0 = a ranks before b, >0 = after, 0 = same record.
function rankcmp(a, b) {
  if (sc[a] != sc[b]) return (sc[a] > sc[b]) ? -1 : 1
  if (a != b) return (a > b) ? -1 : 1
  return 0
}

function add_sorted(id) { sorted[++nsort] = id }

# Heapsort, not insertion sort: the old add_sorted shifted the array on every
# insert, which is quadratic and worst exactly when input arrives in ranked
# order (find | sort feeds it near-sorted ids). O(n log n), in place, no temp
# files, deterministic — same comparator, so output order is unchanged.
function sift(lo, hi,   root, child, tmp) {
  root = lo
  while (root * 2 <= hi) {
    child = root * 2
    if (child < hi && rankcmp(sorted[child], sorted[child + 1]) < 0) child++
    if (rankcmp(sorted[root], sorted[child]) < 0) {
      tmp = sorted[root]; sorted[root] = sorted[child]; sorted[child] = tmp
      root = child
    } else return
  }
}

function heapsort(n,   i, tmp) {
  for (i = int(n / 2); i >= 1; i--) sift(i, n)
  for (i = n; i > 1; i--) {
    tmp = sorted[1]; sorted[1] = sorted[i]; sorted[i] = tmp
    sift(1, i - 1)
  }
}

# the digest block = everything above the first heading: a headline paragraph
# (the trigger, joined to one line) plus optional elaboration lines. Content
# under a heading (## Background) stays in the file and earns the +bg marker.
function analyze(id,   m, t, ln, bl, started, paradone, headseen) {
  if (id in analyzed) return
  analyzed[id] = 1
  m = split(rbody[id], bl, "\n")
  for (t = 1; t <= m; t++) {
    ln = trim(bl[t])
    if (headseen) {
      if (ln != "") { hasbg[id] = 1; break }
      continue
    }
    if (ln ~ /^#/) { headseen = 1; continue }
    if (ln == "") { if (started) paradone = 1; continue }
    started = 1
    blockl[id]++; blockc[id] += length(ln)
    if (!paradone) hl[id] = (hl[id] == "") ? ln : hl[id] " " ln
  }
}

function headline(id) { analyze(id); return hl[id] }

function pointer(id,   p, u, d) {
  p = id
  u = chainagg(id, 1); d = chainagg(id, 2)
  if (u > 0 && d > 0) p = p " +" u "/-" d
  else if (u > 0)     p = p " +" u
  else if (d > 0)     p = p " -" d
  analyze(id)
  if (id in hasbg) p = p " +bg"
  return "[" p "]"
}

# is this record one of several live heads of the same chain?
function contested(id) { return (livecnt[group(id)] >= 2) }

# entry markers: ! = guardrail (safety contract), ~ = contested head
function markpfx(id,   p) {
  p = (rimp[id] == "guardrail") ? "!" : ""
  if (contested(id)) p = p "~"
  return (p == "") ? "" : p " "
}

# headline-only entry (Headlines, reconciliation heads); scope = primary tag.
# nomark: list the record without consuming its digest eligibility — the
# reconciliation index must not spend the entry it is warning about, or a
# contested guardrail loses its elaboration exactly when it is most needed.
function emitline(id, withscope, nomark,   pre) {
  pre = nomark ? ((rimp[id] == "guardrail") ? "! " : "") : markpfx(id)
  if (withscope && pscope[id] != "")
    print "- " pre pscope[id] ": " headline(id) " " pointer(id)
  else
    print "- " pre headline(id) " " pointer(id)
  if (!nomark) printed[id] = 1
  endedblank = 0
}

# full entry: headline line + elaboration lines (rest of the digest block)
function emitfull(id, withscope,   pre, m, bl, t, ln, started, paradone, any) {
  pre = markpfx(id)
  if (withscope && pscope[id] != "")
    print "- " pre pscope[id] ": " headline(id) " " pointer(id)
  else
    print "- " pre headline(id) " " pointer(id)
  m = split(rbody[id], bl, "\n")
  for (t = 1; t <= m; t++) {
    ln = trim(bl[t])
    if (ln ~ /^#/) break
    if (ln == "") { if (started) paradone = 1; continue }
    started = 1
    if (paradone) { print "  " ln; any = 1 }
  }
  if (any) { print ""; endedblank = 1 } else endedblank = 0
  printed[id] = 1
}

END {
  # awk runs END even on a mid-stream exit, so a fatal enumeration-class
  # failure re-asserts its code here before any rendering can happen.
  if (fatalrc) { close("cat 1>&2"); exit fatalrc }
  tdn = daynum(today)

  # ---- the same id live AND archived ----
  # An archive interrupted between copy and unlink (a cross-device move, a
  # sync client putting the file back) leaves both. That is not damage: the
  # live copy is authoritative, the archived one is ignored for ranking, and
  # rerunning the archiver finishes the job — so it warns rather than fails.
  # Saying nothing was the wrong end of that trade: a silently duplicated
  # record is exactly the state nobody goes looking for.
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in archived)
      warn(id " exists both live and archived; the live copy is used. Rerun memory archive to finish the move, or delete one copy.")
  }

  # ---- erasure set: built BEFORE any graph pass reads it ----
  # Every erasure record has its erases: list applied, quarantined or not.
  # erasure can only REMOVE content, so honouring a dubious one is safe while
  # ignoring a valid one resurrects redacted material — the asymmetry that
  # decides which way this fails. A malformed erasure record still quarantines
  # loudly (failing --check and degrading the digest), so the operator hears
  # about it instead of discovering the lapse in a digest.
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (rtype[id] != "erasure") continue
    if (rerases[id] == "") continue
    en = split(rerases[id], eg, ",")
    for (e = 1; e <= en; e++) {
      etgt = trim(eg[e])
      if (etgt != "" && etgt != id) erased[etgt] = 1
    }
  }
  # An erasure record in the ARCHIVE tree redacts exactly as one in the live
  # tree does. The inert rule above now refuses to move them, but a file can
  # reach the archive by other routes: a manual tidy-up, an interrupted run,
  # a merge landing an archived copy. Honouring it here makes the redaction
  # independent of where the file sits, which is the same asymmetry that
  # governs the live pass — ignoring a valid erasure record resurrects
  # redacted material, and unlike everything else here a rerun cannot undo
  # that exposure.
  for (aid in archived) {
    if (atype[aid] != "erasure") continue
    if (aerases[aid] == "") continue
    en = split(aerases[aid], eg, ",")
    for (e = 1; e <= en; e++) {
      etgt = trim(eg[e])
      if (etgt != "" && etgt != aid) erased[etgt] = 1
    }
  }

  # Supersede edges are resolved in three passes so an invalid record can
  # never retire a valid neighbour. The old single pass mutated dead/parent/
  # union-find WHILE walking the edge list, then quarantined the record after
  # a bad edge — so a type-incompatible, duplicate or cyclic edge had already
  # killed its target by the time the record was rejected (silent data loss,
  # exit 0). Validation and cycle detection now complete BEFORE any mutation.

  # 1a. VALIDATE the COMPLETE outgoing edge set of each record, mutating nothing.
  #     A self-edge, a duplicate target or a type-incompatible edge quarantines
  #     the WHOLE record: every edge it carries is then void (fail open on
  #     content, fail closed on authority). A dangling target is a diagnostic
  #     only — it drops its own edge (nothing to retire) without quarantining
  #     the record, so its other valid edges still stand.
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in erased) continue
    if (id in bad) continue
    if (rsup[id] == "") continue
    m = split(rsup[id], tg, ",")
    delete seentgt
    for (t = 1; t <= m; t++) {
      tgt = trim(tg[t])
      if (tgt == "") continue
      if (tgt == id) { rerr(id, filepath[id] ": supersedes itself"); continue }
      if (tgt in seentgt) { rerr(id, filepath[id] ": duplicate supersedes target " tgt); continue }
      seentgt[tgt] = 1
      # An erased target is a known redacted node, not a dangling reference:
      # the erasure procedure (erasure record + delete) leaves successors valid.
      if (tgt in erased) continue
      # An archived target is likewise known-inert, not dangling: `memory
      # archive` moved a fully-retired record out of the scan path but kept
      # its id resolvable. Its type (parsed from the archived header) still
      # participates in compatibility checks; the edge itself is applied as
      # grouping-only in the apply pass.
      #
      # ONLY when there is no live copy, though - the same condition the
      # apply pass uses. An interrupted archive leaves both, and judging the
      # edge by the archived header while applying it to the live record
      # meant validating one thing and killing another: the header carries a
      # type but not a journal class, so a watermark could supersede an
      # entry and retire it, with check none the wiser.
      if ((tgt in archived) && !(tgt in filepath)) {
        if (atype[tgt] != "") {
          if (rtype[id] == "memory" && atype[tgt] == "votes")
            rerr(id, filepath[id] ": memory record cannot supersede a votes record (" tgt ", archived)")
          else if (rtype[id] == "votes" && atype[tgt] != "votes")
            rerr(id, filepath[id] ": votes record may only supersede another votes record (" tgt " is archived " atype[tgt] ")")
          else if (rtype[id] == "digest" && atype[tgt] != "digest")
            rerr(id, filepath[id] ": an elevation (type: digest) may only supersede another elevation (" tgt " is archived " atype[tgt] ")")
          else if (rtype[id] == "memory" && atype[tgt] == "digest")
            rerr(id, filepath[id] ": an entry cannot supersede an elevation (" tgt ", archived)")
        }
        continue
      }
      if (!(tgt in filepath)) {
        err(id ": supersedes target not found: " tgt)
        # A dangling target does NOT quarantine the record (its other edges may
        # be valid) — but it is a global graph defect, so it is surfaced under
        # ## Degraded and forces a non-zero (degraded) publish exit, rather than
        # a healthy-looking exit 0 that hides the broken reference.
        danglingtgt[id] = (danglingtgt[id] == "") ? tgt : danglingtgt[id] ", " tgt
        if (!(id in hasdangling)) { hasdangling[id] = 1; ndangling++ }
        continue
      }
      # type compatibility: a memory record cannot retire a vote, and a vote
      # cannot retire knowledge — only tombstones may retire anything
      if (rtype[id] == "memory" && rtype[tgt] == "votes")
        rerr(id, filepath[id] ": memory record cannot supersede a votes record (" tgt ")")
      else if (rtype[id] == "votes" && rtype[tgt] != "votes")
        rerr(id, filepath[id] ": votes record may only supersede another votes record (" tgt " is " rtype[tgt] ")")
      # a record is exactly one class: an elevation is corrected by another
      # elevation (or retired by a tombstone), never silently by an entry
      else if (rtype[id] == "digest" && rtype[tgt] != "digest")
        rerr(id, filepath[id] ": an elevation (type: digest) may only supersede another elevation (" tgt " is " rtype[tgt] ")")
      else if (rtype[id] == "memory" && rtype[tgt] == "digest")
        rerr(id, filepath[id] ": an entry cannot supersede an elevation (" tgt "); write a newer elevation or a tombstone")
      # Entries and watermarks share type: memory, so type compatibility
      # alone let a coverage claim supersede an episode - which retired it
      # outright, out of the timeline and out of the export, against the
      # rule that digestion never retires what it summarizes. Only a
      # tombstone retires across classes.
      else if (lens == "journal" && rtype[id] == "memory" && rtype[tgt] == "memory" &&
               ((id in haswm) != (tgt in haswm)))
        rerr(id, filepath[id] ": " jclass(id) " may not supersede " jclass(tgt) " (" tgt "); digestion never retires an entry - correct a wrong record with a tombstone")
    }
  }

  # 1b. cycles: a supersede loop makes liveness undefined. Runs after 1a so the
  #     type/self/duplicate offenders are already quarantined and cannot appear
  #     as phantom cycle members. Tarjan quarantines every member of every SCC
  #     that is a cycle, so none of them reaches the apply pass — see tarjan().
  tarjan()

  # 1c. APPLY edges, now that only records with a fully clean, acyclic edge set
  #     remain un-quarantined. Both endpoints must be valid: the edge is
  #     dropped when the TARGET is quarantined too, or a valid record that
  #     supersedes a parse-invalid or cyclic target would still collect
  #     parent/union-find/nsup/chain-depth credit from an edge into nothing —
  #     letting invalid input change the rank of a valid record (fail closed on
  #     authority, on both ends of the edge). Shunned and dangling targets were
  #     diagnosed in 1a and likewise carry no edge.
  #
  #     The edges that survive here are the ONLY ones any later pass may read.
  #     asup[] records that applied adjacency (comma-joined targets); vote and
  #     ancestor aggregation walk asup[], never the raw rsup[], so a vote can
  #     never reach a valid record through a quarantined or dangling ancestor.
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in erased) continue
    if (id in bad) continue
    if (rsup[id] == "") continue
    m = split(rsup[id], tg, ",")
    for (t = 1; t <= m; t++) {
      tgt = trim(tg[t])
      if (tgt == "") continue
      # An edge into an erased or archived target applies as GROUPING AND
      # LINEAGE ONLY: the retired id stays a real graph node (two live
      # successors of one retired target meet in one union-find group and
      # surface under Needs reconciliation), but no dead/nsup/asup mutation
      # happens, so a retired node can never mint ranking credit or route
      # votes into a live record.
      if ((tgt in erased) || ((tgt in archived) && !(tgt in filepath))) {
        uf_union(id, tgt)
        if (!(id in parent)) parent[id] = tgt
        continue
      }
      if ((tgt in bad) || !(tgt in filepath)) continue
      dead[tgt] = 1
      nsup[id]++
      if (!(id in parent)) parent[id] = tgt
      asup[id] = (asup[id] == "") ? tgt : asup[id] "," tgt
      uf_union(id, tgt)
    }
  }

  # Edges BETWEEN retired nodes, parsed from archived headers, keep whole
  # retired chains connected: two live successors attached at different
  # points of one archived chain still meet in one group. Grouping only --
  # nothing here touches liveness, rank or votes.
  for (aid in asupinert) {
    m = split(asupinert[aid], tg, ",")
    for (t = 1; t <= m; t++) {
      tgt = trim(tg[t])
      if (tgt == "" || tgt == aid) continue
      if ((tgt in archived) || (tgt in erased) || (tgt in filepath)) uf_union(aid, tgt)
    }
  }

  # 2a. one active votes record per plan. The votes record for a plan is
  #     corrected by SUPERSEDING it, so more than one active (non-dead) votes
  #     record for the same plan is a bookkeeping error that would double-count
  #     (two "+1 on X" records reading as +2). Only the newest is counted — ids
  #     lead with the creation date, so the lexical maximum is the newest — and
  #     the collision is surfaced under ## Degraded (and fails --check). This
  #     keeps the count deterministic without dropping the signal entirely.
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if ((id in erased) || (id in bad)) continue
    if (rtype[id] != "votes" || (id in dead)) continue
    pl = rplan[id]
    if (pl == "") continue
    nplanvotes[pl]++
    if (!(pl in canonvote) || id > canonvote[pl]) canonvote[pl] = id
  }
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if ((id in erased) || (id in bad)) continue
    if (rtype[id] != "votes" || (id in dead)) continue
    pl = rplan[id]
    if (pl != "" && nplanvotes[pl] > 1 && !(pl in dupvoteseen)) {
      dupvoteseen[pl] = 1
      dupvoteplan[++ndupvote] = pl
      err(pl ": " nplanvotes[pl] " active votes records for one plan (supersede the stale ones; only the newest, " canonvote[pl] ", is counted)")
    }
  }

  # 2. votes: vote records + migration seed votes, all attached to chain roots
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in erased) continue
    if (id in bad) continue
    # A superseded or tombstoned votes record stops counting — superseding a
    # votes record IS the vote-correction path, so it has to actually work.
    if (rtype[id] == "votes" && (id in dead)) continue
    # Only the newest active votes record for a plan counts (see pass 2a); the
    # stale duplicates are surfaced as a degradation instead of double-counting.
    if (rtype[id] == "votes" && rplan[id] != "" && canonvote[rplan[id]] != id) continue
    w = VOTE_WEIGHT * agew(rcreated[id])
    if (rtype[id] == "votes") {
      addvotes(id, rup[id], 1, w)
      addvotes(id, rdown[id], -1, w)
    } else if (rtype[id] == "memory") {
      if (rseedup[id] != "") {
        n = rseedup[id] + 0
        vup_id[id] += n; vsc_id[id] += n * w
      }
      if (rseeddn[id] != "") {
        n = rseeddn[id] + 0
        vdn_id[id] += n; vsc_id[id] -= n * w
      }
    }
  }

  # 3. live set, scores, conflict census
  if (lens == "backlog") build_tombkill()
  nlive = 0
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in erased) continue
    if (id in bad) continue
    if (id in dead) continue
    # Journal classes: an elevation and a watermark are never dormant -
    # decay is an entry concept. They are retired only by supersede,
    # tombstone or erasure (all of which land them in dead/erased above),
    # so a stored digest cannot silently vanish from the views and a
    # coverage claim cannot silently expire.
    if (lens == "journal" && rtype[id] == "digest") { elive[id] = 1; nelev++; continue }
    if (rtype[id] != "memory") continue
    if (lens == "journal" && (id in haswm)) { wmlive[id] = 1; nwm++; continue }
    live[id] = 1; nlive++
    if (area(id) == "other") nother++
    if (rimp[id] == "guardrail") nguard++
    r = group(id)
    livecnt[r]++
    sc[id] = ibase(rimp[id]) * decayw(id) + chainagg(id, 3) + 0.4 * chaindepth(id)
    if (lens == "backlog") {
      # Marked ideas are the selected lane: exempt from dormancy the way
      # guardrails are in the knowledge tree — a selected item never fades
      # silently; it leaves by promote, unmark, or tombstone.
      em = effmark(id)
      if (em != "") { markedof[id] = em; nmarked++ }
      if (sc[id] >= HOT) nhot++
      if (sc[id] < FLOOR && !(id in markedof)) dormant[id] = 1
    } else if (sc[id] < FLOOR && rimp[id] != "guardrail") dormant[id] = 1
    add_sorted(id)
  }
  heapsort(nsort)
  # OTHER_MAX is knowledge policy: the cap exists to force refiling of
  # knowledge into real areas. Backlog capture legitimately defaults to
  # other, and because candidate validation is an error-line diff, keeping
  # the cap here would make the sixth context-free backlog add refuse.
  if (lens == "knowledge" && nother > OTHER_MAX)
    err("other holds " nother " live records (max " OTHER_MAX "); refile each via supersession into a real area")
  if (lens == "backlog" && nmarked > MARKED_MAX)
    warn(nmarked " marked ideas (soft max " MARKED_MAX "). The marked lane is pushed into every session digest and never decays — promote what is starting, unmark what is not.")
  # a warning, not an error: guardrails are a judgement call and blocking the
  # compile over one would be worse than the inflation it guards against
  if (nguard > GUARDRAIL_MAX)
    warn(nguard " live guardrails (soft max " GUARDRAIL_MAX "). Guardrails bypass the digest budget and never decay, so inflation silently grows every session. Reclassify the weakest to useful, or supersede/tombstone what no longer applies.")

  # ---- journal: watermarks, elevations, the undigested set, due-logic ----
  # Every class resolves by VALUE: the effective watermark per pass is the
  # MAX reviewed-through among unretired claims (two concurrent claims are
  # both true and the larger simply covers more - merge-safe, and never id
  # order, which is not chronology); the effective elevation per kind and
  # period is the newest unretired one.
  if (lens == "journal") {
    # What a claim covers is the entries it NAMED (covered:), not everything
    # older than its date: an entry written or merged later, dated before
    # the boundary, existed for nobody to review when the claim was made,
    # and absorbing it would retire it unread with no rerun to bring it
    # back. A claim carrying no covered: list is the blunt hand-written
    # form and keeps date coverage - it is a human asserting the range.
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if (!(id in wmlive)) continue
      p = (rpass[id] == "") ? "triage" : rpass[id]
      if (!(p in wmmax) || rrt[id] > wmmax[p]) { wmmax[p] = rrt[id]; wmid[p] = id }
      if (!(p in wmseen)) { wmseen[p] = 1; wmpass[++nwmpass] = p }
      # An EXACT claim is one that carries the key at all, empty included:
      # "I reviewed these" and "I reviewed nothing new" are both statements
      # of identity. Only a claim with no covered: key is the blunt
      # hand-written date form, and settle always writes the key - a settle
      # that covered nothing must not silently degrade into a date claim
      # that absorbs whatever merges in later.
      if (id in hascovd) {
        if (cover_list_ok(id, rcovd[id], "", rrt[id])) {
          cn = split(rcovd[id], cvg, ",")
          for (ci = 1; ci <= cn; ci++) {
            cvt = trim(cvg[ci])
            if (cvt != "") cov[p SUBSEP cvt] = 1
          }
        }
      } else if (!(p in dateonly) || rrt[id] > dateonly[p]) dateonly[p] = rrt[id]
    }
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if (!(id in elive)) continue
      ek = rdig[id] SUBSEP rcov[id]
      # A correction supersedes, which kills the predecessor outright - so
      # two elevations BOTH live for one kind and period are competing
      # claims, not a revision. Ids lead with the creation date, so the pick
      # is newest-day-wins and deterministic; within one day it comes down
      # to the random suffix, which is not chronology. That case is
      # surfaced (below and in the lens) instead of being decided quietly.
      if (!(ek in eseen)) {
        eseen[ek] = 1; eorder[++nek] = ek
        ekind[ek] = rdig[id]; eper[ek] = rcov[id]
      }
      ecount[ek]++
      if (!(ek in effel) || id > effel[ek]) effel[ek] = id
      if (!(rdig[id] in kindseen)) { kindseen[rdig[id]] = 1; kinds[++nkinds] = rdig[id] }
      if (!(rdig[id] in kmax) || rcov[id] > kmax[rdig[id]]) kmax[rdig[id]] = rcov[id]
    }
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if (!(id in elive)) continue
      if (effel[rdig[id] SUBSEP rcov[id]] != id) continue
      if (length(rcov[id]) == 7) elevmonth[rcov[id]] = elevmonth[rcov[id]] ((elevmonth[rcov[id]] == "") ? "" : ", ") rdig[id]
      else elevyear[rcov[id]] = elevyear[rcov[id]] ((elevyear[rcov[id]] == "") ? "" : ", ") rdig[id]
      # An elevation is a snapshot of a period, and the year view renders
      # it INSTEAD of that period - so an entry the snapshot never saw
      # would be invisible there for good. It names what it saw (covered:),
      # exactly as a watermark does; an entry of the period outside that
      # list makes the elevation stale, and stale means due again. A
      # hand-written elevation naming nothing falls back to the only
      # evidence left, its own date.
      # Three states, not two: an EXACT list (applied), an exact list that
      # does not hold up (exact and EMPTY - a void claim covers nothing,
      # so every entry of the period is uncovered), and no list at all
      # (the hand-written form, judged by the elevation date instead).
      delete ecov
      ecovok = (id in hascovd) ? 1 : 0
      if (ecovok && cover_list_ok(id, rcovd[id], rcov[id], "")) {
        cn = split(rcovd[id], cvg, ",")
        for (ci = 1; ci <= cn; ci++) {
          cvt = trim(cvg[ci])
          if (cvt != "") ecov[cvt] = 1
        }
      }
      for (j = 1; j <= nsort; j++) {
        jd = sorted[j]
        if (substr(rcreated[jd], 1, length(rcov[id])) != rcov[id]) continue
        if (ecovok) {
          if (!(jd in ecov)) {
            stale[rdig[id] SUBSEP rcov[id]]++
            unc[rdig[id] SUBSEP rcov[id], ++uncn[rdig[id] SUBSEP rcov[id]]] = jd
          }
        } else if (rcreated[jd] > rcreated[id]) {
          stale[rdig[id] SUBSEP rcov[id]]++
          unc[rdig[id] SUBSEP rcov[id], ++uncn[rdig[id] SUBSEP rcov[id]]] = jd
        }
      }
    }
    # undigested = created >= watermark, INCLUSIVE: fail-open, because
    # rereading a handful twice is harmless and an exclusive boundary would
    # skip same-day entries forever. Dormancy is irrelevant - the watermark,
    # not liveness, defines the review set; with no claim, everything is.
    nundig = 0; oldest = ""
    for (i = 1; i <= nsort; i++) {
      id = sorted[i]
      pseen[substr(rcreated[id], 1, 7)] = 1
      pseen[substr(rcreated[id], 1, 4)] = 1
      passesof[id] = jpasses(id)
      if (index(" " passesof[id] " ", " triage ") > 0) { reviewed[id] = 1; continue }
      nundig++
      if (oldest == "" || rcreated[id] < oldest) oldest = rcreated[id]
      # An entry created TODAY cannot be cleared by a claim made today: the
      # boundary is inclusive (fail-open), so a claim dated D leaves the
      # entries of D in the set until a later claim covers them. The due
      # decision counts only what a settle WOULD clear - nudging about
      # material no claim can cover asks for an action settle then refuses
      # ("not beyond the current watermark"), and the line never clears.
      if (rcreated[id] < today) {
        nclear++
        if (oldestclear == "" || rcreated[id] < oldestclear) oldestclear = rcreated[id]
      }
    }
    # Due-logic. Triage is due by count or by age. Elevation nudges are
    # OPT-IN BY PRACTICE per built-in kind: the first elevation of a kind
    # is the opt-in switch, due = the most recent completed period with
    # entries beyond the newest elevated one, and a due period more than
    # JOURNAL_LAPSE grains beyond it means the practice lapsed - silent.
    # Nudges serve an active practice; they never enforce one.
    duetri = (nclear >= JOURNAL_REVIEW_COUNT || (oldestclear != "" && civildays(today) - civildays(oldestclear) > JOURNAL_REVIEW_AGE))
    for (kk = 1; kk <= 2; kk++) {
      kind = (kk == 1) ? "monthly" : "yearly"
      if (!(kind in kindseen)) continue
      glen = (kind == "monthly") ? 7 : 4
      cur = substr(today, 1, glen)
      best = ""
      for (pm in pseen) {
        if (length(pm) != glen) continue
        if (pm >= cur) continue
        if (pm <= kmax[kind]) continue
        if (pm > best) best = pm
      }
      # a stale elevation is a period that needs elevating AGAIN, so it
      # counts as due even though it already has one
      if (best == "") {
        for (i = 1; i <= nek; i++) {
          if (ekind[eorder[i]] != kind) continue
          if (!((kind SUBSEP eper[eorder[i]]) in stale)) continue
          if (length(eper[eorder[i]]) != glen) continue
          if (eper[eorder[i]] >= cur) continue
          if (eper[eorder[i]] > best) best = eper[eorder[i]]
        }
        if (best == "") continue
        duekind[++ndue] = kind; dueper[ndue] = best
        continue
      }
      if (grain_dist(kmax[kind], best) > JOURNAL_LAPSE) continue
      duekind[++ndue] = kind; dueper[ndue] = best
    }
  }

  if (check == 1) {
    close("cat 1>&2")
    exit (nerr > 0 ? 1 : 0)
  }

  if (export == 1) {
    jexport()
    close("cat 1>&2")
    # The seam carries the same verdict the lens would: a quarantined or
    # dangling record means these rows are SHORT, and an application reading
    # them cannot see the ## Degraded section that would say so. (nquar is
    # computed further down, on the rendering path this exit precedes.)
    exit ((nbad + ndup > 0 || ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) ? 2 : 0)
  }

  if (listlive == 1) {
    # id <TAB> primary-scope <TAB> all-tags(comma-joined) <TAB> headline.
    # The primary is the display home; ALL tags are emitted so a browse by
    # --scope can match a secondary "selection door", not only the primary.
    for (i = 1; i <= nsort; i++) {
      id = sorted[i]
      alltags = ""
      for (t = 1; t <= tagn[id]; t++)
        alltags = alltags (alltags == "" ? "" : ",") tagsc[id, t]
      if (alltags == "") alltags = "-"
      # TAB-sanitized like every other machine surface here: a headline may
      # legally contain one, and a consumer splitting on TAB would lose
      # everything after it (or read a scope into the wrong column).
      lvs = (pscope[id] == "" ? "-" : pscope[id]); gsub(/\t/, " ", lvs)
      gsub(/\t/, " ", alltags)
      lvh = headline(id); gsub(/\t/, " ", lvh)
      printf "%s\t%s\t%s\t%s\n", id, lvs, alltags, lvh
    }
    close("cat 1>&2")
    exit 0
  }

  # The applied graph, one row per non-quarantined record: id, union-find
  # group label, liveness, type, applied supersede targets (comma-joined,
  # "-" when none). Consumers that must reason about ancestry — backlog
  # promote deciding whether a plan origin belongs to the chain it is about
  # to retire — read THIS instead of re-deriving relatedness from filenames
  # or slugs: the compiler owns the edges, and a slug is not proof of
  # identity.
  if (listgraph == 1) {
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if ((id in erased) || (id in bad)) continue
      printf "%s\t%s\t%d\t%s\t%s\n", id, group(id), (id in live) ? 1 : 0, rtype[id], (asup[id] == "" ? "-" : asup[id])
    }
    close("cat 1>&2")
    exit 0
  }

  # The active (counted) votes records, for the plan<->ledger cross-check. One
  # line per votes record that actually affects ranking: id <TAB> plan <TAB> up
  # <TAB> down. This is the compilers own graph verdict — the cross-check reads
  # it instead of reconstructing "which votes record is superseded" from the
  # filesystem (a substring-fragile, path-unsafe approximation). Superseded and
  # non-canonical duplicates are excluded here exactly as they are from counting.
  if (listvotes == 1) {
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if ((id in erased) || (id in bad)) continue
      if (rtype[id] != "votes" || (id in dead)) continue
      if (rplan[id] != "" && canonvote[rplan[id]] != id) continue
      # normalized lists, never the raw frontmatter value: a TAB is legal
      # whitespace inside a vote list ("up: a,<TAB>b" passes the record
      # contract) but would split into an extra TSV column here, shifting
      # id-b into the down field for any consumer.
      printf "%s\t%s\t%s\t%s\n", id, rplan[id], norm_list(rup[id]), norm_list(rdown[id])
    }
    close("cat 1>&2")
    exit 0
  }

  # 3b. inert components: everything `memory archive` is allowed to move.
  #     A component may go only when NOTHING in it still affects the digest.
  #     Votes aggregate over the whole ancestor chain of a record, so a
  #     dead ancestor of a live head is NOT inert: moving it out of scan
  #     scope would silently drop the vote signal of its descendants and
  #     dangle their supersedes: target. Live votes records are equally
  #     load-bearing.
  if (listinert == 1) {
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if ((id in erased) || (id in bad)) continue
      g = group(id)
      if (rtype[id] == "memory" && (id in live)) keepgrp[g] = 1
      else if (rtype[id] == "votes" && !(id in dead)) keepgrp[g] = 1
      # journal: an unretired elevation or watermark is load-bearing
      else if ((id in elive) || (id in wmlive)) keepgrp[g] = 1
      # An erasure record is load-bearing forever: it is the only thing
      # keeping redacted content out of the digest, and the archive tree is
      # read for names and edges, never for erases:. Moving one therefore
      # un-redacts what it was written to suppress. It is never inert, no
      # matter what else its component holds.
      else if (rtype[id] == "erasure") keepgrp[g] = 1
    }
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if ((id in erased) || (id in bad)) continue
      if (group(id) in keepgrp) continue
      print filepath[id]
    }
    close("cat 1>&2")
    exit 0
  }

  # 4. digest — Digests (full blocks, DIGEST_MAX) + Headlines (one line,
  #    HEADLINE_MAX). Background bodies never enter the digest file.
  nquar = nbad + ndup

  # Zero live records with quarantined files present is indistinguishable
  # from an uninitialized ledger once written to disk — and the session-start
  # ritual answers an empty digest by offering initialization. Refuse to
  # publish instead (exit 3); the caller keeps the previous digest.
  # In the journal, entries are only one of three live classes: a tree
  # holding coverage records and one malformed file is not an unreadable
  # ledger, and refusing to publish it left every read printing nothing at
  # all while export happily returned the survivors.
  nlivecls = nlive + ((lens == "journal") ? nelev + nwm : 0)
  if (nlivecls == 0 && nquar > 0) {
    err("0 live records but " nquar " quarantined: refusing to publish (ledger is unreadable, not empty)")
    close("cat 1>&2")
    exit 3
  }

  # ---- journal lens rendering ----
  # A TIMELINE, not a ranking: months newest first, entries newest first
  # within a month (time: is the intra-day key), headline-only with +bg.
  # Dormant entries collapse to per-month counts (--all expands them);
  # elevations and watermarks stay out of the entry listing - the month
  # headings mark elevations and the header line carries the coverage.
  if (lens == "journal") {
    printf "# ZAMM Journal (%s: files=%d parsed=%d entries=%d undigested=%d elevations=%d watermarks=%d quarantined=%d; generated file - do not edit)\n", today, nfiles, nrec - nbad, nlive, nundig, nelev, nwm, nquar
    print ""
    if (nlive == 0 && nelev == 0 && nwm == 0) {
      print "(no journal entries)"
      if (ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) {
        print ""
        emit_degraded()
      }
      emit_state()
      close("cat 1>&2")
      exit ((ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) ? 2 : 0)
    }
    print "Entry format: - DD  headline [record-id +bg]; newest first, one section per month."
    print "Episodes, not facts: open the record (+bg) for depth. Digestion: journal review"
    print "(triage), journal digest <YYYY[-MM]> (compiled view), journal elevate <kind> <period>."
    print ""
    emit_degraded()
    if ("triage" in wmmax) printf "Reviewed through %s; %d undigested.\n", wmmax["triage"], nundig
    else printf "Never reviewed; %d undigested.\n", nundig
    for (i = 1; i <= nwmpass; i++)
      if (wmpass[i] != "triage") printf "Pass %s: reviewed through %s.\n", wmpass[i], wmmax[wmpass[i]]
    s = jlabels(elevyear, noskip)
    if (s != "") print "Elevated years: " s
    s = ""
    for (i = 1; i <= nek; i++) {
      if (ecount[eorder[i]] < 2) continue
      s = s ((s == "") ? "" : ", ") ekind[eorder[i]] " " eper[eorder[i]] " (" ecount[eorder[i]] " live, showing " effel[eorder[i]] ")"
    }
    if (s != "")
      print "Competing elevations - supersede one to decide it: " s
    s = ""
    for (i = 1; i <= nek; i++) {
      if (!(eorder[i] in stale)) continue
      s = s ((s == "") ? "" : ", ") ekind[eorder[i]] " " eper[eorder[i]] " (" stale[eorder[i]] " uncovered)"
    }
    if (s != "")
      print "Stale elevations - entries they never saw, elevate again: " s
    n = 0
    for (i = 1; i <= nsort; i++) {
      id = sorted[i]
      jarr[++n] = id
      jkey[id] = rcreated[id] "\t" rtime[id] "\t" id
    }
    jheapsort(n)
    curm = ""; ndorm = 0; nda = 0
    for (i = 1; i <= n; i++) {
      id = jarr[i]
      pm = substr(rcreated[id], 1, 7)
      if (id in dormant) {
        if (!(pm in dcount)) dareas[++nda] = pm
        dcount[pm]++; ndorm++
        continue
      }
      if (pm != curm) {
        curm = pm
        shownmonth[pm] = 1
        print ""
        if (pm in elevmonth) print "## " pm " - elevated: " elevmonth[pm]
        else print "## " pm
      }
      print "- " substr(rcreated[id], 9, 2) "  " headline(id) " " pointer(id)
      printed[id] = 1
    }
    nunlist = 0
    # an elevated month whose entries have all gone dormant has no section
    # to carry its marker; the elevation is still the coverage, so say so
    s = jlabels(elevmonth, shownmonth)
    if (s != "") {
      print ""
      print "Elevated months with no listed entries: " s
    }
    if (ndorm > 0) {
      s = ""
      for (i = 1; i <= nda; i++) s = s ((i > 1) ? ", " : "") dareas[i] " x" dcount[dareas[i]]
      print ""
      print "(" ndorm " entries dormant: " s " - journal list --all)"
    }
    emit_state()
    close("cat 1>&2")
    exit ((nquar > 0 || ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) ? 2 : 0)
  }

  # ---- backlog lens rendering ----
  # The pulled counterpart of the digest below: UNCAPPED — every live,
  # non-dormant idea is listed as a headline, because this file is read by
  # someone who chose triage mode and a triage read wants the whole live
  # list. The dormant tail collapses to counts (decay is the only cap), and
  # the marked lane renders first, oldest commitment on top.
  if (lens == "backlog") {
    printf "# ZAMM Backlog (%s: files=%d parsed=%d live=%d hot=%d marked=%d quarantined=%d; generated file - do not edit)\n", today, nfiles, nrec - nbad, nlive, nhot, nmarked, nquar
    print ""
    if (nlive == 0) {
      print "(no ideas in the backlog)"
      if (ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) {
        print ""
        emit_degraded()
      }
      emit_state()
      close("cat 1>&2")
      exit ((ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) ? 2 : 0)
    }
    print "Entry format: - headline [record-id votes +bg]; ~ = variants (parallel forks)."
    print "Hot-to-cold within each area; hot = recently added or voted up. Read the"
    print "record (+bg) before working an idea; supersede or vote instead of duplicating."
    print ""
    emit_degraded()
    if (nmarked > 0) {
      print "## Marked (selected for implementation - promote when work starts)"
      print ""
      # oldest mark first: the longest-standing commitment is what a reader
      # should confront first. Selection sort over the small marked set —
      # bounded by MARKED_MAX in any healthy ledger.
      nmk = 0
      for (i = 1; i <= nsort; i++)
        if (sorted[i] in markedof) mklist[++nmk] = sorted[i]
      for (i = 1; i <= nmk; i++) {
        best = i
        for (j = i + 1; j <= nmk; j++) {
          if (markedof[mklist[j]] < markedof[mklist[best]] ||
              (markedof[mklist[j]] == markedof[mklist[best]] && mklist[j] < mklist[best]))
            best = j
        }
        tmpm = mklist[i]; mklist[i] = mklist[best]; mklist[best] = tmpm
        id = mklist[i]
        print "- " headline(id) " " pointer(id) " (marked " markedof[id] ")"
        printed[id] = 1
      }
      if (nmarked > MARKED_MAX)
        print "(" nmarked " marked exceeds the soft cap " MARKED_MAX " - promote or unmark)"
      print ""
    }
    # Areas ordered by their hottest member; INSIDE an area, entries
    # cluster by full primary scope — same-subpath siblings sit together
    # instead of interleaving by rank across the whole area (first user
    # feedback: same-day lobby ideas scattered between art and cameras
    # read as ungrouped). Clusters order by their hottest member, rank
    # order within; bare-area entries are their own cluster. The heading
    # carries the live counts with the subpath breakdown — the statistics
    # surface the user asked for, keyed off the primary tag (secondaries
    # are bare areas by contract, so the breakdown is well defined).
    hdr = 0
    for (i = 1; i <= nsort; i++) {
      id = sorted[i]
      if ((id in printed) || (id in dormant)) continue
      a = area(id)
      if (a in areadone) continue
      areadone[a] = 1
      if (!hdr) { print "## Ideas (hot to cold)"; hdr = 1 }
      # counting pass: block total plus per-subpath counts, subpaths in
      # hottest-member order (the same order the render pass will use)
      atot = 0; nsp = 0
      for (j = i; j <= nsort; j++) {
        jd = sorted[j]
        if ((jd in printed) || (jd in dormant)) continue
        if (area(jd) != a) continue
        atot++
        p = pscope[jd]
        if (p == a) continue
        if (!((a SUBSEP p) in spc)) splist[++nsp] = p
        spc[a SUBSEP p]++
      }
      hline = "### " ((a == "") ? "(no scope)" : a) " (" atot
      if (nsp > 0) {
        hline = hline ":"
        for (s = 1; s <= nsp; s++)
          hline = hline ((s > 1) ? "," : "") " " substr(splist[s], length(a) + 2) " " spc[a SUBSEP splist[s]]
      }
      print ""
      print hline ")"
      # render pass: one adjacent run per primary scope
      for (j = i; j <= nsort; j++) {
        jd = sorted[j]
        if ((jd in printed) || (jd in dormant)) continue
        if (area(jd) != a) continue
        p = pscope[jd]
        for (k = j; k <= nsort; k++) {
          kd = sorted[k]
          if ((kd in printed) || (kd in dormant)) continue
          if (area(kd) != a || pscope[kd] != p) continue
          # the scope prefix only earns its ink when it adds a subpath
          # the section heading does not already say
          emitline(kd, (p != a) ? 1 : 0)
        }
      }
    }
    nunlist = 0
    ndorm = 0; nda = 0
    for (i = 1; i <= nsort; i++) {
      id = sorted[i]
      if ((id in printed) || !(id in dormant)) continue
      a = area(id)
      if (!(a in dcount)) dareas[++nda] = a
      dcount[a]++
      ndorm++
    }
    if (ndorm > 0) {
      s = ""
      for (i = 1; i <= nda; i++)
        s = s ((i > 1) ? ", " : "") dcount[dareas[i]] " " dareas[i]
      print ""
      print "Dormant (cooled below the floor; re-up by superseding or voting, or see backlog list --all): " s
    }
    emit_state()
    close("cat 1>&2")
    exit ((nquar > 0 || ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) ? 2 : 0)
  }

  printf "# ZAMM Memory Digest (%s: files=%d parsed=%d live=%d quarantined=%d; generated file - do not edit)\n", today, nfiles, nrec - nbad, nlive, nquar
  print ""

  if (nlive == 0) {
    print "(no live memory records - active memory has not been initialized; ask the human before initializing, never write placeholder records)"
    # Zero live records does NOT mean zero problems: a ledger holding only a
    # votes record with a ghost target, or duplicate votes records, reaches
    # here (such records are not "live memory", and with nquar == 0 the
    # refuse-to-publish branch above did not fire). Exiting 0 with a clean
    # "not initialized" digest would hide known graph defects and invite
    # re-seeding, so render ## Degraded and exit 2 like the normal path.
    if (ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) {
      print ""
      emit_degraded()
    }
    emit_state()
    close("cat 1>&2")
    exit ((ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) ? 2 : 0)
  }

  print "Entry format: - headline [record-id votes +bg]; indented lines = elaboration."
  print "Digest section: up to " DIGEST_MAX " actionable full blocks (! = guardrail, do not violate;"
  print "~ = contested head, also listed under Needs reconciliation)."
  print "Headlines section: up to " HEADLINE_MAX " one-line reminders that knowledge exists;"
  print "open the record (+bg) when the topic matches. Id doubles as creation date."
  print "Session read: `memory digest` recompiles and prints this text - one run"
  print "per session is the whole read; do not open the compiled file as well."
  print ""

  # Degraded: ledger integrity problems surfaced in the digest itself, so a
  # broken ledger reads as broken rather than as missing memory. Any kind
  # makes the compile exit 2 (degraded), never a healthy-looking 0.
  emit_degraded()

  if (nother > 0) {
    print "Other: " nother " record(s) in the catch-all area - refile each via"
    print "supersession into a real area when touched."
    print ""
  }

  # One bucketing pass instead of rescanning every record per conflict group:
  # members keep rank order because sorted[] is walked in order.
  nconf = 0
  for (i = 1; i <= nsort; i++) {
    r = group(sorted[i])
    if (livecnt[r] < 2) continue
    nconf++
    gmembers[r, ++gcount[r]] = sorted[i]
    if (gcount[r] == 1) grouplist[++ngroups] = r
  }
  if (nconf > 0) {
    print "## Needs reconciliation (resolve this session)"
    print ""
    print "Per group: read the competing record files, then write ONE new record whose"
    print "supersedes: line lists ALL competing ids. Never edit or delete the files."
    print "This is an index — each head keeps its full block below, marked ~."
    print ""
    for (i = 1; i <= ngroups; i++) {
      r = grouplist[i]
      print "### Heads of " r
      for (j = 1; j <= gcount[r]; j++) emitline(gmembers[r, j], 1, 1)
      print ""
    }
  }

  # Digest selection (full blocks): guardrails first (never squeezed out of
  # the actionable layer), then greedy by
  # log(score) - GROUP_PENALTY x taken(least-crowded tag area) - TAG_COST x
  # (tags - 1) up to DIGEST_MAX — weighted ranking vs per-area diversity.
  # Headlines: next HEADLINE_MAX live records by score as one-line reminders.
  # Anything beyond Digests+Headlines stays live in the ledger but unlisted.
  print "## Digest (actionable; full blocks)"
  ncore = 0
  for (i = 1; i <= nsort; i++) {
    id = sorted[i]
    if ((id in printed) || (id in dormant)) continue
    if (rimp[id] == "guardrail") {
      coretaken[id] = 1
      corelist[++ncore] = id
      takeseats(id)
    }
  }
  while (ncore < DIGEST_MAX) {
    best = ""
    besteff = 0
    for (i = 1; i <= nsort; i++) {
      id = sorted[i]
      if ((id in printed) || (id in coretaken) || (id in dormant)) continue
      # sorted[] is score-descending and both penalties are >= 0, so
      # eff <= log(score) for every record from here on: once log(score) drops
      # to besteff nothing later can beat it. Turns a full rescan per seat
      # into a short window scan without changing the winner.
      if (best != "" && log(sc[id]) <= besteff) break
      eff = log(sc[id]) - GROUP_PENALTY * mintaken(id) - tagcost(id)
      if (best == "" || eff > besteff) { best = id; besteff = eff }
    }
    if (best == "") break
    coretaken[best] = 1
    corelist[++ncore] = best
    takeseats(best)
  }
  for (i = 1; i <= ncore; i++) {
    id = corelist[i]
    if (id in printed) continue
    scp = pscope[id]
    if (!endedblank) print ""
    print "### " ((scp == "") ? "(no scope)" : scp)
    endedblank = 0
    for (j = i; j <= ncore; j++) {
      if (pscope[corelist[j]] == scp && !(corelist[j] in printed))
        emitfull(corelist[j], 0)
    }
  }

  # Headlines: ranked reminders for the next HEADLINE_MAX not already Digested
  nhl = 0; hdr = 0
  for (i = 1; i <= nsort; i++) {
    id = sorted[i]
    if ((id in printed) || (id in dormant)) continue
    if (nhl >= HEADLINE_MAX) break
    if (!hdr) {
      if (!endedblank) print ""
      print "## Headlines (reminders; open the record when the topic matches)"
      hdr = 1; endedblank = 0
    }
    emitline(id, 1)
    nhl++
  }

  # Live but below Digests+Headlines budget: counted, not listed
  nunlist = 0
  for (i = 1; i <= nsort; i++) {
    id = sorted[i]
    if ((id in printed) || (id in dormant)) continue
    nunlist++
  }
  if (nunlist > 0) {
    if (!endedblank) print ""
    print "Unlisted live (below Digests+Headlines budget; ledger stays greppable): " nunlist
    endedblank = 0
  }

  # dormant records: decayed below FLOOR; counted per area, never listed
  ndorm = 0; nda = 0
  for (i = 1; i <= nsort; i++) {
    id = sorted[i]
    if ((id in printed) || !(id in dormant)) continue
    a = area(id)
    if (!(a in dcount)) dareas[++nda] = a
    dcount[a]++
    ndorm++
  }
  if (ndorm > 0) {
    s = ""
    for (i = 1; i <= nda; i++)
      s = s ((i > 1) ? ", " : "") dcount[dareas[i]] " " dareas[i]
    if (!endedblank) print ""
    print "Dormant (decayed below digest floor; ledger stays greppable): " s
  }

  emit_state()
  close("cat 1>&2")
  # exit 2 = the digest was published but a ## Degraded section is present
  # (quarantined records, dangling references, duplicate vote records, or
  # invalid vote references). A caller can tell a clean digest from a degraded
  # one by the code alone, without parsing the Markdown.
  exit ((nquar > 0 || ndangling > 0 || ndupvote > 0 || nbadvoteref > 0 || nbadcover > 0) ? 2 : 0)
}
' "$MANIFEST" > "$TMP_FILE"
rc=$?
set -e

# ---- Plans tail: one compact 2-3 line entry per active plan (status line,
#      title, optional inline scope), derived at compile time (no maintained
#      index files; zamm-status.sh stays the on-demand verbose view)
append_plans_section() {
  # The plan tree enters the digest ONLY through the checked manifest: a glob
  # here followed symlinked directories into external content and read an
  # unreadable tree as "no active plans". Enumeration failure aborts before
  # the digest is published (exit 4, previous digest untouched).
  pmf="$TMP_FILE.pmf"
  if ! sh "$PLAN_MANIFEST" --project-root "$PROJECT_ROOT" > "$pmf"; then
    echo "ERROR: could not enumerate the plan tree; plans are unreadable, not empty." >&2
    echo "       Previous digest left untouched." >&2
    exit 4
  fi
  tab=$(printf '\t')
  # A missing plan root is structural damage, never a healthy zero-plan
  # project: scaffold always creates both roots. Abort before the digest is
  # renamed into place — same taxonomy as an unreadable tree.
  if grep -q "^MISSING${tab}" "$pmf"; then
    grep "^MISSING${tab}" "$pmf" | while IFS="$tab" read -r _ mroot; do
      echo "ERROR: plan root missing: ${mroot#"$PROJECT_ROOT/"} -- structural damage, not an empty project." >&2
    done
    echo "       Restore it ('zamm-run.sh scaffold' recreates the directory), then investigate." >&2
    echo "       Previous digest left untouched." >&2
    exit 4
  fi
  active_prefix="$PROJECT_ROOT/zamm-memory/active/plans/"
  plans_tmp="$PLANS_TMP"
  : > "$plans_tmp"
  # Structural anomalies render as one-liners derived from the entry NAME
  # alone — tagged content is never opened, so a symlinked directory cannot
  # inject external text into the digest.
  while IFS="$tab" read -r tag p1 p2 p3; do
    base=${p1##*/}
    case "$tag" in
      DEBRIS)
        case "$p1" in "$active_prefix"*)
          printf '6\t- Invalid: %s (stray temporary directory inside a plan; raced or interrupted plan create)\n' "$base" >> "$plans_tmp" ;;
        esac ;;
      SYMLINK)
        case "$p1" in "$active_prefix"*)
          printf '6\t- Invalid: %s (symlinked entry; not rendered)\n' "$base" >> "$plans_tmp" ;;
        esac ;;
      NOTDIR)
        case "$p1" in "$active_prefix"*)
          printf '6\t- Invalid: %s (not a plan directory)\n' "$base" >> "$plans_tmp" ;;
        esac ;;
      UNREADABLE)
        case "$p1" in "$active_prefix"*)
          printf '6\t- Unknown: %s (unreadable .plan.md)\n' "$base" >> "$plans_tmp" ;;
        esac ;;
      DUP)
        printf '6\t- Invalid: %s (same plan id active and archived)\n' "$p1" >> "$plans_tmp" ;;
    esac
  done < "$pmf"
  while IFS= read -r pd; do
    [ -n "$pd" ] || continue
    slug=$(basename "$pd")
    # prefer <slug>.plan.md, else the first main candidate the manifest lists
    pf=$(awk -F"$tab" -v want="$pd/$slug.plan.md" '$1 == "PLANFILE" && $2 == want { print $2; exit }' "$pmf")
    [ -n "$pf" ] ||
      pf=$(awk -F"$tab" -v d="$pd/" '$1 == "PLANFILE" && index($2, d) == 1 { print $2; exit }' "$pmf")
    if [ -z "$pf" ]; then
      # an unreadable main candidate already rendered above; only a dir with
      # genuinely no candidate reports "no .plan.md file"
      nun=$(awk -F"$tab" -v d="$pd/" '$1 == "UNREADABLE" && index($2, d) == 1 { n++ } END { print n + 0 }' "$pmf")
      [ "$nun" -eq 0 ] && printf '6\t- Unknown: %s (no .plan.md file)\n' "$slug" >> "$plans_tmp"
      continue
    fi
    awk -v slug="$slug" '
      function trimv(s) { sub(/\r$/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      # normalize the LINE too, not just the values read out of it: the
      # section headings below are compared exactly, so a CRLF plan silently
      # counted no Done-when items at all
      { sub(/\r$/, "") }
      st == "" && /^Status:/              { st = $0; sub(/^Status:/, "", st); st = trimv(st) }
      cf == "" && /^Complexity-forecast:/ { cf = $0; sub(/^Complexity-forecast:/, "", cf); cf = trimv(cf) }
      lu == "" && /^Last updated:/        { lu = $0; sub(/^Last updated:/, "", lu); lu = trimv(lu) }
      ti == "" && /^# /                   { ti = $0; sub(/^# /, "", ti); ti = trimv(ti) }
      si == "" && /^\* In:/               { si = $0; sub(/^\* In:/, "", si); si = trimv(si) }
      # exact heading, not a prefix: "## Done-when-not" is a different section
      $0 == "## Done-when" || $0 ~ /^## Done-when[ \t]/ { dw = 1; next }
      /^## /          { dw = 0 }
      dw && /^- \[ \]/    { nopen++ }
      dw && /^- \[[xX]\]/ { ndone++ }
      END {
        # rank by the leading status word; annotated statuses keep their label
        rank = 6; label = st
        if (st ~ /^Review/)            rank = 1
        else if (st ~ /^Implementing/) rank = 2
        else if (st ~ /^Draft/)        rank = 3
        else if (st ~ /^Done/)         { rank = 4; label = st " (archive-ready)" }
        else if (st ~ /^Abandoned/)    { rank = 5; label = st " (archive-ready)" }
        else if (st == "")             label = "Unknown"
        line = "- " label ": " slug
        if (cf != "" && cf !~ /^</) {
          if (length(cf) > 32) cf = substr(cf, 1, 29) "..."
          line = line " [" cf "]"
        }
        tot = nopen + ndone + 0
        if (tot > 0) line = line " done-when " ndone + 0 "/" tot ","
        if (lu != "" && lu !~ /^</) {
          split(lu, luw, /[ \t]/)
          line = line " last " luw[1]
        }
        sub(/,$/, "", line)
        out = rank "\t" line
        if (ti != "" && ti !~ /^</) {
          if (length(ti) > 100) ti = substr(ti, 1, 97) "..."
          out = out "\t" ti
        }
        if (si != "" && si !~ /^</) {
          if (length(si) > 100) si = substr(si, 1, 97) "..."
          out = out "\tin: " si
        }
        print out
      }
    ' "$pf" >> "$plans_tmp"
  done <<EOF
$(awk -F"$tab" '$1 == "PLANDIR" { print $2 }' "$pmf")
EOF
  {
    printf '\n## Plans (active; compact entries)\n\n'
    if [ -s "$plans_tmp" ]; then
      sort -n "$plans_tmp" | awk -F'\t' '{
        print $2
        for (i = 3; i <= NF; i++) print "  " $i
        print ""
      }'
    else
      echo "(no active plans)"
      echo ""
    fi
  } >> "$TMP_FILE"
  rm -f "$plans_tmp"

  # Recently archived plan IDs: after a pull, a referenced plan directory may
  # have moved to archive on another machine — this list keeps the move
  # visible. Directory mtime sorts fresh arrivals (checkout/closure) first.
  narch=$(awk -F"$tab" '$1 == "ARCHDIR" { n++ } END { print n + 0 }' "$pmf")
  if [ "$narch" -gt 0 ]; then
    {
      if [ "$narch" -gt 10 ]; then
        echo "Recently archived (newest 10 of $narch; full list: zamm-memory/archive/plans/):"
      else
        echo "Recently archived ($narch; in zamm-memory/archive/plans/):"
      fi
      awk -F"$tab" '$1 == "ARCHDIR" { print $2 }' "$pmf" | while IFS= read -r ad; do
        m=$(stat -f %m "$ad" 2>/dev/null || stat -c %Y "$ad" 2>/dev/null || echo 0)
        printf '%s\t%s\n' "$m" "${ad##*/}"
      done | sort -t "$tab" -k1,1rn -k2,2 | head -n 10 | while IFS="$tab" read -r _m nm; do
        echo "- $nm"
      done
    } >> "$TMP_FILE"
  fi
  rm -f "$pmf"
}

# ---- Backlog summary: one pushed line (plus the small marked lane) is the
#      knowledge digest's ENTIRE standing exposure to the backlog. The
#      backlog tree compiles through a full recursive pass of this same
#      script, so the counts come from the same validation and graph the
#      lens itself publishes — never from a shortcut re-parse. Absent tree:
#      no line at all (absence is data; the feature is simply unused).
append_backlog_summary() {
  [ -d "$PROJECT_ROOT/zamm-memory/backlog" ] || return 0
  brc=0
  sh "$0" --project-root "$PROJECT_ROOT" --tree backlog >/dev/null || brc=$?
  # 2 = degraded lens, 3 = nothing live survived: both published-or-refused
  # states the operator must hear about, but neither may hide the knowledge
  # digest — the line carries the degradation and the overall exit becomes 2.
  # Anything else non-zero is an unreadable backlog tree (G3): the digest
  # compile fails whole, previous digest untouched.
  if [ "$brc" -eq 2 ] || [ "$brc" -eq 3 ]; then
    {
      echo ""
      echo "Backlog: DEGRADED - run: zamm-run.sh backlog check"
    } >> "$TMP_FILE"
    BACKLOG_DEGRADED=1
    return 0
  fi
  if [ "$brc" -ne 0 ]; then
    echo "ERROR: the backlog tree did not compile (rc=$brc); previous digest left untouched." >&2
    exit 4
  fi
  bstate="$OUT_DIR/backlog-state.tsv"
  if [ ! -f "$bstate" ]; then
    echo "ERROR: the backlog pass reported success but left no backlog-state.tsv; previous digest left untouched." >&2
    exit 4
  fi
  tab=$(printf '\t')
  blive=$(awk -F"$tab" '$1 == "live"   { print $2; exit }' "$bstate")
  bhot=$(awk  -F"$tab" '$1 == "hot"    { print $2; exit }' "$bstate")
  bmark=$(awk -F"$tab" '$1 == "marked" { print $2; exit }' "$bstate")
  {
    # The marked lane renders BEFORE the one-liner: it is the only backlog
    # content that earned a pushed seat, and it nags oldest-first until
    # someone promotes or unmarks. Zero marked = no section and no ", 0
    # marked" noise on the line.
    if [ "${bmark:-0}" -gt 0 ]; then
      echo ""
      echo "## Marked backlog (implement or unmark)"
      echo ""
      grep "^mselect${tab}" "$bstate" | sort -t "$tab" -k2,2 -k3,3 |
        while IFS="$tab" read -r _ mdate mid mhl; do
          echo "- $mhl [$mid] (marked $mdate)"
        done
      if grep -q "^marked_over${tab}" "$bstate"; then
        echo "(over the soft cap - promote what is starting, unmark what is not)"
      fi
    fi
    echo ""
    if [ "${bmark:-0}" -gt 0 ]; then
      echo "Backlog: ${blive:-0} live (${bhot:-0} hot, ${bmark} marked) - zamm-run.sh backlog list"
    else
      echo "Backlog: ${blive:-0} live (${bhot:-0} hot) - zamm-run.sh backlog list"
    fi
  } >> "$TMP_FILE"
}

# ---- Journal line: the knowledge digest's ENTIRE standing exposure to the
#      journal is one line, present only when digestion is due (triage by
#      count or age; a practiced elevation kind with a completed period
#      unelevated) or when the journal pass is degraded. Absent or quiet
#      tree: no line at all, byte-identical digest. Segments join in the
#      sidecar's fixed order and the line never wraps.
append_journal_line() {
  [ -d "$PROJECT_ROOT/zamm-memory/journal" ] || return 0
  jrc=0
  sh "$0" --project-root "$PROJECT_ROOT" --tree journal >/dev/null || jrc=$?
  if [ "$jrc" -eq 2 ] || [ "$jrc" -eq 3 ]; then
    {
      echo ""
      echo "Journal: DEGRADED - run: zamm-run.sh journal check"
    } >> "$TMP_FILE"
    JOURNAL_DEGRADED=1
    return 0
  fi
  if [ "$jrc" -ne 0 ]; then
    echo "ERROR: the journal tree did not compile (rc=$jrc); previous digest left untouched." >&2
    exit 4
  fi
  jstate="$OUT_DIR/journal-state.tsv"
  if [ ! -f "$jstate" ]; then
    echo "ERROR: the journal pass reported success but left no journal-state.tsv; previous digest left untouched." >&2
    exit 4
  fi
  tab=$(printf '\t')
  jline=$(awk -F"$tab" '
    $1 == "due_triage" { seg = "triage due (" $2 " undigested, oldest " $3 ")"; segs = segs ((segs == "") ? "" : "; ") seg }
    $1 == "due_elev"   { seg = $2 " due (" $3 ")"; segs = segs ((segs == "") ? "" : "; ") seg }
    END { if (segs != "") print "Journal: " segs " - zamm-run.sh journal review" }
  ' "$jstate")
  if [ -n "$jline" ]; then
    {
      echo ""
      echo "$jline"
    } >> "$TMP_FILE"
  fi
}

if [ "$CHECK" -eq 1 ]; then
  # name the tree in the verdict: `check` runs this once per record tree,
  # and two identical pass lines would leave the reader guessing which is which
  if [ "$TREE" = "backlog" ]; then
    checkname="ZAMM backlog check"
  elif [ "$TREE" = "journal" ]; then
    checkname="ZAMM journal check"
  else
    checkname="ZAMM check"
  fi
  if [ "$rc" -ne 0 ]; then
    echo "$checkname failed." >&2
    exit "$rc"
  fi
  echo "$checkname passed."
elif [ "$EXPORT" -eq 1 ]; then
  # The export seam is an APPLICATION contract, so unlike the internal list
  # modes below it propagates a degraded tree (exit 2): its consumer is a
  # program that cannot see the ## Degraded section, and rows silently
  # missing whatever was quarantined are exactly what it must not mistake
  # for the whole journal. Anything worse than degraded refuses outright.
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    echo "ERROR: the journal did not compile; refusing to export." >&2
    exit "$rc"
  fi
  cat "$TMP_FILE"
  exit "$rc"
elif [ "$LIST_INERT" -eq 1 ] || [ "$LIST_LIVE" -eq 1 ] || [ "$LIST_VOTES" -eq 1 ] || [ "$LIST_GRAPH" -eq 1 ]; then
  # read-only: the awk wrote the list rows to the private temp file, so
  # emit them and publish nothing. Exit 2 (a degraded but valid ledger) is not
  # a failure for a read-only listing; only a real failure (>2) refuses.
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    echo "ERROR: ledger did not compile; refusing to list records." >&2
    exit "$rc"
  fi
  cat "$TMP_FILE"
else
  # rc 3 = every record quarantined (nothing live survived validation).
  # Publishing an empty digest here would read as "memory not initialized"
  # and invite re-seeding over an intact-but-unreadable ledger, so the
  # previous digest is left in place and the failure is loud instead.
  if [ "$rc" -eq 3 ]; then
    echo "ERROR: refusing to publish a digest with 0 live records while the ledger holds quarantined records." >&2
    echo "       Fix the errors above, then recompile. Previous digest left untouched:" >&2
    if [ -f "$OUT_FILE" ]; then
      echo "       $OUT_FILE" >&2
    else
      echo "       (none existed)" >&2
    fi
    exit 3
  fi
  # rc 2 = degraded publish: the digest WAS built (with a ## Degraded section)
  # and must be published; the caller learns of the degradation from the exit
  # code, not from a missing digest. Any other non-zero code is a real failure
  # that leaves the previous digest untouched.
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    echo "ERROR: digest compilation failed; previous digest left untouched." >&2
    exit "$rc"
  fi
  if [ "$TREE" = "knowledge" ]; then
    append_plans_section
    append_backlog_summary
    append_journal_line
  fi
  # The digest and the sidecar are two separate renames that cannot be one
  # atomic step, and rename ORDER alone only chooses which mismatched pairing
  # survives a crash between them. So the pair carries a shared generation
  # token (a checksum of the digest content, stamped into both files), and
  # sidecar CONSUMERS verify it: on a mismatch they refuse with "recompile"
  # instead of mixing authorities (e.g. memory list serving a selection the
  # published digest never surfaced). Sidecar absence is tolerated (only
  # replaced when the awk produced one); the next compile re-derives both.
  gen=$(cksum < "$TMP_FILE" | tr -s ' \t' '-')
  printf '<!-- zamm-generation: %s -->\n' "$gen" >> "$TMP_FILE"
  if [ -f "$STATE_TMP" ]; then
    printf 'generation\t%s\n' "$gen" >> "$STATE_TMP"
    mv "$STATE_TMP" "$STATE_FILE"
  fi
  mv "$TMP_FILE" "$OUT_FILE"
  # A degraded backlog pass degrades the DIGEST run too: exit 2 must always
  # pair with a visible degradation notice in the published output, and the
  # published digest carries the "Backlog: DEGRADED" line.
  degnote="degraded - see ## Degraded"
  if [ "$rc" -eq 0 ] && [ "${BACKLOG_DEGRADED:-0}" -eq 1 ]; then
    rc=2
    degnote="degraded backlog - see the Backlog line"
  fi
  if [ "$rc" -eq 0 ] && [ "${JOURNAL_DEGRADED:-0}" -eq 1 ]; then
    rc=2
    degnote="degraded journal - see the Journal line"
  fi
  if [ "$TREE" = "backlog" ]; then
    outname="ZAMM backlog lens"
  elif [ "$TREE" = "journal" ]; then
    outname="ZAMM journal lens"
  else
    outname="ZAMM digest"
  fi
  if [ "$rc" -eq 2 ]; then
    echo "$outname: $OUT_FILE ($degnote)"
  else
    echo "$outname: $OUT_FILE"
  fi
  exit "$rc"
fi
