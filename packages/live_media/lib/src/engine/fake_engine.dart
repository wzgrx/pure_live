import 'dart:async';

import 'package:live_media/src/engine/engine.dart';
import 'package:live_media/src/engine/trace.dart';

/// A [PlayerEngine] test double that emits media_kit's recorded event order
/// (spec §4, `fixtures/player`).
///
/// Two modes:
/// - **Trace replay** ([FakeEngine.replay]): each command the session sends
///   that matches the trace's next command releases the recorded events up to
///   the following command, at their recorded offsets (on the zone's timers,
///   so `fake_async` controls them).
/// - **Scripted**: [open], [pause], [play] and [stop] emit the recorded
///   reactions (EVT-13, EVT-18); the scenario helpers ([startStreaming],
///   [endOfStream], [networkTimeout]…) emit the recorded sequences of the
///   matching trace. Nothing here invents an order the real engine never
///   produced.
final class FakeEngine implements PlayerEngine {
  /// Creates a scripted engine.
  new({this.capabilities = const EngineCapabilities(), this.openLatency = Duration.zero, this.startDelay = _startDelay})
    : _trace = null;

  /// Creates an engine that replays [trace].
  new replay(EngineTrace trace, {this.capabilities = const EngineCapabilities(), this.openLatency = Duration.zero})
    : _trace = trace,
      startDelay = _startDelay;

  static const _startDelay = Duration(milliseconds: 10);

  @override
  final EngineCapabilities capabilities;

  /// How long [open] takes to return after its reset events.
  final Duration openLatency;

  /// Delay between the open reset events and `playing=true, buffering=true`
  /// (about 10 ms in the recordings).
  final Duration startDelay;

  final EngineTrace? _trace;
  var _traceCursor = 0;
  Timer? _traceTimer;

  final _events = StreamController<EngineEvent>.broadcast();

  /// Every command received, in order (`open <uri>`, `play`, `pause`, `stop`,
  /// `volume 0.5`, `audioOnly true`, `dispose`).
  final List<String> commands = [];

  /// Every media opened.
  final List<EngineMedia> opened = [];

  /// Every event emitted, in order.
  final List<EngineEvent> emitted = [];

  bool? _playing;
  bool? _completed;
  bool? _buffering;
  EngineTracks? _tracks;
  EngineVideoSize? _size;
  var _frame = 0;
  String? _failNextOpen;
  Completer<void>? _heldOpen;
  var _holdNextOpen = false;

  /// Current volume.
  double volume = 1;

  /// Whether video is off.
  bool audioOnly = false;

  /// Whether [dispose] ran.
  bool disposed = false;

  /// When false, [play] is recorded but the engine stays paused (a stuck
  /// output the session must escalate).
  bool respondToPlay = true;

  /// When true, [setAudioOnly] never returns (a stuck native switch, AUD-4).
  bool hangAudioSwitch = false;

  /// When set, every [open] fails with this message (a dead CDN, EVT-17).
  String? failEveryOpen;

  /// Whether the engine currently reports playing.
  bool get playing => _playing ?? false;

  /// Whether the engine currently reports buffering.
  bool get buffering => _buffering ?? false;

  @override
  Stream<EngineEvent> get events => _events.stream;

  void _emit(EngineEvent event) {
    if (_events.isClosed) return;
    emitted.add(event);
    _events.add(event);
  }

  void _setPlaying(bool value) {
    if (_playing == value) return;
    _playing = value;
    _emit(EnginePlaying(value));
  }

  void _setCompleted(bool value) {
    if (_completed == value) return;
    _completed = value;
    _emit(EngineCompleted(value));
  }

  void _setBuffering(bool value) {
    if (_buffering == value) return;
    _buffering = value;
    _emit(EngineBuffering(value));
  }

  void _setTracks(int video, int audio) {
    final current = _tracks;
    if (current != null && current.video == video && current.audio == audio) return;
    _emit(_tracks = EngineTracks(video: video, audio: audio));
  }

  void _setSize(int? width, int? height) {
    final current = _size;
    if (current != null && current.width == width && current.height == height) return;
    _emit(_size = EngineVideoSize(width, height));
  }

  /// Makes the next [open] fail the way a 403 or non-media response does:
  /// only an error, playing and buffering stay true (EVT-17).
  // Reads as a scenario step, not a property.
  // ignore: use_setters_to_change_properties
  void failNextOpen([String message = 'Failed to open http://127.0.0.1/live.flv.']) => _failNextOpen = message;

  /// Makes the next [open] wait until [releaseOpen] (an open that does not return).
  void holdNextOpen() => _holdNextOpen = true;

  /// Lets a held [open] return.
  void releaseOpen() {
    final held = _heldOpen;
    _heldOpen = null;
    if (held != null && !held.isCompleted) held.complete();
  }

