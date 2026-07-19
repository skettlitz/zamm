#!/bin/sh
# ZAMM compile — builds the gitignored memory digest from the append-only
# knowledge ledger. Deterministic, read-only over the ledger, safe to rerun.
# POSIX sh + POSIX awk only: runs on stock macOS, Linux, and git-bash.
#
# Usage: zamm-compile.sh [--project-root <path>] [--check]
#   --check   validate ledger records (naming, schema, references) and exit
#             non-zero on violations; writes no digest.

set -eu
LC_ALL=C
export LC_ALL

PROJECT_ROOT="$PWD"
CHECK=0
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
    -h|--help)
      echo "Usage: zamm-compile.sh [--project-root <path>] [--check]"
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
TODAY=$(date +%Y-%m-%d)

if [ ! -d "$KNOWLEDGE_DIR" ]; then
  echo "ERROR: missing $KNOWLEDGE_DIR (run zamm-scaffold.sh first)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
TMP_FILE="$OUT_DIR/memory.md.tmp"

set +e
find "$KNOWLEDGE_DIR" -type f -name '*.md' | sort | awk \
  -v today="$TODAY" -v check="$CHECK" '
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
  VALID_AREAS = " domain contracts conventions internals quality tooling ops meta "
  nrec = 0; nerr = 0; nsort = 0; nother = 0
}

# ---- input: one record file path per line ----
{
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

function read_record(path, base,   id, line, state, firstline, fmclosed, pos, key, val, lc, q, n2, ydir, t, a, hasother) {
  id = base
  sub(/\.md$/, "", id)

  # lint: naming rules (lowercase date-slug-suffix, portable charset)
  if (base !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z0-9][a-z0-9-]*\.md$/)
    err(path ": filename violates YYYY-MM-DD-slug-suffix.md lowercase [a-z0-9-] rule")
  else if (base !~ /-[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]\.md$/)
    err(path ": filename missing the 5-char uniqueness suffix before .md")
  lc = tolower(base)
  if ((lc in casemap) && casemap[lc] != path)
    err(path ": case-fold collision with " casemap[lc])
  casemap[lc] = path
  if (id in filepath) { err(path ": duplicate record id " id); return }

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
        # unknown keys are ignored on purpose
      }
      continue
    }
    if (state == 2) rbody[id] = rbody[id] line "\n"
  }
  close(path)

  # ---- record contract (violations fail --check; normal compile stays lenient) ----
  if (fmclosed == 0) {
    if (state == 1) err(path ": frontmatter not closed (missing second ---)")
    else err(path ": missing frontmatter block")
  }
  if (rcreated[id] == "")
    err(path ": missing created:")
  else if (rcreated[id] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/)
    err(path ": created: is not YYYY-MM-DD: " rcreated[id])
  else if (id ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/ && rcreated[id] != substr(id, 1, 10))
    err(path ": created: " rcreated[id] " does not match filename date " substr(id, 1, 10))
  n2 = split(path, q, "/")
  if (n2 >= 2) {
    ydir = q[n2 - 1]
    if (ydir ~ /^[0-9][0-9][0-9][0-9]$/ && ydir != substr(id, 1, 4))
      err(path ": year directory " ydir " does not match filename year " substr(id, 1, 4))
  }
  if (rschema[id] == "")
    err(path ": missing schema:")
  else if (rschema[id] != "3")
    err(path ": unsupported schema: " rschema[id])
  if (rtype[id] != "memory" && rtype[id] != "tombstone" && rtype[id] != "votes")
    err(path ": unknown type \"" rtype[id] "\"")
  if (rtype[id] == "memory") {
    parsetags(id)
    if (rscope[id] == "") err(path ": memory record missing scope:")
    else {
      if (tagn[id] > 3)
        err(path ": scope has " tagn[id] " tags (max 3)")
      hasother = 0
      for (t = 1; t <= tagn[id]; t++) {
        a = areaof(tagsc[id, t])
        if (a == "other") hasother = 1
        else if (index(VALID_AREAS, " " a " ") == 0)
          err(path ": unknown scope area \"" a "\" (fixed set: domain contracts conventions internals quality tooling ops meta; or other alone)")
        if (t > 1 && index(tagsc[id, t], "/") > 0)
          err(path ": secondary scope tag \"" tagsc[id, t] "\" carries a subpath (bare areas only)")
        if ((a in dupechk) && dupechk[a] == id)
          err(path ": duplicate scope area \"" a "\"")
        dupechk[a] = id
      }
      if (hasother && (tagn[id] > 1 || index(pscope[id], "/") > 0))
        err(path ": other must be the sole scope tag, without subpath")
    }
    if (rimp[id] == "") err(path ": memory record missing importance: (the ranking depends on it)")
    if (rdur[id] == "") err(path ": memory record missing durability: (the ranking depends on it)")
    if (rbody[id] !~ /[^ \t\n]/) err(path ": memory record has empty body")
    else if (headline(id) == "")
      err(path ": missing headline (body starts with a heading)")
    else {
      # Headline length (~300 chars) is a soft authoring guide, not a hard
      # --check fail — prefer a complete trigger over mid-thought truncation.
      # Digest-block size stays hard-capped (attention budget).
      if (blockl[id] > 12)
        err(path ": digest block exceeds 12 lines; move detail under ## Background")
      if (blockc[id] > 1200)
        err(path ": digest block exceeds 1200 chars; move detail under ## Background")
    }
  }
  if (rtype[id] == "tombstone" && rsup[id] == "")
    err(path ": tombstone without supersedes target")
  if (rtype[id] == "votes") {
    if (rplan[id] == "") err(path ": votes record missing plan:")
    if (rup[id] == "" && rdown[id] == "") err(path ": votes record with neither up: nor down:")
  }
  if (rimp[id] != "" && rimp[id] !~ /^(guardrail|useful|minor)$/)
    err(path ": unknown importance \"" rimp[id] "\" (guardrail|useful|minor)")
  if (rdur[id] != "" && rdur[id] !~ /^(days|weeks|months|years|permanent)$/)
    err(path ": unknown durability \"" rdur[id] "\" (days|weeks|months|years|permanent)")

  if (rcreated[id] == "" && id ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/)
    rcreated[id] = substr(id, 1, 10)
}

