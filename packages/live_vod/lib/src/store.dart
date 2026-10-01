/// Where the music domain keeps its small state (daily picks, lyric
/// choices). The app implements it on `live_store` (M14.4); this package
/// never touches storage itself.
abstract interface class VodKeyValueStore {
  /// The value of [key], or null.
  String? read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes [key].
  Future<void> remove(String key);
}

/// A store in memory, for tests and the command line.
final class MemoryVodStore implements VodKeyValueStore {
  /// Values by key.
  final Map<String, String> values = {};

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}
