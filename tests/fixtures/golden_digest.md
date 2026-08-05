# ZAMM Memory Digest (2026-07-19: files=22 parsed=22 live=17 quarantined=0; generated file - do not edit)

Entry format: - headline [record-id votes +bg]; indented lines = elaboration.
Digest section: up to 75 actionable full blocks (! = guardrail, do not violate;
~ = contested head, also listed under Needs reconciliation).
Headlines section: up to 150 one-line reminders that knowledge exists;
open the record (+bg) when the topic matches. Id doubles as creation date.

## Needs reconciliation (resolve this session)

Per group: read the competing record files, then write ONE new record whose
supersedes: line lists ALL competing ids. Never edit or delete the files.
This is an index — each head keeps its full block below, marked ~.

### Heads of 2026-07-11-contested-root-2222k
- tooling/build: Branch beta of the contested statement. [2026-07-16-contested-beta-2222n]
- tooling/build: Branch alpha of the contested statement. [2026-07-16-contested-alpha-2222m]

## Digest (actionable; full blocks)

### ops/migrations
- ! Never run a migration against production without a snapshot first. [2026-07-10-guard-snapshot-22222]
  Recovery without one has cost a full day twice.

### contracts/payments
- ! Always send an idempotency key with payment calls. [2026-07-10-guard-idempotency-22223]

### conventions/naming
- Record with an upvote, which should lift it above its unvoted peers. [2026-07-13-voted-record-2222e +1]

### tooling/build
- ~ Branch beta of the contested statement. [2026-07-16-contested-beta-2222n]
  Elaboration explaining what branch beta assumes.

- ~ Branch alpha of the contested statement. [2026-07-16-contested-alpha-2222m]
  Elaboration explaining what branch alpha assumes.

### internals/ranking
- Current version of the revised rule. [2026-07-15-chained-rule-2222j]

### contracts/versioning
- Contract rule about versioning that exists to crowd the contracts area. [2026-07-12-contracts-versioning-22229]

### internals/digest
- Record carrying a Background section, so it must show the +bg pointer. [2026-07-13-with-background-2222d +bg]

### quality/checks
- Three-tag record: more selection doors, larger parsimony cost. [2026-07-12-three-tag-record-2222c]

### contracts/cli-flags
- Two-tag record: enters via the least crowded of its areas and pays for the extra tag. [2026-07-12-multi-tag-record-2222b]

### contracts/timeouts
- Contract rule about timeouts that exists to crowd the contracts area. [2026-07-12-contracts-timeouts-22225]

### contracts/retries
- Contract rule about retries that exists to crowd the contracts area. [2026-07-12-contracts-retries-22224]

### contracts/pagination
- Contract rule about pagination that exists to crowd the contracts area. [2026-07-12-contracts-pagination-22226]

### domain/audience
- Domain rule in an otherwise empty area; it should enter early on diversity. [2026-07-12-sparse-domain-2222a]

### contracts/errors
- Contract rule about errors that exists to crowd the contracts area. [2026-07-12-contracts-errors-22228]

### contracts/batching
- Contract rule about batching that exists to crowd the contracts area. [2026-07-12-contracts-batching-22227]

Dormant (decayed below digest floor; ledger stays greppable): 1 meta

## Plans (active; compact entries)

(no active plans)

<!-- zamm-generation: 1122320421-3272 -->
