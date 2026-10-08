import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';

/// Builds a new connection for one platform.
typedef DanmakuConnectionFactory = DanmakuConnection Function();

/// The connection of a platform without danmaku (3.x `EmptyDanmaku`): it
/// never connects and never reports, and [close] is harmless. The UI tells
/// "this platform has no danmaku" from [DanmakuRegistry.supports] (or this
/// type), as 3.x did from `engine is EmptyDanmaku`: it shows
/// `remote_danmaku_not_integrated` once and treats the room as settled, so a
/// picture-in-picture return does not retry it.
final class EmptyDanmakuConnection implements DanmakuConnection {
  /// Creates the connection.
  new();

  @override
  Stream<DanmakuEvent> get events => const Stream.empty();

  @override
  DanmakuStatus get status => DanmakuStatus.idle;

  @override
  bool get isConnected => false;

  /// 60 s, as 3.x's `EmptyDanmaku.heartbeatTime` (nothing is sent).
  @override
  Duration get heartbeatInterval => const Duration(seconds: 60);

  /// Does nothing, whatever [args] is.
  @override
  Future<void> connect(Object? args) async {}

  @override
  void heartbeat() {}

  @override
  Future<void> close() async {}
}

/// Which platforms have danmaku and how to connect them: the only place
/// (3.x asked each site with `LiveSite.getDanmaku()`; `live_core` cannot
/// depend on this package, and its adapters only hand over the arguments
/// in `LiveRoom.danmakuData`). The
/// app builds it once with a factory per platform; each factory captures what
/// its platform needs (proxy policy, HTTP client, cookies, settings).
final class DanmakuRegistry {
  /// A registry of [factories] keyed by platform id (`SiteIds`). Throws
  /// [ArgumentError] for an id that is not a supported platform, or given
  /// twice.
  new(Map<String, DanmakuConnectionFactory> factories) : _factories = _normalize(factories);

  /// A registry without platforms: every platform gets
  /// [EmptyDanmakuConnection].
  new empty() : _factories = const {};

  final Map<String, DanmakuConnectionFactory> _factories;

  static Map<String, DanmakuConnectionFactory> _normalize(Map<String, DanmakuConnectionFactory> factories) {
    final normalized = <String, DanmakuConnectionFactory>{};
    for (final MapEntry(:key, :value) in factories.entries) {
      final id = key.trim().toLowerCase();
      if (!SiteIds.isSupported(id)) throw ArgumentError.value(key, 'factories', 'Not a supported platform');
      if (normalized.containsKey(id)) throw ArgumentError.value(key, 'factories', 'Registered twice');
      normalized[id] = value;
    }
    return Map.unmodifiable(normalized);
  }

  /// Platforms with danmaku, in display order.
  List<String> get platforms => [
    for (final id in SiteIds.supported)
      if (_factories.containsKey(id)) id,
  ];

  /// Whether [platform] (case and spaces ignored) has danmaku.
  bool supports(String platform) => _factories.containsKey(platform.trim().toLowerCase());

  /// A new connection for [platform] (case and spaces ignored), or an
  /// [EmptyDanmakuConnection] when it has none.
  DanmakuConnection connectionFor(String platform) =>
      _factories[platform.trim().toLowerCase()]?.call() ?? EmptyDanmakuConnection();
}
