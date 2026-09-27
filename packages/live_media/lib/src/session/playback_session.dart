import 'dart:async';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/src/engine/diagnostics.dart';
import 'package:live_media/src/engine/engine.dart';
import 'package:live_media/src/relay/source_pipeline.dart';
import 'package:live_media/src/session/geometry.dart';
import 'package:live_media/src/session/playback_state.dart';
import 'package:live_media/src/session/recovery.dart';

/// A diagnostic waiting to be processed.
typedef _Staged = ({String message, String? prefix});

/// One player's playback: session lifecycle, play intent and suspension,
/// source pipeline and leases, health monitoring and recovery
/// (spec/modules/playback.md §1–§3, §5–§8).
///
/// Drive it with user commands ([open], [play], [pause], [selectQuality],
/// [selectLine], [retry], [setAudioOnly], [close]) and lifecycle signals
/// ([suspend], [resume], [setVisible]); render [states]. Native commands run
/// one at a time in arrival order, while intent changes take effect when the
/// command is issued (SES-2): every user command bumps the intent revision,
/// and queued or in-flight work that sees a newer revision gives up.
///
/// The engine is created on the first [open] (SES-1), kept for
/// [PlaybackTimings.idleRelease] after [close] (SES-7) and released by
/// [close] with `release: true` or [dispose] (SES-8).
final class PlaybackSession {
  /// Creates a session. [engine] creates the engine on first use; [pipeline]
  /// turns lines into engine inputs (a default one starts its own relay).
  new({required EngineFactory engine, SourcePipeline? pipeline, this.timings = const PlaybackTimings()})
    : _engineFactory = engine,
      _pipeline = pipeline ?? SourcePipeline(),
      _ownsPipeline = pipeline == null {
    _geometry = GeometryTracker((geometry) {
      _geometryValue = geometry;
      _publish();
    });
  }

  /// Watchdog and retry limits.
  final PlaybackTimings timings;

  final EngineFactory _engineFactory;
  final SourcePipeline _pipeline;
  final bool _ownsPipeline;
  late final GeometryTracker _geometry;
  final _states = StreamController<PlaybackState>.broadcast();
  var _state = const PlaybackState();

  // Serial native commands (SES-2).
  Future<void> _tail = Future.value();

  // Engine.
  PlayerEngine? _engine;
  StreamSubscription<EngineEvent>? _engineEvents;
  var _engineRevision = 0;
  Timer? _idleTimer;

  // Session and intent (§0, INT-1, INT-2).
  var _session = 0;
  var _intent = 0;
  var _wantsPlay = false;
  final _suspensions = <SuspendReason>{};
  var _closed = true;
  var _disposed = false;

  // Request and source.
  PlaybackRequest? _request;
  StreamSet? _set;
  Quality? _quality;
  StreamLine? _line;
  var _resolving = false;
  var _generation = 0;
  var _opening = false;
  var _sourceOpened = false;
  var _playedThisGeneration = false;
  PlaybackInput? _input;
  Uri? _softwareFor;
  SourceCommit? _commit;
  var _volume = 1.0;

  // Engine mirror for the current generation (EVT-10).
  var _enginePlaying = false;
  var _engineBuffering = false;
  var _engineCompleted = false;
  int? _width;
  int? _height;
  var _hasPicture = false;
  var _hasTracks = false;
  var _progress = 0;
  VideoGeometry _geometryValue = VideoGeometry.unknown;

  // Diagnostics (EVT-5 to EVT-7).
  final _staged = <_Staged>[];
  String? _lastDiagnostic;
  DateTime? _lastDiagnosticAt;
  Timer? _observeTimer;

  // Monitoring (§5).
  var _visible = true;
  Timer? _bufferingTimer;
  Timer? _pauseTimer;
  var _pauseAttempt = 0;
  Timer? _frameTimer;
  DateTime? _lastFrameAt;
  Timer? _healthyTimer;

  // Recovery (§6).
  final _ledger = RecoveryLedger();
  final _failedLines = <String>{};
  final _handled = <String>{};
  var _recovering = false;
  PlaybackFailure? _queued;
  PlaybackFailure? _failure;
  var _ended = false;
  Timer? _backoffTimer;
  Completer<bool>? _backoffWait;

  // Leases (SRC-6).
  Timer? _prefetchTimer;
  StreamLine? _prefetched;

  // Audio mode (§7).
  var _audioOnly = false;
  var _audioRequested = false;
  Future<void>? _audioSwitch;
  String? _notice;

  /// The latest state.
  PlaybackState get state => _state;

  /// State changes; each distinct state once.
  Stream<PlaybackState> get states => _states.stream;

  /// The engine, once created; rebind views when [PlaybackState.engineRevision] changes.
  PlayerEngine? get engine => _engine;

  /// Recovery counts, for diagnostics and tests.
  RecoveryLedger get ledger => _ledger;

  // ---------------------------------------------------------------------------
  // User commands

