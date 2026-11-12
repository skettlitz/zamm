# Backlog — reading

- `backlog list [--scope <tag>]` — recompiles and prints the lens: every
  live, non-dormant idea as `- area/subpath: headline [id votes +bg]`,
  grouped under counted area headings (`### internals (2: compiler 2)`),
  hot to cold within each area — hot is recently added or voted up. The
  marked lane renders first, oldest commitment on top. `--scope` prints a
  filtered listing, and a subpath filters its family. `--all` adds the parked
  ideas, each with its reason, and the dormant tail; the lens otherwise
  collapses both to counts. `(was parked ...)` or `(was marked ...)` on a line
  means that decision has reached its `--until` date and is over.
- `backlog show <slug|id>` — one idea in full. `+bg` means the record holds
  a `## Background` section: read it before working the idea — it is the
  case for doing it and the sketch of how.
- The session digest shows only MARKED ideas (`## Marked backlog`, one
  headline each with its mark date, and its end date and reason when it has
  them) and a `Backlog:` line of counts.
- `~` marks variants: parallel forks of one idea, both live until one
  supersedes the other.
- `backlog check` validates the tree. Reads exit 2 when the tree is
  degraded, with the reason on stderr.
