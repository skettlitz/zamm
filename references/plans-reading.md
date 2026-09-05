# Plans — reading

- The session digest ends with `## Plans (active; compact entries)`: one
  entry per active plan — `- Status: <plan-dir> [complexity] done-when x/y,
  last <date>` and the title on the next line — ranked Review, Implementing,
  Draft; terminal plans still under `active/` are flagged archive-ready. A
  "Recently archived" list follows: check it before treating a referenced
  plan directory as missing after a pull.
- `plan show <slug>` — one plan with its progress line. `plan list` — every
  active plan grouped by status (`Draft`, `Implementing`, `Review`, `Done`,
  `Abandoned`, `Unknown`). `plan check` — required fields for the declared
  status and unchecked Done-when items. `plan archive --list` — what is
  archive-ready, moving nothing.
- Deeper: `zamm-memory/active/plans/**/*.plan.md`, reading `Status:`. Do not
  maintain separate workstream state or index files; the digest's tail is
  the index.
- Precedence: the active plan file and terminal-status semantics rank below
  current human instruction and below code, tests and contracts, and above
  ledger records.
