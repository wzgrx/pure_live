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

`android_proxy_occluded_entry.xml` is the actual settings hierarchy from
`android-recording-smoke-20260907T175408445/proxy-before-stop/proxy-ui-5.xml`.
It contains only generic settings UI. The proxy entry center (600,399) overlaps
the clickable floating player [390,300][1050,671]. It verifies rectangle
exclusion and an uncovered point (219,399), not Android hit-test order or a
successful live route transition. Foreground checks remain required per input.

`android_proxy_menu_backdrop.xml` is the floating-player popup hierarchy from
`android-recording-smoke-20260907T181304774/proxy-before-stop/proxy-ui-2.xml`.
Only generic settings/about/history and popup-dismiss semantics are present.
Unlike a cold-start popup, its labelled dismiss backdrop is not an ancestor of
the native MenuItems. Tests recognize that exact role pairing, not arbitrary
overlay order; an unlabelled backdrop or a non-menu target still blocks input.
