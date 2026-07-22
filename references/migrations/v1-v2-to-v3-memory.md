# Migration: ZAMM Memory v1/v2 to v3

Use this guide when upgrading a project from tiered card memory (v1 Bedrock era
or v2 Boulders era) to the v3 append-only ledger. It covers both starting
points; v1 projects migrate directly to v3 without passing through v2.

## Summary

Memory v3 replaces the four tier card files with an append-only ledger of
immutable record files under `zamm-memory/knowledge/<YYYY>/`. Tier thresholds,
`Next ID` counters, in-place vote counters, and consolidation rituals are
removed. A gitignored digest (`zamm-memory/.compiled/memory.md`) is compiled
from the ledger by `zamm-compile.sh`.

**Transfer live cards only.** Migrate every card still present in the active
tier files. Do **not** import consolidations, dropped-card archives, or other
`zamm-memory/archive/knowledge/` history into the ledger. The old archive stays
on disk as v1/v2 history (git already preserves it); replaying it creates
orphan live heads and fake reconciliation work for no digest benefit.

Migration state is recorded only in `zamm-memory/VERSION`. Current version is
`3`. Do not update this file until the migration is complete.

The migration is one-shot and must run on a single machine with all branches
merged; other clones are protected by the version check until they pull.

## Preconditions

1. `git status` is clean and all machines/branches are merged to one point
   (when the project uses git).
2. Pending plan bookkeeping is completed under the old rules (no half-open
   transitions).
3. The v3 skill is installed (this guide, `zamm-compile.sh`,
   `zamm-new-memory.sh`, and the v3 scaffold templates are present).

### If plans were still open when the migration ran

Precondition 2 is routinely missed, so handle it rather than assume it. Any
plan that crossed the migration still carries v2-era `Memory-upvotes:` /
`Memory-downvotes:` values — old tier card IDs (`S28`, `B3`, ...) that no
longer name anything in a v3 ledger.

**Clear those fields; do NOT convert them into v3 votes records.** The card
counters they fed were already migrated into `seed-up:` / `seed-dn:` on the
new records, so re-emitting them double-counts. Worse, a votes record written
today carries today's date, and vote weight is recency-decayed — a vote cast
months ago would land with full fresh weight and outrank genuinely current
signal.

Note the reason in the plan's `## Loose ends` when closing it, so the cleared
fields do not read as an oversight later. If the arithmetic does not
reconcile (counters that do not match the number of plans citing a card),
that history is not recoverable — say so and move on; do not reconstruct
votes by guesswork.

## Source files by starting version

- v1 (Bedrock era): `zamm-memory/active/knowledge/BEDROCK.md`, `COBBLES.md`,
  `PEBBLES.md`, `SAND.md`. Cards may still carry legacy fields
  (`Claim`, `Evidence`, `Last verified`, `Confidence`, `Expiry hint`).
- v2 (Boulders era): `zamm-memory/active/knowledge/BOULDERS.md`, `COBBLES.md`,
  `PEBBLES.md`, `SAND.md` with the lean schema (`Ln`, `St`, `Lu`, `Up`, `Dn`).

If both `BEDROCK.md` and `BOULDERS.md` exist, reconcile manually before
migrating (same rule as the old v1-to-v2 guide).

Do **not** treat `zamm-memory/archive/knowledge/consolidations/` (or any other
archive tree) as a migration source.

## Required Steps

1. Map every **live** card's old free-form `(Scope: ...)` onto 1-3 fixed v3
   areas (`domain`, `contracts`, `conventions`, `internals`, `quality`,
   `tooling`, `ops`, `meta`). Primary tag first; optional `/subpath` may carry
   the old topic slug. Use a second bare area only when the card genuinely
   straddles a boundary. Prefer the closest real area over `other`; use
   `other` alone (no subpath) only when nothing fits, and keep the live
   `other` count ≤ 5 (refile later via supersession).

   Mapping examples (old free-form → v3):

   | Old `(Scope: ...)` | v3 `scope:` | Why |
   | --- | --- | --- |
   | `product/users` | `domain/users` | purpose / audience |
   | `api/record-schema` | `contracts/record-schema` | interop boundary |
   | `naming/plan-dirs` | `conventions/plan-dirs` | consistency, not correctness |
   | `zamm/archive-script-behavior` | `internals/archive-script` | how a shipped script works |
   | `testing/compile-check` | `quality/compile-check` | how correctness is verified |
   | `dev/macos-awk` | `tooling/macos-awk` | dev-time platform quirk |
   | `release/version-file` | `ops/version-file` | ship/migration mechanics |
   | `agent/cold-start` | `meta/cold-start` | agent/process norm |
   | `cli/flag-naming` (interop + style) | `contracts/cli-flags, conventions` | boundary straddle |
   | truly none of the above | `other` | temporary; refile soon |

