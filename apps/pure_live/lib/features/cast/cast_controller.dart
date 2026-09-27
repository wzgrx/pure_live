import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_cast/live_cast.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';

/// Android's Wi-Fi multicast lock around a search (F-CAST-01): many Wi-Fi
/// drivers drop SSDP traffic while no app holds it. `CastMulticast.kt` owns
/// the lock behind the channel `purelive/cast`; overlapping searches share
/// one hold. Other platforms need none, and a missing channel is ignored.
final class MulticastLock {
  new({this._channel = const MethodChannel('purelive/cast'), bool? enabled}) : _enabled = enabled ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _enabled;
  int _holders = 0;

  /// Takes a hold; the first one acquires the lock.
  Future<void> acquire() async {
    if (!_enabled) return;
    _holders++;
    if (_holders == 1) await _call('acquire');
  }

  /// Gives a hold back; the last one releases the lock.
  Future<void> release() async {
    if (!_enabled || _holders == 0) return;
    _holders--;
    if (_holders == 0) await _call('release');
  }

  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<Object?>(method);
    } on PlatformException {
      // No permission or no Wi-Fi: search anyway, answers may still arrive.
    } on MissingPluginException {
      // An engine without the channel (tests, other hosts).
    }
  }
}

/// Runs [search] while holding [lock]; cancelling the stream releases it.
Stream<CastDevice> searchWithLock(MulticastLock lock, Stream<CastDevice> Function() search) async* {
  await lock.acquire();
  try {
    yield* search();
  } finally {
    await lock.release();
  }
}

/// HTTP to renderers: one direct client for the app.
final Provider<CastHttp> castHttpProvider = Provider<CastHttp>((ref) {
  final http = IoCastHttp();
  ref.onDispose(http.close);
  return http;
});

/// The multicast lock.
final Provider<MulticastLock> multicastLockProvider = Provider<MulticastLock>((ref) => MulticastLock());

/// Starts one search of the local network.
typedef CastSearch = Stream<CastDevice> Function();

/// Searches for renderers (4 s, every IPv4 interface) under the multicast
/// lock; tests replace it.
final Provider<CastSearch> castSearchProvider = Provider<CastSearch>((ref) {
  final http = ref.watch(castHttpProvider);
  final lock = ref.watch(multicastLockProvider);
  return () => searchWithLock(lock, CastDiscovery(http: http).search);
});

/// Makes the controller of one renderer.
typedef CastRendererFactory = CastRenderer Function(CastDevice device);

/// Controls renderers over DLNA; tests replace it.
final Provider<CastRendererFactory> castRendererProvider = Provider<CastRendererFactory>((ref) {
  final http = ref.watch(castHttpProvider);
  return (device) => DlnaRenderer(device, http: http);
});

/// What the sheet can cast from the room's playback, or why it cannot.
@immutable
final class CastSource {
  const new({this.media, this.problem, this.needsHeaders = false, this.expires = false});

  /// The media to send; null when [problem] says why not.
  final CastMedia? media;

  /// Why the address cannot be cast, as UI copy.
  final String? problem;

  /// The line needs request headers (Referer, Cookie…) the renderer will not send.
  final bool needsHeaders;

  /// The URL expires while playing (a lease): the renderer stops then.
  final bool expires;
}

/// The upstream URL of the line playing (or being opened) in [state]: never
/// the loopback relay's address, which another device cannot reach
/// (REG-LEASE-017). Only a normalised http(s) address with a host and no user
/// info is accepted (REG-ROOM-016).
CastSource castSourceOf(RoomDetail detail, PlaybackState state) {
  final line = state.line ?? state.commit?.line;
  if (line == null) return const CastSource(problem: '还没有拿到直播地址，等画面出来后再投屏');
  final url = line.url;
  if (!(url.isScheme('http') || url.isScheme('https'))) {
    return const CastSource(problem: '当前线路不是 http(s) 地址，电视打不开');
  }
  if (url.host.isEmpty || url.userInfo.isNotEmpty) return const CastSource(problem: '当前线路的地址无效');
  if (isLocalHost(url.host)) return const CastSource(problem: '当前线路是本机地址，电视访问不到');
  final card = detail.card;
  final title = [card.anchorName.trim(), card.title.trim()].where((part) => part.isNotEmpty).join(' - ');
  return CastSource(
    media: CastMedia(
      url: url,
      title: title.isEmpty ? '直播' : title,
      mimeType: line.format == StreamFormat.hls ? CastMime.hls : CastMime.guess(url),
    ),
    needsHeaders: line.headers.isNotEmpty,
    expires: line.lease != null,
  );
}

/// Loopback and unspecified hosts, which another device cannot reach.
bool isLocalHost(String host) {
  final name = host.toLowerCase();
  if (name == 'localhost' || name.endsWith('.localhost')) return true;
  final address = InternetAddress.tryParse(name);
  return address != null && (address.isLoopback || address.address == '0.0.0.0' || address.address == '::');
}

/// Where a cast is.
enum CastPhase {
  /// Nothing cast.
  idle,

  /// Sending the commands to [CastState.device].
  connecting,

