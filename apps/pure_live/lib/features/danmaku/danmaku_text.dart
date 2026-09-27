import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart' show formatCount;
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';

/// Status line text of the chat panel; null when nothing needs saying.
String? connectionText(ChatConnection connection) => switch (connection) {
  ChatConnection.off => null,
  ChatConnection.connecting => '正在连接弹幕…',
  ChatConnection.connected => null,
  ChatConnection.reconnecting => '弹幕连接断开，正在重连…',
  ChatConnection.closed => '弹幕已断开',
  ChatConnection.unsupported => '这个平台暂不支持弹幕',
};

/// Text for a notice (spec §1 system: codes are mapped here, never sent as
/// prose); null for the ones the status line already covers.
String? noticeText(DanmakuSystem notice) => switch (notice.status) {
  DanmakuStatus.replayMode => '正在播放录像，弹幕来自录像',
  DanmakuStatus.bilibiliGuestMasked => '未登录 B 站账号，观众昵称会被平台隐藏',
  DanmakuStatus.timeout => '弹幕连接超时',
  DanmakuStatus.closed => switch (notice.args.firstOrNull) {
    'credentials' => '弹幕连接失败：取不到平台凭据',
    'rejected' => '弹幕连接被平台拒绝',
    _ => '弹幕多次重连失败',
  },
  DanmakuStatus.connecting ||
  DanmakuStatus.connected ||
  DanmakuStatus.reconnecting ||
  DanmakuStatus.unsupported => null,
};

/// Short name of an audience figure.
String audienceLabel(AudienceKind kind) => switch (kind) {
  AudienceKind.online => '在线',
  AudienceKind.popularity => '人气',
  AudienceKind.cumulative => '看过',
};

/// "在线 3.5万" for a figure.
String audienceText(AudienceKind kind, int value) => '${audienceLabel(kind)} ${formatCount(value)}';

/// Price of a super chat: "¥30".
String priceText(int yuan) => '¥$yuan';

/// A gift line: "送出 小心心 ×3".
String giftText(DanmakuGift gift) => gift.count > 1 ? '送出 ${gift.giftName} ×${gift.count}' : '送出 ${gift.giftName}';
