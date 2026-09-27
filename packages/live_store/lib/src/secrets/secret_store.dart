import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_store/src/secrets/secret_cipher.dart';
import 'package:live_store/src/store_log.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Reference names of secrets (spec/modules/store.md §4).
abstract final class SecretRefs {
  /// Cookie header of [platform]: `cookie/<platform>`.
  static String cookie(String platform) => 'cookie/${platform.trim().toLowerCase()}';

  /// Douyu LTP0 token.
  static const douyuLtp0 = 'cookie/douyu.ltp0';

  /// Douyu device id.
  static const douyuDid = 'cookie/douyu.did';

  /// Password of WebDAV profile [profileId].
  static String webdav(String profileId) => 'webdav/$profileId';

  /// Password of Xtream provider [providerId].
  static String xtream(String providerId) => 'iptv/xtream/$providerId';

  /// The platform a `cookie/...` reference belongs to (`cookie/douyu.ltp0`
  /// belongs to `douyu`), or null for other references.
  static String? platformOf(String ref) {
    if (!ref.startsWith('cookie/')) return null;
    final rest = ref.substring('cookie/'.length);
    final dot = rest.indexOf('.');
    final platform = dot < 0 ? rest : rest.substring(0, dot);
    return platform.isEmpty ? null : platform;
  }
}

/// Where sealed secrets live: a map from reference name to sealed blob.
abstract interface class SecretBackend {
  /// Every stored blob.
  Future<Map<String, Uint8List>> read();

  /// Replaces every stored blob; must be atomic.
  Future<void> write(Map<String, Uint8List> blobs);
}

/// Keeps blobs in memory, for tests.
final class MemorySecretBackend implements SecretBackend {
  /// Starts with [blobs].
  new([Map<String, Uint8List>? blobs]) : blobs = {...?blobs};

  /// The stored blobs.
  final Map<String, Uint8List> blobs;

  @override
  Future<Map<String, Uint8List>> read() async => {...blobs};

  @override
  Future<void> write(Map<String, Uint8List> blobs) async {
    this.blobs
      ..clear()
      ..addAll(blobs);
  }
}

/// Stores blobs in a JSON file, separate from the main database (ADR 0004
/// §3), written to `<file>.part` and renamed over the old file.
final class FileSecretBackend implements SecretBackend {
  /// Uses [file].
  const new(this.file);

  /// The secrets file under the data root [rootDirectory]:
  /// `<root>/DB/secrets.json`.
  factory inRoot(String rootDirectory) => FileSecretBackend(File(p.join(rootDirectory, 'DB', 'secrets.json')));

  /// The secrets file.
  final File file;

  static const _format = 'pure_live.secrets';

  @override
  Future<Map<String, Uint8List>> read() async {
    if (!file.existsSync()) return {};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?> || decoded['format'] != _format || decoded['version'] != 1) {
      throw const FormatException('Not a v1 secrets file');
    }
    final entries = decoded['entries'];
    if (entries is! Map<String, Object?>) return {};
    return {
      for (final MapEntry(:key, :value) in entries.entries)
        if (value is String) key: base64Decode(value),
    };
  }

  @override
  Future<void> write(Map<String, Uint8List> blobs) async {
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.part');
    final text = jsonEncode({
      'format': _format,
      'version': 1,
      'entries': {for (final MapEntry(:key, :value) in blobs.entries) key: base64Encode(value)},
    });
    await staged.writeAsString(text, flush: true);
    await staged.rename(file.path);
  }
}

/// Secrets (cookies, passwords) encrypted at rest (store.md §4).
///
/// Secrets are decrypted once when the store opens and kept in memory, so
/// [read] is synchronous (the shape `live_net`'s `CookieVault` needs). A
/// secret that cannot be decrypted (other device, reinstall, lost key) reads
/// as absent, which the app shows as "signed out"; it is listed in
/// [unreadable] and kept on disk until that reference is written again.
/// Values never appear in [toString], logs or exceptions.
final class SecretStore {
  new _(this._cipher, this._backend, this._log);

