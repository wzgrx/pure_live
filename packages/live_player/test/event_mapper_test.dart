import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:media_kit/media_kit.dart';

/// media_kit-like streams driven by the test in a recorded order.
final class _FakePlayerStreams {
  final playing = StreamController<bool>.broadcast();
  final completed = StreamController<bool>.broadcast();
  final buffering = StreamController<bool>.broadcast();
  final position = StreamController<Duration>.broadcast();
  final duration = StreamController<Duration>.broadcast();
  final tracks = StreamController<Tracks>.broadcast();
  final videoParams = StreamController<VideoParams>.broadcast();
  final log = StreamController<PlayerLog>.broadcast();
  final frames = ValueNotifier<int>(0);

  MediaKitEventMapper mapper() => MediaKitEventMapper(
    MediaKitStreams(
      playing: playing.stream,
      completed: completed.stream,
      buffering: buffering.stream,
      position: position.stream,
      duration: duration.stream,
      tracks: tracks.stream,
      videoParams: videoParams.stream,
      log: log.stream,
    ),
    frames: frames,
  );
}

const _realTracks = Tracks(
  video: [VideoTrack('auto', null, null), VideoTrack('no', null, null), VideoTrack('1', null, null)],
  audio: [AudioTrack('auto', null, null), AudioTrack('no', null, null), AudioTrack('1', null, null)],
);

void main() {
  test('keeps the recorded end-of-stream order and drops pseudo tracks (EVT-1, EVT-14)', () async {
    final source = _FakePlayerStreams();
    final mapper = source.mapper();
    final events = <String>[];
    mapper.events.listen((event) => events.add('$event'));

    // fixtures/player/eof: open resets, data arrives, then the stream ends.
    // media_kit adds each mpv event in its own turn; a burst of adds across
    // its separate broadcast controllers would be delivered round-robin.
    final steps = <void Function()>[
      () => source.playing.add(false),
      () => source.completed.add(false),
      () => source.buffering.add(false),
      () => source.tracks.add(const Tracks()),
      () => source.videoParams.add(const VideoParams()),
      () => source.playing.add(true),
      () => source.buffering.add(true),
      () => source.buffering.add(false),
      () => source.tracks.add(_realTracks),
      () => source.videoParams.add(const VideoParams(w: 1920, h: 1080, dw: 1920, dh: 1080)),
      () => source.position.add(const Duration(milliseconds: 500)),
      () => source.buffering.add(true),
      () => source.playing.add(false),
      () => source.completed.add(true),
      () => source.buffering.add(false),
      () => source.tracks.add(const Tracks()),
    ];
    for (final step in steps) {
      step();
      await pumpEventQueue();
    }

    expect(events, [
      'playing=false',
      'completed=false',
      'buffering=false',
      'tracks=v0/a0',
      'size=nullxnull',
      'playing=true',
      'buffering=true',
      'buffering=false',
      'tracks=v1/a1',
      'size=1920x1080',
      'position=500',
      'buffering=true',
      'playing=false',
      'completed=true',
      'buffering=false',
      'tracks=v0/a0',
    ]);
    await mapper.close();
  });

  test('reports a size change once and prefers the display size', () async {
    final source = _FakePlayerStreams();
    final mapper = source.mapper();
    final sizes = <String>[];
    mapper.events.where((event) => event is EngineVideoSize).listen((event) => sizes.add('$event'));
    source.videoParams
      ..add(const VideoParams(w: 1440, h: 1080, dw: 1920, dh: 1080))
      ..add(const VideoParams(w: 1440, h: 1080, dw: 1920, dh: 1080, rotate: 0))
      ..add(const VideoParams(w: 720, h: 1280));
    await pumpEventQueue();
    expect(sizes, ['size=1920x1080', 'size=720x1280']);
    await mapper.close();
  });

  test('turns only actionable error-level log lines into errors (EVT-7)', () async {
    final source = _FakePlayerStreams();
    final mapper = source.mapper();
    final errors = <EngineError>[];
    mapper.events.where((event) => event is EngineError).cast<EngineError>().listen(errors.add);
    source.log
      ..add(const PlayerLog(prefix: 'cplayer', level: 'error', text: 'Failed to open http://x/live.flv.'))
      ..add(const PlayerLog(prefix: 'ffmpeg', level: 'error', text: 'tcp: Connection reset by peer'))
      ..add(const PlayerLog(prefix: 'ffmpeg', level: 'error', text: 'http: HTTP error 404'))
      ..add(const PlayerLog(prefix: 'vd', level: 'warn', text: 'Error while decoding frame'))
      ..add(const PlayerLog(prefix: 'ao/audiotrack', level: 'error', text: 'underrun'))
      ..add(const PlayerLog(prefix: 'ffmpeg/video', level: 'error', text: 'h264: Invalid NAL unit size'));
    await pumpEventQueue();
    expect(errors.map((error) => '${error.prefix}: ${error.message}'), [
      'cplayer: Failed to open http://x/live.flv.',
      'ffmpeg: tcp: Connection reset by peer',
      'ffmpeg/video: h264: Invalid NAL unit size',
    ]);
    await mapper.close();
  });

  test('maps frame revisions to frame progress (EVT-11) and stops on close', () async {
    final source = _FakePlayerStreams();
    final mapper = source.mapper();
    final frames = <int>[];
    mapper.events
        .where((event) => event is EngineFrame)
        .cast<EngineFrame>()
        .listen((event) => frames.add(event.revision));
    source.frames.value = 1;
    source.frames.value = 2;
    await pumpEventQueue();
    await mapper.close();
    source.frames.value = 3;
    source.playing.add(true);
    await pumpEventQueue();
    expect(frames, [1, 2]);
  });
}