  /// Opens a room (SES-3). Another room clears the recovery history, failed
  /// lines and commit (REC-7).
  Future<void> open(PlaybackRequest request) {
    _checkNotDisposed();
    _bumpIntent(wantsPlay: true);
    _suspensions.clear();
    if (request.roomKey != _request?.roomKey) {
      _ledger.clear();
      _failedLines.clear();
      _prefetched = null;
      _softwareFor = null;
      _commit = null;
      _audioOnly = false;
      _audioRequested = false;
    }
    _session++;
    _closed = false;
    _idleTimer?.cancel();
    _cancelSourceWork();
    _generation++;
    _request = request;
    _set = request.initial;
    _quality = request.quality ?? request.initial?.selected;
    _line = null;
    _sourceOpened = false;
    _failure = null;
    _ended = false;
    _handled.clear();
    _resolving = request.initial == null;
    _publish();
    final session = _session;
    final intent = _intent;
    return _enqueue(() async {
      if (!_isCurrent(session, intent)) return;
      var set = _set;
      if (set == null) {
        set = await _resolve(request.quality);
        if (!_isCurrent(session, intent)) return;
        _resolving = false;
        if (set == null) return;
        _set = set;
        _quality = set.selected;
      }
      final line = _pickLine(set, request.lineId);
      if (line == null) {
        _handleFailure(const PlaybackFailure(FailureKind.unavailable, 'no_lines'));
        return;
      }
      await _openLine(line);
    });
  }

  /// Resumes (SES-5). A source that had not finished opening is reopened
  /// (REG-PLAY-033); after a terminal error this is a [retry].
  Future<void> play() {
    _checkNotDisposed();
    if (_closed) return Future.value();
    if (_failure != null) return retry();
    _bumpIntent(wantsPlay: true);
    _suspensions.clear();
    _publish();
    final intent = _intent;
    return _enqueue(() async {
      if (intent != _intent) return;
      final line = _line;
      if (!_sourceOpened) {
        if (line != null && !_opening) await _openLine(line);
        return;
      }
      await _engine?.play();
      _armMonitoring();
      _scheduleLease();
    });
  }

  /// Pauses (SES-5): the intent is withdrawn before the engine is paused, so
  /// only this shows as "paused" (INT-1).
  Future<void> pause() {
    _checkNotDisposed();
    if (_closed) return Future.value();
    _bumpIntent(wantsPlay: false);
    _suspensions.clear();
    _cancelMonitoring();
    _prefetchTimer?.cancel();
    _publish();
    final intent = _intent;
    return _enqueue(() async {
      if (intent != _intent) return;
      await _engine?.pause();
    });
  }

  /// Retries after an error (REC-6): clears every count and the round
  /// window, resolves fresh URLs for the current quality and line, and opens.
  Future<void> retry() {
    _checkNotDisposed();
    final request = _request;
    if (_closed || request == null) return Future.value();
    _bumpIntent(wantsPlay: true);
    _suspensions.clear();
    _ledger.clear();
    _failedLines.clear();
    _handled.clear();
    _failure = null;
    _ended = false;
    _publish();
    final intent = _intent;
    return _enqueue(() async {
      if (intent != _intent) return;
      final set = await _resolve(_quality);
      if (intent != _intent) return;
      if (set != null) _set = set;
      final line = set == null ? _line : _pickLine(set, _line?.lineId ?? request.lineId);
      if (line == null) {
        if (set == null) return;
        _handleFailure(const PlaybackFailure(FailureKind.unavailable, 'no_lines'));
        return;
      }
      await _openLine(line);
    });
  }

  /// Switches quality; keeps the current line when the new set has it (REC-3).
  Future<void> selectQuality(Quality quality) {
    _checkNotDisposed();
    if (_closed) return Future.value();
    _bumpIntent(wantsPlay: true);
    _failedLines.clear();
    _failure = null;
    _quality = quality;
    _publish();
    final intent = _intent;
    return _enqueue(() async {
      if (intent != _intent) return;
      final set = await _resolve(quality);
      if (intent != _intent || set == null) return;
      _set = set;
      _quality = set.selected;
      final line = _pickLine(set, _line?.lineId);
      if (line != null) await _openLine(line);
    });
  }

  /// Switches to another line at the current quality.
  Future<void> selectLine(String lineId) {
    _checkNotDisposed();
    final line = _set?.lines.where((line) => line.lineId == lineId).firstOrNull;
    if (_closed || line == null) return Future.value();
    _bumpIntent(wantsPlay: true);
    _failure = null;
    _failedLines.remove(lineId);
    _publish();
    final intent = _intent;
    return _enqueue(() async {
      if (intent == _intent) await _openLine(line);
    });
  }

  /// Sets the volume, 0 to 1 (SES-10).
  Future<void> setVolume(double volume) {
    _volume = volume.clamp(0, 1).toDouble();
    return _enqueue(() async {
      await _engine?.setVolume(_volume);
    });
  }

  /// Turns video off or on in place (§7). Quick toggles run only the last
  /// request; a switch that does not finish in time rolls back and sets
  /// [PlaybackState.notice] without entering recovery (AUD-4). Entering shows
  /// the audio presentation first; leaving keeps it until the engine reports
  /// a picture again (AUD-2).
  Future<void> setAudioOnly({required bool enabled}) {
    _checkNotDisposed();
    _audioRequested = enabled;
    return _audioSwitch ??= _runAudioSwitch().whenComplete(() => _audioSwitch = null);
  }

