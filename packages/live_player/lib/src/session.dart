import 'dart:async';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/src/engine.dart';
import 'package:live_player/src/state.dart';
import 'package:meta/meta.dart';

/// Resolves the playing quality again (3.x's `PlaybackSourceResolver`): a
/// fresh plan with renewed signatures. The room page builds it from the
/// platform's `resolvePlayUrlsForRecovery`.
typedef PlanRefresher = Future<PlaybackPlan> Function();

/// What to play (3.x's `playSource` arguments).
@immutable
final class PlaybackRequest {
  /// Creates a request.
  const new({required this.site, required this.plan, this.refresh, this.audioOnly = false, this.volume = 1});

  /// The platform id: the proxy route key and the relay's site.
  final String site;

  /// The sources of the chosen quality.
  final PlaybackPlan plan;

  /// Renews signed lines: relays splice renewals in, leases that do not cut
  /// the connection are prefetched at `refreshAt`, and a transport failure
  /// refreshes before walking the lines. Without it the plan is played as is.
  final PlanRefresher? refresh;

  /// Start without video output.
  final bool audioOnly;

  /// Volume, 0 to 1 (3.x restored the room's saved volume on desktop).
  final double volume;
}

/// The session's deadlines, 3.x's `PlayerManager` defaults.
@immutable
final class SessionTimings {
  /// Creates the timings.
  const new({
    this.sourceOpen = const Duration(seconds: 18),
    this.sourceRefresh = const Duration(seconds: 12),
    this.unexpectedPauseGrace = const Duration(milliseconds: 350),
    this.unexpectedPauseFailure = const Duration(seconds: 5),
    this.bufferingStall = const Duration(seconds: 12),
    this.stallNotice = const Duration(seconds: 4),
    this.frameStall = const Duration(seconds: 10),
    this.recoveryBudgetReset = const Duration(seconds: 30),
    this.liveRetryDelays = const [Duration(milliseconds: 750), Duration(seconds: 2)],
    this.idleRelease = const Duration(seconds: 45),
    this.refreshRetry = const Duration(seconds: 10),
    this.offlineGrace = const Duration(seconds: 20),
    this.networkProbe = const Duration(seconds: 2),
    this.networkProbeTimeout = const Duration(seconds: 5),
  });

  /// Longest wait for an input plus the engine's open.
  final Duration sourceOpen;

  /// Longest wait for a refreshed plan.
  final Duration sourceRefresh;

  /// How long an unrequested pause of a live source may last before the
  /// session asks the engine to play again.
  final Duration unexpectedPauseGrace;

  /// How long after that the pause counts as a failure.
  final Duration unexpectedPauseFailure;

  /// How long buffering may last before it counts as a failure; for a live
  /// source whose position moves (mpv's `time-pos`), also how long it may
  /// go without moving, whatever the engine's flags say (G02.3).
  final Duration bufferingStall;

  /// How long a live source that was moving may stand still before the
  /// session says it reconnects ([PlaybackState.recovery]), ahead of
  /// [bufferingStall] (G02.3: "正在重连" within ten seconds of a cut; a
  /// shorter stall is a buffering, B02).
  final Duration stallNotice;

  /// How long without a presented frame counts as a failure (engines that
  /// report frames, video shown).
  final Duration frameStall;

  /// Sustained playback that restores the refresh and retry budgets.
  final Duration recoveryBudgetReset;

  /// Delays of the bounded retry rounds after immediate recovery is
  /// exhausted on a live source.
  final List<Duration> liveRetryDelays;

  /// How long a stopped session keeps its engine for the next room.
  final Duration idleRelease;

  /// Delay before trying a failed lease prefetch again.
  final Duration refreshRetry;

  /// How long the session keeps saying it reconnects after it found the
  /// network gone, before it publishes [networkLostCode] (and keeps
  /// looking).
  final Duration offlineGrace;

  /// The pause between two looks at the network while it is gone.
  final Duration networkProbe;

  /// Longest wait for one look at the network.
  final Duration networkProbeTimeout;
}

/// The playback session of one player (the session and recovery half of
/// 3.x's `PlayerManager`): open a plan, follow the engine, recover, stop.
///
/// Recovery after a failure of the current source, in 3.x's order:
/// 1. network or source failure with a refresher: refresh the plan (a
///    prefetched one first) and reopen the same line, the next one on the
///    second try (at most two refreshes per budget);
/// 2. network or source failure: the next line that has not failed
///    ([LineFallback], keyed by CDN code);
/// 3. a presented-frame stall: recreate the engine once;
/// 4. a decoder-class failure that is not about audio: software decoding
///    ([DecoderFallback]);
/// 5. a live source: bounded retry rounds after [SessionTimings.liveRetryDelays]
///    with fresh budgets;
/// 6. otherwise the error is published and playback stops.
///
/// The platform saying the stream cannot be played (offline, login, region)
/// is published at once without walking the lines. An on-demand source
/// (replay) ends as [PlaybackStatus.completed] and seeks.
///
/// G02.3, a live source and the network:
/// - a source is judged by its position moving, where the engine reports
///   one, not by the engine's flags (mpv's `playing` only means "not
///   paused", and its buffering flag flips while nothing arrives): standing
///   still for [SessionTimings.stallNotice] after it moved is the first
///   attempt of a recovery, for [SessionTimings.bufferingStall] a failure;
///   a reopened source ends its recovery once it moves;
/// - a refresh that fails because nothing answered means the network is
///   gone: no line or decoder is tried; the session looks at the network
///   every [SessionTimings.networkProbe] (each look another attempt), after
///   [SessionTimings.offlineGrace] publishes [networkLostCode] and keeps
///   looking, and reopens the stream once the platform answers.
final class PlaybackSession {
  /// Creates a session. The opener is the caller's (it may share a relay
  /// with other players); [engine] creates the engine on first open.
  new({
    required EngineFactory engine,
    required this._opener,
    DecoderFallback? decoders,
    this.timings = const SessionTimings(),
  }) : _createEngine = engine,
       _decoders = decoders ?? DecoderFallback();

