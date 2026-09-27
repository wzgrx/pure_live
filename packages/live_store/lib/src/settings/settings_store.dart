import 'dart:async';
import 'dart:convert';

import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/settings/registry.dart';
import 'package:live_store/src/settings/setting.dart';
import 'package:live_store/src/store_log.dart';
import 'package:meta/meta.dart';

/// Typed access to the settings table (spec/modules/store.md §5).
///
/// Values load once when the store opens, so [get] is synchronous and the UI
/// can build from it (REG-STORE-001: storage is ready before the first
/// frame). Writes complete in the database before the cached value and the
/// [watch] streams change.
final class SettingsStore {
  /// Wraps [_db]; call [load] before reading.
  new(this._db, {StoreLog? log}) : _log = log ?? StoreLog.silent;

  final StoreDatabase _db;
  final StoreLog _log;
  final Map<String, Object> _values = {};
  final StreamController<String> _changes = StreamController<String>.broadcast();

  /// Ids of settings that changed, after the change is stored.
  Stream<String> get changes => _changes.stream;

  /// (Re)reads every stored value, emitting [changes] for values that differ
  /// from the cache. Unknown keys and invalid values are ignored and logged.
  Future<void> load() async {
    final rows = await _db.select(_db.settingEntries).get();
    final next = <String, Object>{};
    for (final row in rows) {
      final setting = Settings.byId(row.key);
      if (setting == null) {
        _log.warning('settings: ignoring unknown key ${row.key}');
        continue;
      }
      final value = setting.decode(_tryDecode(row.value));
      if (value == null) {
        _log.warning('settings: invalid stored value for ${row.key}, using the default');
        continue;
      }
      next[row.key] = value;
    }
    final changed = <String>{
      for (final id in {..._values.keys, ...next.keys})
        if (!_sameJson(_values[id], next[id])) id,
    };
    _values
      ..clear()
      ..addAll(next);
    changed.forEach(_changes.add);
  }

  /// The current value of [setting].
  T get<T extends Object>(Setting<T> setting) {
    final value = _values[setting.id];
    return value is T ? value : setting.defaultValue;
  }

  /// Whether [setting] has a stored value (as opposed to its default).
  bool isSet(Setting<Object> setting) => _values.containsKey(setting.id);

  /// Stores [value]; throws [ArgumentError] when the setting rejects it.
  /// Out-of-range numbers are clamped.
  Future<void> set<T extends Object>(Setting<T> setting, T value) async {
    // Through decode, so an int for a double setting (inferred T = Object)
    // converts instead of failing a runtime cast.
    final normalized = setting.decode(value is Enum ? value.name : value);
    if (normalized == null) throw ArgumentError.value(value, setting.id, 'Invalid value');
    await _db
        .into(_db.settingEntries)
        .insertOnConflictUpdate(
          SettingEntriesCompanion.insert(
            key: setting.id,
            value: jsonEncode(setting.encode(normalized)),
            updatedAt: _now(),
          ),
        );
    final previous = _values[setting.id];
    _values[setting.id] = normalized;
    if (!_sameJson(previous, normalized)) _changes.add(setting.id);
  }

  /// Removes the stored value of [setting], so it reads as its default.
  Future<void> reset(Setting<Object> setting) async {
    await (_db.delete(_db.settingEntries)..where((row) => row.key.equals(setting.id))).go();
    if (_values.remove(setting.id) != null) _changes.add(setting.id);
  }

  /// Resets every setting in [scopes]; internal settings are never reset.
  Future<void> resetAll({Set<SettingScope> scopes = const {SettingScope.synced, SettingScope.device}}) async {
    final ids = [
      for (final setting in Settings.all)
        if (setting.scope != SettingScope.internal && scopes.contains(setting.scope)) setting.id,
    ];
    await (_db.delete(_db.settingEntries)..where((row) => row.key.isIn(ids))).go();
    await load();
  }

  /// Emits the current value of [setting] on listen and after each change.
  Stream<T> watch<T extends Object>(Setting<T> setting) {
    late final StreamController<T> controller;
    StreamSubscription<String>? subscription;
    controller = StreamController<T>(
      onListen: () {
        var last = get(setting);
        controller.add(last);
        subscription = _changes.stream.where((id) => id == setting.id).listen((_) {
          final next = get(setting);
          if (_sameJson(last, next)) return;
          last = next;
          controller.add(next);
        });
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  /// Stored values of the settings in [scopes], encoded as JSON values, in
  /// registry order. Defaults that were never set are left out.
  Map<String, Object> export(Set<SettingScope> scopes) => {
    for (final setting in Settings.all)
      if (scopes.contains(setting.scope) && _values.containsKey(setting.id))
        setting.id: setting.encode(_values[setting.id]!),
  };

  /// Closes [changes]; streams from [watch] stop emitting.
  @internal
  Future<void> dispose() => _changes.close();

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static bool _sameJson(Object? a, Object? b) {
    if (a is List || b is List) return jsonEncode(_encodable(a)) == jsonEncode(_encodable(b));
    return a == b;
  }

  static Object? _encodable(Object? value) => value is Enum ? value.name : value;

  static int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;
}
