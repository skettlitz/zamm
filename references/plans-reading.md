# Plans — reading

- The session digest ends with `## Plans (active; compact entries)`: one
  entry per active plan — `- Status: <plan-dir> [complexity] done-when x/y,
  last <date>` and the title on the next line — ranked Blocked, Review,
  Implementing, Draft; terminal plans still under `active/` are flagged
  archive-ready. A Blocked entry adds `blocked <N>d` to its line and one
  `blocked[<class>]: <sentence>` line per open block under the title: the
  reason is in the digest itself, never one file-open away. Blocked outranks
  Review because both want a human, but Review is finished work awaiting a
  blessing while Blocked is work that has stopped. A
  "Recently archived" list follows: check it before treating a referenced
  plan directory as missing after a pull.
- `plan show <slug>` — one plan with its progress line. `plan list` — every
  active plan grouped by status (`Draft`, `Implementing`, `Blocked`, `Review`,
  `Done`, `Abandoned`, `Unknown`). `plan check` — required fields for the
  declared status, unchecked Done-when items, and the block log: an unknown
  or missing class, a `[plan:<id>]` naming a plan that does not exist, a block
  older than its class allows, and — the one worth waiting for — a plan still
  blocked on a dependency that has already landed. An open entry is an error
  under every status but `Blocked` and `Abandoned`; abandoning is how a block
  that never cleared is closed out. `plan archive --list` — what is
  archive-ready, moving nothing.
- Deeper: `zamm-memory/active/plans/**/*.plan.md`, reading `Status:`. Do not
  maintain separate workstream state or index files; the digest's tail is
  the index.
- Precedence: the active plan file and terminal-status semantics rank below
  current human instruction and below code, tests and contracts, and above
  ledger records.
