/// Platforms whose lists, search and links run on the v4 platform layer
/// (docs/adr/0012-legacy-bridge.md). A platform joins only when its bridge
/// output matches the legacy expected values in `test/v4_bridge/`; removing it
/// here is the rollback.
const Set<String> v4BridgePlatforms = {'douyu'};
