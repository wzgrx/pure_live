import 'dart:async';

import 'package:live_cast/live_cast.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';

/// A renderer on the LAN.
CastDevice castDevice(String name, {required String id, String host = '192.168.1.20', String? manufacturer}) =>
    CastDevice(
      id: id,
      name: name,
      location: Uri.parse('http://$host:49152/description.xml'),
      avTransport: CastService(
        serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
        controlUrl: Uri.parse('http://$host:49152/AVTransport/control'),
      ),
      manufacturer: manufacturer,
    );

/// The upstream URL the room plays in [playingState].
final Uri upstreamUrl = Uri.parse('https://cdn.example.com/live/1.flv?sign=abc&t=1');

/// A playing room on one line.
PlaybackState playingState({
  Uri? url,
  StreamFormat format = StreamFormat.flv,
  Map<String, String> headers = const {},
  Lease? lease,
}) => PlaybackState(
  phase: PlaybackPhase.playing,
  wantsPlay: true,
  roomKey: 'douyu:1',
  line: StreamLine(
    url: url ?? upstreamUrl,
    format: format,
    lineId: 'ws',
    requested: const Quality(id: 'hd', label: '原画', rank: 3),
    headers: headers,
    lease: lease,
  ),
);

/// Renderers that write every command to one [log] and fail as scripted.
final class FakeRenderers {
  /// `set 客厅电视 <url> <mime>`, `play 客厅电视`, `stop 客厅电视`…
  final List<String> log = [];

  /// Failures thrown by the next command of that kind (`set`, `play`, `stop`, `info`), per device name.
  final Map<String, CastFailure> failures = {};

  /// Makes the renderer of [device].
  CastRenderer call(CastDevice device) => _FakeRenderer(device, this);
}

final class _FakeRenderer implements CastRenderer {
  new(this.device, this._owner);

  @override
  final CastDevice device;

  final FakeRenderers _owner;

  Future<void> _run(String command, [String detail = '']) async {
    _owner.log.add('$command ${device.name}$detail');
    final failure = _owner.failures.remove('$command ${device.name}');
    if (failure != null) throw failure;
  }

  @override
  Future<void> setMedia(CastMedia media) => _run('set', ' ${media.url} ${media.mimeType}');

  @override
  Future<void> play() => _run('play');

  @override
  Future<void> pause() => _run('pause');

  @override
  Future<void> stop() => _run('stop');

  @override
  Future<TransportInfo> transportInfo() async {
    await _run('info');
    return const TransportInfo(state: TransportState.pausedPlayback);
  }
}

/// Searches whose streams the test drives: each call opens a new controller.
final class FakeSearches {
  final List<StreamController<CastDevice>> searches = [];

  /// Starts a search.
  Stream<CastDevice> call() {
    final controller = StreamController<CastDevice>();
    searches.add(controller);
    return controller.stream;
  }

  /// The latest search.
  StreamController<CastDevice> get last => searches.last;
}
