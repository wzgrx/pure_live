import 'package:pure_live/core/iptv/models/channel.dart';
import 'package:pure_live/core/iptv/parsers/playlist_parse_result.dart';

/// Parses M3U and M3U Plus playlist formats.
///
/// Supports:
/// - Standard M3U (#EXTM3U / #EXTINF)
/// - M3U Plus extended attributes (tvg-id, tvg-name, tvg-logo, group-title, etc.)
/// - Channel numbering through tvg-chno
/// - Multiple URL formats (HTTP, HTTPS, RTMP, RTSP, UDP)
/// - EXTGRP inheritance and explicit group-title reset
class M3uParser {
  static const String _extInf = '#EXTINF:';
  static const String _extGrp = '#EXTGRP:';

  static String? lastEpgUrl;

  static final _header = RegExp(r'^#EXTM3U(?:\s|$)');

  PlaylistParseResult parse(String content, {required String providerId}) {
    final lines = content.split(RegExp(r'\r\n?|\n'));
    final channels = <Channel>[];
    final errors = <String>[];
    bool sawContent = false;
    _M3uMetadata? pending;
    int pendingLine = 0;
    String? directiveGroup;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (!sawContent) {
        sawContent = true;
        if (!_header.hasMatch(line)) errors.add('Line ${i + 1}: Missing #EXTM3U header');
      }
      if (_header.hasMatch(line)) continue;
      if (line.startsWith(_extInf)) {
        if (pending != null) errors.add('Line $pendingLine: Missing stream URL');
        pending = null;
        pendingLine = i + 1;
        try {
          pending = _parseMetadata(line.substring(_extInf.length));
          // A group-title belongs to this entry and ends EXTGRP inheritance.
          if (pending.attributes.containsKey('group-title')) directiveGroup = null;
        } on FormatException catch (e) {
          errors.add('Line $pendingLine: ${e.message}');
        }
        continue;
      }
      if (line.startsWith(_extGrp)) {
        directiveGroup = _emptyToNull(line.substring(_extGrp.length).trim());
        continue;
      }
      // Unknown extension directives are not stream URLs.
      if (line.startsWith('#')) continue;
      if (pending != null) {
        try {
          channels.add(_parseEntry(pending, line, providerId, directiveGroup));
        } on FormatException catch (e) {
          errors.add('Line ${i + 1}: ${e.message}');
        }
        pending = null;
      }
    }
    if (pending != null) errors.add('Line $pendingLine: Missing stream URL');
    if (!sawContent) errors.add('Playlist content is empty');
    return PlaylistParseResult(channels: channels, errors: errors);
  }

  Channel _parseEntry(_M3uMetadata metadata, String url, String providerId, String? directiveGroup) {
    if (!_isValidStreamUrl(url)) throw const FormatException('Invalid or unsupported stream URL');
    final attrs = {...metadata.attributes};
    if (!attrs.containsKey('group-title') && directiveGroup != null) attrs['group-title'] = directiveGroup;
    final name = metadata.displayName.isNotEmpty ? metadata.displayName : attrs['tvg-name'];
    if (name == null || name.isEmpty) throw const FormatException('Missing channel name');

    // 生成唯一频道ID
    final tvgId = attrs['tvg-id'];
    final String uniqueKey;

    // 智能生成唯一键：优先 tvg-id → 其次频道名 → 最后链接
    if (tvgId != null && tvgId.isNotEmpty) {
      uniqueKey = tvgId;
    } else if (name.isNotEmpty) {
      uniqueKey = name;
    } else {
      uniqueKey = url;
    }
    final channelId = '${providerId}_${uniqueKey.hashCode}';

    // 解析频道序号
    int? channelNumber;
    final chnoStr = attrs['tvg-chno'];
    if (chnoStr != null) channelNumber = int.tryParse(chnoStr);

    return Channel(
      id: channelId,
      providerId: providerId,
      name: name,
      tvgId: _emptyToNull(attrs['tvg-id']),
      tvgName: _emptyToNull(attrs['tvg-name']),
      tvgLogo: _emptyToNull(attrs['tvg-logo']),
      groupTitle: _emptyToNull(attrs['group-title']),
      channelNumber: channelNumber,
      streamUrl: url,
      streamType: _inferStreamType(attrs, url),
    );
  }

  /// Read one attribute at a time, stopping at the first comma outside a
  /// quoted value. Display text is never scanned as metadata. Quoted values
  /// may contain commas and the opposite quote; unquoted values end at space.
  static _M3uMetadata _parseMetadata(String content) {
    final attributes = <String, String>{};
    int i = 0;
    while (i < content.length) {
      while (i < content.length && _space(content.codeUnitAt(i))) {
        i++;
      }
      if (i == content.length) break;
      if (content[i] == ',') return _M3uMetadata(attributes, content.substring(i + 1).trim());
      final keyStart = i;
      while (i < content.length && !_space(content.codeUnitAt(i)) && content[i] != '=' && content[i] != ',') {
        i++;
      }
      final key = content.substring(keyStart, i).toLowerCase();
      while (i < content.length && _space(content.codeUnitAt(i))) {
        i++;
      }
      // Skip duration and unknown bare tokens without losing the next key.
      if (i == content.length || content[i] != '=') continue;
      if (key.isEmpty) throw const FormatException('Missing attribute key');
      i++;
      while (i < content.length && _space(content.codeUnitAt(i))) {
        i++;
      }
      String value;
      if (i < content.length && (content[i] == '"' || content[i] == "'")) {
        final quote = content[i++];
        final start = i;
        while (i < content.length && content[i] != quote) {
          i++;
        }
        if (i == content.length) throw const FormatException('Unclosed attribute quote');
        value = content.substring(start, i++);
        if (i < content.length && !_space(content.codeUnitAt(i)) && content[i] != ',') {
          throw const FormatException('Missing separator after quoted attribute');
        }
      } else {
        final start = i;
        while (i < content.length && !_space(content.codeUnitAt(i)) && content[i] != ',') {
          i++;
        }
        value = content.substring(start, i);
      }
      attributes[key] = value.trim();
    }
    // Retain the existing tvg-name fallback for a missing display delimiter.
    return _M3uMetadata(attributes, '');
  }

  static bool _space(int c) => c == 32 || (c >= 9 && c <= 13);

  /// 自动判断流类型：直播/电影/剧集
  StreamType _inferStreamType(Map<String, String> attrs, String url) {
    final group = attrs['group-title']?.toLowerCase() ?? '';
    final lowerUrl = url.toLowerCase();

    if (group.contains('vod') || group.contains('movie') || lowerUrl.contains('/movie/')) {
      return StreamType.vod;
    }
    if (group.contains('series') || lowerUrl.contains('/series/')) {
      return StreamType.series;
    }
    return StreamType.live;
  }

  /// 校验直播地址协议合法性
  bool _isValidStreamUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && const {'http', 'https', 'rtmp', 'rtsp', 'udp', 'mms'}.contains(uri.scheme);
    } catch (_) {
      return false;
    }
  }

  /// 空字符串转为null
  String? _emptyToNull(String? value) {
    return (value == null || value.isEmpty) ? null : value;
  }
}

class _M3uMetadata {
  const _M3uMetadata(this.attributes, this.displayName);
  final Map<String, String> attributes;
  final String displayName;
}

/// 解析结果实体
class M3uResult {
  final List<Channel> channels;
  final List<String> errors;

  const M3uResult({required this.channels, this.errors = const []});

  bool get hasErrors => errors.isNotEmpty;
  int get channelCount => channels.length;
}