# ---- helpers ----
function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }

function err(msg) { print "zamm-compile: ERROR: " msg | "cat 1>&2"; nerr++ }

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

function chainroot(id,   r, hops) {
  r = id; hops = 0
  while ((r in parent) && hops < 200) { r = parent[r]; hops++ }
  if (hops >= 200) err(id ": supersede chain too deep or cyclic")
  return r
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
  return d
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
  tagn[id] = 0; pscope[id] = ""; parea[id] = ""
  if (rscope[id] == "") return
  m = split(rscope[id], tv, ",")
  for (t = 1; t <= m; t++) {
    tag = trim(tv[t])
    if (tag == "") continue
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
function addvotes(list, sign, w,   m, t, tgt, av) {
  if (list == "") return
  m = split(list, av, ",")
  for (t = 1; t <= m; t++) {
    tgt = trim(av[t])
    if (tgt == "") continue
    if (!(tgt in filepath)) err("vote target not found: " tgt)
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
function ranks_below(a, b) {
  if (sc[a] != sc[b]) return sc[a] < sc[b]
  return a < b
}

function add_sorted(id,   j) {
  j = ++nsort
  while (j > 1 && ranks_below(sorted[j-1], id)) { sorted[j] = sorted[j-1]; j-- }
  sorted[j] = id
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

# headline-only entry (Index, reconciliation heads); scope shown = primary tag
function emitline(id, withscope,   pre) {
  pre = (rimp[id] == "guardrail") ? "! " : ""
  if (withscope && pscope[id] != "")
    print "- " pre pscope[id] ": " headline(id) " " pointer(id)
  else
    print "- " pre headline(id) " " pointer(id)
  printed[id] = 1
  endedblank = 0
}

# full entry: headline line + elaboration lines (rest of the digest block)
function emitfull(id, withscope,   pre, m, bl, t, ln, started, paradone, any) {
  pre = (rimp[id] == "guardrail") ? "! " : ""
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

  # 1. supersede edges -> dead set + parent links
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in shun) continue
    if (rsup[id] == "") continue
    m = split(rsup[id], tg, ",")
    for (t = 1; t <= m; t++) {
      tgt = trim(tg[t])
      if (tgt == "") continue
      dead[tgt] = 1
      nsup[id]++
      if (!(id in parent)) parent[id] = tgt
      if (!(tgt in filepath)) err(id ": supersedes target not found: " tgt)
    }
  }

  # 2. votes: vote records + migration seed votes, all attached to chain roots
  for (i = 1; i <= nrec; i++) {
    id = order[i]
    if (id in shun) continue
    w = VOTE_WEIGHT * agew(rcreated[id])
    if (rtype[id] == "votes") {
      addvotes(rup[id], 1, w)
      addvotes(rdown[id], -1, w)
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
    if (rtype[id] != "memory" || (id in dead)) continue
    live[id] = 1; nlive++
    if (area(id) == "other") nother++
    r = chainroot(id)
    livecnt[r]++
    sc[id] = ibase(rimp[id]) * decayw(id) + chainagg(id, 3) + 0.4 * chaindepth(id)
    if (sc[id] < FLOOR && rimp[id] != "guardrail") dormant[id] = 1
    add_sorted(id)
  }
  if (nother > OTHER_MAX)
    err("other holds " nother " live records (max " OTHER_MAX "); refile each via supersession into a real area")

  if (check == 1) {
    close("cat 1>&2")
    exit (nerr > 0 ? 1 : 0)
  }

  # 4. digest — Digests (full blocks, DIGEST_MAX) + Headlines (one line,
  #    HEADLINE_MAX). Background bodies never enter the digest file.
  printf "# ZAMM Memory Digest (%s: %d records, %d live; generated file - do not edit)\n", today, nrec, nlive
  print ""

  if (nlive == 0) {
    print "(no live memory records - active memory has not been initialized)"
    close("cat 1>&2")
    exit 0
  }

  print "Entry format: - headline [record-id votes +bg]; indented lines = elaboration."
  print "Digest section: up to " DIGEST_MAX " actionable full blocks (! = guardrail, do not violate)."
  print "Headlines section: up to " HEADLINE_MAX " one-line reminders that knowledge exists;"
  print "open the record (+bg) when the topic matches. Id doubles as creation date."
  print ""

  if (nother > 0) {
    print "Other: " nother " record(s) in the catch-all area - refile each via"
    print "supersession into a real area when touched."
    print ""
  }

  nconf = 0
  for (i = 1; i <= nsort; i++) {
    if (livecnt[chainroot(sorted[i])] >= 2) nconf++
  }
  if (nconf > 0) {
    print "## Needs reconciliation (resolve this session)"
    print ""
    print "Per group: read the competing record files, then write ONE new record whose"
    print "supersedes: line lists ALL competing ids. Never edit or delete the files."
    print ""
    for (i = 1; i <= nsort; i++) {
      id = sorted[i]
      r = chainroot(id)
      if (livecnt[r] < 2 || (r in confdone)) continue
      confdone[r] = 1
      print "### Heads of " r
      for (j = 1; j <= nsort; j++) {
        if (chainroot(sorted[j]) == r) emitline(sorted[j], 1)
      }
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
  plans_tmp="$OUT_DIR/plans.tmp"
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
      /^## Done-when/ { dw = 1; next }
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
  rm -f "$TMP_FILE"
  if [ "$rc" -ne 0 ]; then
    echo "ZAMM check failed." >&2
    exit "$rc"
  fi
  echo "ZAMM check passed."
else
  if [ "$rc" -ne 0 ]; then
    rm -f "$TMP_FILE"
    echo "ERROR: digest compilation failed." >&2
    exit "$rc"
  fi
  append_plans_section
  mv "$TMP_FILE" "$OUT_FILE"
  echo "ZAMM digest: $OUT_FILE"
fi
