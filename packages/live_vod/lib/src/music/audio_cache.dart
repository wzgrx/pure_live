import 'package:meta/meta.dart';

/// A file in the cache directory.
typedef CachedFile = ({String name, int size, DateTime modified});

/// The file operations the cache needs, on its own directory. The app
/// implements it with `dart:io` under its data directory (M14.4); tests use
/// a map.
abstract interface class AudioCacheFiles {
  /// Every file in the directory.
  Future<List<CachedFile>> list();

  /// Size of [name], or null when it does not exist.
  Future<int?> sizeOf(String name);

  /// Renames [from] to [to], replacing [to].
  Future<void> rename(String from, String to);

  /// Deletes [name]; a missing file is not an error.
  Future<void> delete(String name);
}

/// Cache keys: one file per track and audio tier.
abstract final class AudioCacheKey {
  static final RegExp _unsafe = RegExp('[^A-Za-z0-9_-]');

  /// The key of a part's audio: `{bvid}_{cid}` plus `_hires` for lossless.
  /// Video is never cached (a song's audio is a few megabytes).
  static String of({required String bvid, required int cid, bool lossless = false}) =>
      '${bvid.replaceAll(_unsafe, '')}_$cid${lossless ? '_hires' : ''}';

  /// The finished file of [key].
  static String fileOf(String key) => '$key.m4a';

  /// The download in progress of [key]; renamed to [fileOf] only when the
  /// response was written whole, so a partial file is never played.
  static String partOf(String key) => '$key.m4a.part';
}

/// Persistent audio cache of music mode (pure_live_TV `b9d2f739`
/// `music_audio_cache.dart` without its I/O): a track heard once plays from
/// disk, so it no longer depends on expiring CDN links.
///
/// The TV cache never removed anything; this one keeps at most [maxBytes]
/// and evicts the least recently played files first, never the ones in
/// `keep` (the track playing and the one prefetched next).
final class AudioCache {
  /// Creates the cache over [files].
  new(this.files, {this.maxBytes = 1024 * 1024 * 1024, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The directory.
  final AudioCacheFiles files;

  /// Size limit.
  int maxBytes;

  final DateTime Function() _now;
  final Map<String, _Entry> _entries = {};
  final Set<String> _downloading = {};

  /// Bytes in finished files.
  int get totalBytes => _entries.values.fold(0, (sum, entry) => sum + entry.size);

  /// What the storage settings show.
  AudioCacheUsage get usage => AudioCacheUsage(files: _entries.length, bytes: totalBytes, limit: maxBytes);

  /// Keys of finished files, least recently used first.
  List<String> get keys =>
      ([..._entries.entries]..sort((a, b) => a.value.used.compareTo(b.value.used))).map((entry) => entry.key).toList();

  /// Reads the directory: finished files join the index (last use = their
  /// modification time), leftover partial files are deleted.
  Future<void> load() async {
    _entries.clear();
    for (final file in await files.list()) {
      if (file.name.endsWith('.m4a.part')) {
        await files.delete(file.name);
      } else if (file.name.endsWith('.m4a')) {
        _entries[file.name.substring(0, file.name.length - 4)] = _Entry(file.size, file.modified);
      }
    }
  }

  /// The file of [key] when it is cached (and marks it used), else null.
  String? lookup(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    entry.used = _now();
    return AudioCacheKey.fileOf(key);
  }

  /// Whether [key] is downloading.
  bool isDownloading(String key) => _downloading.contains(key);

  /// Starts a download of [key]: the partial file name to write, or null
  /// when it is cached or already downloading.
  String? begin(String key) {
    if (_entries.containsKey(key) || !_downloading.add(key)) return null;
    return AudioCacheKey.partOf(key);
  }

  /// The download of [key] finished: the partial file becomes the cached
  /// file (an empty one is dropped), then the cache is trimmed. Returns the
  /// evicted keys.
  Future<List<String>> commit(String key, {Set<String> keep = const {}}) async {
    _downloading.remove(key);
    final part = AudioCacheKey.partOf(key);
    final size = await files.sizeOf(part) ?? 0;
    if (size <= 0) {
      await files.delete(part);
      return const [];
    }
    await files.rename(part, AudioCacheKey.fileOf(key));
    _entries[key] = _Entry(size, _now());
    return await trim(keep: {...keep, key});
  }

  /// The download of [key] failed or was cancelled: its partial file goes.
  Future<void> abort(String key) async {
    _downloading.remove(key);
    await files.delete(AudioCacheKey.partOf(key));
  }

  /// Evicts least recently used files until the cache fits [maxBytes];
  /// [keep] is never evicted. Returns the evicted keys.
  Future<List<String>> trim({Set<String> keep = const {}}) async {
    final evicted = <String>[];
    var total = totalBytes;
    for (final key in keys) {
      if (total <= maxBytes) break;
      if (keep.contains(key)) continue;
      total -= _entries.remove(key)!.size;
      await files.delete(AudioCacheKey.fileOf(key));
      evicted.add(key);
    }
    return evicted;
  }

  /// Removes [key].
  Future<void> remove(String key) async {
    if (_entries.remove(key) != null) await files.delete(AudioCacheKey.fileOf(key));
  }

  /// Empties the cache (downloads in progress finish into it).
  Future<void> clear() async {
    for (final key in [..._entries.keys]) {
      await remove(key);
    }
  }
}

final class _Entry {
  new(this.size, this.used);

  final int size;
  DateTime used;
}

/// A cached file as the app shows it in storage settings.
@immutable
final class AudioCacheUsage {
  /// Creates the usage.
  const new({required this.files, required this.bytes, required this.limit});

  /// Number of tracks.
  final int files;

  /// Bytes used.
  final int bytes;

  /// The limit.
  final int limit;
}
