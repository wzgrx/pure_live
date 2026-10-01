import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';

/// The system share sheet (3.x `share_plus` on phones), or null where the
/// app has none yet: then a share copies the text (M12.3 adds the plugin
/// and sets `sheet` in `main`).
abstract final class SystemShare {
  /// Hands the text to the share sheet; completes with whether it was shown.
  static Future<bool> Function(String text)? sheet;
}

/// 3.x's room share code (`ShareCommandCodec.encodeShort`): a MessagePack map
/// `{m: pure_live, p, r, ti, n, l, c, a}` in URL-safe Base64 without
/// padding, which 3.x and the link page read back. Empty when the room has
/// no platform or room id (3.x `share_failed`).
String encodeRoomShareCode(LiveRoom room) {
  if (room.platform.trim().isEmpty || room.roomId.trim().isEmpty) return '';
  final fields = <String, String>{
    'm': 'pure_live',
    'p': room.platform,
    'r': room.roomId,
    'ti': room.title,
    'n': room.nick,
    'l': room.link ?? '',
    'c': room.cover,
    'a': room.avatar,
  };
  final bytes = BytesBuilder(copy: false)..addByte(0x80 | fields.length);
  void string(String text) {
    final utf8Bytes = utf8.encode(text);
    final length = utf8Bytes.length;
    if (length < 32) {
      bytes.addByte(0xa0 | length);
    } else if (length < 0x100) {
      bytes
        ..addByte(0xd9)
        ..addByte(length);
    } else if (length < 0x10000) {
      bytes
        ..addByte(0xda)
        ..add([length >> 8, length & 0xff]);
    } else {
      bytes
        ..addByte(0xdb)
        ..add([length >> 24 & 0xff, length >> 16 & 0xff, length >> 8 & 0xff, length & 0xff]);
    }
    bytes.add(utf8Bytes);
  }

  for (final MapEntry(:key, :value) in fields.entries) {
    string(key);
    string(value);
  }
  return base64Url.encode(bytes.takeBytes()).replaceAll('=', '');
}
