import 'package:live_core/src/live_gift.dart';
import 'package:meta/meta.dart';

/// Kind of a danmaku message.
enum LiveMessageType {
  /// Chat.
  chat,

  /// A gift, membership, gifted subscription or tip; [LiveMessage.data]
  /// holds it as a [LiveGift] (a platform's subclass), the text is
  /// [LiveGift.plainText]. Local gifts hold the local interaction's map.
  gift,

  /// Audience update; [LiveMessage.data] holds a [LiveAudienceUpdate].
  online,

  /// Super chat.
  superChat,

  /// Takes back messages shown earlier (a moderator deleted one, or cleared
  /// a user's or the whole chat); [LiveMessage.data] holds a
  /// [LiveRetraction].
  retraction,

  /// A platform notice shown as a line of its own; [LiveMessage.data] holds
  /// its [LiveNoticeKind], [LiveMessage.message] the text.
  notice,
}

/// What a [LiveMessageType.retraction] takes back.
@immutable
final class LiveRetraction {
  /// The message whose [LiveMessage.messageId] is [messageId].
  const new message(String this.messageId) : userId = null;

  /// Every message of the sender whose [LiveMessage.userId] is [userId].
  const new user(String this.userId) : messageId = null;

  /// Every message shown so far.
  const new all() : messageId = null, userId = null;

  /// The message taken back, for [LiveRetraction.message].
  final String? messageId;

  /// The sender whose messages are taken back, for [LiveRetraction.user].
  final String? userId;

  /// Whether the whole chat is taken back.
  bool get isAll => messageId == null && userId == null;

  @override
  bool operator ==(Object other) => other is LiveRetraction && other.messageId == messageId && other.userId == userId;

  @override
  int get hashCode => Object.hash(messageId, userId);

  @override
  String toString() => messageId != null
      ? 'LiveRetraction.message($messageId)'
      : userId != null
      ? 'LiveRetraction.user($userId)'
      : 'LiveRetraction.all()';
}

/// Kind of a [LiveMessageType.notice].
enum LiveNoticeKind {
  /// A message from the platform or the room (rules, announcements).
  system,

  /// A viewer subscribed, renewed or gifted subscriptions.
  subscription,

  /// Another channel brought its viewers over.
  raid,
}

/// Which audience number an update carries.
enum LiveAudienceMetricKind {
  /// Popularity or heat.
  popularity,

  /// Concurrent viewers.
  onlineViewers,

  /// Cumulative viewers.
  totalViewers,
}

/// A typed audience update, so heat, concurrent and cumulative viewers are
/// never relabelled as the same number.
@immutable
final class LiveAudienceUpdate {
  /// Creates an update.
  const new({required this.kind, required this.value});

  /// What [value] means.
  final LiveAudienceMetricKind kind;

  /// The number.
  final int value;
}

/// Where a locally composed danmaku flies.
enum LiveMessagePlacement {
  /// Scrolling.
  scroll,

  /// Fixed at the top.
  top,

  /// Fixed at the bottom.
  bottom,
}

/// Presentation of a locally composed danmaku; platform messages use the
/// room's danmaku settings.
@immutable
final class LiveMessageStyle {
  /// Creates a style.
  const new({
    required this.fontSize,
    required this.baseSpeed,
    required this.fontWeight,
    required this.showStroke,
    required this.strokeWidth,
    this.placement = LiveMessagePlacement.scroll,
    this.fontFamily,
    this.italic = false,
    this.opacity = 1,
    this.letterSpacing = 0,
    this.strokeColor = 0xFF000000,
    this.showShadow = false,
    this.shadowColor = 0xFF000000,
    this.shadowBlur = 2,
    this.shadowOffset = 1,
    this.fixedDurationMs = 4000,
  });

  /// Font size.
  final double fontSize;

  /// Scrolling speed.
  final double baseSpeed;

  /// Font weight (100–900).
  final int fontWeight;

  /// Whether to draw an outline.
  final bool showStroke;