  /// Opens the store, decrypting every blob from [backend] with [cipher].
  static Future<SecretStore> open({
    required SecretCipher cipher,
    required SecretBackend backend,
    StoreLog log = StoreLog.silent,
  }) async {
    final store = SecretStore._(cipher, backend, log);
    Map<String, Uint8List> blobs;
    try {
      blobs = await backend.read();
    } on Object catch (error) {
      log.warning('secrets: store unreadable (${error.runtimeType}); treating every account as signed out');
      blobs = {};
    }
    store._blobs.addAll(blobs);
    for (final MapEntry(:key, :value) in blobs.entries) {
      try {
        store._values[key] = utf8.decode(await cipher.open(value, _aad(key)));
      } on Object catch (error) {
        store._unreadable.add(key);
        log.warning('secrets: cannot decrypt $key (${error.runtimeType}); treating it as signed out');
      }
    }
    return store;
  }

  /// A store in memory with [values], for tests and the command-line tools.
  static Future<SecretStore> memory([Map<String, String> values = const {}]) async {
    final store = SecretStore._(_PlainCipher(), MemorySecretBackend(), StoreLog.silent);
    await store.writeAll(values);
    return store;
  }

  final SecretCipher _cipher;
  final SecretBackend _backend;
  final StoreLog _log;
  final Map<String, String> _values = {};
  // Every blob on disk, including unreadable ones, so a write never drops a
  // secret that only failed to decrypt this time.
  final Map<String, Uint8List> _blobs = {};
  final Set<String> _unreadable = {};
  final StreamController<String> _changes = StreamController<String>.broadcast();
  Future<void> _pending = Future.value();

  static Uint8List _aad(String ref) => Uint8List.fromList(utf8.encode('pure_live.secret|$ref'));

  /// The secret [ref], or null when absent or unreadable.
  String? read(String ref) => _values[ref];

  /// Reference names with a readable value.
  Set<String> get refs => Set.unmodifiable(_values.keys);

  /// Reference names stored on disk that could not be decrypted.
  Set<String> get unreadable => Set.unmodifiable(_unreadable);

  /// Emits a reference name after its value changed and was stored.
  Stream<String> get changes => _changes.stream;

  /// The cookie header of [platform], or null when signed out.
  String? cookieFor(String platform) => read(SecretRefs.cookie(platform));

  /// Emits a platform id whenever one of its `cookie/...` secrets changes;
  /// with [cookieFor] this implements `live_net`'s `CookieVault`.
  Stream<String> get cookieChanges =>
      changes.map(SecretRefs.platformOf).where((platform) => platform != null).cast<String>();

  /// Stores [value] under [ref]; null or blank removes it.
  Future<void> write(String ref, String? value) => writeAll({ref: value});

  /// Stores several values at once (one file write); null or blank removes.
  Future<void> writeAll(Map<String, String?> values) {
    final run = _pending.then((_) => _writeAll(values));
    _pending = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _writeAll(Map<String, String?> values) async {
    final blobs = {..._blobs};
    final next = {..._values};
    final changed = <String>{};
    for (final MapEntry(:key, :value) in values.entries) {
      if (value == null || value.trim().isEmpty) {
        if (next.remove(key) != null) changed.add(key);
        blobs.remove(key);
        continue;
      }
      if (next[key] == value && !_unreadable.contains(key)) continue;
      blobs[key] = await _cipher.seal(Uint8List.fromList(utf8.encode(value)), _aad(key));
      next[key] = value;
      changed.add(key);
    }
    final replacedUnreadable = values.keys.where(_unreadable.contains).toSet();
    if (changed.isEmpty && replacedUnreadable.isEmpty) return;
    await _backend.write(blobs);
    _blobs
      ..clear()
      ..addAll(blobs);
    _values
      ..clear()
      ..addAll(next);
    _unreadable.removeAll(replacedUnreadable);
    changed.forEach(_changes.add);
  }

  /// Removes every secret (readable or not) whose reference passes [test].
  Future<void> removeWhere(bool Function(String ref) test) => writeAll({
    for (final ref in {..._values.keys, ..._unreadable})
      if (test(ref)) ref: null,
  });

  /// Every readable secret, for an encrypted backup section (store.md §7.3).
  @internal
  Map<String, String> exportAll() => Map.unmodifiable(_values);

  /// Closes [changes].
  Future<void> dispose() async {
    await _pending;
    await _changes.close();
  }

  @override
  String toString() => 'SecretStore(${_values.length} secrets)';

  /// Logs through the store's log; used by importers.
  @internal
  void warn(String message) => _log.warning(message);
}

/// No encryption; only for [SecretStore.memory].
final class _PlainCipher implements SecretCipher {
  @override
  Future<Uint8List> open(Uint8List sealed, Uint8List associatedData) async => sealed;

  @override
  Future<Uint8List> seal(Uint8List plaintext, Uint8List associatedData) async => plaintext;
}
