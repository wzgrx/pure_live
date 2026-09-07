# Android proxy UI fixture

`android_proxy_switches_enabled.xml` retains only two switches and four text fields
from the local 2026-09-06 10:19:49 Android proxy observation. Source evidence:
`local-artifacts/diagnostics/android-proxy-localclash-20260906T101949560/proxy-fast-verify.xml`.

The fixture contains generic Pure Live labels, checked states, bounds, and the
local loopback/7897 test endpoint. Activity metadata and unrelated UI nodes were
removed. It verifies parsing of a previously observed layout, not a fresh device
run, current proxy state, network connectivity, or recording acceptance.
