#!/bin/sh
# ZAMM compile — builds the gitignored memory digest from the append-only
# knowledge ledger. Deterministic, read-only over the ledger, safe to rerun.
# POSIX sh + POSIX awk only: runs on stock macOS, Linux, and git-bash.
#
# Usage: zamm-compile.sh [--project-root <path>] [--check]
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
    --check)
      CHECK=1
      shift
      ;;
    --list-inert)
      LIST_INERT=1
      shift
      ;;
    --list-live)
      LIST_LIVE=1
      shift
      ;;
    -h|--help)
      echo "Usage: zamm-compile.sh [--project-root <path>] [--check] [--list-live] [--list-inert]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

KNOWLEDGE_DIR="$PROJECT_ROOT/zamm-memory/knowledge"
OUT_DIR="$PROJECT_ROOT/zamm-memory/.compiled"
OUT_FILE="$OUT_DIR/memory.md"
# ZAMM_TODAY pins the clock (YYYY-MM-DD). Test-only: scoring decays over
# dates, so golden digests need a fixed today. Unset in normal use.
TODAY=${ZAMM_TODAY:-$(date +%Y-%m-%d)}

if [ ! -d "$KNOWLEDGE_DIR" ]; then
  echo "ERROR: missing $KNOWLEDGE_DIR (run zamm-scaffold.sh first)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

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
trap 'rm -f "$TMP_FILE" "$PLANS_TMP"' EXIT HUP INT TERM

set +e
{
  find "$KNOWLEDGE_DIR" -type f -name '*.md'
  # Symlinked records are invisible to `-type f`, so a symlink under knowledge/
  # would be silently skipped (unscanned, uncounted). Register them explicitly
  # so the compiler REJECTS them instead: the ledger holds real files only, no
  # symlinks (they invite loops and path escapes and hide records from --check).
  find "$KNOWLEDGE_DIR" -type l -name '*.md' | sed 's/^/SYMLINK\t/'
  # Archived ids, filename only. A record moved out by `memory archive` must
  # still resolve as a known-inert reference target rather than reading as a
  # dangling supersedes:, so its NAME is registered without parsing content.
  if [ -d "$PROJECT_ROOT/zamm-memory/archive/knowledge" ]; then
    find "$PROJECT_ROOT/zamm-memory/archive/knowledge" -type f -name '*.md' \
      | sed 's/^/ARCHIVED\t/'
  fi
} | sort | awk \
  -v today="$TODAY" -v check="$CHECK" -v listinert="$LIST_INERT" -v listlive="$LIST_LIVE" -v root="$PROJECT_ROOT/" '
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

  VALID_AREAS = " domain contracts conventions internals quality tooling ops meta "
  # every key the compiler acts on; anything else is a typo until proven
  # otherwise (x- prefix reserved for deliberate extensions)
  KNOWN_KEYS = " type scope supersedes created schema plan up down importance durability seed-up seed-dn migrated-from "
  nrec = 0; nerr = 0; nsort = 0; nother = 0
  nfiles = 0; nbad = 0; ndup = 0; nwarn = 0
}

# ---- input: one record file path per line ----
{
  if (index($0, "SYMLINK\t") == 1) {
    err(relpath(substr($0, 9)) ": symlinked record files are not allowed in the ledger (no symlinks)")
    next
  }
  if (index($0, "ARCHIVED\t") == 1) {
    n = split(substr($0, 10), pp, "/")
    aid = pp[n]; sub(/\.md$/, "", aid)
    archived[aid] = 1
    next
  }
  path = $0
  n = split(path, pp, "/")
  base = pp[n]
  if (base == "shun.md") { read_shun(path); next }
  read_record(path, base)
}