  Future<void> _runAudioSwitch() async {
    while (_audioOnly != _audioRequested) {
      final target = _audioRequested;
      final previous = _audioOnly;
      final engine = _engine;
      if (engine == null || !_sourceOpened) {
        _audioOnly = target;
        _publish();
        return;
      }
      if (target) {
        _audioOnly = true;
        _cancelFrameWatchdog();
        _publish();
      }
      try {
        await _enqueue(() => engine.setAudioOnly(enabled: target)).timeout(timings.audioSwitchTimeout);
        _audioOnly = target;
        if (_commit case final commit?) _commit = _commitFor(commit.line);
      } on Object {
        _audioOnly = previous;
        _audioRequested = previous;
        _notice = target ? 'audio_only_failed' : 'video_restore_failed';
        // Queued behind the stuck command, never concurrent with it (AUD-4).
        unawaited(_enqueue(() => engine.setAudioOnly(enabled: previous)).catchError((Object _) {}));
      }
      _armFrameWatchdog();
      _publish();
    }
  }

  /// Clears [PlaybackState.notice] after the UI showed it.
  void clearNotice() {
    _notice = null;
    _publish();
  }

  /// Leaves the room (SES-6): intent, session and commit end now; the engine
  /// then soft-stops and is released after [PlaybackTimings.idleRelease]
  /// (SES-7), or at once with [release] or after an error.
  Future<void> close({bool release = false}) {
    if (_disposed) return Future.value();
    _bumpIntent(wantsPlay: false);
    _session++;
    _closed = true;
    _commit = null;
    _suspensions.clear();
    _cancelSourceWork();
    _generation++;
    final hardRelease = release || _failure != null;
    _request = null;
    _set = null;
    _line = null;
    _failure = null;
    _resolving = false;
    _sourceOpened = false;
    _publish();
    return _enqueue(() async {
      final input = _input;
      _input = null;
      await input?.close();
      final engine = _engine;
      if (engine == null) return;
      if (hardRelease) {
        await _releaseEngine();
        return;
      }
      try {
        await engine.stop();
      } on Object {
        await _releaseEngine();
        return;
      }
      _idleTimer?.cancel();
      _idleTimer = Timer(timings.idleRelease, () {
        if (_closed) unawaited(_enqueue(_releaseEngine));
      });
    });
  }

