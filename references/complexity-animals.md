# Animal scale for complexity estimation

Plans rate `Complexity-forecast:` and `Complexity-felt:` on this nine-animal
scale (see `Execution Telemetry` in the protocol). The compact canonical
definitions travel as a comment in `references/templates/plan.template.md`;
this file holds the fuller cues for calibration.

`Complexity-forecast: ant|gecko|raccoon|capybara|badger|octopus|manatee|shark|godzilla|kraken`

| Level | Animal       | The character it signals | Typical cues                                                     |
| ----- | ------------ | ------------------------ | ---------------------------------------------------------------- |
| 1     | **ant**      | tiny + obvious           | one tiny surface, no debate, trivial validation                  |
| 2     | **gecko**    | small + quick            | small change, minimal side effects, easy to revert               |
| 3     | **raccoon**  | small but sneaky         | edge cases, odd environments, "it depends" lurking               |
| 4     | **capybara** | medium + chill           | normal feature slice, known path, steady work                    |
| 5     | **badger**   | medium + stubborn        | tricky testing, awkward constraints, needs persistence           |
| 6     | **octopus**  | many tentacles           | multiple components/dependencies, integration work, coordination |
| 7     | **manatee**  | big but gentle           | lots of work, **low drama**: predictable, repeatable steps       |
| 8     | **shark**    | big + toothy             | high consequence / blast radius, rollout/rollback matters        |
| 9     | **godzilla** | city-level               | initiative-sized, unknown unknowns, must be sliced + discovery   |
| W     | **kraken**   | wicked, off-scale        | looks solvable but never truly resolves; each attempt only redraws the map |

## The kraken (off-scale)

`kraken` is not level 10 — it sits off the scale, because wickedness is orthogonal to size:
a problem of any apparent size can be wicked. It marks a problem that looks like it could be
solved but never really is; only your perception of its shape changes. Most of the body stays
under water — you only ever see the tentacle currently above the surface.

Tells that you are facing a kraken rather than a big godzilla:

- the problem statement changes each time you approach it,
- every fix spawns a new formulation of the problem somewhere else,
- "done" cannot be defined without picking a frame that someone will dispute,
- previous "solutions" have quietly become part of the problem.

Plan guidance: never scope a plan as "solve the kraken" — that plan cannot close. Scope a
bounded probe instead, one tentacle at a time: a time-boxed experiment, a reframing, a
mitigation with explicit exit criteria. `Done-when` items must describe the probe's outcome or
the mitigation shipped, not the disappearance of the problem. After each engagement, distill
the updated shape-perception into the ledger so the next attempt starts from the newest map
instead of rediscovering the beast.
