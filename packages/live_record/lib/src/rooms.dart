import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_record/src/errors.dart';

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

/// Opens upstream FLV connections for a platform.
typedef RecordOpener = FlvSourceOpener Function(String platform);

/// The default opener: `openHttpFlv` with [proxy]'s route for the platform and
/// the `record.readTimeout` idle timeout (spec §5.4, §18).
RecordOpener httpRecordOpener({
  ProxyPolicy proxy = const FixedProxyPolicy(),
  Duration readTimeout = const Duration(seconds: 15),
}) =>
    (platform) =>
        (line) =>
            openHttpFlv(line, proxyDirective: proxy.routeFor(platform, line.url).directive, idleTimeout: readTimeout);