  /// Releases everything; the session cannot be used afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    await close(release: true);
    _disposed = true;
    _idleTimer?.cancel();
    _geometry.dispose();
    if (_ownsPipeline) await _pipeline.close();
    unawaited(_states.close());
  }

  // ---------------------------------------------------------------------------
  // Lifecycle signals

  /// Pauses for a non-user reason (INT-2) without changing the intent.
  SuspendToken suspend(SuspendReason reason) {
    final token = SuspendToken(_session, _intent, reason);
    if (_closed || !_wantsPlay) return token;
    _suspensions.add(reason);
    _cancelMonitoring();
    _publish();
    final session = _session;
    unawaited(
      _enqueue(() async {
        if (session == _session && _suspensions.isNotEmpty) await _engine?.pause();
      }),
    );
    return token;
  }

  /// Ends the suspension of [token]. Returns false when the token is stale:
  /// another session, a newer user command, no play intent, or not suspended
  /// for that reason. Playback resumes only when no other reason remains.
  bool resume(SuspendToken token) {
    if (token.session != _session ||
        token.intentRevision != _intent ||
        !_wantsPlay ||
        !_suspensions.contains(token.reason)) {
      return false;
    }
    _suspensions.remove(token.reason);
    if (_suspensions.isNotEmpty) return true;
    _publish();
    final intent = _intent;
    unawaited(
      _enqueue(() async {
        if (intent != _intent || _suspensions.isNotEmpty) return;
        final line = _line;
        if (!_sourceOpened) {
          if (line != null && !_opening) await _openLine(line);
          return;
        }
        await _engine?.play();
        _armMonitoring();
      }),
    );
    return true;
  }

  /// Whether the picture is on screen; the frame watchdog only runs while it
  /// is (MON-3, MON-4).
  void setVisible({required bool visible}) {
    if (_visible == visible) return;
    _visible = visible;
    if (visible) {
      _lastFrameAt = null;
      _armFrameWatchdog();
    } else {
      _cancelFrameWatchdog();
    }
  }

  // ---------------------------------------------------------------------------
  // Serial execution and staleness

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  void _bumpIntent({required bool wantsPlay}) {
    _intent++;
    _wantsPlay = wantsPlay;
    _cancelBackoff();
  }

  bool _isCurrent(int session, int intent) => session == _session && intent == _intent && !_closed;

  void _checkNotDisposed() {
    if (_disposed) throw StateError('PlaybackSession is disposed');
  }

  // ---------------------------------------------------------------------------
  // Sources

  StreamLine? _pickLine(StreamSet set, String? lineId) {
    if (set.lines.isEmpty) return null;
    if (lineId != null) {
      final match = set.lines.where((line) => line.lineId == lineId).firstOrNull;
      if (match != null) return match;
    }
    return set.lines.where((line) => !_failedLines.contains(line.lineId)).firstOrNull ?? set.lines.first;
  }

  /// Resolves a stream set; a failure goes to recovery and returns null.
  Future<StreamSet?> _resolve(Quality? quality) async {
    final request = _request;
    if (request == null) return null;
    try {
      return await request.resolve(quality).timeout(timings.refreshTimeout);
    } on Object catch (error) {
      _resolving = false;
      _handleFailure(_resolveFailure(error));
      return null;
    }
  }

  static PlaybackFailure _resolveFailure(Object error) => switch (error) {
    TimeoutException() => const PlaybackFailure(FailureKind.network, 'source_refresh_timeout'),
    SiteError(isTransient: true) => PlaybackFailure(FailureKind.network, 'resolve_failed', '$error'),
    SiteError(:final kind) => PlaybackFailure(FailureKind.unavailable, kind, '$error'),
    _ => PlaybackFailure(FailureKind.source, 'resolve_failed', '$error'),
  };

  /// Starts a new source generation on [line] (SES-3, SRC-1, EVT-10). Runs
  /// on the serial queue.
  Future<void> _openLine(StreamLine line) async {
    final request = _request;
    if (request == null || _closed) return;
    final generation = ++_generation;
    final session = _session;
    _resetGeneration();
    _line = line;
    _opening = true;
    _sourceOpened = false;
    _resolving = false;
    _publish();

    final PlayerEngine engine;
    try {
      engine = await _ensureEngine();
    } on Object catch (error) {
      if (generation != _generation) return;
      _opening = false;
      _handleFailure(PlaybackFailure(FailureKind.engine, 'engine_init', '$error'));
      return;
    }
    if (generation != _generation) return;

    final PlaybackInput input;
    try {
      input = await _pipeline.open(
        line,
        site: request.site,
        renew: _renewLine,
        onRenewed: (renewed) => _onRelayRenewed(generation, renewed),
      );
    } on Object catch (error) {
      if (generation != _generation) return;
      _opening = false;
      _handleFailure(PlaybackFailure(FailureKind.source, 'input_failed', '$error'));
      return;
    }
    if (generation != _generation) {
      await input.close();
      return;
    }

    try {
      await engine
          .open(
            EngineMedia(
              uri: input.uri,
              headers: input.headers,
              local: input.local,
              softwareDecoding: _softwareFor == line.url,
              audioOnly: _audioOnly,
            ),
          )
          .timeout(timings.openTimeout);
    } on Object catch (error) {
      if (generation != _generation) {
        await input.close();
        return;
      }
      _opening = false;
      await input.close();
      _handleFailure(
        error is TimeoutException
            ? const PlaybackFailure(FailureKind.network, 'open_timeout')
            : PlaybackFailure(FailureKind.source, 'open_failed', '$error'),
      );
      return;
    }
    if (generation != _generation || session != _session) {
      await input.close();
      // Closed while opening: nothing may play (SES-2).
      if (_closed || !_wantsPlay) await engine.stop();
      return;
    }
    _opening = false;
    if (!_wantsPlay) {
      // Paused while opening: forget the half-opened source; play reopens it (SES-5).
      await input.close();
      await engine.stop();
      _publish();
      return;
    }
    final previous = _input;
    _input = input;
    if (previous != null) await previous.close();
    _sourceOpened = true;
    _commit = _commitFor(line);
    if (_suspensions.isNotEmpty) await engine.pause();
    _processStaged();
    _armMonitoring();
    _scheduleLease();
    _publish();
  }

  SourceCommit _commitFor(StreamLine line) => SourceCommit(
    session: _session,
    intentRevision: _intent,
    roomKey: _request?.roomKey ?? '',
    quality: _quality ?? line.requested,
    line: line,
    audioOnly: _audioOnly,
  );

  Future<PlayerEngine> _ensureEngine() async {
    _idleTimer?.cancel();
    final existing = _engine;
    if (existing != null) return existing;
    final engine = await _engineFactory();
    if (_disposed) {
      await engine.dispose();
      throw StateError('PlaybackSession is disposed');
    }
    _engine = engine;
    _engineRevision++;
    _engineEvents = engine.events.listen((event) => _onEvent(engine, event));
    await engine.setVolume(_volume);
    _publish();
    return engine;
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    if (engine == null) return;
    _engine = null;
    _engineRevision++;
    _idleTimer?.cancel();
    // Not awaited: a broadcast cancel completes in the root zone, and nothing
    // depends on it; events of a released engine are ignored anyway.
    unawaited(_engineEvents?.cancel());
    _engineEvents = null;
    _audioOnly = false;
    _audioRequested = false;
    _ledger.clear();
    _publish();
    await engine.dispose();
  }

  void _resetGeneration() {
    _cancelMonitoring();
    _observeTimer?.cancel();
    _observeTimer = null;
    _prefetchTimer?.cancel();
    _staged.clear();
    _lastDiagnostic = null;
    _lastDiagnosticAt = null;
    _enginePlaying = false;
    _engineBuffering = false;
    _engineCompleted = false;
    _width = null;
    _height = null;
    _hasPicture = false;
    _hasTracks = false;
    _playedThisGeneration = false;
    _lastFrameAt = null;
    _geometry.reset();
  }

  void _cancelSourceWork() {
    _cancelMonitoring();
    _observeTimer?.cancel();
    _prefetchTimer?.cancel();
    _cancelBackoff();
    _opening = false;
  }

  // ---------------------------------------------------------------------------
  // Leases (SRC-5, SRC-6)

  Future<StreamLine> _renewLine(StreamLine current) async {
    final request = _request;
    if (request == null) throw StateError('No open room');
    final set = await request.resolve(_quality ?? current.requested);
    _set = set;
    return set.lines.where((line) => line.lineId == current.lineId).firstOrNull ?? set.lines.first;
  }

  void _onRelayRenewed(int generation, StreamLine line) {
    if (generation != _generation) return;
    _line = line;
    if (_commit != null) _commit = _commitFor(line);
    _publish();
  }

  void _scheduleLease() {
    _prefetchTimer?.cancel();
    final line = _line;
    final lease = line?.lease;
    if (line == null || lease == null || (_input?.renewsLease ?? false) || !_wantsPlay) return;
    _schedulePrefetch(lease.refreshAt, _generation);
  }

  void _schedulePrefetch(DateTime at, int generation) {
    var delay = at.difference(clock.now());
    if (delay < timings.minimumLeaseDelay) delay = timings.minimumLeaseDelay;
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(delay, () => unawaited(_prefetch(generation)));
  }

  /// Prefetches fresh credentials without touching the connection (SRC-6);
  /// network work, so it stays off the serial queue (REG-PLAY-024).
  Future<void> _prefetch(int generation) async {
    final request = _request;
    final current = _line;
    if (generation != _generation || request == null || current == null || !_wantsPlay) return;
    try {
      final set = await request.resolve(_quality).timeout(timings.refreshTimeout);
      if (generation != _generation) return;
      final line = set.lines.where((line) => line.lineId == current.lineId).firstOrNull;
      if (line == null) throw StateError('line ${current.lineId} missing from the renewed set');
      _prefetched = line;
      final next = line.lease?.refreshAt;
      if (next != null) _schedulePrefetch(next, generation);
    } on Object {
      if (generation != _generation) return;
      _prefetchTimer?.cancel();
      _prefetchTimer = Timer(timings.prefetchRetry, () => unawaited(_prefetch(generation)));
    }
  }

  StreamLine? _takePrefetched(String lineId) {
    final line = _prefetched;
    if (line == null || line.lineId != lineId) return null;
    final lease = line.lease;
    final limit = lease?.expiresAt ?? lease?.refreshAt;
    if (limit != null && !limit.isAfter(clock.now())) {
      _prefetched = null;
      return null;
    }
    _prefetched = null;
    return line;
  }

  // ---------------------------------------------------------------------------
  // Engine events (§4)

  bool get _monitoring =>
      _wantsPlay && _suspensions.isEmpty && _sourceOpened && !_opening && !_recovering && _failure == null && !_closed;

  bool get _live => _request?.continuousLive ?? true;

  void _onEvent(PlayerEngine engine, EngineEvent event) {
    if (!identical(engine, _engine) || _disposed) return;
    switch (event) {
      case EnginePlaying(:final playing):
        _enginePlaying = playing;
        if (playing) {
          _cancelPauseCheck();
          _noteProgress();
        } else if (_monitoring) {
          if (_engineBuffering) {
            _armBufferingWatchdog();
          } else if (!_engineCompleted) {
            _schedulePauseCheck();
          }
        }
      case EngineBuffering(:final buffering):
        _engineBuffering = buffering;
        if (buffering) {
          _cancelPauseCheck();
          if (_monitoring) _armBufferingWatchdog();
        } else {
          _cancelBufferingWatchdog();
          _noteProgress();
          if (_monitoring && !_enginePlaying && !_engineCompleted) _schedulePauseCheck();
        }
      case EngineCompleted(:final completed):
        _engineCompleted = completed;
        if (completed) {
          _cancelPauseCheck();
          if (_monitoring) {
            if (_live) {
              _handleFailure(const PlaybackFailure(FailureKind.liveCompleted, 'live_source_completed'));
            } else {
              _ended = true;
            }
          }
        }
      case EngineVideoSize(:final width, :final height):
        _width = width;
        _height = height;
        _geometry.add(width, height);
        if (event.hasPicture) {
          _hasPicture = true;
          _noteProgress();
        }
      case EngineFrame():
        _lastFrameAt = clock.now();
        _noteProgress();
      case EngineError(:final message, :final prefix):
        _onDiagnostic(message, prefix);
      case EngineTracks(:final video, :final audio):
        _hasTracks = video + audio > 0;
      case EnginePosition() || EngineDuration():
        return;
    }
    // playing=true arrives before buffering=true right after open (EVT-13);
    // only parsed media makes it real playback.
    if (_enginePlaying && !_engineBuffering && _sourceOpened && (_hasTracks || _hasPicture)) {
      _playedThisGeneration = true;
    }
    _armFrameWatchdog();
    _updateHealthy();
    _publish();
  }

  void _noteProgress() {
    _progress++;
  }

  // ---------------------------------------------------------------------------
  // Diagnostics (EVT-5 to EVT-7, EVT-12)

  void _onDiagnostic(String message, String? prefix) {
    if (_opening) {
      _staged.add((message: message, prefix: prefix));
      return;
    }
    if (!_sourceOpened || _closed) return;
    _processDiagnostic(message, prefix);
  }

  void _processStaged() {
    final staged = List.of(_staged);
    _staged.clear();
    for (final diagnostic in staged) {
      final component = classifyDiagnostic(diagnostic.message, prefix: diagnostic.prefix).component;
      if (_componentReady(component)) continue;
      _processDiagnostic(diagnostic.message, diagnostic.prefix);
    }
  }

  bool _componentReady(DiagnosticComponent component) => switch (component) {
    DiagnosticComponent.video => _hasPicture,
    DiagnosticComponent.audio => _playedThisGeneration,
    DiagnosticComponent.either => _hasPicture || _playedThisGeneration,
  };

  void _processDiagnostic(String message, String? prefix) {
    final now = clock.now();
    final lastAt = _lastDiagnosticAt;
    if (_lastDiagnostic == message && lastAt != null && now.difference(lastAt) < timings.diagnosticDedupe) return;
    _lastDiagnostic = message;
    _lastDiagnosticAt = now;
    final diagnosis = classifyDiagnostic(message, prefix: prefix);
    final failure = _failureFor(diagnosis, message);
    if (diagnosis.kind.terminal) {
      _handleFailure(failure);
      return;
    }
    if (_observeTimer != null) return;
    final progress = _progress;
    final generation = _generation;
    _observeTimer = Timer(timings.diagnosticObservation, () {
      _observeTimer = null;
      if (generation != _generation) return;
      final recovered = _progress > progress && _enginePlaying && !_engineBuffering;
      if (recovered || (_enginePlaying && !_engineBuffering && _componentReady(diagnosis.component))) return;
      _handleFailure(failure);
    });
  }

  static PlaybackFailure _failureFor(Diagnosis diagnosis, String message) {
    final kind = switch (diagnosis.kind) {
      DiagnosticKind.lifecycle || DiagnosticKind.videoOutput => FailureKind.engine,
      DiagnosticKind.transport => FailureKind.network,
      DiagnosticKind.decoderInit || DiagnosticKind.decoderRuntime =>
        diagnosis.component == DiagnosticComponent.audio ? FailureKind.audioDecode : FailureKind.videoDecode,
      DiagnosticKind.sourceOpen || DiagnosticKind.sourceRuntime || DiagnosticKind.other => FailureKind.source,
    };
    return PlaybackFailure(kind, diagnosis.code, message);
  }

  // ---------------------------------------------------------------------------
  // Monitoring (§5)

  void _armMonitoring() {
    if (!_monitoring) return;
    if (_engineBuffering) {
      _armBufferingWatchdog();
    } else if (!_enginePlaying && !_engineCompleted) {
      _schedulePauseCheck();
    }
    _armFrameWatchdog();
    _updateHealthy();
  }

  void _cancelMonitoring() {
    _cancelBufferingWatchdog();
    _cancelPauseCheck();
    _cancelFrameWatchdog();
    _healthyTimer?.cancel();
    _healthyTimer = null;
  }

  /// One deadline per buffering episode; playing/paused notifications do not
  /// extend it (EVT-3, REG-PLAY-003).
  void _armBufferingWatchdog() {
    if (_bufferingTimer != null || !_monitoring) return;
    final generation = _generation;
    _bufferingTimer = Timer(timings.bufferingStall, () {
      _bufferingTimer = null;
      if (generation != _generation || !_engineBuffering || !_monitoring) return;
      _handleFailure(const PlaybackFailure(FailureKind.bufferingStall, 'buffering_stall_timeout'));
    });
  }

  void _cancelBufferingWatchdog() {
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
  }

  bool get _unexpectedlyPaused => _monitoring && !_enginePlaying && !_engineBuffering && !_engineCompleted;

  /// playing=false without buffering: wait 350 ms, call play() with a 5 s
  /// limit, then wait 5 s more before escalating (§5). Live streams only.
  void _schedulePauseCheck() {
    if (_pauseTimer != null || !_live) return;
    final generation = _generation;
    final attempt = ++_pauseAttempt;
    _pauseTimer = Timer(timings.pauseGrace, () async {
      if (!_pauseCurrent(generation, attempt)) return;
      final engine = _engine;
      if (engine == null) return;
      final intent = _intent;
      try {
        await _enqueue(() async {
          if (intent == _intent) await engine.play();
        }).timeout(timings.pauseResumeTimeout);
      } on Object {
        if (!_pauseCurrent(generation, attempt)) return;
        _pauseTimer = null;
        _handleFailure(const PlaybackFailure(FailureKind.unexpectedPause, 'unexpected_pause_resume_failed'));
        return;
      }
      if (!_pauseCurrent(generation, attempt)) return;
      _pauseTimer = Timer(timings.pauseConfirm, () {
        if (!_pauseCurrent(generation, attempt)) return;
        _pauseTimer = null;
        _handleFailure(const PlaybackFailure(FailureKind.unexpectedPause, 'unexpected_pause_timeout'));
      });
    });
  }

  bool _pauseCurrent(int generation, int attempt) =>
      generation == _generation && attempt == _pauseAttempt && _pauseTimer != null && _unexpectedlyPaused;

  void _cancelPauseCheck() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _pauseAttempt++;
  }

  bool get _frameWatchable =>
      _monitoring &&
      (_engine?.capabilities.frameProgress ?? false) &&
      _visible &&
      !_audioOnly &&
      _enginePlaying &&
      !_engineBuffering &&
      _hasPicture;

  /// The deadline moves with each frame; the timer is not rebuilt per frame (EVT-11).
  void _armFrameWatchdog() {
    if (!_frameWatchable) {
      _cancelFrameWatchdog();
      return;
    }
    _lastFrameAt ??= clock.now();
    if (_frameTimer == null) _scheduleFrameCheck();
  }

  void _scheduleFrameCheck() {
    final last = _lastFrameAt ?? clock.now();
    var wait = last.add(timings.frameStall).difference(clock.now());
    if (wait < Duration.zero) wait = Duration.zero;
    final generation = _generation;
    _frameTimer = Timer(wait, () {
      _frameTimer = null;
      if (generation != _generation || !_frameWatchable) return;
      final since = clock.now().difference(_lastFrameAt ?? clock.now());
      if (since < timings.frameStall) {
        _scheduleFrameCheck();
        return;
      }
      _handleFailure(const PlaybackFailure(FailureKind.frameStall, 'video_frame_stall_timeout'));
    });
  }

  void _cancelFrameWatchdog() {
    _frameTimer?.cancel();
    _frameTimer = null;
    _lastFrameAt = null;
  }

  /// Healthy continuous play ends the recovery round (REC-2).
  void _updateHealthy() {
    final healthy =
        _monitoring && _enginePlaying && !_engineBuffering && !_recovering && _observeTimer == null && _ledger.inRound;
    if (!healthy) {
      _healthyTimer?.cancel();
      _healthyTimer = null;
      return;
    }
    if (_healthyTimer != null) return;
    final generation = _generation;
    _healthyTimer = Timer(timings.healthyPlay, () {
      _healthyTimer = null;
      if (generation != _generation) return;
      _ledger.endRound();
      _failedLines.clear();
      _handled.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // Recovery (§6)

  /// Entry for every failure: confirmed ones act at once, one recovery runs
  /// at a time and the latest failure waits behind it (MON-2).
  void _handleFailure(PlaybackFailure failure) {
    if (!_wantsPlay || _closed || _failure != null) return;
    if (_recovering) {
      _queued = failure;
      return;
    }
    final key = '$_generation/${failure.kind.name}/${failure.code}';
    if (!_handled.add(key)) return;
    _cancelMonitoring();
    unawaited(_recover(failure));
  }

  bool _stillNeeded(PlaybackFailure failure, int session, int intent) {
    if (!_isCurrent(session, intent) || !_wantsPlay || _suspensions.isNotEmpty || _failure != null) return false;
    // MON-1: an inferred failure is overturned by progress.
    return switch (failure.kind) {
      FailureKind.bufferingStall => !_sourceOpened || _engineBuffering,
      FailureKind.unexpectedPause => !_sourceOpened || !_enginePlaying,
      _ => true,
    };
  }

  Future<void> _recover(PlaybackFailure failure) async {
    _recovering = true;
    _publish();
    final session = _session;
    final intent = _intent;
    try {
      if (!_ledger.inRound &&
          !_ledger.startRound(clock.now(), window: timings.roundWindow, maxRounds: timings.maxRoundsPerWindow)) {
        _giveUp(
          PlaybackFailure(FailureKind.exhausted, 'recovery_exhausted', '${failure.code}: ${failure.message ?? ''}'),
        );
        return;
      }
      await _runChain(failure, session, intent);
    } finally {
      _recovering = false;
      final queued = _queued;
      _queued = null;
      _publish();
      if (queued != null && _isCurrent(session, _intent)) _handleFailure(queued);
      _armMonitoring();
    }
  }

  Future<void> _runChain(PlaybackFailure failure, int session, int intent) async {
    while (true) {
      if (!_stillNeeded(failure, session, intent)) {
        _handled.remove('$_generation/${failure.kind.name}/${failure.code}');
        _armMonitoring();
        return;
      }
      final current = _line;
      final step = nextRecoveryStep(
        failure,
        _ledger,
        canRefresh: _request != null,
        hasSpareLine: _spareLine() != null,
        softwareTried: current != null && _ledger.softwareTried.contains(current.url),
        continuousLive: _live,
        backoff: timings.backoff,
      );
      switch (step) {
        case RefreshStep(:final nextLine, :final usePrefetch):
          if (await _refresh(session, intent, nextLine: nextLine, usePrefetch: usePrefetch)) return;
        case SwitchLineStep():
          final spare = _spareLine()!;
          if (current != null) _failedLines.add(current.lineId);
          await _enqueue(() => _openIfCurrent(session, intent, spare));
          return;
        case RebuildStep():
          _ledger.rebuilds++;
          if (current == null) continue;
          await _enqueue(() => _openIfCurrent(session, intent, current));
          return;
        case SoftwareDecodeStep():
          _ledger.softwareTried.add(current!.url);
          _softwareFor = current.url;
          await _enqueue(() => _openIfCurrent(session, intent, current));
          return;
        case BackoffStep(:final delay):
          _ledger.startBackoff();
          _failedLines.clear();
          if (!await _wait(delay) || !_stillNeeded(failure, session, intent)) return;
          if (await _refresh(session, intent, nextLine: false, usePrefetch: true)) return;
          final line = _line;
          if (line == null) continue;
          await _enqueue(() => _openIfCurrent(session, intent, line));
          return;
        case GiveUpStep():
          _giveUp(failure);
          return;
      }
    }
  }

  Future<void> _openIfCurrent(int session, int intent, StreamLine line) async {
    if (_isCurrent(session, intent)) await _openLine(line);
  }

  StreamLine? _spareLine() {
    final current = _line;
    final lines = _set?.lines ?? const <StreamLine>[];
    return lines.where((line) => line.lineId != current?.lineId && !_failedLines.contains(line.lineId)).firstOrNull;
  }

  /// Signature refresh (REC-1 step 1, SRC-8): always a new connection, even
  /// for the same URL. Returns false when resolving failed, so the chain
  /// continues with its next step.
  Future<bool> _refresh(int session, int intent, {required bool nextLine, required bool usePrefetch}) async {
    final current = _line;
    final spare = nextLine ? _spareLine() : null;
    final targetId = spare?.lineId ?? current?.lineId ?? _request?.lineId;
    var fresh = usePrefetch && targetId != null ? _takePrefetched(targetId) : null;
    if (fresh == null) {
      final request = _request;
      if (request == null) return false;
      final StreamSet set;
      try {
        set = await request.resolve(_quality).timeout(timings.refreshTimeout);
      } on Object catch (error) {
        if (_resolveFailure(error).kind == FailureKind.unavailable) {
          _giveUp(_resolveFailure(error));
          return true;
        }
        _ledger.refreshes++;
        return false;
      }
      if (!_isCurrent(session, intent)) return true;
      _set = set;
      _quality = set.selected;
      fresh = _pickLine(set, targetId);
      if (fresh == null) return false;
    }
    _ledger.refreshes++;
    if (nextLine && current != null && fresh.lineId != current.lineId) _failedLines.add(current.lineId);
    final line = fresh;
    await _enqueue(() => _openIfCurrent(session, intent, line));
    return true;
  }

  Future<bool> _wait(Duration delay) {
    _cancelBackoff();
    final wait = Completer<bool>();
    _backoffWait = wait;
    _backoffTimer = Timer(delay, () {
      if (!wait.isCompleted) wait.complete(true);
    });
    return wait.future;
  }

  void _cancelBackoff() {
    _backoffTimer?.cancel();
    _backoffTimer = null;
    final wait = _backoffWait;
    _backoffWait = null;
    if (wait != null && !wait.isCompleted) wait.complete(false);
  }

  /// Terminal error (REC-1 step 6): the intent is withdrawn, monitoring
  /// stops, the error and a retry show.
  void _giveUp(PlaybackFailure failure) {
    _failure = failure;
    _wantsPlay = false;
    _intent++;
    _cancelMonitoring();
    _prefetchTimer?.cancel();
    _publish();
    unawaited(
      _enqueue(() async {
        if (_failure == failure) await _engine?.stop();
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // State

  PlaybackPhase _phase() {
    if (_closed || _request == null) return PlaybackPhase.idle;
    if (_failure != null) return PlaybackPhase.error;
    if (_ended) return PlaybackPhase.ended;
    if (!_wantsPlay) return PlaybackPhase.paused;
    if (_suspensions.isNotEmpty) return PlaybackPhase.suspended;
    if (_recovering) return PlaybackPhase.recovering;
    if (_resolving || (_line == null && _set == null)) return PlaybackPhase.resolving;
    if (_opening || !_sourceOpened || !_playedThisGeneration) return PlaybackPhase.connecting;
    if (_enginePlaying && !_engineBuffering) return PlaybackPhase.playing;
    return PlaybackPhase.stalled;
  }

  void _publish() {
    if (_disposed) return;
    final set = _set;
    final next = PlaybackState(
      phase: _phase(),
      wantsPlay: _wantsPlay,
      roomKey: _request?.roomKey,
      qualities: set?.qualities ?? const [],
      quality: _quality,
      lines: set?.lines ?? const [],
      line: _line,
      failure: _failure,
      audioOnly: _audioOnly,
      hasPicture: _hasPicture,
      videoWidth: _width,
      videoHeight: _height,
      geometry: _geometryValue,
      engineRevision: _engineRevision,
      commit: _commit,
      notice: _notice,
    );
    if (next == _state) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}
