import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/hls/client.dart';
import 'package:live_record/src/ts/stream_source.dart';

/// What the recorder needs from the platform adapters: the strict room
/// check (spec §4.1: errors are errors, never "offline") and stream sets.
abstract interface class RecordRooms {
  /// The room's detail; throws a `SiteError` when the check fails.
  Future<RoomDetail> detail(RoomRef room);

  /// Streams of [room] at [quality] (null: the platform's best).
  Future<StreamSet> streams(RoomDetail room, {Quality? quality});
}

/// [RecordRooms] over live_core adapters: `lookup` returns the adapter of a
/// platform id (an object implementing `RoomSource` and `StreamSource`), or
/// null when there is none.
final class SiteRecordRooms implements RecordRooms {
  /// Creates the access.
  const new(this._lookup);

  final Object? Function(String platform) _lookup;

  T _site<T>(String platform) {
    final site = _lookup(platform);
    if (site is T) return site;
    throw RecordException(RecordErrorKind.platformUnsupported, RecordStage.room, 'no recorder adapter for $platform');
  }

  @override
  Future<RoomDetail> detail(RoomRef room) => _site<RoomSource>(room.platform).detail(room);

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) =>
      _site<StreamSource>(room.ref.platform).streams(room, quality: quality);
}

/// The recorder's access to the upstream of one platform: FLV connections,
/// HLS requests and single HTTP streams (spec §5, §7, §8), all through the
/// app's proxy policy and with the line's headers (§18).
abstract interface class RecordOpener {
  /// An opener from functions (tests, tools): [flv] opens FLV connections;
  /// [hls] creates an HLS client for a session, or null when HLS lines
  /// cannot be recorded; [stream] opens single HTTP streams, or null when
  /// `StreamFormat.other` lines cannot be recorded.
  factory({
    required FlvSourceOpener Function(String platform) flv,
    HlsClient Function(String platform)? hls,
    ByteSourceOpener Function(String platform)? stream,
  }) = _FunctionOpener;

  /// Opens FLV connections for [platform].
  FlvSourceOpener flv(String platform);

  /// A new HLS client for one session of [platform] (it holds the session's
  /// cookies, §7.7; the session closes it), or null when HLS is not recorded.
  HlsClient? hls(String platform);

  /// Opens single HTTP streams (`StreamFormat.other`: IPTV `.ts`, udpxy,
  /// §8) for [platform], or null when they are not recorded.
  ByteSourceOpener? stream(String platform);
}

final class _FunctionOpener implements RecordOpener {
  new({required this._flv, this._hls, this._stream});

  final FlvSourceOpener Function(String platform) _flv;
  final HlsClient Function(String platform)? _hls;
  final ByteSourceOpener Function(String platform)? _stream;

  @override
  ByteSourceOpener? stream(String platform) => _stream?.call(platform);

  @override
  FlvSourceOpener flv(String platform) => _flv(platform);

  @override
  HlsClient? hls(String platform) => _hls?.call(platform);
}

/// The default opener: `openHttpFlv`, [IoHlsClient] and [openHttpStream]
/// with [proxy]'s route for the platform, and the `record.readTimeout` idle
/// timeout (spec §5.4, §18).
RecordOpener httpRecordOpener({
  ProxyPolicy proxy = const FixedProxyPolicy(),
  Duration readTimeout = const Duration(seconds: 15),
}) => RecordOpener(
  flv: (platform) =>
      (line) =>
          openHttpFlv(line, proxyDirective: proxy.routeFor(platform, line.url).directive, idleTimeout: readTimeout),
  hls: (platform) => IoHlsClient(findProxy: (url) => proxy.routeFor(platform, url).directive, idleTimeout: readTimeout),
  stream: (platform) =>
      (line) =>
          openHttpStream(line, proxyDirective: proxy.routeFor(platform, line.url).directive, idleTimeout: readTimeout),
);