  /// Deadlines.
  final SessionTimings timings;

  final EngineFactory _createEngine;
  final MediaOpener _opener;
  final DecoderFallback _decoders;
  final LineFallback _lines = LineFallback();
  final SourceEventFence _fence = SourceEventFence();
  final StreamController<PlaybackState> _states = StreamController.broadcast(sync: true);

  PlaybackTransport _transport = PlaybackTransport();
  PlayerEngine? _engine;
  Future<PlayerEngine>? _engineCreating;
  StreamSubscription<EngineEvent>? _events;

  PlaybackState _state = const PlaybackState();
  PlaybackRequest? _request;
  PlaybackPlan? _plan;
  PlaybackSource? _source;
  DecoderMode _decoder = DecoderMode.hardware;
  PlaybackPlan? _prefetched;

  int _session = 0;
  bool _disposed = false;
  bool _wantPlaying = false;
  bool _playing = false;
  bool _buffering = false;
  PlayerException? _openingError;

  final Set<String> _errorSignatures = {};
  int? _recoveringSession;
  PlayerException? _pendingError;
  int _refreshAttempts = 0;
  int _retryRounds = 0;
  bool _engineRecreated = false;
  bool _presentationVisible = true;

  /// Recovery attempts in a row ([PlaybackState.recovery]): counted by
  /// [_recover] and every retry round, reset by the user's reopenings and
  /// by sustained playback ([_armBudgetReset]).
  int _recoveries = 0;

  /// The engine's positions moved on a live source at least once: from
  /// then on a source is judged by moving, not by the engine's flags.
  bool _engineMoves = false;

  /// The last position of the current source (null: none since it opened).
  Duration? _lastPosition;

  /// When the current source last moved, or started waiting to.
  DateTime? _lastMove;

  /// The current source moved since it opened or resumed.
  bool _moved = false;

  /// A reopened source of a recovery: the engine's flags do not end the
  /// recovery, moving does.
  bool _awaitingMove = false;

  /// The source stood still for [SessionTimings.stallNotice]: the
  /// recovery's attempt is shown before the recovery acts.
  bool _stallNoticed = false;

  /// The network is gone: [_probe] owns the recovery.
  bool _offline = false;
  DateTime? _offlineSince;
  Object? _offlineError;

  Timer? _bufferingTimer;
  Timer? _moveTimer;
  Timer? _probeTimer;
  Timer? _pauseTimer;
  Timer? _frameTimer;
  DateTime? _lastFrame;
  Timer? _budgetTimer;
  Timer? _retryTimer;
  Timer? _prefetchTimer;
  Timer? _idleTimer;

  /// The current snapshot.
  PlaybackState get state => _state;

  /// Every new snapshot, synchronously.
  Stream<PlaybackState> get states => _states.stream;

  /// The engine, once created; the video view renders it.
  PlayerEngine? get engine => _engine;

  /// The input the engine plays.
  MediaInput? get input => _transport.active;

  /// The plan being played (after refreshes, the refreshed one).
  PlaybackPlan? get plan => _plan;

  bool _current(int session) => !_disposed && session == _session;

  void _emit(PlaybackState next) {
    if (_disposed) return;
    _state = next;
    _states.add(next);
  }

  /// Plays [request] (3.x's `playSource`), replacing whatever plays.
  Future<void> open(PlaybackRequest request) async {
    _checkAlive();
    final session = _begin();
    _request = request;
    _plan = request.plan;
    _prefetched = null;
    _lines.reset();
    _decoders.resetAll();
    _decoder = _decoders.preferred;
    _refreshAttempts = 0;
    _retryRounds = 0;
    _recoveries = 0;
    _engineRecreated = false;
    _wantPlaying = true;
    _emit(
      PlaybackState(
        status: PlaybackStatus.opening,
        lineCount: request.plan.sources.length,
        decoder: _decoder,
        audioOnly: request.audioOnly,
        volume: request.volume.clamp(0, 1).toDouble(),
        onDemand: request.plan.onDemand,
        appliedQualityData: request.plan.appliedQualityData,
      ),
    );
    if (request.plan.isEmpty) {
      _publishError(
        const PlayerException(message: 'The plan has no source', type: PlayerErrorType.source, code: 'no_source'),
        SourceFailureKind.terminal,
      );
      return;
    }
    // A kept engine gets this room's volume; a new one gets it on creation.
    await _engine?.setVolume(_state.volume);
    if (!_current(session)) return;
    await _openSource(request.plan.sources.first, session);
  }

  /// Opens the source at [index] of the plan (a manual line switch).
  Future<void> selectLine(int index) async {
    _checkAlive();
    final plan = _plan;
    if (plan == null || index < 0 || index >= plan.sources.length) return;
    final session = _begin();
    _refreshAttempts = 0;
    _retryRounds = 0;
    _recoveries = 0;
    _wantPlaying = true;
    await _openSource(plan.sources[index], session);
  }

