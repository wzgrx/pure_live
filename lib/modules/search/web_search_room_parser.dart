import 'package:pure_live/core/sites.dart';
import 'package:pure_live/core/site/picarto/picarto_api.dart';
import 'package:pure_live/core/site/twitcasting/twitcasting_api.dart';

class WebSearchRoomTarget {
  const WebSearchRoomTarget({required this.platform, required this.roomId});

  final String platform;
  final String roomId;

  String get key => '$platform:$roomId';
}

/// Converts a supported platform room URL into the adapter identity used by
/// native playback. Search/category/account URLs are deliberately ignored.
class WebSearchRoomParser {
  const WebSearchRoomParser._();

  static const Set<String> _reservedSegments = {
    'search',
    'category',
    'categories',
    'directory',
    'directories',
    'game',
    'games',
    'video',
    'videos',
    'user',
    'users',
    'index',
    'topic',
    'topics',
    'downloads',
    'settings',
    'login',
    'signup',
  };

  static WebSearchRoomTarget? parse(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    final picarto = PicartoApi.channelFromUri(uri);
    if (picarto != null) return WebSearchRoomTarget(platform: Sites.picartoSite, roomId: picarto);
    final twitcasting = TwitcastingApi.channelFromUri(uri);
    if (twitcasting != null) return WebSearchRoomTarget(platform: Sites.twitcastingSite, roomId: twitcasting);
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((segment) => segment.trim().isNotEmpty).toList(growable: false);

    if (_matchesHost(host, 'huya.com')) {
      return _firstSegment(segments, Sites.huyaSite, RegExp(r'^[a-zA-Z0-9_-]+$'));
    }
    if (host == 'live.douyin.com') {
      return _firstSegment(segments, Sites.douyinSite, RegExp(r'^\d+$'));
    }
    if (_matchesHost(host, 'douyu.com')) {
      return _firstSegment(segments, Sites.douyuSite, RegExp(r'^\d+$'));
    }
    if (host == 'live.kuaishou.com') {
      if (segments.length < 2 || segments.first.toLowerCase() != 'u') return null;
      return _target(Sites.kuaishouSite, segments[1], RegExp(r'^[a-zA-Z0-9_-]+$'));
    }
    if (host == 'cc.163.com') {
      return _firstSegment(segments, Sites.ccSite, RegExp(r'^\d+$'));
    }
    if (host == 'live.bilibili.com') {
      return _firstSegment(segments, Sites.bilibiliSite, RegExp(r'^\d+$'));
    }
    if (_matchesHost(host, 'twitch.tv')) {
      return _firstSegment(segments, Sites.twitchSite, RegExp(r'^[a-zA-Z0-9_]+$'));
    }
    if (_matchesHost(host, 'sooplive.co.kr')) {
      return _firstSegment(segments, Sites.soopSite, RegExp(r'^[a-zA-Z0-9_-]+$'));
    }
    if (_matchesHost(host, 'yy.com')) {
      return _firstSegment(segments, Sites.yySite, RegExp(r'^\d+$'));
    }
    if (host == 'live.acfun.cn' && uri.userInfo.isEmpty && segments.length == 2 && segments.first == 'live') {
      return _target(Sites.acfunSite, segments[1], RegExp(r'^[1-9][0-9]{0,19}$'));
    }
    return null;
  }

  static bool _matchesHost(String host, String root) => host == root || host.endsWith('.$root');

  static WebSearchRoomTarget? _firstSegment(List<String> segments, String platform, RegExp pattern) {
    if (segments.isEmpty) return null;
    return _target(platform, segments.first, pattern);
  }

  static bool isRoomIdentifier(String roomId, RegExp pattern) =>
      roomId.isNotEmpty && !_reservedSegments.contains(roomId.toLowerCase()) && pattern.hasMatch(roomId);

  static WebSearchRoomTarget? _target(String platform, String rawRoomId, RegExp pattern) {
    final roomId = rawRoomId.trim();
    if (!isRoomIdentifier(roomId, pattern)) return null;
    return WebSearchRoomTarget(platform: platform, roomId: roomId);
  }
}
