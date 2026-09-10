import 'package:dio/dio.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';
import 'package:pure_live/recorder/services/niconico_hls_input.dart';

import 'playback_proxy_policy.dart';
import 'playback_source_transport.dart';

typedef NiconicoPlaybackInputOpener = Future<NiconicoHlsInput> Function(
  NiconicoWatch watch, {
  required String? resolution,
  int? bandwidth,
  required bool recording,
  required String Function(Uri) findProxy,
  CancelToken? cancel,
});

/// A recreation recipe containing public program/quality identity, never a
/// cached watch websocket, media grant or active seat. Each engine/recovery open
/// resolves fresh metadata and acquires its own input inside the transaction.
class NiconicoPlaybackInput {
  NiconicoPlaybackInput({
    required String programId,
    required this.resolution,
    this.bandwidth,
    NiconicoApi? api,
    this._findProxy,
    NiconicoPlaybackInputOpener? openInput,
  }) : programId = NiconicoWatch.validateProgramId(programId),
       _api = api ?? NiconicoApi(),
       _openInput = openInput ?? NiconicoHlsInput.open {
    if (bandwidth != null && (resolution == null || bandwidth! <= 0)) {
      throw ArgumentError('A positive bandwidth selector requires an explicit resolution');
    }
  }
  final String programId;
  final String? resolution;
  final int? bandwidth;
  final NiconicoApi _api;
  final String Function(Uri)? _findProxy;
  final NiconicoPlaybackInputOpener _openInput;

  Future<PlaybackInputLease> open(CancelToken cancel) async {
    if (cancel.isCancelled) throw cancel.cancelError!;
    final directive = PlaybackProxyPolicy.currentDirective();
    final findProxy = _findProxy ?? (_) => directive;
    try {
      final watch = await _api.room(programId, cancel: cancel);
      if (cancel.isCancelled) throw cancel.cancelError!;
      final input = await _openInput(
        watch,
        resolution: resolution,
        bandwidth: bandwidth,
        recording: false,
        findProxy: findProxy,
        cancel: cancel,
      );
      try {
        if (cancel.isCancelled) throw cancel.cancelError!;
        return PlaybackInputLease(input.inputUri, input.close, isUsable: () => !input.isClosed);
      } catch (_) {
        await input.close();
        rethrow;
      }
    } on NiconicoException catch (error) {
      if (error.kind == NiconicoFailure.cancelled && cancel.isCancelled) throw cancel.cancelError!;
      rethrow;
    }
  }
}
