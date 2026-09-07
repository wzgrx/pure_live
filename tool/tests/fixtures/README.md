# Android proxy UI fixture

`android_proxy_switches_enabled.xml` retains only two switches and four text fields
from the local 2026-09-06 10:19:49 Android proxy observation. Source evidence:
`local-artifacts/diagnostics/android-proxy-localclash-20260906T101949560/proxy-fast-verify.xml`.

The fixture contains generic Pure Live labels, checked states, bounds, and the
local loopback/7897 test endpoint. Activity metadata and unrelated UI nodes were
removed. It verifies parsing of a previously observed layout, not a fresh device
run, current proxy state, network connectivity, or recording acceptance.

`android_proxy_nested_settings.xml` is the 2026-09-07 16:38 settings hierarchy
from `android-recording-smoke-20260907T163502928/proxy-before-stop/proxy-ui-3.xml`
under the local diagnostics directory. It contains generic settings labels and
no account or endpoint credentials. The floating-player wrapper exposes a
scrollable outer View around a nested ScrollView. This reproduces the cleanup
failure and checks selection of the unique inner viewport; replaying this XML
is an offline test, not proof that a new native recording round restored proxy.
