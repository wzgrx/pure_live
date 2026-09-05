---
name: pure-live-build
description: Select and run Pure Live validation, local platform builds, packaging and verified GitHub releases. Use for build or delivery work; not for routine source reading or documentation-only edits.
---

# Pure Live Build

Read [BUILD_POLICY.md](../../../BUILD_POLICY.md) for resource and delivery invariants, then choose the applicable route in [AGENT_WORKFLOW.md](../../../docs/AGENT_WORKFLOW.md). Do not load unrelated release or device procedures.

1. Identify the requested platform, variant and delivery stage. Completed bug-fix batches retain `bugfix-android-release-default`; an explicit analysis-only/deferred request takes precedence. Multiple related fixes share one version.
2. Use `tool/local_ci.ps1` for affected tests/analyze or formal Full validation. Use `tool/build_local_release.ps1` for a single target/configuration. These entrypoints own resource arbitration; do not wrap them in a second nested lease.
3. Direct heavy commands use `tool/build_resource_guard.ps1`. Preserve caches and use the pinned wrapper. Check existing command results before starting another run.
4. After required checks pass, continue to the requested delivery stage. Repeat or broaden validation only for new edits, failures or unresolved risks. Packaging-only retries can reuse the same app-source quality evidence under BUILD_POLICY.md.
5. Verify artifacts with the repository scripts; preserve ABI, assets, 16 KB ELF/alignment, versionCode, source SHA and fixed signing-certificate checks. Record command, duration, resource data, hashes and output paths.

Root-cause/upstream review belongs to [MAINTENANCE_POLICY.md](../../../MAINTENANCE_POLICY.md) when that work is in scope. A build request by itself does not require reopening a completed upstream audit. Keep source, build, signing, publication and device results distinct.
