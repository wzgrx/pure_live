import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart' show formatCount;
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Status line text of the chat panel; null when nothing needs saying.
String? connectionText(ChatConnection connection) => switch (connection) {
  ChatConnection.off => null,
  ChatConnection.connecting => t.danmaku.connecting,
  ChatConnection.connected => null,
  ChatConnection.reconnecting => t.danmaku.reconnecting,
  ChatConnection.closed => t.danmaku.disconnected,
  ChatConnection.unsupported => t.danmaku.unsupported,
};

/// Text for a notice (spec §1 system: codes are mapped here, never sent as
/// prose); null for the ones the status line already covers.
String? noticeText(DanmakuSystem notice) => switch (notice.status) {
  DanmakuStatus.replayMode => t.danmaku.replayMode,
  DanmakuStatus.bilibiliGuestMasked => t.danmaku.bilibiliGuest,
  DanmakuStatus.timeout => t.danmaku.timeout,
  DanmakuStatus.closed => switch (notice.args.firstOrNull) {
    'credentials' => t.danmaku.noCredentials,
    'rejected' => t.danmaku.rejected,
    _ => t.danmaku.retriesFailed,
  },
  DanmakuStatus.connecting ||
  DanmakuStatus.connected ||
  DanmakuStatus.reconnecting ||
  DanmakuStatus.unsupported => null,
};

/// Short name of an audience figure.
String audienceLabel(AudienceKind kind) => switch (kind) {
  AudienceKind.online => t.danmaku.audience.online,
  AudienceKind.popularity => t.danmaku.audience.popularity,
  AudienceKind.cumulative => t.danmaku.audience.cumulative,
};

/// "在线 3.5万" for a figure.
String audienceText(AudienceKind kind, int value) => '${audienceLabel(kind)} ${formatCount(value)}';

/// Price of a super chat: "¥30".
String priceText(int yuan) => '¥$yuan';

/// A gift line: "送出 小心心 ×3".
String giftText(DanmakuGift gift) =>
    gift.count > 1 ? t.danmaku.giftMany(gift: gift.giftName, count: gift.count) : t.danmaku.gift(gift: gift.giftName);
