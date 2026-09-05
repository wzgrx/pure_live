---
name: pure-live-build
description: Select and run Pure Live validation, local platform builds, packaging and verified GitHub releases. Use for build or delivery work; not for routine source reading or documentation-only edits.
---

# Pure Live Build

Read [BUILD_POLICY.md](../../../BUILD_POLICY.md) for resource and delivery invariants, then choose the applicable route in [AGENT_WORKFLOW.md](../../../docs/AGENT_WORKFLOW.md). Do not load unrelated release or device procedures.

Identify the platform, variant and requested delivery stage. Related fixes share one version under `bugfix-android-release-default` in BUILD_POLICY.md.

- Quality: `tool/local_ci.ps1`; packaging: `tool/build_local_release.ps1`, one target/configuration. Both own the resource lease; avoid nesting it. Direct heavy commands use `tool/build_resource_guard.ps1`.
- Resume retries at the failed stage. Reuse app-source quality evidence only under BUILD_POLICY.md's unchanged-input conditions; check an existing run's result before starting another.
- Verify ABI, assets, 16 KB ELF/alignment, actual APK versionCode, source SHA and the fixed signing certificate using repository scripts. Record command, duration, resources, hashes and paths.

Root-cause/upstream review belongs to [MAINTENANCE_POLICY.md](../../../MAINTENANCE_POLICY.md) when that work is in scope. A build request by itself does not require reopening a completed upstream audit. Keep source, build, signing, publication and device results distinct.
