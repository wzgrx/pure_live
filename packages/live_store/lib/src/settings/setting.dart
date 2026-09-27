import 'package:meta/meta.dart';

/// Where a setting travels (spec/modules/store.md §5).
enum SettingScope {
  /// In every backup and in cross-device sync.
  synced,

  /// Only in full backups, and restored only on the same platform family
  /// (Android to Android, Windows to Windows).
  device,

  /// Never backed up and never reset: migration counters, caches, ids.
  internal,
}

/// Converts a 3.x value to the v4 JSON value of a setting; returns null when
/// the old value should be ignored.
typedef LegacyConvert = Object? Function(Object? value);

/// A 3.x name of a setting: a Hive key or a field name in an old backup.
@immutable
final class LegacyKey {
  /// A 3.x [name] whose value converts with [convert], or unchanged when
  /// [convert] is null.
  const new(this.name, {this.convert});

  /// Hive key or backup field name.
  final String name;

  /// Value conversion; null keeps the value as it is.
  final LegacyConvert? convert;

  /// Converts a 3.x [value] to a v4 JSON value.
  Object? apply(Object? value) => convert == null ? value : convert!(value);
}

/// One entry of the settings registry (store.md §5, ADR 0004 §4).
///
/// A setting knows its id, default, validation and JSON codec, its 3.x names
/// and its scope. Backup range, reset and import all derive from the registry.
@immutable
abstract base class Setting<T extends Object> {
  /// Creates a definition.
  const new(this.id, this.defaultValue, {this.scope = SettingScope.synced, this.legacy = const []});

  /// v4 key, for example `danmaku.speed`.
  final String id;

  /// Value used when nothing valid is stored.
  final T defaultValue;

  /// Backup and sync range.
  final SettingScope scope;

  /// 3.x names, tried in order.
  final List<LegacyKey> legacy;

  /// Decodes a stored JSON [value]; returns null when it is not valid for
  /// this setting. Values out of range are clamped rather than rejected.
  T? decode(Object? value);

  /// Encodes a valid [value] as JSON.
  Object encode(T value) => value;

  /// Clamps or checks [value]; returns null when it cannot be stored.
  T? normalize(T value) => value;

  /// Decodes [value], falling back to [defaultValue].
  T decodeOrDefault(Object? value) => decode(value) ?? defaultValue;

  @override
  String toString() => 'Setting($id)';
}

/// A true/false setting.
final class BoolSetting extends Setting<bool> {
  /// Creates a definition. The default is positional like every other
  /// setting type, so registry entries read `(id, default)`.
  // ignore: avoid_positional_boolean_parameters
  const new(super.id, super.defaultValue, {super.scope, super.legacy});

  @override
  bool? decode(Object? value) => switch (value) {
    final bool flag => flag,
    'true' => true,
    'false' => false,
    _ => null,
  };
}

/// An integer setting, clamped to [min]..[max].
final class IntSetting extends Setting<int> {
  /// Creates a definition.
  const new(super.id, super.defaultValue, {this.min, this.max, super.scope, super.legacy});

  /// Lowest allowed value.
  final int? min;

  /// Highest allowed value.
  final int? max;

  @override
  int? decode(Object? value) {
    final number = switch (value) {
      final int whole => whole,
      final double real when real.isFinite => real.round(),
      final String text => int.tryParse(text.trim()) ?? double.tryParse(text.trim())?.round(),
      _ => null,
    };
    return number == null ? null : normalize(number);
  }

  @override
  int normalize(int value) {
    var result = value;
    if (min != null && result < min!) result = min!;
    if (max != null && result > max!) result = max!;
    return result;
  }
}

/// A floating-point setting, clamped to [min]..[max].
final class DoubleSetting extends Setting<double> {
  /// Creates a definition.
  const new(super.id, super.defaultValue, {this.min, this.max, super.scope, super.legacy});

  /// Lowest allowed value.
  final double? min;

  /// Highest allowed value.
  final double? max;

  @override
  double? decode(Object? value) {
    final number = switch (value) {
      final num real => real.toDouble(),
      final String text => double.tryParse(text.trim()),
      _ => null,
    };
    return number == null ? null : normalize(number);
  }

  @override
  double? normalize(double value) {
    if (!value.isFinite) return null;
    var result = value;
    if (min != null && result < min!) result = min!;
    if (max != null && result > max!) result = max!;
    return result;
  }
}

/// A text setting; [allowed] restricts it to a fixed set of values.
final class StringSetting extends Setting<String> {
  /// Creates a definition.
  const new(super.id, super.defaultValue, {this.allowed, this.maxLength = 4096, super.scope, super.legacy});

  /// Allowed values; null allows any text up to [maxLength].
  final Set<String>? allowed;

  /// Longest allowed text.
  final int maxLength;

  @override
  String? decode(Object? value) => value is String ? normalize(value) : null;

  @override
  String? normalize(String value) {
    if (value.length > maxLength) return null;
    if (allowed != null && !allowed!.contains(value)) return null;
    return value;
  }
}

/// A setting whose value is one of an enum's [values], stored by name.
final class EnumSetting<E extends Enum> extends Setting<E> {
  /// Creates a definition.
  const new(super.id, super.defaultValue, this.values, {super.scope, super.legacy});

  /// Every allowed value.
  final List<E> values;

  @override
  E? decode(Object? value) {
    if (value is! String) return null;
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    return null;
  }

  @override
  Object encode(E value) => value.name;
}

/// A list of strings, trimmed, without empty or duplicate items.
final class StringListSetting extends Setting<List<String>> {
  /// Creates a definition.
  const new(super.id, super.defaultValue, {this.lowerCase = false, this.maxItems = 1000, super.scope, super.legacy});

  /// Whether items are lower-cased (platform ids).
  final bool lowerCase;

  /// Longest allowed list.
  final int maxItems;

  @override
  List<String>? decode(Object? value) {
    if (value is! List) return null;
    return normalize([
      for (final item in value)
        if (item is String) item,
    ]);
  }

  @override
  List<String> normalize(List<String> value) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      final trimmed = lowerCase ? item.trim().toLowerCase() : item.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      result.add(trimmed);
      if (result.length == maxItems) break;
    }
    return List.unmodifiable(result);
  }
}