  /// Opens the current source again with fresh budgets (the retry button
  /// after an error).
  Future<void> retry() async {
    _checkAlive();
    final plan = _plan;
    if (plan == null || plan.isEmpty) return;
    final session = _begin();
    _lines.reset();
    _decoders.resetAll();
    _decoder = _decoders.preferred;
    _refreshAttempts = 0;
    _retryRounds = 0;
    _recoveries = 0;
    _engineRecreated = false;
    _wantPlaying = true;
    final source = _source;
    await _openSource(source != null && plan.sources.contains(source) ? source : plan.sources.first, session);
  }

  /// Pauses (a user pause: no watchdog reverses it).
  Future<void> pause() async {
    if (_disposed) return;
    _wantPlaying = false;
    _cancelWatchdogs();
    _retryTimer?.cancel();
    // A pause while the network is gone stops looking for it; resume
    // reopens a failed stream.
    _leaveOffline();
    _stallNoticed = false;
    _awaitingMove = false;
    final engine = _engine;
    if (engine != null && _transport.active != null) await engine.pause();
    if (_state.status != PlaybackStatus.error && _state.status != PlaybackStatus.stopped) {
      _emit(_state.copyWith(status: PlaybackStatus.paused, recovery: 0));
    }
  }

  /// Resumes after [pause]; reopens when the input is gone (a closed grant,
  /// an error) or an on-demand source ended.
  Future<void> resume() async {
    if (_disposed || _plan == null) return;
    final engine = _engine;
    if (engine == null || !_transport.activeInputIsUsable || _state.status == PlaybackStatus.error) {
      await retry();
      return;
    }
    _wantPlaying = true;
    // A resume that waits is no drop (B02) until the source moved again.
    _moved = false;
    _lastMove = null;
    _emit(_state.copyWith(status: PlaybackStatus.buffering));
    await engine.play();
    _settle(_session);
  }

  /// Pauses or resumes.
  Future<void> togglePlayPause() => _wantPlaying ? pause() : resume();

  /// Seeks an on-demand source; ignored for live ones.
  Future<void> seek(Duration position) async {
    final engine = _engine;
    if (_disposed || engine == null || !(_plan?.onDemand ?? false)) return;
    await engine.seek(position);
    if (_state.status == PlaybackStatus.completed) {
      _wantPlaying = true;
      _emit(_state.copyWith(status: PlaybackStatus.buffering, position: position));
      await engine.play();
    }
  }

  /// Turns video output off or on without reopening (3.x's audio-only mode).
  Future<void> setAudioOnly({required bool enabled}) async {
    if (_disposed) return;
    _emit(_state.copyWith(audioOnly: enabled));
    if (enabled) _cancelFrameWatchdog();
    await _engine?.setAudioOnly(enabled: enabled);
  }

  /// Whether the picture is on screen (default true). A picture nobody can
  /// see (a multiview cell scrolled away, a hidden window) presents no
  /// frames on some platforms, so the stalled-picture watchdog is off until
  /// it is visible again; then it starts afresh. Playback is not touched.
  bool get presentationVisible => _presentationVisible;

  /// Tells the session whether its picture is on screen; see
  /// [presentationVisible].
  void setPresentationVisible({required bool visible}) {
    if (_disposed || visible == _presentationVisible) return;
    _presentationVisible = visible;
    _cancelFrameWatchdog();
    if (visible && _playing && !_buffering && _state.status == PlaybackStatus.playing) _armFrameWatchdog(_session);
  }

