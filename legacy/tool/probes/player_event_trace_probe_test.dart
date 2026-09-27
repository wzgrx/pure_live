// Records real libmpv event sequences for the v4 replay fake
// (docs/rewrite/diagnosis/06-tests.md ⑥-4, spec/modules/playback.md).
//
// Opt-in, no network beyond loopback:
//   PURELIVE_TRACE_LIB=<libmpv.so|dll> PURELIVE_TRACE_MEDIA=<synthetic.flv> \
//   flutter test tool/probes/player_event_trace_probe_test.dart
// Output: ../fixtures/player/<scenario>/trace.jsonl plus ../fixtures/player/meta.json
// (override the folder with PURELIVE_TRACE_OUT). The media must be synthetic,
// e.g. ffmpeg testsrc2 + sine, H.264/AAC, one keyframe per second.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

final _library = Platform.environment['PURELIVE_TRACE_LIB'];
final _media = Platform.environment['PURELIVE_TRACE_MEDIA'];
final _out = Platform.environment['PURELIVE_TRACE_OUT'] ?? '../fixtures/player';

/// How the loopback server behaves for one request.
enum _Serve {
  /// Send every tag at its media time, then close: a live stream that ends.
  realtime,

  /// Send 3 s at media time, then keep the connection open without data.
  stall,

  /// Send 3 s at media time, then destroy the socket.
  reset,

  /// Answer 403.
  forbidden,

  /// Answer 200 with bytes that are not media.
  garbage,
}

class _Scenario {
  const _Scenario(this.name, this.description, this.serves, this.drive);

  final String name;
  final String description;

  /// Behaviour per request, in order; later requests reuse the last entry.
  final List<_Serve> serves;

  /// Drives the player; `open(n)` opens request slot n.
  final Future<void> Function(mk.Player player, Future<void> Function() open, void Function(String) mark) drive;
}

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

final _scenarios = <_Scenario>[
  _Scenario('eof', 'Live FLV delivered in real time, then the server closes the connection.', [_Serve.realtime], (
    player,
    open,
    mark,
  ) async {
    await open();
    await _wait(14000);
  }),
  _Scenario(
    'stall',
    'Delivery stops after 3 s while the connection stays open for 15 s, then closes.',
    [_Serve.stall],
    (player, open, mark) async {
      await open();
      await _wait(22000);
    },
  ),
  _Scenario('reset', 'Delivery stops after 3 s with an abrupt socket reset.', [_Serve.reset], (
    player,
    open,
    mark,
  ) async {
    await open();
    await _wait(10000);
  }),
  _Scenario('http403', 'The media URL answers 403.', [_Serve.forbidden], (player, open, mark) async {
    await open();
    await _wait(6000);
  }),
  _Scenario('garbage', 'The media URL answers 200 with bytes that are not media.', [_Serve.garbage], (
    player,
    open,
    mark,
  ) async {
    await open();
    await _wait(6000);
  }),
  _Scenario('pause_resume', 'Pause after 3 s of playback for 3 s, resume, run to the end.', [_Serve.realtime], (
    player,
    open,
    mark,
  ) async {
    await open();
    await _wait(3000);
    mark('pause');
    await player.pause();
    await _wait(3000);
    mark('play');
    await player.play();
    await _wait(12000);
  }),
  _Scenario(
    'reopen_after_403',
    'First open answers 403; the same player then opens a working URL.',
    [_Serve.forbidden, _Serve.realtime],
    (player, open, mark) async {
      await open();
      await _wait(4000);
      await open();
      await _wait(14000);
    },
  ),
  _Scenario('stop_while_buffering', 'Stop the player during the stall.', [_Serve.stall], (player, open, mark) async {
    await open();
    await _wait(6000);
    mark('stop');
    await player.stop();
    await _wait(3000);
  }),
];

class _Tag {
  const _Tag(this.ms, this.bytes);

  final int ms;
  final Uint8List bytes;
}