2. For every card in every **active** tier file, create one ledger record
   (1:1 — do not merge, drop, or invent history during migration):
   - Path: `zamm-memory/knowledge/<year-of-Lu>/<Lu>-<slug>-<suffix>.md`, where
     `<Lu>` is the card's last-updated date (fallback: today), `<slug>` is a
     fresh lowercase `[a-z0-9-]` slug derived from the card's Scope and
     statement gist (max 40 chars), and `<suffix>` is 5 random chars from
     `23456789abcdefghjkmnpqrstvwxyz`.
   - Recommended: `bash <zamm-skill>/scripts/zamm-run.sh memory create --date <Lu> --scope <scope> <slug>`
     creates the file with the `Lu`-dated filename in the matching year
     directory and a matching `created:` line in one step. The filename date,
     `created:` field, and year directory MUST all agree;
     `zamm-run.sh memory check` fails on any mismatch.
   - Frontmatter:
     - `type: memory`
     - `scope:` mapped per step 1
     - `importance:` / `durability:` from the card's source tier, overriding
       per card where the content clearly warrants it:
       - BEDROCK / BOULDERS: `guardrail` / `permanent` (downgrade durability
         per card where the content is clearly time-bound)
       - COBBLES: `useful` / `years`
       - PEBBLES: `useful` / `months`
       - SAND: `useful` / `weeks` (`minor` for observations that never
         proved out)
     - `created:` the card's `Lu` (v1 legacy: `Last verified`, else today)
     - `schema: 3`
     - `migrated-from:` the card ID (`B3`, `C1`, `P7`, `S36`, ...)
     - `seed-up:` / `seed-dn:` the card's `Up` / `Dn` counts (omit when 0)
   - Body (headline craft):
     - The card's `St` (v1: `Claim`) becomes the FIRST PARAGRAPH — the digest
       headline. Preserve the statement's essence. Prefer a clean, standalone
       sentence: natural imperative when it fits ("When touching X, do Y
       because Z"), or a clear descriptive guardrail. Do **not** mechanically
       rewrite with a `Remember:` prefix or other boilerplate.
     - ~300 characters is a soft guide, not a hard cap — prefer a complete
       trigger-worthy statement over mid-thought truncation.
     - If the `St` carries secondary detail beyond a scannable headline, keep
       the core statement in the first paragraph and move the rest under a
       `## Background` heading.
     - v1 legacy: `Evidence` goes under `## Background` as a short
       "Evidence:" line; drop `Confidence` and `Expiry hint` (fold genuinely
       load-bearing caveats into the prose).
   - Do not fabricate `supersedes:` links between migrated records. Live cards
     are independent heads after migration; later cleanup uses normal
     supersession.
3. Migrate lineage only as provenance: `Ln` chains may be noted in
   `migrated-from` context or Background; they are not v3 supersede edges.
4. Delete the four tier files (git history preserves them). Leave
   `zamm-memory/archive/knowledge/` untouched — it is not part of the v3
   ledger and is not scanned by the compiler.
5. Run `bash <zamm-skill>/scripts/zamm-run.sh scaffold` — on a repo without
   `active/knowledge/` and with the new records in place it will create the
   ledger directories, append `zamm-memory/.compiled/` to `.gitignore`,
   append the `.gitattributes` line, refresh `AGENTS.md` and
   `.cursor/rules/zamm.mdc` from the v3 protocol, and write `VERSION` as `3`.
   (The scaffold refuses to run while tier card files remain under
   `zamm-memory/active/knowledge/` — the guard that you completed step 4. A
   leftover pre-v3 `VERSION` value is expected at this point; the scaffold
   overwrites it.)
6. Run `bash <zamm-skill>/scripts/zamm-run.sh memory check` and fix any
   reported naming/schema violations.
7. Run `bash <zamm-skill>/scripts/zamm-run.sh memory digest` and verify:
   - the digest's live-record count equals the total live card count from
     step 2,
   - former Boulder/Bedrock cards appear as `!` guardrails in ## Digest,
   - ## Digest and ## Headlines together cover the migrated live set (or
     note unlisted-live if over the 75+150 budget),
   - no `Needs reconciliation` section exists,
   - live `other` count is ≤ 5 (ideally 0).
8. Commit everything as one migration commit; only then let other
   machines/branches pull.

## Verification

```bash
grep -RIl "Next ID" zamm-memory/ && echo "FAIL: counter headers remain" || echo "ok: no counters"
find zamm-memory/active/knowledge -type f 2>/dev/null | grep . && echo "FAIL: tier files remain" || echo "ok: no tier files"
bash <zamm-skill>/scripts/zamm-run.sh memory check
cat zamm-memory/VERSION   # must be exactly: 3
grep -Fx "zamm-memory/.compiled/" .gitignore
```

## Notes

- The tier-derived `importance`/`durability` values carry the hand-curated
  hierarchy into the new ranking (guardrails sit at the top and do not decay);
  `seed-up`/`seed-dn` seed the vote totals. Later corrections happen through
  supersession and votes, never by editing the migrated files.
- The v2 plan model is unchanged (the wellbeing fields are renamed to `Execution-context-before` / `Execution-friction-after`); plan files and the archive flow
  migrate as-is.
- After migration, memory updates follow v3 rules only: new records, never
  in-place edits.
- Moving tombstoned or long-dormant ledger files out of the compile scan path
  (e.g. via `git mv` into a non-scanned archive directory) is intentionally
  deferred; dormancy and tombstones already keep them out of the digest.

## Optional: recover historical card text from git

Not part of the required migration. Consolidation archives often store only
IDs and one-line drop rationales, not full card bodies. If you separately need
old wording for archaeology, and the project has git history of the tier files,
you *may* recover text with something like:

```bash
# Example only — paths/dates vary; skip entirely when git is unavailable.
git log -p -- zamm-memory/active/knowledge/SAND.md
```

Do not bulk-import recovered drops into the live ledger. Live-only migration
is the supported path.
