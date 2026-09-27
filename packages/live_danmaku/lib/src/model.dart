import 'package:meta/meta.dart';

/// The five kinds of message the UI isolate receives (spec/modules/danmaku.md §1).
enum DanmakuKind {
  /// A viewer's chat line.
  chat,

  /// A gift, shown as a list line only.
  gift,

  /// A paid pinned message (醒目留言 / SC).
  superChat,

  /// An audience figure.
  online,

  /// A connection or room notice for the UI to translate.
  system,
}

/// Where a local message is drawn (§1 chat style).
enum DanmakuPosition {
  /// Scrolls across the screen.
  scroll,

  /// Fixed at the top.
  top,

  /// Fixed at the bottom.
  bottom,
}

/// RGB colours as `0xRRGGBB` integers.
abstract final class DanmakuColors {
  /// The default chat colour.
  static const white = 0xFFFFFF;

  /// The RGB part of a platform colour number: 4 and 6 hex digits are RGB,
  /// 8 digits are ARGB and the alpha is ignored (§1).
  static int fromNumber(int value) => value & 0xFFFFFF;

  /// Parses `#RRGGBB`, `RRGGBB`, `0xAARRGGBB` and the 4-digit form; null when
  /// [text] is not hex.
  static int? parse(String? text) {
    if (text == null) return null;
    var hex = text.trim();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    } else if (hex.toLowerCase().startsWith('0x')) {
      hex = hex.substring(2);
    }
    if (hex.isEmpty || hex.length > 8 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    return fromNumber(int.parse(hex, radix: 16));
  }
}

/// Presentation of a locally composed message (§1 chat: local messages only).
@immutable
final class DanmakuStyle {
  /// Creates a style; [duration] is how long a fixed message stays.
  const new({
    this.position = DanmakuPosition.scroll,
    this.fontSize,
    this.fontWeight,
    this.strokeWidth,
    this.shadow = false,
    this.duration = const Duration(seconds: 4),
  });

  /// Scroll, top or bottom.
  final DanmakuPosition position;

  /// Font size in logical pixels; null uses the room setting.
  final double? fontSize;

  /// Font weight 100–900; null uses the room setting.
  final int? fontWeight;

  /// Stroke width; null uses the room setting.
  final double? strokeWidth;

  /// Whether to draw a shadow.
  final bool shadow;

  /// How long a fixed message stays on screen.
  final Duration duration;
}

/// A unified message (§1). Every kind carries the room key and the session
/// token so late messages of an old connection can be told apart (CONN-4).
@immutable
sealed class DanmakuEvent {
  const new({
    required this.room,
    required this.session,
    required this.receivedAt,
    this.id,
    this.sentAt,
    this.isLocal = false,
  });

  /// `platform:roomId` of the room the connection joined.
  final String room;

  /// Token of the session that produced the message.
  final int session;

  /// Platform-prefixed stable id (`douyu:<cid>`), or null when the platform
  /// gives none.
  final String? id;

  /// Platform timestamp; null when the platform gives none.
  final DateTime? sentAt;

  /// Monotonic receive time in microseconds (`Timeline.now`, shared by all
  /// isolates of the process).
  final int receivedAt;

  /// Whether this device composed the message (local interaction, send
  /// echo); local messages bypass filters and sampling.
  final bool isLocal;

  /// The message kind.
  DanmakuKind get kind;
}

/// A chat line.
final class DanmakuChat extends DanmakuEvent {
  /// Creates a chat line.
  const new({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.text,
    super.id,
    super.sentAt,
    super.isLocal,
    this.userId = '',
    this.color = DanmakuColors.white,
    this.userLevel,
    this.medalLevel,
    this.medalName,
    this.style,
    this.suspectedBot = false,
  });

  /// Sender's platform id; empty when unknown.
  final String userId;

  /// Sender's display name.
  final String userName;

  /// Message text.
  final String text;

  /// `0xRRGGBB`.
  final int color;

  /// Sender's platform level.
  final int? userLevel;

  /// Fan medal level.
  final int? medalLevel;

  /// Fan medal name.
  final String? medalName;

  /// Local messages only: how to draw it.
  final DanmakuStyle? style;

  /// Douyu FLT-5: neither `dms` nor `if=1`; hidden only when the user turns
  /// the filter on.
  final bool suspectedBot;

  @override
  DanmakuKind get kind => DanmakuKind.chat;

  @override
  String toString() => 'DanmakuChat($userName: $text)';
}

