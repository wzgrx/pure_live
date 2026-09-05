---
name: pure-live-maintenance
description: Diagnose Pure Live bugs and review upstream Issues or code changes while preserving fork behavior. Use for bug fixes or upstream reviews; not ordinary wording edits or standalone builds.
---

# Pure Live Maintenance

<!-- maintenance-skill-markers: bug-provenance-required; semantic change ledger -->

Use [MAINTENANCE_POLICY.md](../../../MAINTENANCE_POLICY.md) for provenance and product invariants. Read only the sections relevant to the task.

1. Inspect current Git state, the symptom and its call/event path. Record the local SHA; inspect the relevant upstream history when needed to distinguish provenance. Mark unproven claims explicitly rather than blocking a local repair on an unrelated network fetch.
2. Identify the first invalid state, ownership and affected modes. Build a focused reproduction from tests, logs or source evidence, then implement the smallest coherent fix and check its callers.
3. Match verification to risk using [AGENT_WORKFLOW.md](../../../docs/AGENT_WORKFLOW.md). Lifecycle, retry, persistence and source-switch changes need behavioral regression; cosmetic edits do not need implementation-mirroring tests.
4. For actual upstream integration, follow [UPSTREAM_REVIEW_POLICY.md](../../../UPSTREAM_REVIEW_POLICY.md), including the semantic change ledger for every incoming commit/file. Read-only comparison is separate from merge authorization.
5. Finish the requested work and record remaining evidence gaps. Completed bug-fix delivery follows `bugfix-android-release-default` in [BUILD_POLICY.md](../../../BUILD_POLICY.md); an analysis-only request or deferred release stays scoped accordingly.

Phone access is governed by AGENTS.md, not by this skill. Fork Issue feature requests route upstream; that intake policy does not override an explicit development request from the user.
