import 'dart:async';
import 'dart:convert';

import 'package:live_store/src/database.dart';
import 'package:live_store/src/settings/setting.dart';
import 'package:live_store/src/settings/settings.dart';

/// Settings values: read synchronously from memory (loaded when the store
/// opens, so the UI never builds before them; 3.x REG: first launch after an
/// upgrade built the UI before the settings service), written through to the
/// database.
final class SettingsStore {
  new _(this._db, this._values);

  /// Loads every stored value from [db].
  static Future<SettingsStore> load(StoreDatabase db) async {
    final values = <String, Object?>{};
    for (final row in await db.rows('SELECT key, value FROM settings')) {
      try {
        values[row.read<String>('key')] = jsonDecode(row.read<String>('value'));
      } on FormatException {
        // A damaged value reads as the default.
      }
    }
    return SettingsStore._(db, values);
  }

  final StoreDatabase _db;
  final Map<String, Object?> _values;
  final StreamController<Setting<Object>> _changes = StreamController.broadcast();

  /// The current value of [setting]: the stored one when valid, else its
  /// default.
  T get<T extends Object>(Setting<T> setting) => setting.read(_values[setting.key]);

  /// Whether a value is stored for [setting] (not just the default).
  bool isSet(Setting<Object> setting) => _values.containsKey(setting.key);

  /// Stores [value], repaired by the setting's rules (clamped, or the default
  /// for an unknown choice).
  Future<void> set<T extends Object>(Setting<T> setting, T value) => setAll({setting: value});

  /// Stores several values in one transaction (3.x `HivePrefUtil.setPrefs`).
  Future<void> setAll(Map<Setting<Object>, Object> values) async {
    final encoded = <Setting<Object>, Object>{
      for (final entry in values.entries) entry.key: _encode(entry.key, entry.value),
    };
    await _db.write({StoreTables.settings}, () async {
      for (final entry in encoded.entries) {
        await _db.run('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [
          entry.key.key,
          jsonEncode(entry.value),
        ]);
      }
    });
    for (final entry in encoded.entries) {
      final changed = jsonEncode(_values[entry.key.key]) != jsonEncode(entry.value);
      _values[entry.key.key] = entry.value;
      if (changed) _changes.add(entry.key);
    }
  }

  /// Back to the default.
  Future<void> reset(Setting<Object> setting) async {
    await _db.write({StoreTables.settings}, () => _db.run('DELETE FROM settings WHERE key = ?', [setting.key]));
    if (_values.remove(setting.key) != null) _changes.add(setting);
  }

  /// Every user setting back to its default ([SettingScope.internal] ones
  /// stay).
  Future<void> resetAll() async {
    final user = [
      for (final setting in Settings.all)
        if (setting.scope != SettingScope.internal && _values.containsKey(setting.key)) setting,
    ];
    await _db.write({StoreTables.settings}, () async {
      for (final setting in user) {
        await _db.run('DELETE FROM settings WHERE key = ?', [setting.key]);
      }
    });
    for (final setting in user) {
      _values.remove(setting.key);
      _changes.add(setting);
    }
  }

  /// Settings whose value changed.
  Stream<Setting<Object>> get changes => _changes.stream;

  /// The value of [setting] now and after every change.
  Stream<T> watch<T extends Object>(Setting<T> setting) => Stream.multi((controller) {
    controller.add(get(setting));
    final subscription = changes
        .where((changed) => changed.key == setting.key)
        .listen((_) => controller.add(get(setting)));
    controller.onCancel = subscription.cancel;
  });

  Object _encode(Setting<Object> setting, Object value) {
    final repaired = setting.read(value);
    return setting.encode(repaired);
  }

  /// Closes [changes].
  Future<void> close() => _changes.close();
}