/// Splits an FLV file into the header and one chunk per tag (with its trailing size).
(Uint8List, List<_Tag>) _tags(Uint8List bytes) {
  final header = Uint8List.sublistView(bytes, 0, 13);
  final tags = <_Tag>[];
  var offset = 13;
  while (offset + 11 <= bytes.length) {
    final size = (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
    final ms = (bytes[offset + 7] << 24) | (bytes[offset + 4] << 16) | (bytes[offset + 5] << 8) | bytes[offset + 6];
    final end = offset + 11 + size + 4;
    if (end > bytes.length) break;
    tags.add(_Tag(ms, Uint8List.sublistView(bytes, offset, end)));
    offset = end;
  }
  return (header, tags);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = _library != null && _media != null;

  setUpAll(() {
    if (enabled) mk.MediaKit.ensureInitialized(libmpv: _library);
  });

  for (final scenario in _scenarios) {
    test(
      scenario.name,
      () async {
        final (header, tags) = _tags(File(_media!).readAsBytesSync());
        final clock = Stopwatch()..start();
        final events = <Map<String, Object?>>[];
        void record(String kind, Object? value) => events.add({'ms': clock.elapsedMilliseconds, kind: value});

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        final cancel = Completer<void>();
        server.listen((request) async {
          final serve = scenario.serves[requests.clamp(0, scenario.serves.length - 1)];
          requests++;
          record('server', '${serve.name} ${request.uri.path}');
          final response = request.response;
          switch (serve) {
            case _Serve.forbidden:
              response.statusCode = HttpStatus.forbidden;
              await response.close();
            case _Serve.garbage:
              response.headers.contentType = ContentType('video', 'x-flv');
              response.add(List<int>.generate(256 * 1024, (i) => (i * 7919) & 0xff));
              await response.close();
            case _Serve.realtime || _Serve.stall || _Serve.reset:
              response.headers.contentType = ContentType('video', 'x-flv');
              response.headers.chunkedTransferEncoding = true;
              // Own the socket and frame the chunks by hand, so `reset` can
              // cut the body without the terminating chunk: the client sees a
              // truncated response, not a clean end of stream.
              final socket = await response.detachSocket();
              void send(List<int> bytes) => socket
                ..write('${bytes.length.toRadixString(16)}\r\n')
                ..add(bytes)
                ..write('\r\n');
              send(header);
              final start = clock.elapsedMilliseconds;
              for (final tag in tags) {
                if (serve != _Serve.realtime && tag.ms >= 3000) break;
                final due = start + tag.ms - clock.elapsedMilliseconds;
                if (due > 0) await Future.any([cancel.future, _wait(due)]);
                if (cancel.isCompleted) break;
                send(tag.bytes);
                await socket.flush();
              }
              if (serve == _Serve.reset) {
                record('server', 'reset');
                socket.destroy();
                return;
              }
              if (serve == _Serve.stall) {
                record('server', 'stall');
                await Future.any([cancel.future, _wait(15000)]);
              }
              record('server', 'close');
              socket.write('0\r\n\r\n');
              await socket.flush();
              await socket.close();
          }
        });

        final player = mk.Player(
          configuration: const mk.PlayerConfiguration(vo: 'null', title: 'trace'),
        );
        final stream = player.stream;
        var lastPosition = -1000;
        var lastDuration = -1000;
        final subscriptions = <StreamSubscription<Object?>>[
          stream.playing.listen((value) => record('playing', value)),
          stream.completed.listen((value) => record('completed', value)),
          stream.buffering.listen((value) => record('buffering', value)),
          stream.error.listen((value) => record('error', value)),
          stream.width.listen((value) => record('width', value)),
          stream.height.listen((value) => record('height', value)),
          stream.duration.listen((value) {
            // A live FLV without duration metadata reports the growing buffered length.
            if ((value.inMilliseconds - lastDuration).abs() < 500 && value.inMilliseconds != 0) return;
            lastDuration = value.inMilliseconds;
            record('duration', value.inMilliseconds);
          }),
          stream.tracks.listen((value) => record('tracks', {'video': value.video.length, 'audio': value.audio.length})),
          stream.position.listen((value) {
            // Positions arrive many times per second; one per 500 ms is enough to replay progress.
            if (value.inMilliseconds - lastPosition < 500 && value.inMilliseconds >= lastPosition) return;
            lastPosition = value.inMilliseconds;
            record('position', value.inMilliseconds);
          }),
        ];
        var slot = 0;
        Future<void> open() async {
          final url = 'http://127.0.0.1:${server.port}/live/${slot++}.flv';
          record('command', 'open');
          await player.open(mk.Media(url));
        }

        try {
          await scenario.drive(player, open, (command) => record('command', command));
          record('command', 'dispose');
        } finally {
          cancel.complete();
          for (final subscription in subscriptions) {
            await subscription.cancel();
          }
          await player.dispose();
          await server.close(force: true);
        }

        final directory = Directory('$_out/${scenario.name}')..createSync(recursive: true);
        File('${directory.path}/trace.jsonl').writeAsStringSync('${events.map(jsonEncode).join('\n')}\n');
        File('${directory.path}/README.md').writeAsStringSync('# ${scenario.name}\n\n${scenario.description}\n');
        expect(events.where((event) => event.containsKey('command')), isNotEmpty);
      },
      skip: enabled ? false : 'Set PURELIVE_TRACE_LIB and PURELIVE_TRACE_MEDIA',
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('meta', () async {
    final player = mk.Player(configuration: const mk.PlayerConfiguration(vo: 'null'));
    final native = player.platform! as dynamic;
    final mpv = await native.getProperty('mpv-version') as String;
    final ffmpeg = await native.getProperty('ffmpeg-version') as String;
    final options = <String, String>{
      for (final name in [
        'network-timeout',
        'cache',
        'cache-secs',
        'demuxer-readahead-secs',
        'demuxer-max-bytes',
        'hwdec',
      ])
        name: await native.getProperty(name) as String,
    };
    await player.dispose();
    final media = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'stream=codec_name,width,height,r_frame_rate:format=duration',
      '-of',
      'compact',
      _media!,
    ]);
    final meta = {
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'host': Platform.operatingSystem,
      'mpv': mpv,
      'ffmpeg': ffmpeg,
      'mediaKit': 'third_party/media_kit (docs/adr/0002-media-kit-fork.md)',
      'mpvOptions': options,
      'media': (media.stdout as String).trim().split('\n'),
      'recorder': 'tool/probes/player_event_trace_probe_test.dart',
      'note': 'Times are wall-clock ms from the scenario start; replay keeps order and relative gaps.',
    };
    Directory(_out).createSync(recursive: true);
    File('$_out/meta.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(meta)}\n');
  }, skip: enabled ? false : 'Set PURELIVE_TRACE_LIB and PURELIVE_TRACE_MEDIA');
}