/// A gift, for the list (LST-8); never drawn on the video.
final class DanmakuGift extends DanmakuEvent {
  /// Creates a gift line.
  const new({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.giftName,
    super.id,
    super.sentAt,
    super.isLocal,
    this.userId = '',
    this.giftId = '',
    this.count = 1,
    this.yuan,
    this.icon,
  });

  /// Sender's platform id.
  final String userId;

  /// Sender's display name.
  final String userName;

  /// Platform gift id.
  final String giftId;

  /// Gift display name.
  final String giftName;

  /// How many were sent.
  final int count;

  /// Total value in yuan when the platform's unit is known; null otherwise.
  final double? yuan;

  /// Gift image.
  final Uri? icon;

  @override
  DanmakuKind get kind => DanmakuKind.gift;

  @override
  String toString() => 'DanmakuGift($userName: $giftName x$count)';
}

/// A paid pinned message.
///
/// Equality (§1): with both ids present only the ids are compared; with
/// neither, (user name, text, price); never the start time, which some
/// platforms recompute from a countdown on every poll (REG-DANMAKU-018).
final class DanmakuSuperChat extends DanmakuEvent {
  /// Creates a super chat.
  const new({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.userName,
    required this.text,
    required this.price,
    required this.startAt,
    required this.endAt,
    super.id,
    super.sentAt,
    super.isLocal,
    this.avatar,
    this.backgroundColor,
    this.bottomColor,
  });

  /// Sender's display name.
  final String userName;

  /// Sender's avatar.
  final Uri? avatar;

  /// Message text.
  final String text;

  /// Price in yuan.
  final int price;

  /// When it was pinned.
  final DateTime startAt;

  /// When it expires.
  final DateTime endAt;

  /// Body colour `0xRRGGBB`, when the platform gives one.
  final int? backgroundColor;

  /// Footer colour `0xRRGGBB`, when the platform gives one.
  final int? bottomColor;

  @override
  DanmakuKind get kind => DanmakuKind.superChat;

  @override
  bool operator ==(Object other) {
    if (other is! DanmakuSuperChat) return false;
    final mine = id;
    final theirs = other.id;
    if (mine != null && theirs != null) return mine == theirs;
    if (mine != null || theirs != null) return false;
    return other.userName == userName && other.text == text && other.price == price;
  }

  @override
  int get hashCode => id?.hashCode ?? Object.hash(userName, text, price);

  @override
  String toString() => 'DanmakuSuperChat($userName ¥$price: $text)';
}

/// Which audience figure a number is (§1 online, REG-DANMAKU-019).
enum AudienceKind {
  /// Platform heat score (Bilibili op 3, Huya 8006).
  popularity,

  /// Concurrent viewers.
  online,

  /// Viewers so far in this broadcast.
  cumulative,
}

/// An audience figure.
final class DanmakuOnline extends DanmakuEvent {
  /// Creates a figure.
  const new({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.audience,
    required this.value,
    super.id,
    super.sentAt,
  });

  /// Which measure [value] is.
  final AudienceKind audience;

  /// The figure, zero or more.
  final int value;

  @override
  DanmakuKind get kind => DanmakuKind.online;

  @override
  String toString() => 'DanmakuOnline(${audience.name}: $value)';
}

/// Status codes of system messages; the UI maps them to text (§1 system).
enum DanmakuStatus {
  /// Opening the first connection.
  connecting,

  /// Joined and receiving.
  connected,

  /// Lost the connection, retrying.
  reconnecting,

  /// Gave up (terminal); the room key is released and a manual refresh
  /// connects again. The argument is the reason.
  closed,

  /// Did not connect within the start timeout (20 s).
  timeout,

  /// The platform has no chat connector.
  unsupported,

  /// The room plays a recording; chat is the recording's.
  replayMode,

  /// Bilibili guest session: viewer names are masked by the platform.
  bilibiliGuestMasked,
}

/// A connection or room notice.
final class DanmakuSystem extends DanmakuEvent {
  /// Creates a notice.
  const new({
    required super.room,
    required super.session,
    required super.receivedAt,
    required this.status,
    this.args = const [],
  });

  /// What happened.
  final DanmakuStatus status;

  /// Codes, not prose: for [DanmakuStatus.closed] the reason
  /// (`maxRetries`, `credentials`, `rejected`, `failed`), then detail.
  final List<String> args;

  @override
  DanmakuKind get kind => DanmakuKind.system;

  @override
  String toString() => 'DanmakuSystem(${status.name}${args.isEmpty ? '' : ' $args'})';
}