  /// [CastState.device] plays [CastState.room].
  casting,

  /// The last cast to [CastState.device] failed with [CastState.failure].
  failed,
}

/// The app-wide cast: one renderer at a time.
@immutable
final class CastState {
  const new({this.phase = CastPhase.idle, this.device, this.room, this.roomTitle, this.failure, this.tvState});

  /// Phase.
  final CastPhase phase;

  /// The renderer of the cast or attempt.
  final CastDevice? device;

  /// The room sent.
  final RoomRef? room;

  /// Its streamer, for "正在投：…".
  final String? roomTitle;

  /// What went wrong, in [CastPhase.failed].
  final Object? failure;

  /// What the renderer last said it does; null when not asked or unknown.
  final TransportState? tvState;

  /// Whether a renderer plays a room now.
  bool get casting => phase == CastPhase.casting;
}

/// The cast (F-CAST-01). App-wide, so leaving the room does not stop it.
///
/// One command sequence runs at a time: a second tap while one runs joins it
/// (REG-ROOM-016). Switching renderers stops the previous one first and waits
/// for it.
class CastNotifier extends Notifier<CastState> {
  CastRenderer? _renderer;
  Future<bool>? _task;

  @override
  CastState build() => const CastState();

  /// Casts [media] of [room] to [device]; true when it plays.
  Future<bool> cast(CastDevice device, CastMedia media, {required RoomRef room, required String roomTitle}) {
    final running = _task;
    if (running != null) return running;
    final task = _cast(device, media, room, roomTitle);
    _task = task;
    task.whenComplete(() {
      if (identical(_task, task)) _task = null;
    }).ignore();
    return task;
  }

  Future<bool> _cast(CastDevice device, CastMedia media, RoomRef room, String roomTitle) async {
    state = CastState(phase: CastPhase.connecting, device: device, room: room, roomTitle: roomTitle);
    final previous = _renderer;
    _renderer = null;
    final same = previous != null && previous.device.id == device.id;
    if (previous != null && !same) {
      try {
        await previous.stop();
      } on Exception {
        // The previous renderer is gone or busy; the new cast goes on.
      }
    }
    final renderer = same ? previous : ref.read(castRendererProvider)(device);
    try {
      await castTo(renderer, media);
    } on Exception catch (error) {
      if (ref.mounted) {
        state = CastState(phase: CastPhase.failed, device: device, room: room, roomTitle: roomTitle, failure: error);
      }
      return false;
    }
    if (!ref.mounted) return false;
    _renderer = renderer;
    state = CastState(
      phase: CastPhase.casting,
      device: device,
      room: room,
      roomTitle: roomTitle,
      tvState: TransportState.playing,
    );
    return true;
  }

  /// Stops the cast; false when the renderer did not confirm (it may still
  /// be playing). The app forgets the cast either way.
  Future<bool> stop() async {
    final running = _task;
    if (running != null) await running;
    final renderer = _renderer;
    _renderer = null;
    if (ref.mounted) state = const CastState();
    if (renderer == null) return true;
    try {
      await renderer.stop();
      return true;
    } on Exception {
      return false;
    }
  }

  /// Asks the renderer what it does now (GetTransportInfo), for the sheet.
  Future<void> refreshStatus() async {
    final renderer = _renderer;
    if (renderer == null || _task != null) return;
    TransportState? tvState;
    try {
      tvState = (await renderer.transportInfo()).state;
    } on Exception {
      tvState = null;
    }
    if (!ref.mounted || !identical(_renderer, renderer)) return;
    final current = state;
    state = CastState(
      phase: current.phase,
      device: current.device,
      room: current.room,
      roomTitle: current.roomTitle,
      tvState: tvState,
    );
  }
}

/// The cast.
final NotifierProvider<CastNotifier, CastState> castProvider = NotifierProvider<CastNotifier, CastState>(
  CastNotifier.new,
);

/// A failure as UI copy.
String castFailureText(Object failure) => switch (failure) {
  CastTimeoutFailure() || CastNetworkFailure() => '连不上这台设备，确认它开着，并且和手机连着同一个 Wi-Fi',
  UpnpActionFailure(:final error) when error.busy => '设备正忙，稍后再试',
  UpnpActionFailure(error: UpnpError.formatNotSupported || UpnpError.illegalMimeType) => '设备不支持这种直播流格式，换一条线路试试',
  UpnpActionFailure(:final error) when error.unplayable => '设备打不开这个直播地址，换一条线路试试',
  UpnpActionFailure(:final code) => '设备拒绝了投屏（错误码 $code）',
  CastHttpFailure(:final statusCode) => '设备返回了错误（HTTP $statusCode）',
  CastProtocolFailure() => '设备的回应无法识别',
  _ => '投屏失败',
};

/// What the renderer does, as UI copy; null when unknown.
String? tvStateText(TransportState? state) => switch (state) {
  TransportState.playing => '电视正在播放',
  TransportState.transitioning => '电视正在加载',
  TransportState.pausedPlayback => '电视已暂停',
  TransportState.stopped || TransportState.noMediaPresent => '电视已停止播放',
  _ => null,
};
