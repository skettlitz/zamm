# Resolve `<zamm-skill>` placeholders at scaffold/install time

Status: Done
Wellbeing-before: Focused; investigating placeholder resolution boundaries in templates vs runtime outputs.
Complexity-forecast: raccoon
Memory-upvotes: W3, W13
Memory-downvotes:
Owner agent: Codex (GPT-5)
Last updated: 2026-02-20

Scope:
* In:
  - Trace current `<zamm-skill>` placeholder behavior in scaffold/install flow.
  - Decide whether scaffold should materialize concrete paths in generated `AGENTS.md` and `.cursor/rules/zamm.mdc`.
  - Implement and verify script/template changes if safe.
  - Add easy-to-remember resolved install path alias wording in shared protocol template.
* Out:
  - Changes unrelated to placeholder resolution in runtime instruction surfaces.

## Done-when

- [x] Current placeholder handling is documented from code behavior.
- [x] A clear decision is made for scaffold-time replacement in runtime files.
- [x] If decision is yes, `scripts/scaffold.sh` applies deterministic replacement and generated files validate.
- [x] README/docs are updated if behavior changes.
- [x] Shared protocol includes a mnemonic resolved-path alias convention for quick reuse.

## Approach

1. Inspect scaffold script and template references around runtime generation.
2. Confirm where `<zamm-skill>` should remain symbolic vs concrete.
3. Apply minimal code changes and regenerate runtime surfaces.
4. Validate outputs and summarize tradeoffs.

## Learnings

- Rendering placeholder paths at scaffold time works best with install-aware display normalization (`<project-root>`, then `~`, then absolute fallback) so generated runtime guidance stays concrete without being machine-noisy.
- Keeping canonical template files unchanged while resolving placeholders only in generated runtime surfaces preserves template portability and keeps one source of truth.
- Adding assignment-style mnemonic aliases (`ZAMM_SCRIPTS_DIR=...`, `ZAMM_SKILL_DIR=...`) in `Script Path Resolution` makes path recall easier during execution without requiring actual shell exports.

## Loose ends

- (none yet)

Wellbeing-after: Clear; behavior is now deterministic and easier for agents to follow in generated runtime files.
Complexity-felt: raccoon
Complexity-delta: as-expected
Done-approved-by: human user (sk)
Done-approved-at: 2026-02-20 15:33 CET
Done-approval-evidence: User message in chat: "all good then, we can mark this done"
