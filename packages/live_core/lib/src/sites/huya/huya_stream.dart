import 'package:live_core/src/stream.dart';
import 'package:meta/meta.dart';

/// One CDN line of a live Huya room before signing (spec/sites/huya.md §5.2).
///
/// The media URL needs the AntiCode signed with md5 (§6.2–§6.4), which is
/// adapter work. The adapter signs [antiCode] (or fetches a native WUP token
/// for FLV) and passes the resulting query to `HuyaParse.mediaUrl`.
@immutable
final class HuyaLine {
  /// Creates a line.
  const new({
    required this.cdnType,
    required this.format,
    required this.base,
    required this.streamName,
    required this.antiCode,
    this.presenterUid,
  });

  /// Server CDN type (`AL`, `TX`, `HS24`); the line id (§5.3).
  final String cdnType;

  /// FLV or HLS.
  final StreamFormat format;

  /// CDN base without the stream name; `http://` on huya.com hosts is already
  /// upgraded to `https://` (§5.2).
  final Uri base;

  /// Stream name; also the key of the native WUP token request (§6.2).
  final String streamName;

  /// The room's AntiCode for this format: `sFlvAntiCode` for FLV,
  /// `sHlsAntiCode` for HLS, never the other one (§6.1, REG-HUYA-006).
  final String antiCode;

  /// The streamer UID that signs native FLV: `lPresenterUid`, else
  /// `profileInfo.uid`, else `lChannelId` (§1); null when none is positive.
  final int? presenterUid;

  /// Whether [antiCode] is a template (`fm`) that must be signed before use;
  /// otherwise it is a legacy static token used as is (§6.3 step 1).
  bool get needsSigning => RegExp('(^|&)fm=').hasMatch(antiCode);

  /// Diagnostics without tokens (§6.7, REG-HUYA-023).
  @override
  String toString() => 'HuyaLine($cdnType ${format.name} ${base.host})';
}

/// Validity of a WUP `getCdnTokenInfoEx` token (§6.2, §6.6).
@immutable
final class HuyaTokenWindow {
  /// Creates a window; [refreshAt] is not after [invalidAt].
  new({required this.refreshAt, required this.invalidAt})
    : assert(!refreshAt.isAfter(invalidAt), 'refreshAt must not be after invalidAt');

  /// When to fetch the next token.
  final DateTime refreshAt;

  /// When the token stops working for new connections.
  final DateTime invalidAt;
}
