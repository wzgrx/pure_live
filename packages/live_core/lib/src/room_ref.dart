import 'package:meta/meta.dart';

/// The identity of a live room: a platform id and a room id.
///
/// The platform id is trimmed and lower-cased; the room id is trimmed and keeps
/// its case, because some platforms use case-sensitive room ids
/// (spec/modules/store.md).
@immutable
final class RoomRef {
  /// Normalises [platform] and [roomId]; throws [FormatException] when either
  /// is empty or a placeholder such as `0`, `null` or `undefined`.
  factory(String platform, String roomId) {
    final normalizedPlatform = platform.trim().toLowerCase();
    final normalizedRoomId = roomId.trim();
    if (normalizedPlatform.isEmpty) {
      throw const FormatException('Empty platform id');
    }
    if (_isPlaceholder(normalizedRoomId)) {
      throw FormatException('Invalid room id', roomId);
    }
    return RoomRef._(normalizedPlatform, normalizedRoomId);
  }

  const new _(this.platform, this.roomId);

  /// Parses the `platform:roomId` form produced by [key].
  factory parse(String key) {
    final separator = key.indexOf(':');
    if (separator <= 0) throw FormatException('Expected platform:roomId', key);
    return RoomRef(key.substring(0, separator), key.substring(separator + 1));
  }

  /// Lower-case platform id, for example `douyu`.
  final String platform;

  /// Room id as the platform spells it.
  final String roomId;

  /// Stable storage key: `platform:roomId`.
  String get key => '$platform:$roomId';

  static const _placeholders = {'', '0', 'null', 'undefined', 'nan', 'none'};

  static bool _isPlaceholder(String roomId) => _placeholders.contains(roomId.toLowerCase());

  @override
  bool operator ==(Object other) => other is RoomRef && other.platform == platform && other.roomId == roomId;

  @override
  int get hashCode => Object.hash(platform, roomId);

  @override
  String toString() => 'RoomRef($key)';
}
