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

  /// The quality actually delivered as far as known: [confirmed], else [requested].
  Quality get effective => confirmed ?? requested;
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

  /// Lines in the platform's order.
  final List<StreamLine> lines;
}