function read_shun(path,   line) {
  while ((getline line < path) > 0) {
    sub(/\r$/, "", line)
    sub(/#.*$/, "", line)
    line = trim(line)
    if (line != "") shun[line] = 1
  }
  close(path)
}

function read_record(path, base,   id, line, state, firstline, fmclosed, pos, key, val, lc, q, n2, ydir, t, a, hasother, fdate, frest, fsuf, fslug) {
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
  lc = tolower(base)
  if ((lc in casemap) && casemap[lc] != path)
    rerr(id, path ": case-fold collision with " casemap[lc])
  casemap[lc] = path
  if (id in filepath) {
    err(path ": duplicate record id " id)
    dupfile[++ndup] = path
    return
  }

  filepath[id] = path
  order[++nrec] = id
  rtype[id] = "memory"

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
        if (index(KNOWN_KEYS, " " key " ") == 0 && key !~ /^x-/)
          warn(path ": unknown frontmatter key \"" key "\" (ignored; use x- prefix for extensions)")
        if      (key == "type")       rtype[id] = val
        else if (key == "scope")      rscope[id] = val
        else if (key == "supersedes") rsup[id] = val
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
  if (rtype[id] != "memory" && rtype[id] != "tombstone" && rtype[id] != "votes")
    rerr(id, path ": unknown type \"" rtype[id] "\"")
  if (rtype[id] == "memory") {
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
  if (rtype[id] == "votes") {
    if (rplan[id] == "") rerr(id, path ": votes record missing plan:")
    if (rup[id] == "" && rdown[id] == "") rerr(id, path ": votes record with neither up: nor down:")
    if (rbody[id] ~ /[^ \t\n]/) rerr(id, path ": votes record must have an empty body (the up:/down: lists are the payload)")
  }
  if (rimp[id] != "" && rimp[id] !~ /^(guardrail|useful|minor)$/)
    rerr(id, path ": unknown importance \"" rimp[id] "\" (guardrail|useful|minor)")
  if (rdur[id] != "" && rdur[id] !~ /^(days|weeks|months|years|permanent)$/)
    rerr(id, path ": unknown durability \"" rdur[id] "\" (days|weeks|months|years|permanent)")
  # seed-up/seed-dn carry pre-migration vote counts and feed the ranking
  # directly; they are meaningful ONLY on a migration record. Requiring
  # migrated-from: closes a hand-authored forge (a record with seed-up: 50 but
  # no migration provenance would otherwise inflate its own rank and pass --check).
  if ((rseedup[id] != "" || rseeddn[id] != "") && rmigfrom[id] == "")
    rerr(id, path ": seed-up/seed-dn are migration seeds and require migrated-from:")

  if (rcreated[id] == "" && id ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/)
    rcreated[id] = substr(id, 1, 10)
}

# ---- helpers ----
function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }

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

function daynum(d) {
  if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 0
  return substr(d, 1, 4) * 372 + substr(d, 6, 2) * 31 + substr(d, 9, 2) + 0
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

# cycle detection over the supersede DAG (white/grey/black DFS). A cycle
# makes liveness meaningless — every record in it supersedes the next — and
# previously only surfaced as "chain too deep" after 200 hops, or not at all
# when the whole cycle was dead.
# The grey stack (cyc_stack) is retained on detection: the caller reads it to
# quarantine EVERY member of the cycle, not just the node where it closed, so
# no cyclic record survives to apply its edges to a valid neighbour.
function dfs_cycle(u,   m, tg, t, v) {
  color[u] = 1
  cyc_stack[++cyc_sp] = u
  if (rsup[u] != "") {
    m = split(rsup[u], tg, ",")
    for (t = 1; t <= m; t++) {
      v = trim(tg[t])
      if (v == "" || !(v in filepath) || (v in shun) || (v in bad)) continue
      if (color[v] == 1) { cyc_back = v; return 1 }
      if (color[v] == 0 && dfs_cycle(v)) return 1
    }
  }
  color[u] = 2
  cyc_sp--
  return 0
}

# quarantine the actual cycle: the grey stack holds root..u; the members are
# the suffix from cyc_back (the node the back edge closed onto) to the top.
# The prefix leading INTO the cycle is a valid successor lineage and is spared.
function quarantine_cycle(   s, started) {
  started = 0
  for (s = 1; s <= cyc_sp; s++) {
    if (cyc_stack[s] == cyc_back) started = 1
    if (started)
      rerr(cyc_stack[s], filepath[cyc_stack[s]] ": supersede cycle member (closes onto " cyc_back ")")
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
function addvotes(voter, list, sign, w,   m, t, tgt, av) {
  if (list == "") return
  m = split(list, av, ",")
  for (t = 1; t <= m; t++) {
    tgt = trim(av[t])
    if (tgt == "") continue
    # shunned or archived target = known inert node: no vote, no error
    if ((tgt in shun) || (tgt in archived)) continue
    if (!(tgt in filepath)) { err(voter ": vote target not found: " tgt); continue }
    if (tgt in bad) continue
    # votes rate knowledge, so only memory records can be voted on: a vote on
    # a tombstone or on another votes record carries no meaning and would
    # silently vanish from the ranking. Bad target is skipped rather than
    # quarantining the whole record, so co-listed valid votes still count
    # (same handling as a dangling target above).
    if (rtype[tgt] != "memory") {
      err(voter ": vote target " tgt " is a " rtype[tgt] " record; only memory records can be voted on")
      continue
    }
    if (sign > 0) { vup_id[tgt]++; vsc_id[tgt] += w }
    else          { vdn_id[tgt]++; vsc_id[tgt] -= w }
  }
}

# DAG walk over the ancestor set: which 1 = up count, 2 = down count, 3 = score
function chainagg(id, which,   q, qh, qt, cur, m, tg, t, tgt, tot) {
  epoch++
  tot = 0; qh = 1; qt = 1; q[1] = id
  while (qh <= qt && qt < 500) {
    cur = q[qh++]
    if (vseen[cur] == epoch) continue
    vseen[cur] = epoch
    if (which == 1)      tot += vup_id[cur]
    else if (which == 2) tot += vdn_id[cur]
    else                 tot += vsc_id[cur]
    if (rsup[cur] != "") {
      m = split(rsup[cur], tg, ",")
      for (t = 1; t <= m; t++) {
        tgt = trim(tg[t])
        if (tgt != "") q[++qt] = tgt
      }
    }
  }
  return tot
}

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
  tdn = daynum(today)

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
    if (id in shun) continue
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
      # A shunned target is a known redacted node, not a dangling reference:
      # the erasure procedure (shun + delete) must leave successors valid.
      if (tgt in shun) continue
      if (!(tgt in filepath)) { err(id ": supersedes target not found: " tgt); continue }
      # type compatibility: a memory record cannot retire a vote, and a vote
      # cannot retire knowledge — only tombstones may retire anything
      if (rtype[id] == "memory" && rtype[tgt] == "votes")
        rerr(id, filepath[id] ": memory record cannot supersede a votes record (" tgt ")")
      else if (rtype[id] == "votes" && rtype[tgt] != "votes")
        rerr(id, filepath[id] ": votes record may only supersede another votes record (" tgt " is " rtype[tgt] ")")
    }
  }

  # 1b. cycles: a supersede loop makes liveness undefined. Runs after 1a so the
  #     type/self/duplicate offenders are already quarantined and cannot appear
  #     as phantom cycle members. Every member of a detected cycle is
  #     quarantined, so none of them reaches the apply pass.
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if ((id in shun) || (id in bad)) continue
    if (color[id] == 0) {
      cyc_sp = 0
      if (dfs_cycle(id)) quarantine_cycle()
    }
  }

  # 1c. APPLY edges, now that only records with a fully clean, acyclic edge set
  #     remain un-quarantined. Both endpoints must be valid: the edge is
  #     dropped when the TARGET is quarantined too, or a valid record that
  #     supersedes a parse-invalid or cyclic target would still collect
  #     parent/union-find/nsup/chain-depth credit from an edge into nothing —
  #     letting invalid input change the rank of a valid record (fail closed on
  #     authority, on both ends of the edge). Shunned and dangling targets were
  #     diagnosed in 1a and likewise carry no edge.
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in shun) continue
    if (id in bad) continue
    if (rsup[id] == "") continue
    m = split(rsup[id], tg, ",")
    for (t = 1; t <= m; t++) {
      tgt = trim(tg[t])
      if (tgt == "" || (tgt in shun) || (tgt in bad) || !(tgt in filepath)) continue
      dead[tgt] = 1
      nsup[id]++
      if (!(id in parent)) parent[id] = tgt
      uf_union(id, tgt)
    }
  }

  # 2. votes: vote records + migration seed votes, all attached to chain roots
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in shun) continue
    if (id in bad) continue
    # A superseded or tombstoned votes record stops counting — superseding a
    # votes record IS the vote-correction path, so it has to actually work.
    if (rtype[id] == "votes" && (id in dead)) continue
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
  nlive = 0
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in shun) continue
    if (id in bad) continue
    if (rtype[id] != "memory" || (id in dead)) continue
    live[id] = 1; nlive++
    if (area(id) == "other") nother++
    if (rimp[id] == "guardrail") nguard++
    r = group(id)
    livecnt[r]++
    sc[id] = ibase(rimp[id]) * decayw(id) + chainagg(id, 3) + 0.4 * chaindepth(id)
    if (sc[id] < FLOOR && rimp[id] != "guardrail") dormant[id] = 1
    add_sorted(id)
  }
  heapsort(nsort)
  if (nother > OTHER_MAX)
    err("other holds " nother " live records (max " OTHER_MAX "); refile each via supersession into a real area")
  # a warning, not an error: guardrails are a judgement call and blocking the
  # compile over one would be worse than the inflation it guards against
  if (nguard > GUARDRAIL_MAX)
    warn(nguard " live guardrails (soft max " GUARDRAIL_MAX "). Guardrails bypass the digest budget and never decay, so inflation silently grows every session. Reclassify the weakest to useful, or supersede/tombstone what no longer applies.")

  if (check == 1) {
    close("cat 1>&2")
    exit (nerr > 0 ? 1 : 0)
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
      printf "%s\t%s\t%s\t%s\n", id, (pscope[id] == "" ? "-" : pscope[id]), alltags, headline(id)
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
      if ((id in shun) || (id in bad)) continue
      g = group(id)
      if (rtype[id] == "memory" && (id in live)) keepgrp[g] = 1
      else if (rtype[id] == "votes" && !(id in dead)) keepgrp[g] = 1
    }
    for (i = 1; i <= nrec; i++) {
      id = order[i]
      if ((id in shun) || (id in bad)) continue
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
  if (nlive == 0 && nquar > 0) {
    err("0 live records but " nquar " quarantined: refusing to publish (ledger is unreadable, not empty)")
    close("cat 1>&2")
    exit 3
  }

  printf "# ZAMM Memory Digest (%s: files=%d parsed=%d live=%d quarantined=%d; generated file - do not edit)\n", today, nfiles, nrec - nbad, nlive, nquar
  print ""

  if (nlive == 0) {
    print "(no live memory records - active memory has not been initialized)"
    close("cat 1>&2")
    exit 0
  }

  print "Entry format: - headline [record-id votes +bg]; indented lines = elaboration."
  print "Digest section: up to " DIGEST_MAX " actionable full blocks (! = guardrail, do not violate;"
  print "~ = contested head, also listed under Needs reconciliation)."
  print "Headlines section: up to " HEADLINE_MAX " one-line reminders that knowledge exists;"
  print "open the record (+bg) when the topic matches. Id doubles as creation date."
  print ""

  # Quarantined records: excluded from every calculation above, surfaced here
  # so a broken file is visible as a broken file rather than as missing memory.
  if (nquar > 0) {
    print "## Degraded (quarantined records - excluded from the digest)"
    print ""
    print "These files failed the record contract and were ignored for liveness,"
    print "supersession, votes and ranking. Fix them and recompile; run --check for"
    print "the full error list."
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

  close("cat 1>&2")
  exit 0
}
' > "$TMP_FILE"
rc=$?
set -e

# ---- Plans tail: one compact 2-3 line entry per active plan (status line,
#      title, optional inline scope), derived at compile time (no maintained
#      index files; zamm-status.sh stays the on-demand verbose view)
append_plans_section() {
  plans_dir="$PROJECT_ROOT/zamm-memory/active/plans"
  plans_tmp="$PLANS_TMP"
  : > "$plans_tmp"
  for pd in "$plans_dir"/*/; do
    [ -d "$pd" ] || continue
    pd=${pd%/}
    slug=$(basename "$pd")
    pf="$pd/$slug.plan.md"
    if [ ! -f "$pf" ]; then
      pf=""
      for cand in "$pd"/*.plan.md; do
        if [ -f "$cand" ]; then pf="$cand"; break; fi
      done
    fi
    if [ -z "$pf" ]; then
      printf '6\t- Unknown: %s (no .plan.md file)\n' "$slug" >> "$plans_tmp"
      continue
    fi
    awk -v slug="$slug" '
      function trimv(s) { sub(/\r$/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
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
  done
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
  arch_dir="$PROJECT_ROOT/zamm-memory/archive/plans"
  narch=0
  for ad in "$arch_dir"/*/; do
    [ -d "$ad" ] && narch=$((narch + 1))
  done
  if [ "$narch" -gt 0 ]; then
    {
      if [ "$narch" -gt 10 ]; then
        echo "Recently archived (newest 10 of $narch; full list: zamm-memory/archive/plans/):"
      else
        echo "Recently archived ($narch; in zamm-memory/archive/plans/):"
      fi
      # shellcheck disable=SC2012
      ls -1td "$arch_dir"/*/ 2>/dev/null | head -n 10 | while IFS= read -r ad; do
        ad=${ad%/}
        echo "- $(basename "$ad")"
      done
    } >> "$TMP_FILE"
  fi
}

if [ "$CHECK" -eq 1 ]; then
  if [ "$rc" -ne 0 ]; then
    echo "ZAMM check failed." >&2
    exit "$rc"
  fi
  echo "ZAMM check passed."
elif [ "$LIST_INERT" -eq 1 ] || [ "$LIST_LIVE" -eq 1 ]; then
  # read-only: the awk wrote the inert paths to the private temp file, so
  # emit them and publish nothing
  if [ "$rc" -ne 0 ]; then
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
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: digest compilation failed; previous digest left untouched." >&2
    exit "$rc"
  fi
  append_plans_section
  mv "$TMP_FILE" "$OUT_FILE"
  echo "ZAMM digest: $OUT_FILE"
fi
