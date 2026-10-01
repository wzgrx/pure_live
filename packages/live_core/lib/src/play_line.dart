import 'package:meta/meta.dart';

/// Container format of a play line.
enum StreamFormat {
  /// HTTP-FLV.
  flv,

  /// HLS playlist.
  hls,

  /// One HTTP(S) response that is the whole stream, its container told by
  /// its first bytes (IPTV MPEG-TS, udpxy, FLV without a `.flv` path).
  other,
}

/// When a signed play URL must be renewed.
@immutable
final class PlayLease {
  /// Creates a lease; [refreshAt] must not be after [expiresAt].
  new({required this.refreshAt, this.expiresAt, this.cutsConnection = false})
    : assert(expiresAt == null || !refreshAt.isAfter(expiresAt), 'refreshAt must not be after expiresAt');

  /// When to fetch a fresh URL.
  final DateTime refreshAt;

  /// When the URL stops opening new connections, if known.
  final DateTime? expiresAt;

  /// Whether expiry also ends an established connection (Douyu), so the
  /// renewed stream must be spliced in; otherwise it is only prefetched.
  final bool cutsConnection;
}

/// One playable line and everything needed to open it.
///
/// 3.x kept request headers and lease times apart from the URLs (a
/// per-platform `PlaybackHeaderResolver` in the player and the
/// `LivePlayLeaseMetadata` capability); a line now describes itself, so the
/// player and the recorder need no per-platform code.
@immutable
final class LivePlayLine {
  /// Creates a line; header names are lower case.
  const new(
    this.url, {
    this.headers = const {},
    this.format,
    this.codec,
    this.lineId,
    this.lease,
    this.width,
    this.height,
  });

  /// Media URL.
  final String url;

  /// Request headers the CDN needs.
  final Map<String, String> headers;

  /// Container format, when known.
  final StreamFormat? format;

  /// Video codec when known (`avc`, `hevc`).
  final String? codec;

  /// Line identity stable across renewals (a CDN code), when known.
  final String? lineId;

  /// Renewal rule; null when the URL does not expire while playing.
  final PlayLease? lease;

  /// Picture width the platform declares for this line (3.x
  /// `LiveStreamGeometryHint`), when it does: the player lays the picture
  /// out by it before the first frame; the decoded size wins once known.
  final int? width;

  /// Picture height the platform declares for this line; see [width].
  final int? height;

  /// [width] over [height], when both are declared.
  double? get declaredAspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  @override
  String toString() => 'LivePlayLine(${lineId ?? url})';
}
