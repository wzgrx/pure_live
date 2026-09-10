import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_state.dart';

// Native boundary fixture; no network, renderer or device is allocated.
class OwnedSourceTestPlayer implements UnifiedPlayer, PrivateInputAwarePlayer {
  bool _privateInput = false;
  final openedPrivateInputs = <bool>[];
  final openedSourceIdentities = <String?>[];
  String? _sourceIdentity;
  final openedHeaders = <Map<String, String>>[];
  final openedChoices = <List<String>>[];
  @override
  void setPrivateInput(bool value, {String? sourceIdentity}) {
    _privateInput = value;
    _sourceIdentity = sourceIdentity;
  }

  OwnedSourceTestPlayer(
    this.engine,
    this.failureForUrl, {
    this.initFailure,
    this.emitPlaying = true,
    this.hangWhileOpening = false,
    this.initBarrier,
    this.openBarrier,
    this.onOpenSource,
    this.pauseBarrier,
    this.unmuteBarrier,
    this.emittedWidth,
    this.emittedHeight,
  });

  @override
  final PlayerEngine engine;
  final PlayerException? Function(String url) failureForUrl;
  final Object? initFailure;
  final bool emitPlaying;
  final bool hangWhileOpening;
  final Future<void>? initBarrier;
  final Future<void>? openBarrier;
  final void Function()? onOpenSource;
  final Future<void>? pauseBarrier;
  final Future<void>? unmuteBarrier;
  int unmuteCalls = 0;
  int? emittedWidth;
  int? emittedHeight;
  final List<String> openedUrls = <String>[];
  final StreamController<PlayerState> _state = StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<bool> _playing = StreamController<bool>.broadcast(sync: true);
  final StreamController<bool> _loading = StreamController<bool>.broadcast(sync: true);
  final StreamController<bool> _complete = StreamController<bool>.broadcast(sync: true);
  final StreamController<PlayerException> _error = StreamController<PlayerException>.broadcast(sync: true);
  final StreamController<int?> _width = StreamController<int?>.broadcast(sync: true);
  final StreamController<int?> _height = StreamController<int?>.broadcast(sync: true);
  bool _initialized = false;
  bool _isPlaying = false;
  int playCalls = 0;
  int disposeCalls = 0;
  int softStopCalls = 0;

  void emitUnexpectedPlaying(bool playing) {
    _isPlaying = playing;
    _playing.add(playing);
  }

  void emitLoading(bool loading) {
    _loading.add(loading);
  }

  void emitNativeState(PlayerState state) {
    _state.add(state);
  }

  void emitCompleted() {
    _isPlaying = false;
    _playing.add(false);
    _complete.add(true);
  }

  void emitError(PlayerException error) {
    _error.add(error);
  }

  @override
  Future<void> init({bool audioOnly = false}) async {
    final error = initFailure;
    if (error != null) throw error;
    if (initBarrier != null) await initBarrier;
    _initialized = true;
  }

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
  }) async {
    openedUrls.add(url);
    openedPrivateInputs.add(_privateInput);
    openedSourceIdentities.add(_sourceIdentity);
    openedHeaders.add(Map.of(headers));
    openedChoices.add(List.of(playUrls));
    onOpenSource?.call();
    if (openBarrier != null) await openBarrier;
    if (hangWhileOpening) await Completer<void>().future;
    final failure = failureForUrl(url);
    if (failure != null) throw failure;
    if (emittedWidth != null && emittedHeight != null) {
      _width.add(emittedWidth);
      _height.add(emittedHeight);
    }
    if (emitPlaying) {
      _isPlaying = true;
      _state.add(PlayerState.playing);
      _playing.add(true);
      _loading.add(false);
    }
  }

  @override
  Future<void> hardDispose() async {
    disposeCalls++;
    _initialized = false;
    _isPlaying = false;
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _playing.add(false);
    if (pauseBarrier != null) await pauseBarrier;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> setAudioOnly(bool audioOnly) async {}

  @override
  Future<void> setVolume(double volume) async {
    if (volume > 0) {
      unmuteCalls++;
      if (unmuteBarrier != null) await unmuteBarrier;
    }
  }

  @override
  Future<void> softStop() async {
    softStopCalls++;
    _isPlaying = false;
  }

  @override
  Future<void> stop() async {
    _isPlaying = false;
  }

  @override
  Widget getVideoWidget({BoxFit? fit}) => const SizedBox.shrink();

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlayingNow => _isPlaying;

  @override
  bool get isReusable => true;

  @override
  Stream<bool> get onComplete => _complete.stream;

  @override
  Stream<PlayerException> get onError => _error.stream;

  @override
  Stream<bool> get onLoading => _loading.stream;

  @override
  Stream<bool> get onPlaying => _playing.stream;

  @override
  Stream<PlayerState> get onStateChanged => _state.stream;

  @override
  Stream<int?> get width => _width.stream;

  @override
  Stream<int?> get height => _height.stream;
}