  /// Outline width.
  final double strokeWidth;

  /// Placement.
  final LiveMessagePlacement placement;

  /// Font family, or null for the default.
  final String? fontFamily;

  /// Italic.
  final bool italic;

  /// Opacity 0–1.
  final double opacity;

  /// Letter spacing.
  final double letterSpacing;

  /// Outline colour, ARGB.
  final int strokeColor;

  /// Whether to draw a shadow.
  final bool showShadow;

  /// Shadow colour, ARGB.
  final int shadowColor;

  /// Shadow blur.
  final double shadowBlur;

  /// Shadow offset.
  final double shadowOffset;

  /// How long a fixed (top or bottom) message stays, in milliseconds.
  final int fixedDurationMs;
}

/// A danmaku colour.
@immutable
final class LiveMessageColor {
  /// Creates a colour from its channels (0–255).
  const new(this.r, this.g, this.b);

  /// The colour of a platform's integer: `0xRRGGBB`, or `0xAARRGGBB` with
  /// the alpha ignored (negative 32-bit values included).
  ///
  /// 3.x parsed the hexadecimal text and only understood 4, 6 or 8 digits:
  /// values with 1–3, 5 or 7 digits (blue `0x0000FF`, dark grey `0x0A0A0A`)
  /// and negative 32-bit values all came out white.
  factory numberToColor(int value) => LiveMessageColor((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);

  /// White, the default.
  static const LiveMessageColor white = LiveMessageColor(255, 255, 255);

  /// Red.
  final int r;

  /// Green.
  final int g;

  /// Blue.
  final int b;

  @override
  bool operator ==(Object other) => other is LiveMessageColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  /// `#rrggbb`.
  @override
  String toString() =>
      '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
}

/// A picture in a message: [code] is the text that stands for it in
/// [LiveMessage.message], exactly as written there, and every occurrence of
/// it is the picture at [url].
///
/// Codes by platform: CHZZK `{:d_47:}` (the line's `extras.emojis`),
/// YouTube a channel emoji's shortcut `:face-purple-crying:`, Bilibili an
/// inline code `[dog]` (the line's `emots`) or, for a sticker, the whole
/// text, Kuaishou `[笑哭]` (the room page's emoji table).
@immutable
final class LiveEmote {
  /// Creates an emote.
  const new({required this.code, required this.url});

  /// The text standing for the picture.
  final String code;

  /// The picture's address (https or http, as the platform gives it).
  final String url;

  @override
  bool operator ==(Object other) => other is LiveEmote && other.code == code && other.url == url;

  @override
  int get hashCode => Object.hash(code, url);

  @override
  String toString() => 'LiveEmote($code, $url)';
}

/// A picture a platform shows next to a sender's name (B-14: 17LIVE's
/// prefix, role, attendance and level badges): what the chat line draws,
/// in the platform's order. Level and fan-club text stay in
/// [LiveMessage.userLevel] and [LiveMessage.fansName].
@immutable
final class LiveBadge {
  /// Creates a badge.
  const new({required this.url, this.id = ''});

  /// The picture's address (https).
  final String url;

  /// The platform's id for the badge (17LIVE's `styleID`), empty when it
  /// has none.
  final String id;

  @override
  bool operator ==(Object other) => other is LiveBadge && other.url == url && other.id == id;

  @override
  int get hashCode => Object.hash(url, id);

  @override
  String toString() => 'LiveBadge($url${id.isEmpty ? '' : ', $id'})';
}

/// One danmaku message.
@immutable
final class LiveMessage {
  /// Creates a message.
  const new({
    required this.type,
    required this.userName,
    required this.message,
    required this.color,
    this.userId = '',
    this.data,
    this.userLevel = '',
    this.fansLevel = '',
    this.fansName = '',
    this.isLocal = false,
    this.messageId = '',
    this.sentAt,
    this.style,
    this.replayed = false,
    this.emotes = const [],
    this.sourceRoomId = '',
    this.nameColor,
    this.badges = const [],
  });

