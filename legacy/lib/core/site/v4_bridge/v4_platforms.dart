/// Platforms whose lists, search and links run on the v4 platform layer
/// (docs/adr/0012-legacy-bridge.md). A platform joins only when its bridge
/// output matches the legacy expected values in `test/v4_bridge/`; removing it
/// here is the rollback.
///
/// Only the legacy entry points that start with `V4Bridge.handles` are
/// bridged: Bilibili and Douyin search and Kuaishou's rooms and search stay on
/// the legacy code (the reasons head their tests in `test/v4_bridge/`).
const Set<String> v4BridgePlatforms = {'douyu', 'bilibili', 'douyin', 'kuaishou'};