  /// Sets the volume, 0 to 1.
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final value = volume.isFinite ? volume.clamp(0, 1).toDouble() : 1.0;
    _emit(_state.copyWith(volume: value));
    await _engine?.setVolume(value);
  }

  /// Stops and releases the input but keeps the engine for
  /// [SessionTimings.idleRelease] (3.x's `close`/`softStop`). Only the
  /// latest stop arms that release, and only while nothing was opened since;
  /// it checks again that the session is still idle when it fires.
  Future<void> stop() async {
    if (_disposed) return;
    final session = _begin();
    _wantPlaying = false;
    _fence.clear();
    final transport = _transport;
    _transport = PlaybackTransport();
    _source = null;
    _emit(_state.copyWith(status: PlaybackStatus.stopped, clearVideoSize: true, recovery: 0));
    await transport.close();
    final engine = _engine;
    if (engine != null) {
      try {
        await engine.stop();
      } on Object {
        // Already stopped or never opened.
      }
      // A newer stop arms its own release; a newer open needs the engine.
      if (!_current(session)) return;
      _idleTimer?.cancel();
      _idleTimer = Timer(timings.idleRelease, () {
        if (_current(session) && _state.status == PlaybackStatus.stopped) unawaited(_releaseEngine());
      });
    }
  }

  /// Releases everything; the session cannot be used afterwards. An engine
  /// still being created is waited for and released too.
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _idleTimer?.cancel();
    _disposed = true;
    final creating = _engineCreating;
    if (creating != null) {
      try {
        // [_engineNow] no longer adopts it once disposed.
        final created = await creating;
        if (!identical(created, _engine)) await created.dispose();
      } on Object {
        // The creation failed: nothing to release.
      }
    }
    await _releaseEngine();
    await _states.close();
  }

  void _checkAlive() {
    if (_disposed) throw StateError('Playback session is disposed');
  }

  /// Starts a new session generation: older async work stops at its next
  /// check, and every timer of the older generation is cancelled.
  int _begin() {
    _session++;
    _cancelWatchdogs();
    _retryTimer?.cancel();
    _prefetchTimer?.cancel();
    _idleTimer?.cancel();
    _leaveOffline();
    _pendingError = null;
    return _session;
  }

  Future<PlayerEngine> _engineNow() async {
    _idleTimer?.cancel();
    final engine = _engine;
    if (engine != null) return engine;
    final creating = _engineCreating ??= _createEngine();
    try {
      final created = await creating;
      // Disposed meanwhile: not adopted, dispose() releases it.
      _checkAlive();
      if (_engine == null) {
        _engine = created;
        _events = created.events.listen(_onEvent);
        await created.setVolume(_state.volume);
      }
      return _engine!;
    } on Object catch (error, stack) {
      throw PlayerException(
        message: 'Engine creation failed: $error',
        type: PlayerErrorType.initialization,
        error: error,
        stackTrace: stack,
      );
    } finally {
      if (identical(_engineCreating, creating)) _engineCreating = null;
    }
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;
    _engineMoves = false;
    // Not awaited: a broadcast cancel completes in the root zone.
    unawaited(_events?.cancel());
    _events = null;
    await engine?.dispose();
  }

  /// Opens [source]; [recovering] keeps the state's [PlaybackState.recovery]
  /// (a step of [_recover]), otherwise it is the user's reopening.
  Future<void> _openSource(PlaybackSource source, int session, {bool recovering = false}) async {
    final request = _request!;
    final plan = _plan!;
    _cancelWatchdogs();
    _source = source;
    if (source case LineSource(:final line)) _lines.select(line);
    final generation = _fence.begin(source.url);
    _errorSignatures.clear();
    _openingError = null;
    _playing = false;
    _buffering = true;
    _lastPosition = null;
    _lastMove = null;
    _moved = false;
    _stallNoticed = false;
    // mpv says it plays as soon as a load starts: a recovery's source has
    // to move before the recovery ends.
    _awaitingMove = recovering && _engineMoves && !plan.onDemand;
    final opened = _state.status == PlaybackStatus.playing || _state.status == PlaybackStatus.buffering;
    _emit(
      _state.copyWith(
        status: opened ? PlaybackStatus.buffering : PlaybackStatus.opening,
        source: source,
        line: switch (source) {
          LineSource(:final line) => line,
          RecipeSource() => null,
        },
        lineIndex: plan.sources.indexOf(source).clamp(0, plan.sources.length),
        lineCount: plan.sources.length,
        decoder: _decoder,
        clearVideoSize: true,
        appliedQualityData: plan.appliedQualityData,
        recovery: recovering ? _recoveries : 0,
      ),
    );
    try {
      final engine = await _engineNow();
      if (!_current(session) || _fence.generation != generation) return;
      final refresh = request.refresh;
      await _transport
          .open(
            (cancel) => _opener.open(
              source,
              site: request.site,
              renew: refresh == null ? null : _renewer(session, refresh),
              queryPolicy: plan.queryPolicyFor(source),
              onRenewed: (line) {
                if (_current(session)) _emit(_state.copyWith(line: line));
              },
              onDemand: plan.onDemand,
              start: plan.start,
              cancel: cancel,
            ),
            (input) => engine.open(EngineMedia.of(input, decoder: _decoder, audioOnly: _state.audioOnly)),
          )
          .timeout(
            timings.sourceOpen,
            onTimeout: () {
              unawaited(_transport.cancelPending());
              throw const PlayerException(
                message: 'The source did not open before the deadline',
                type: PlayerErrorType.source,
                code: 'source_open_timeout',
              );
            },
          );
      if (!_current(session) || _fence.generation != generation) return;
      _fence.finishOpen(const [], authorizeSuccessfulOpen: true);
      final input = _transport.active;
      if (input?.line case final line?) _emit(_state.copyWith(line: line));
      _schedulePrefetch(session);
      final openingError = _openingError;
      _openingError = null;
      if (openingError != null && !_playing) {
        _handleError(openingError, session);
        return;
      }
      _settle(session);
    } on Object catch (error, stack) {
      if (!_current(session) || _fence.generation != generation) return;
      _fence.finishOpen(const [], authorizeSuccessfulOpen: false);
      final kind = classifySourceFailure(error);
      if (kind == SourceFailureKind.cancelled) return;
      if (kind == SourceFailureKind.terminal) {
        _publishError(error, kind);
        return;
      }
      _handleError(
        error is PlayerException
            ? error
            : PlayerException(
                message: 'Source open failed: $error',
                type: PlayerErrorType.source,
                code: 'source_open',
                error: error,
                stackTrace: stack,
              ),
        session,
        fenced: false,
      );
    }
  }

  /// A renewer for the relays: the refreshed line with the same CDN code,
  /// else the one at the same place, else the first.
  LineRenewer _renewer(int session, PlanRefresher refresh) => (current) async {
    if (!_current(session)) throw StateError('Playback session moved on');
    final lines = (await refresh().timeout(timings.sourceRefresh)).lines;
    if (lines.isEmpty) throw StateError('The refreshed plan has no lines');
    final previous = _plan?.lines ?? const <LivePlayLine>[];
    final index = previous.indexWhere((line) => line.url == current.url);
    return lines.where((line) => current.lineId != null && line.lineId == current.lineId).firstOrNull ??
        (index >= 0 && index < lines.length ? lines[index] : lines.first);
  };

  // Engine events.

  bool get _accepting => _fence.accepts(_fence.generation);

  void _onEvent(EngineEvent event) {
    if (_disposed) return;
    final session = _session;
    switch (event) {
      case EnginePlaying(:final playing):
        _playing = playing;
        if (_accepting) _onPlaying(playing, session);
      case EngineBuffering(:final buffering):
        _buffering = buffering;
        if (_accepting) _onBuffering(buffering, session);
      case EngineCompleted():
        if (_accepting) _onCompleted(session);
      case EngineVideoSize(:final width, :final height):
        if (_accepting && width > 0 && height > 0) _emit(_state.copyWith(videoWidth: width, videoHeight: height));
      case EngineFrameRate(:final fps):
        if (_accepting && fps > 0) _emit(_state.copyWith(frameRate: fps));
      case EnginePosition(:final position):
        if (_accepting && _state.onDemand) _emit(_state.copyWith(position: position));
        if (_accepting) _onPosition(position, session);
      case EngineDuration(:final duration):
        if (_accepting && _state.onDemand) _emit(_state.copyWith(duration: duration));
      case EngineFrame():
        if (_accepting) _onFrame(session);
      case EngineError(:final error):
        if (_fence.isOpening) {
          // Held until the open settles: a frame or playing state that
          // follows refutes it (3.x's opening diagnostic).
          _openingError = error;
        } else if (_accepting) {
          _handleError(error, session);
        }
    }
  }

  /// Publishes the state the engine's flags imply and arms the matching
  /// watchdog.
  void _settle(int session) {
    if (!_current(session) || !_accepting) return;
    if (!_wantPlaying) {
      if (_state.status != PlaybackStatus.error && _state.status != PlaybackStatus.completed) {
        _emit(_state.copyWith(status: PlaybackStatus.paused, recovery: 0));
      }
      return;
    }
    if (_buffering) {
      _emit(_state.copyWith(status: PlaybackStatus.buffering));
      _armBufferingWatchdog(session);
    } else if (_playing) {
      _onPlaying(true, session);
    } else {
      _armUnexpectedPause(session);
    }
  }

  void _onPlaying(bool playing, int session) {
    if (playing) {
      _pauseTimer?.cancel();
      _pauseTimer = null;
      if (_awaitingMove || _stallNoticed || _offline) {
        // The flag is no proof anything arrived (G02.3): the recovery goes
        // on until the source moves.
        if (_wantPlaying) {
          _emit(_state.copyWith(status: PlaybackStatus.buffering));
          if (_buffering) _armBufferingWatchdog(session);
          _armMoveWatchdog(session);
        }
        return;
      }
      if (_source case LineSource(:final line)) _lines.markSuccess(line);
      _decoders.reset(_decoder);
      if (!_wantPlaying) return;
      if (_buffering) {
        _emit(_state.copyWith(status: PlaybackStatus.buffering));
        _armBufferingWatchdog(session);
        _armMoveWatchdog(session);
      } else {
        _bufferingTimer?.cancel();
        _bufferingTimer = null;
        // Playing again ends a recovery (its count runs on, see
        // [_armBudgetReset]).
        _emit(_state.copyWith(status: PlaybackStatus.playing, recovery: 0));
        _armFrameWatchdog(session);
        _armMoveWatchdog(session);
        _armBudgetReset(session);
      }
      return;
    }
    _cancelFrameWatchdog();
    _budgetTimer?.cancel();
    if (!_wantPlaying) {
      // A published failure stays: the engine stopping is no user pause.
      if (_state.status != PlaybackStatus.completed && _state.status != PlaybackStatus.error) {
        _emit(_state.copyWith(status: PlaybackStatus.paused, recovery: 0));
      }
    } else if (_buffering) {
      _armBufferingWatchdog(session);
    } else {
      // A live source the user did not pause: transport state, not intent.
      _armUnexpectedPause(session);
    }
  }

  void _onBuffering(bool buffering, int session) {
    if (buffering) {
      _cancelFrameWatchdog();
      _budgetTimer?.cancel();
      if (_wantPlaying) {
        _emit(_state.copyWith(status: PlaybackStatus.buffering));
        _armBufferingWatchdog(session);
      }
      return;
    }
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    if (_playing) {
      _onPlaying(true, session);
    } else if (_wantPlaying) {
      _armUnexpectedPause(session);
    }
  }

  void _onCompleted(int session) {
    if (_plan?.onDemand ?? false) {
      _wantPlaying = false;
      _cancelWatchdogs();
      _emit(_state.copyWith(status: PlaybackStatus.completed, recovery: 0));
      return;
    }
    if (!_wantPlaying) return;
    _handleError(
      const PlayerException(
        message: 'Live source ended unexpectedly',
        type: PlayerErrorType.source,
        code: 'live_source_completed',
      ),
      session,
    );
  }

  void _onFrame(int session) {
    _lastFrame = clock.now();
    _armFrameWatchdog(session);
  }

  /// A live source's position: moving on is the proof that it plays.
  void _onPosition(Duration position, int session) {
    if (_plan?.onDemand ?? true) return;
    final last = _lastPosition;
    _lastPosition = position;
    if (last == null || position <= last) return;
    _engineMoves = true;
    _lastMove = clock.now();
    _moved = true;
    final waited = _awaitingMove || _stallNoticed || _offline;
    _awaitingMove = false;
    _stallNoticed = false;
    if (_offline) {
      // The stream came back by itself (an HLS demuxer that kept asking).
      _leaveOffline();
      _wantPlaying = true;
    }
    _armMoveWatchdog(session);
    if (waited && _playing && !_buffering) _onPlaying(true, session);
  }

  // Watchdogs.

  /// Repeated buffering notifications keep the first deadline (3.x).
  void _armBufferingWatchdog(int session) {
    if (_bufferingTimer != null || !_wantPlaying) return;
    _bufferingTimer = Timer(timings.bufferingStall, () {
      _bufferingTimer = null;
      if (!_current(session) || !_buffering || !_wantPlaying) return;
      _handleError(
        const PlayerException(
          message: 'Buffering did not end before the deadline',
          type: PlayerErrorType.source,
          code: 'buffering_stall_timeout',
        ),
        session,
      );
    });
  }

  /// An unrequested pause of a live source: ask the engine to play once,
  /// then count it as a failure (3.x's continuity supervisor).
  void _armUnexpectedPause(int session) {
    if (_pauseTimer != null || !_wantPlaying) return;
    _pauseTimer = Timer(timings.unexpectedPauseGrace, () {
      if (!_current(session) || !_wantPlaying || _playing || _buffering) {
        _pauseTimer = null;
        return;
      }
      unawaited(_engine?.play().catchError((Object _) {}));
      _pauseTimer = Timer(timings.unexpectedPauseFailure, () {
        _pauseTimer = null;
        if (!_current(session) || !_wantPlaying || _playing || _buffering) return;
        _handleError(
          const PlayerException(
            message: 'The live source stayed paused',
            type: PlayerErrorType.source,
            code: 'unexpected_pause_timeout',
          ),
          session,
        );
      });
    });
  }

  /// One timer for many frames: it re-arms itself for the time left since
  /// the last frame (3.x allocated nothing per frame either).
  void _armFrameWatchdog(int session) {
    final engine = _engine;
    if (_frameTimer != null ||
        engine == null ||
        !engine.reportsFrames ||
        _state.audioOnly ||
        !_wantPlaying ||
        !_presentationVisible) {
      return;
    }
    _lastFrame ??= clock.now();
    void check() {
      _frameTimer = null;
      if (!_current(session) || !_wantPlaying || _state.audioOnly || _buffering || !_presentationVisible) return;
      final idle = clock.now().difference(_lastFrame ?? clock.now());
      if (idle < timings.frameStall) {
        _frameTimer = Timer(timings.frameStall - idle, check);
        return;
      }
      _handleError(
        const PlayerException(
          message: 'No video frame was presented before the deadline',
          type: PlayerErrorType.source,
          code: 'video_frame_stall_timeout',
        ),
        session,
      );
    }

    _frameTimer = Timer(timings.frameStall, check);
  }

  /// G02.3: a live source that moved, or a recovery's source that has to,
  /// is judged by its position: the engine's flags neither postpone nor end
  /// the wait (one timer, re-armed for the time left, like the frame
  /// watchdog). Standing still for [SessionTimings.stallNotice] after
  /// moving shows the recovery's attempt; for [SessionTimings.bufferingStall]
  /// it is a failure.
  void _armMoveWatchdog(int session) {
    if (_moveTimer != null || !_wantPlaying || _offline || (_plan?.onDemand ?? true)) return;
    if (!_moved && !_awaitingMove) return;
    _lastMove ??= clock.now();
    Duration next(Duration still) {
      final notice = _moved && !_stallNoticed && !_state.recovering && still < timings.stallNotice;
      return (notice ? timings.stallNotice : timings.bufferingStall) - still;
    }

    void check() {
      _moveTimer = null;
      if (!_current(session) || !_wantPlaying || _offline) return;
      final still = clock.now().difference(_lastMove ?? clock.now());
      if (still >= timings.bufferingStall) {
        _handleError(
          const PlayerException(
            message: 'The live source did not move before the deadline',
            type: PlayerErrorType.source,
            code: 'playback_stall_timeout',
          ),
          session,
        );
        return;
      }
      if (_moved && !_stallNoticed && !_state.recovering && still >= timings.stallNotice) _noticeStall();
      _moveTimer = Timer(next(still), check);
    }

    _moveTimer = Timer(next(clock.now().difference(_lastMove!)), check);
  }

  /// The source stands still: the first attempt of the recovery shows now
  /// ([_recover] does not count it again).
  void _noticeStall() {
    _stallNoticed = true;
    _recoveries++;
    _cancelFrameWatchdog();
    _budgetTimer?.cancel();
    _emit(_state.copyWith(status: PlaybackStatus.buffering, recovery: _recoveries));
  }

  void _cancelMoveWatchdog() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  void _cancelFrameWatchdog() {
    _frameTimer?.cancel();
    _frameTimer = null;
    _lastFrame = null;
  }

  /// Sustained playback restores the refresh, retry and recreation budgets.
  void _armBudgetReset(int session) {
    _budgetTimer?.cancel();
    _budgetTimer = Timer(timings.recoveryBudgetReset, () {
      if (!_current(session) || !_playing || _buffering) return;
      _refreshAttempts = 0;
      _retryRounds = 0;
      _recoveries = 0;
      _engineRecreated = false;
    });
  }

  void _cancelWatchdogs() {
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _budgetTimer?.cancel();
    _cancelFrameWatchdog();
    _cancelMoveWatchdog();
  }

  // Lease prefetch.

  /// For a lease that does not cut the connection: fetch fresh credentials
  /// at `refreshAt` without touching the healthy transport, for the next
  /// reconnect to use (3.x's credential prefetch). Relayed leases that cut
  /// the connection are renewed by the relay instead.
  void _schedulePrefetch(int session, {DateTime? at}) {
    _prefetchTimer?.cancel();
    final input = _transport.active;
    final lease = input?.line?.lease;
    if (_request?.refresh == null || input == null || lease == null) return;
    final relayRenews = switch (input.route) {
      MediaRoute.flvSplice => true,
      MediaRoute.hlsRelay => lease.cutsConnection,
      _ => false,
    };
    if (relayRenews) return;
    final remaining = (at ?? lease.refreshAt).difference(clock.now());
    final delay = remaining > const Duration(seconds: 1) ? remaining : const Duration(seconds: 1);
    _prefetchTimer = Timer(delay, () => unawaited(_prefetch(session)));
  }

  Future<void> _prefetch(int session) async {
    final refresh = _request?.refresh;
    if (!_current(session) || !_wantPlaying || refresh == null) return;
    try {
      final plan = await refresh().timeout(timings.sourceRefresh);
      if (!_current(session)) return;
      _prefetched = plan;
      final next = _matching(plan, _source)?.line.lease?.refreshAt;
      final now = clock.now();
      _schedulePrefetch(session, at: next != null && next.isAfter(now) ? next : now.add(timings.refreshRetry));
    } on Object {
      if (!_current(session)) return;
      _schedulePrefetch(session, at: clock.now().add(timings.refreshRetry));
    }
  }

  /// The prefetched plan while its matching line has not expired.
  PlaybackPlan? _takePrefetched() {
    final plan = _prefetched;
    _prefetched = null;
    if (plan == null || plan.isEmpty) return null;
    final expiresAt = _matching(plan, _source)?.line.lease?.expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(clock.now())) return null;
    return plan;
  }

  /// The line of [plan] that continues [source]: same CDN code, else same
  /// URL.
  LineSource? _matching(PlaybackPlan plan, PlaybackSource? source) {
    if (source is! LineSource) return null;
    final key = lineKey(source.line);
    for (final candidate in plan.sources) {
      if (candidate is LineSource && (lineKey(candidate.line) == key || candidate.url == source.url)) return candidate;
    }
    return null;
  }

  // Recovery.

  void _handleError(PlayerException error, int session, {bool fenced = true}) {
    // While the network is gone, the dead source's failures say nothing new.
    if (!_current(session) || _offline) return;
    // The engine may repeat a failure after its recovery was queued.
    if (fenced && !_errorSignatures.add('${error.type.name}:${error.code ?? '-'}:${error.message}')) return;
    _cancelWatchdogs();
    if (_recoveringSession == session) {
      // A replacement can fail while the previous step is on the stack:
      // keep the newest failure and drain it when that step returns.
      _pendingError = error;
      return;
    }
    unawaited(_drain(error, session));
  }

  Future<void> _drain(PlayerException error, int session) async {
    _recoveringSession = session;
    try {
      PlayerException? current = error;
      while (current != null && _current(session)) {
        _pendingError = null;
        await _recover(current, session);
        current = _pendingError;
      }
    } finally {
      if (_recoveringSession == session) {
        _recoveringSession = null;
        _pendingError = null;
      }
    }
  }

  Future<void> _recover(PlayerException error, int session) async {
    if (!_current(session) || !_wantPlaying || _offline) return;
    final plan = _plan!;
    final source = _source;
    // The stream failed on its own: say so, with the attempt (the "正在重连
    // （第 N 次）" of the room; a plain buffering is no recovery). A stall
    // already showed this attempt.
    if (_stallNoticed) {
      _stallNoticed = false;
    } else {
      _recoveries++;
    }
    _emit(_state.copyWith(status: PlaybackStatus.buffering, recovery: _recoveries));
    final transport = error.type == PlayerErrorType.network || error.type == PlayerErrorType.source;

    if (transport && await _tryRefresh(session)) return;
    if (!_current(session)) return;

    if (transport && source is LineSource && plan.sources.length > 1) {
      _lines.markFailed(source.line);
      final next = _lines.next(plan.lines);
      if (next != null && next.url != source.url) {
        await _openSource(LineSource(next), session, recovering: true);
        return;
      }
    }

    if (error.code == 'video_frame_stall_timeout' && !_engineRecreated && source != null) {
      // A Windows renderer that stopped presenting while mpv still plays.
      _engineRecreated = true;
      final transport = _transport;
      _transport = PlaybackTransport();
      await transport.close();
      await _releaseEngine();
      if (!_current(session)) return;
      await _openSource(source, session, recovering: true);
      return;
    }

    if (source != null &&
        !_state.audioOnly &&
        _decoders.shouldFallback(error) &&
        !(error.code?.startsWith('audio_') ?? false)) {
      try {
        final mode = _decoders.fallback(_decoder, error);
        if (mode != _decoder) {
          _decoder = mode;
          await _openSource(source, session, recovering: true);
          return;
        }
      } on PlayerException {
        // Every decoder failed; fall through.
      }
    }
    if (!_current(session)) return;

    if (transport && !plan.onDemand && _scheduleRetryRound(session)) return;
    _publishError(error, SourceFailureKind.transient);
  }

  /// Refreshes the plan and reopens: the same line first, the next one on
  /// the second attempt. Returns whether it handled the failure.
  Future<bool> _tryRefresh(int session) async {
    final refresh = _request?.refresh;
    if (refresh == null || _refreshAttempts >= 2) return false;
    final attempt = _refreshAttempts++;
    final PlaybackPlan plan;
    try {
      plan = (attempt == 0 ? _takePrefetched() : null) ?? await refresh().timeout(timings.sourceRefresh);
    } on Object catch (error) {
      if (!_current(session)) return true;
      if (classifySourceFailure(error) == SourceFailureKind.terminal) {
        _publishError(error, SourceFailureKind.terminal);
        return true;
      }
      if (isNetworkFailure(error) && !(_plan?.onDemand ?? false)) {
        // Neither the stream nor the platform answers: the network is gone.
        // Other lines and decoders go through the same network.
        _enterOffline(error, session);
        return true;
      }
      return false;
    }
    if (!_current(session) || !_wantPlaying) return true;
    if (plan.isEmpty) return false;
    final previous = _source;
    _plan = plan;
    PlaybackSource next;
    if (attempt == 0) {
      next = _matching(plan, previous) ?? plan.sources.first;
    } else {
      if (previous is LineSource) _lines.markFailed(previous.line);
      final line = _lines.next(plan.lines);
      next = line != null ? LineSource(line) : plan.sources.first;
    }
    await _openSource(next, session, recovering: true);
    return true;
  }

  bool _scheduleRetryRound(int session) {
    if (_retryRounds >= timings.liveRetryDelays.length) return false;
    final delay = timings.liveRetryDelays[_retryRounds++];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!_current(session) || !_wantPlaying) return;
      // A new round gets fresh line, decoder and refresh budgets; the round
      // count itself only resets after sustained playback.
      _refreshAttempts = 0;
      _prefetched = null;
      _lines.reset();
      _decoders.resetAll();
      _decoder = _decoders.preferred;
      unawaited(_retryRound(session));
    });
    return true;
  }

  Future<void> _retryRound(int session) async {
    _recoveringSession = session;
    // Each round is another attempt.
    _recoveries++;
    _emit(_state.copyWith(status: PlaybackStatus.buffering, recovery: _recoveries));
    try {
      if (await _tryRefresh(session)) return;
      final source = _source;
      if (source != null && _current(session)) await _openSource(source, session, recovering: true);
    } finally {
      if (_recoveringSession == session) _recoveringSession = null;
    }
    final pending = _pendingError;
    _pendingError = null;
    if (pending != null) _handleError(pending, session, fenced: false);
  }

  void _publishError(Object error, SourceFailureKind kind) {
    _cancelWatchdogs();
    _retryTimer?.cancel();
    _prefetchTimer?.cancel();
    _wantPlaying = false;
    _emit(_state.copyWith(status: PlaybackStatus.error, error: error, failure: kind, recovery: 0));
  }

  // The network is gone (G02.3).

  /// [error] said nothing answers: keep the attempt on screen and look at
  /// the network until it answers.
  void _enterOffline(Object error, int session) {
    _offline = true;
    _offlineSince = clock.now();
    _offlineError = error;
    _cancelWatchdogs();
    _retryTimer?.cancel();
    _scheduleProbe(session);
  }

  void _leaveOffline() {
    _offline = false;
    _offlineSince = null;
    _offlineError = null;
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  void _scheduleProbe(int session) {
    _probeTimer?.cancel();
    _probeTimer = Timer(timings.networkProbe, () {
      _probeTimer = null;
      unawaited(_probe(session));
    });
  }

  /// One look at the network: the plan refresh, which asks the platform.
  /// Nothing answering again is another attempt (after
  /// [SessionTimings.offlineGrace], the published [networkLostCode]); an
  /// answer reopens the stream as the next attempt.
  Future<void> _probe(int session) async {
    final refresh = _request?.refresh;
    if (!_current(session) || !_offline || refresh == null) return;
    final published = _state.status == PlaybackStatus.error;
    if (!published) {
      _recoveries++;
      _emit(_state.copyWith(status: PlaybackStatus.buffering, recovery: _recoveries));
    }
    PlaybackPlan? plan;
    try {
      plan = await refresh().timeout(timings.networkProbeTimeout);
    } on Object catch (error) {
      if (!_current(session) || !_offline) return;
      if (classifySourceFailure(error) == SourceFailureKind.terminal) {
        _leaveOffline();
        _publishError(error, SourceFailureKind.terminal);
        return;
      }
      if (isNetworkFailure(error)) {
        _offlineError = error;
        final since = _offlineSince ?? clock.now();
        if (!published && clock.now().difference(since) >= timings.offlineGrace) _publishOffline();
        _scheduleProbe(session);
        return;
      }
      // Something answered (a refusal for now): the network is back, the
      // plan at hand is played.
    }
    if (!_current(session) || !_offline) return;
    _leaveOffline();
    if (plan != null && !plan.isEmpty) _plan = plan;
    final current = _plan!;
    // Back online: the next attempt, with fresh budgets.
    _refreshAttempts = 0;
    _retryRounds = 0;
    _prefetched = null;
    _lines.reset();
    _decoders.resetAll();
    _decoder = _decoders.preferred;
    _engineRecreated = false;
    _wantPlaying = true;
    if (published) _recoveries++;
    final previous = _source;
    final next =
        _matching(current, previous) ??
        (previous != null && current.sources.contains(previous) ? previous : current.sources.first);
    await _openSource(next, session, recovering: true);
  }

  /// Publishes that the network is gone; [_probe] keeps looking and plays
  /// again once it answers.
  void _publishOffline() {
    _cancelWatchdogs();
    _retryTimer?.cancel();
    _prefetchTimer?.cancel();
    _wantPlaying = false;
    _emit(
      _state.copyWith(
        status: PlaybackStatus.error,
        error: PlayerException(
          message: 'The network is gone',
          type: PlayerErrorType.network,
          code: networkLostCode,
          error: _offlineError,
        ),
        failure: SourceFailureKind.transient,
        recovery: 0,
      ),
    );
  }
}
