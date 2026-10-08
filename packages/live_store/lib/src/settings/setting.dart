import 'dart:convert';

import 'package:meta/meta.dart';

/// Who a setting belongs to, which decides whether a backup carries it.
enum SettingScope {
  /// Carried by backups (3.x exported the same keys).
  synced,

  /// Bookkeeping such as 3.x's migration counters: never exported, never
  /// reset by the user.
  internal,
}

/// One typed setting: its storage key (the 3.x Hive key, so 3.x data and
/// backups map one to one), the 3.x backup section and field it travels in,
/// its default and how a stored value is checked.
///
/// A stored or imported value that does not fit is repaired by [normalize]
/// (clamped, trimmed) or replaced by [defaultValue]; it never throws.
@immutable
sealed class Setting<T extends Object> {
  const new(
    this.key, {
    required this.section,
    required this.defaultValue,
    String? backupKey,
    this.scope = SettingScope.synced,
    this.legacyKeys = const [],
  }) : backupKey = backupKey ?? key;

  /// Storage key; the same as 3.x's Hive key.
  final String key;

  /// The 3.x backup section (`app`, `danmaku`, ...) the setting is written to.
  final String section;

  /// The field name inside [section]; differs from [key] for a few 3.x
  /// settings (for example `pipDanmaNoEmojiMode` is written as
  /// `pipDanmakuNoEmojiMode`).
  final String backupKey;

  /// Older names read when [backupKey] is absent from a backup.
  final List<String> legacyKeys;

  /// The value used when nothing (or nothing valid) is stored.
  final T defaultValue;

  /// Whether backups carry the setting.
  final SettingScope scope;

  /// [raw] as a valid value, or null when it cannot be read as one.
  T? decode(Object? raw);

  /// [value] repaired to the allowed range; the identity by default.
  T normalize(T value) => value;

  /// [raw] read and repaired, or [defaultValue].
  T read(Object? raw) {
    final value = decode(raw);
    return value == null ? defaultValue : normalize(value);
  }

  /// [value] as stored (JSON-compatible).
  Object encode(T value) => value;

  @override
  String toString() => 'Setting($key)';
}

/// A switch.
final class BoolSetting extends Setting<bool> {
  /// Creates a switch.
  const new(super.key, {required super.section, required super.defaultValue, super.backupKey, super.scope});

  @override
  bool? decode(Object? raw) => switch (raw) {
    final bool value => value,
    'true' => true,
    'false' => false,
    _ => null,
  };
}

/// A whole number, clamped to [min]..[max] when given; or, as 3.x repaired
/// some (J01.3), back to [defaultValue] when out of range
/// ([resetOutOfRange]), or rounded to the nearest multiple of [step].
final class IntSetting extends Setting<int> {
  /// Creates a whole-number setting.
  const new(
    super.key, {
    required super.section,
    required super.defaultValue,
    this.min,
    this.max,
    this.resetOutOfRange = false,
    this.step = 1,
    super.backupKey,
    super.scope,
  });

  /// Smallest allowed value.
  final int? min;

  /// Largest allowed value.
  final int? max;

  /// Whether a value outside [min]..[max] reads as [defaultValue] instead
  /// of the nearer end (3.x's history limit, picture fit, proxy ports).
  final bool resetOutOfRange;

  /// The value is rounded to a multiple of this after clamping, then
  /// clamped again (3.x's danmaku weight: 550 is 600); 1 keeps it.
  final int step;

  @override
  int? decode(Object? raw) => switch (raw) {
    final int value => value,
    final double value when value.isFinite => value.round(),
    final String value => int.tryParse(value.trim()),
    _ => null,
  };

  @override
  int normalize(int value) {
    final clamped = _clamp(value);
    if (clamped != value && resetOutOfRange) return defaultValue;
    return step > 1 ? _clamp((clamped / step).round() * step) : clamped;
  }

  int _clamp(int value) {
    if (min case final low? when value < low) return low;
    if (max case final high? when value > high) return high;
    return value;
  }
}

/// A finite number, clamped to [min]..[max] when given.
final class DoubleSetting extends Setting<double> {
  /// Creates a number setting.
  const new(
    super.key, {
    required super.section,
    required super.defaultValue,
    this.min,
    this.max,
    super.backupKey,
    super.scope,
  });

  /// Smallest allowed value.
  final double? min;

  /// Largest allowed value.
  final double? max;

  @override
  double? decode(Object? raw) {
    final value = switch (raw) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value.trim()),
      _ => null,
    };
    return value != null && value.isFinite ? value : null;
  }

  @override
  double normalize(double value) {
    if (min case final low? when value < low) return low;
    if (max case final high? when value > high) return high;
    return value;
  }
}

/// A text value; with [allowed], anything else reads as the default.
final class StringSetting extends Setting<String> {
  /// Creates a text setting.
  const new(
    super.key, {
    required super.section,
    required super.defaultValue,
    this.allowed,
    super.backupKey,
    super.scope,
    super.legacyKeys,
  });

  /// The only accepted values, when the setting is a choice.
  final Set<String>? allowed;

  @override
  String? decode(Object? raw) {
    if (raw is! String) return null;
    final choices = allowed;
    return choices == null || choices.contains(raw) ? raw : null;
  }
}

/// An ordered list of texts (platform ids, menu ids).
final class StringListSetting extends Setting<List<String>> {
  /// Creates a list setting.
  const new(super.key, {required super.section, required super.defaultValue, super.backupKey, super.scope});

  @override
  List<String>? decode(Object? raw) => raw is List ? List.unmodifiable([for (final item in raw) '$item']) : null;

  @override
  Object encode(List<String> value) => List<String>.of(value);
}

/// A JSON object stored as 3.x did: a JSON string in Hive, an object in
/// backups (room card appearance, per-room volumes).
final class JsonSetting extends Setting<Map<String, Object?>> {
  /// Creates a JSON object setting.
  const new(super.key, {required super.section, required super.defaultValue, super.backupKey, super.scope});

  @override
  Map<String, Object?>? decode(Object? raw) {
    var value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    return value is Map ? Map<String, Object?>.unmodifiable(value.map((k, v) => MapEntry('$k', v))) : null;
  }

  @override
  Object encode(Map<String, Object?> value) => Map<String, Object?>.of(value);
}
