import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

/// A room share code (spec/modules/store.md §8), compatible with 3.x: the
/// base64url text (no padding) of a MessagePack map
/// `{m: 'pure_live', p, r, ti, n, l, c, a}`.
@immutable
final class ShareCode {
  /// Creates a code for [ref] with optional display data.
  const new(this.ref, {this.title = '', this.anchorName = '', this.link = '', this.cover = '', this.avatar = ''});

  /// Room identity.
  final RoomRef ref;

  /// Broadcast title.
  final String title;

  /// Streamer's name.
  final String anchorName;

  /// Room link.
  final String link;

  /// Cover URL.
  final String cover;

  /// Avatar URL.
  final String avatar;

  static const _magic = 'pure_live';

  /// The share text.
  String encode() {
    final bytes = _MessagePack.encodeMap({
      'm': _magic,
      'p': ref.platform,
      'r': ref.roomId,
      'ti': title,
      'n': anchorName,
      'l': link,
      'c': cover,
      'a': avatar,
    });
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Decodes share [text]; null when it is not a Pure Live share code or its
  /// room identity is invalid.
  static ShareCode? decode(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 8192) return null;
    try {
      final normalized = trimmed.replaceAll('+', '-').replaceAll('/', '_');
      final padded = normalized.padRight(normalized.length + (4 - normalized.length % 4) % 4, '=');
      final map = _MessagePack.decodeMap(base64Url.decode(padded));
      if (map == null || map['m'] != _magic) return null;
      String field(String key) => switch (map[key]) {
        final String value => value,
        final int value => '$value',
        _ => '',
      };
      return ShareCode(
        RoomRef(field('p'), field('r')),
        title: field('ti'),
        anchorName: field('n'),
        link: field('l'),
        cover: field('c'),
        avatar: field('a'),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'ShareCode(${ref.key})';
}

/// The MessagePack subset share codes use: a map of strings, integers, nil
/// and booleans.
abstract final class _MessagePack {
  static Uint8List encodeMap(Map<String, String> map) {
    final out = BytesBuilder();
    if (map.length < 16) {
      out.addByte(0x80 | map.length);
    } else {
      out
        ..addByte(0xde)
        ..add(_u16(map.length));
    }
    for (final MapEntry(:key, :value) in map.entries) {
      _string(out, key);
      _string(out, value);
    }
    return out.takeBytes();
  }

  static void _string(BytesBuilder out, String value) {
    final bytes = utf8.encode(value);
    final length = bytes.length;
    if (length < 32) {
      out.addByte(0xa0 | length);
    } else if (length < 0x100) {
      out
        ..addByte(0xd9)
        ..addByte(length);
    } else if (length < 0x10000) {
      out
        ..addByte(0xda)
        ..add(_u16(length));
    } else {
      out
        ..addByte(0xdb)
        ..add(_u32(length));
    }
    out.add(bytes);
  }

  static List<int> _u16(int value) => [value >> 8 & 0xff, value & 0xff];

  static List<int> _u32(int value) => [value >> 24 & 0xff, value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff];

  static Map<String, Object?>? decodeMap(Uint8List bytes) {
    final reader = _Reader(bytes);
    final value = reader.value();
    if (!reader.done) throw const FormatException('Trailing bytes');
    if (value is! Map) return null;
    return {
      for (final MapEntry(:key, :value) in value.entries)
        if (key is String) key: value,
    };
  }
}

final class _Reader {
  new(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;
  int _depth = 0;

  bool get done => _offset == _bytes.length;

  int _byte() {
    if (_offset >= _bytes.length) throw const FormatException('Truncated share code');
    return _bytes[_offset++];
  }

  int _uint(int length) {
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = value << 8 | _byte();
    }
    return value;
  }

  Object? value() {
    final type = _byte();
    if (type <= 0x7f) return type;
    if (type >= 0xe0) return type - 0x100;
    if (type & 0xe0 == 0xa0) return _string(type & 0x1f);
    if (type & 0xf0 == 0x80) return _map(type & 0x0f);
    return switch (type) {
      0xc0 => null,
      0xc2 => false,
      0xc3 => true,
      0xcc => _uint(1),
      0xcd => _uint(2),
      0xce => _uint(4),
      0xcf => _uint(8),
      0xd0 => _uint(1).toSigned(8),
      0xd1 => _uint(2).toSigned(16),
      0xd2 => _uint(4).toSigned(32),
      0xd3 => _uint(8).toSigned(64),
      0xd9 => _string(_uint(1)),
      0xda => _string(_uint(2)),
      0xdb => _string(_uint(4)),
      0xde => _map(_uint(2)),
      0xdf => _map(_uint(4)),
      _ => throw const FormatException('Unsupported MessagePack type'),
    };
  }

  String _string(int length) {
    if (_offset + length > _bytes.length) throw const FormatException('Truncated string');
    final text = utf8.decode(Uint8List.sublistView(_bytes, _offset, _offset + length));
    _offset += length;
    return text;
  }

  Map<Object?, Object?> _map(int length) {
    if (++_depth > 4) throw const FormatException('Nested too deep');
    final map = <Object?, Object?>{};
    for (var i = 0; i < length; i++) {
      final key = value();
      map[key] = value();
    }
    _depth--;
    return map;
  }
}
