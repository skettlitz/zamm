# ZAMM Migration Guides

Major-version migrations live here so routine runtime protocol and active memory files stay small.

Agents should read these guides only when explicitly asked to upgrade ZAMM, when scaffold refuses to run over a legacy memory tree, or when diagnosing an upgrade issue.

Migration state is checked through `zamm-memory/VERSION`. Current version is `3`; migration guides update that file only after their steps are complete.

Available guides:

- `v1-v2-to-v3-memory.md`: migrate tiered card memory (v1 Bedrock era or v2 Boulders era) to the v3 append-only ledger. Transfers **live tier cards only** (ignores archive/consolidations). v1 projects migrate directly to v3; the retired v1-to-v2 guide is preserved in git history only.
