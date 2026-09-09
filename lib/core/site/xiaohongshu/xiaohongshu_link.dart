import 'xiaohongshu_share.dart';

/// Broadcast room identity only. Profile IDs, notes and recommended rooms are
/// not aliases. Short links and route aliases need their own verified contract.
class XiaohongshuLink {
  static String? parse(String raw) {
    final value = raw.trim();
    if (RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.host != 'www.xiaohongshu.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    final path = value.split('://').last.split(RegExp(r'[?#]')).first;
    if (path.contains('%') || path.contains('\\') || path.contains('/./') || path.contains('/../')) return null;
    final match = RegExp(r'^/livestream/([1-9][0-9]{0,19})/?$').firstMatch(uri.path);
    return match?[1];
  }

  static String url(String roomId) =>
      'https://www.xiaohongshu.com/livestream/${XiaohongshuShare.validateRoomId(roomId)}';
}
