import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A selectable quality (ADR 0010, rule 5).
@immutable
final class Quality {
  /// Creates a quality.
  const new({required this.id, required this.label, required this.rank});

  /// The platform's opaque request code (Douyu rate, Bilibili qn).
  final String id;

  /// Name shown to the user.
  final String label;

  /// Ordering key: higher is better.
  final int rank;

  @override
  bool operator ==(Object other) => other is Quality && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Quality($id, $label)';
}

/// Container format of a stream line.
enum StreamFormat {
  /// HTTP-FLV.
  flv,

  /// HLS playlist.
  hls,

  /// One HTTP(S) response that is the whole stream, its container told by
  /// its first bytes (IPTV MPEG-TS, udpxy, FLV without a `.flv` path). The
  /// player opens it directly; the recorder sniffs it (record spec §8).
  other,
}

/// When a stream URL must be renewed (ADR 0010, rule 5).
@immutable
final class Lease {
  /// Creates a lease; [refreshAt] must not be after [expiresAt].
  new({required this.refreshAt, required this.cutsConnection, this.expiresAt})
    : assert(expiresAt == null || !refreshAt.isAfter(expiresAt), 'refreshAt must not be after expiresAt');

  /// When to fetch a fresh URL.
  final DateTime refreshAt;

  /// When the URL stops working for new connections, if known.
  final DateTime? expiresAt;

  /// Whether expiry also ends an established connection (Douyu: splice the
  /// renewed stream in; Huya: only prefetch).
  final bool cutsConnection;
}

/// Everything needed to play one line (ADR 0010, rule 5).
@immutable
final class StreamLine {
  /// Creates a line.
  const new({
    required this.url,
    required this.format,
    required this.lineId,
    required this.requested,
    this.confirmed,
    this.headers = const {},
    this.codec,
    this.lease,
    this.hlsRelay,
  });

  /// Media URL.
  final Uri url;

  /// Container format.
  final StreamFormat format;

  /// Line identity, stable across renewals (a CDN code).
  final String lineId;

  /// Quality asked for.
  final Quality requested;

  /// Quality the server confirmed; null when the platform does not report it.
  final Quality? confirmed;

  /// Request headers the CDN needs; lower-case names.
  final Map<String, String> headers;

  /// Video codec when known (`avc`, `hevc`).
  final String? codec;

  /// Renewal rule; null when the URL does not expire while playing.
  final Lease? lease;

  /// What the HLS relay must do for this line; null when the engine can
  /// fetch it by itself (playback spec SRC-2).
  final HlsRelayRecipe? hlsRelay;

  /// The quality actually delivered as far as known: [confirmed], else [requested].
  Quality get effective => confirmed ?? requested;
}

/// A cookie sent only to matching hosts and paths (RFC 6265 §5.1.3–5.1.4).
@immutable
final class ScopedCookie {
  /// Creates a cookie.
  const new({required this.name, required this.value, required this.domain, required this.path, this.expires});

  /// Cookie name (the same name may repeat under different paths).
  final String name;

  /// Cookie value.
  final String value;

  /// Domain; subdomains match too.
  final String domain;

  /// Path prefix it applies to.
  final String path;

  /// Expiry, when given.
  final DateTime? expires;

  /// Whether this cookie is sent to [url].
  bool appliesTo(Uri url) {
    final domain = this.domain.startsWith('.') ? this.domain.substring(1) : this.domain;
    final host = url.host.toLowerCase();
    if (host != domain && !host.endsWith('.$domain')) return false;
    final path = url.path.isEmpty ? '/' : url.path;
    return path == this.path ||
        (path.startsWith(this.path) && (this.path.endsWith('/') || path[this.path.length] == '/'));
  }
}

/// Restores one media segment.
typedef SegmentRestore = Uint8List Function(Uint8List segment);

/// What the HLS relay does for a line the engine cannot play by itself
/// (playback spec SRC-2 item 3); recording applies it too (SRC-4).
@immutable
final class HlsRelayRecipe {
  /// Creates a recipe.
  const new({this.cookies, this.restore});

  /// The cookies to send, read at every request so a renewed grant applies
  /// at once; each request carries only the ones that match its host and
  /// path (niconico). Null keeps the line's own `cookie` header.
  final List<ScopedCookie> Function()? cookies;

  /// For the text of a media playlist, how its segments are restored, or
  /// null when they pass as they are (Bigo's scrambling).
  final SegmentRestore? Function(String playlist)? restore;

  /// The `Cookie` header for [url], or null when no cookie applies.
  String? cookieHeaderFor(Uri url) {
    final list = cookies?.call();
    if (list == null) return null;
    final matching = [
      for (final cookie in list)
        if (cookie.appliesTo(url)) '${cookie.name}=${cookie.value}',
    ];
    return matching.isEmpty ? null : matching.join('; ');
  }
}

/// The result of one stream request.
@immutable
final class StreamSet {
  /// Creates a set.
  const new({required this.qualities, required this.selected, required this.lines});

  /// Qualities offered, best first.
  final List<Quality> qualities;

  /// The quality these lines were requested at.
  final Quality selected;

  /// Lines in the order the platform spec defines.
  final List<StreamLine> lines;
}
