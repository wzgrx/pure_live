import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// A room found in shared or copied text.
@immutable
final class SharedRoom {
  /// Creates a result.
  const new(this.ref, {this.title = '', this.anchorName = '', this.fromShareCode = false});

  /// The room.
  final RoomRef ref;

  /// Title carried by a share code.
  final String title;

  /// Streamer's name carried by a share code.
  final String anchorName;

  /// Whether the text was a share code (not a link).
  final bool fromShareCode;

  @override
  bool operator ==(Object other) =>
      other is SharedRoom &&
      other.ref == ref &&
      other.title == title &&
      other.anchorName == anchorName &&
      other.fromShareCode == fromShareCode;

  @override
  int get hashCode => Object.hash(ref, title, anchorName, fromShareCode);

  @override
  String toString() => 'SharedRoom(${ref.key}${fromShareCode ? ', code' : ''})';
}

/// Finds a room in text (F-SHR-02): a 3.x-compatible share code first, then
/// a room link through the platform adapters. Only rooms of platforms this
/// build supports count.
final class ShareTextRecognizer {
  /// Creates a recognizer; [resolveLink] asks the adapters, [supports] says
  /// whether a platform id has an adapter.
  new({required this.resolveLink, required this.supports});

  /// The adapters' link resolution.
  final Future<RoomRef?> Function(String text) resolveLink;

  /// Whether a platform id has an adapter.
  final bool Function(String platform) supports;

  /// Longest text looked at; clipboards can hold whole documents.
  static const maxLength = 4096;

  /// The share code in [text] (the whole text or one of its words), or null.
  static ShareCode? findShareCode(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    final whole = ShareCode.decode(trimmed);
    if (whole != null) return whole;
    for (final word in trimmed.split(RegExp(r'\s+'))) {
      if (word.length < 16 || word == trimmed) continue;
      final code = ShareCode.decode(word);
      if (code != null) return code;
    }
    return null;
  }

  /// Whether [text] may hold a link worth asking the adapters about.
  static bool mayContainLink(String text) =>
      RegExp(r'https?://|\b[\w-]+\.(com|cn|tv|net)\b', caseSensitive: false).hasMatch(text);

  /// The room in [text], or null.
  Future<SharedRoom?> recognize(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    final code = findShareCode(trimmed);
    if (code != null) {
      if (!supports(code.ref.platform)) return null;
      return SharedRoom(code.ref, title: code.title, anchorName: code.anchorName, fromShareCode: true);
    }
    if (!mayContainLink(trimmed)) return null;
    try {
      final ref = await resolveLink(trimmed);
      return ref == null || !supports(ref.platform) ? null : SharedRoom(ref);
    } on Object {
      return null;
    }
  }
}