  /// Kind.
  final LiveMessageType type;

  /// Sender name.
  final String userName;

  /// Sender id.
  final String userId;

  /// Text.
  final String message;

  /// For [LiveMessageType.online] a [LiveAudienceUpdate] (older engines may
  /// send a number); for [LiveMessageType.gift] a [LiveGift].
  final Object? data;

  /// Colour.
  final LiveMessageColor color;

  /// Sender level.
  final String userLevel;

  /// Fan badge level.
  final String fansLevel;

  /// Fan badge name.
  final String fansName;

  /// Composed on this device.
  final bool isLocal;

  /// The platform's id for the message, when it has one: suppresses packets
  /// replayed after a reconnect without merging two genuine identical texts.
  final String messageId;

  /// The platform's timestamp; null when it has none (reception order then).
  final DateTime? sentAt;

  /// Presentation of a local message.
  final LiveMessageStyle? style;

  /// Not something that just happened: sent again after a reconnect resumed
  /// the chat, or a backlog the platform gives on joining (such as super
  /// chats still on display). The duplicate gate accepts it for longer.
  final bool replayed;

  /// The pictures the platform names for codes in [message], each code once;
  /// empty when it names none (the app may still know codes of its own,
  /// such as the bundled emoticon lists).
  final List<LiveEmote> emotes;

  /// The room the message was said in when it is not the room joined, as
  /// the platform names it (B-16: Kugou's PK partner); empty for this
  /// room. The chat marks such a line as the other room's.
  final String sourceRoomId;

  /// The colour the platform gives the sender's name (B-14: 17LIVE's
  /// `name.textColor`); null for the chat's default.
  final LiveMessageColor? nameColor;

  /// The badges the platform shows next to the sender's name, in its order
  /// (B-14); empty when it shows none.
  final List<LiveBadge> badges;

  /// [data] when it is a [LiveGift] (E05.5: what every platform's gift
  /// message holds); null for other kinds and for local gifts.
  LiveGift? get gift => switch (data) {
    final LiveGift gift => gift,
    _ => null,
  };

  /// Whether [sourceRoomId] names another room.
  bool get isFromOtherRoom => sourceRoomId.isNotEmpty;
}

/// A super chat (paid message).
@immutable
final class LiveSuperChatMessage {
  /// Creates a message.
  const new({
    required this.userName,
    required this.face,
    required this.message,
    required this.price,
    required this.startTime,
    required this.endTime,
    required this.backgroundColor,
    required this.backgroundBottomColor,
    this.messageId = '',
    this.priceText = '',
    this.image = '',
  });

  /// The platform's id for the event, when it has one. Some message-board
  /// APIs rebuild [startTime] from a countdown on every poll, so equality by
  /// time would make the same paid message look new.
  final String messageId;

  /// Sender name.
  final String userName;

  /// Sender avatar URL.
  final String face;

  /// Text.
  final String message;

  /// Price in the platform's unit.
  final int price;

  /// The price as the platform shows it (`$5.00`, `1,000 치즈`), when
  /// [price] alone cannot say it (several currencies); empty otherwise.
  final String priceText;

  /// Start of display.
  final DateTime startTime;

  /// End of display.
  final DateTime endTime;

  /// Top background colour.
  final String backgroundColor;

  /// Bottom background colour.
  final String backgroundBottomColor;

  /// The picture the message is, an https URL (YouTube's Super Sticker,
  /// D07.6); empty for a message of text.
  final String image;

  /// Same [messageId] when either has one; otherwise same sender, text and
  /// price.
  @override
  bool operator ==(Object other) {
    if (other is! LiveSuperChatMessage) return false;
    if (messageId.isNotEmpty || other.messageId.isNotEmpty) {
      return messageId.isNotEmpty && other.messageId == messageId;
    }
    return other.userName == userName && other.message == message && other.price == price;
  }

  @override
  int get hashCode => messageId.isNotEmpty ? messageId.hashCode : Object.hash(userName, message, price);
}