  bool _replayCommand(String command) {
    final trace = _trace;
    if (trace == null) return false;
    while (_traceCursor < trace.steps.length && trace.steps[_traceCursor].command == null) {
      _traceCursor++;
    }
    if (_traceCursor >= trace.steps.length || trace.steps[_traceCursor].command != command) return true;
    final start = trace.steps[_traceCursor].ms;
    _traceCursor++;
    final segment = <TraceStep>[];
    while (_traceCursor < trace.steps.length && trace.steps[_traceCursor].command == null) {
      segment.add(trace.steps[_traceCursor++]);
    }
    _traceTimer?.cancel();
    _playSegment(segment, 0, start);
    return true;
  }

  void _playSegment(List<TraceStep> segment, int index, int at) {
    if (index >= segment.length) return;
    final ms = segment[index].ms;
    void fire() {
      var next = index;
      while (next < segment.length && segment[next].ms == ms) {
        _applyReplayed(segment[next++].event!);
      }
      _playSegment(segment, next, ms);
    }

    if (ms <= at) {
      fire();
    } else {
      _traceTimer = Timer(Duration(milliseconds: ms - at), fire);
    }
  }

  void _applyReplayed(EngineEvent event) {
    switch (event) {
      case EnginePlaying(:final playing):
        _playing = playing;
      case EngineCompleted(:final completed):
        _completed = completed;
      case EngineBuffering(:final buffering):
        _buffering = buffering;
      case EngineTracks():
        _tracks = event;
      case EngineVideoSize():
        _size = event;
      default:
    }
    _emit(event);
  }

  @override
  Future<void> open(EngineMedia media) async {
    commands.add('open ${media.uri}');
    opened.add(media);
    audioOnly = media.audioOnly;
    if (!_replayCommand('open')) {
      // EVT-13: reset first, then "trying to play" before any data.
      _setPlaying(false);
      _setCompleted(false);
      _emit(const EnginePosition(Duration.zero));
      _emit(const EngineDuration(Duration.zero));
      _setBuffering(false);
      _setTracks(0, 0);
      _setSize(null, null);
      final failure = _failNextOpen ?? failEveryOpen;
      _failNextOpen = null;
      Timer(startDelay, () {
        if (disposed) return;
        _setPlaying(true);
        _setBuffering(true);
        if (failure != null) _emit(EngineError(failure, prefix: 'cplayer'));
      });
    }
    if (_holdNextOpen) {
      _holdNextOpen = false;
      await (_heldOpen = Completer<void>()).future;
    }
    if (openLatency > Duration.zero) await Future<void>.delayed(openLatency);
  }

  /// Data arrived: buffering ends, tracks appear, then the decoded size (the
  /// start of every recorded scenario).
  void startStreaming({int width = 1920, int height = 1080, int videoTracks = 1, int audioTracks = 1}) {
    _setBuffering(false);
    _setTracks(videoTracks, audioTracks);
    _setSize(width, height);
  }

  /// A new decoded size.
  void resize(int? width, int? height) => _setSize(width, height);

  /// The connection ended cleanly or was reset mid-stream (EVT-14, EVT-16:
  /// indistinguishable): buffering, playing=false, completed=true, buffering
  /// off, tracks reset.
  void endOfStream() {
    _setBuffering(true);
    _setPlaying(false);
    _setCompleted(true);
    _setBuffering(false);
    _setTracks(0, 0);
  }

  /// Data stopped arriving on an open connection: buffering starts (`stall` trace).
  void stallBegin() => _setBuffering(true);

  /// Buffering ended without other changes.
  void stallEnd() => _setBuffering(false);

  /// The stalled connection hit mpv's `network-timeout` (EVT-15): no error,
  /// just end of stream, followed by buffering=true.
  void networkTimeout() {
    _setBuffering(false);
    _setPlaying(false);
    _setCompleted(true);
    _setTracks(0, 0);
    _setBuffering(true);
  }

  /// A presented frame ([EngineCapabilities.frameProgress]).
  void frame() => _emit(EngineFrame(++_frame));

  /// An error-level diagnostic.
  void diagnostic(String message, {String prefix = 'cplayer'}) => _emit(EngineError(message, prefix: prefix));

  @override
  Future<void> play() async {
    commands.add('play');
    if (!_replayCommand('play') && respondToPlay) _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    if (!_replayCommand('pause')) _setPlaying(false);
  }

  @override
  Future<void> stop() async {
    commands.add('stop');
    if (!_replayCommand('stop')) {
      // EVT-18: no completed.
      _setPlaying(false);
      _emit(const EngineDuration(Duration.zero));
      _setBuffering(false);
      _setTracks(0, 0);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    commands.add('volume $volume');
    this.volume = volume;
  }

  @override
  Future<void> setAudioOnly({required bool enabled}) async {
    commands.add('audioOnly $enabled');
    if (hangAudioSwitch) await Completer<void>().future;
    audioOnly = enabled;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    commands.add('dispose');
    _replayCommand('dispose');
    disposed = true;
    _traceTimer?.cancel();
    releaseOpen();
    unawaited(_events.close());
  }
}
