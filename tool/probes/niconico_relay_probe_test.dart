// Opt-in external protocol/native evidence, not application or Android acceptance.
// Own one anonymous seat and one production relay; record six seconds, decode
// both tracks, then close all owners. Signed URLs/cookies stay out of process args.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/services/settings/log_controller.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_session.dart';
import 'package:pure_live/core/site/niconico/niconico_stream.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

import 'niconico_capture_contract.dart';

void main() {
  test(
    'Niconico owned session through production relay records and decodes audio/video',
    () async {
      Get.put<LogController>(_QuietLogController());
      addTearDown(() => Get.delete<LogController>(force: true));
      final env = io.Platform.environment;
      final directory = io.Directory(env['PURELIVE_NICONICO_RELAY_OUTPUT']!);
      await directory.create(recursive: true);
      final report = <String, Object?>{
        'utc': DateTime.now().toUtc().toIso8601String(),
        'result': 'failed',
        'stage': 'watch',
        'decoded': false,
        'route': 'PROXY 127.0.0.1:7897',
        'applicationConsumer': false,
      };
      await io.HttpOverrides.runWithHttpOverrides(() async {
        final previous = HttpClient.instance.dio;
        final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)))
          ..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () => io.HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:7897',
          );
        NiconicoSession? session;
        NiconicoStream? grant;
        FFmpegHlsInputRelay? relay;
        final requests = <String, int>{};
        final diagnostics = HlsRelayDiagnostics();
        HttpClient.instance.dio = dio;
        configureWebSocketProxyRouting((_) => 'PROXY 127.0.0.1:7897');
        try {
          final watch = await NiconicoApi().room(env['PURELIVE_NICONICO_PROGRAM']!);
          report['stage'] = 'session';
          final owned = await NiconicoSession.open(watch);
          session = owned;
          grant = owned.current;
          final source = grant.uri;
          report['cookiesAtStart'] = grant.retainedCookieCount;
          report['stage'] = 'relay';
          relay = (await FFmpegHlsInputRelay.startForArguments(
            ['-rw_timeout', '20000000', '-i', source.toString()],
            requestCookies: (uri) {
              final current = owned.current;
              // A changed root requires consumer reacquisition, not old cached
              // playlists with a new session's credentials. Same-root refresh is OK.
              if (current.uri != source) throw StateError('Stream source changed');
              final cookie = current.cookieHeaderFor(uri);
              final kind = uri.path.startsWith('/hls/keys/')
                  ? 'keys'
                  : uri.path.startsWith('/hls/segments/')
                  ? 'segments'
                  : uri.path.startsWith('/hls/playlists/')
                  ? 'playlists'
                  : 'other';
              requests.update('$kind:${cookie != null}', (n) => n + 1, ifAbsent: () => 1);
              return cookie;
            },
            findProxy: (_) => 'PROXY 127.0.0.1:7897',
            diagnostics: diagnostics,
          ))!;
          final ownedRelay = relay;
          final seatCleanup = owned.done.then((_) => ownedRelay.close());
          // Observe immediate failures even while the native process is running.
          unawaited(seatCleanup.catchError((Object _) {}));
          final output = '${directory.path}/capture.mp4';
          report['stage'] = 'record';
          await _run(
            env['PURELIVE_FFMPEG']!,
            [
              '-hide_banner',
              '-v',
              'verbose',
              '-debug_ts',
              '-nostdin',
              '-n',
              '-rw_timeout',
              '25000000',
              '-i',
              relay.inputUri.toString(),
              '-t',
              '6',
              '-map',
              '0:v:0',
              '-map',
              '0:a:0',
              '-c',
              'copy',
              output,
            ],
            directory,
            'record',
            const Duration(seconds: 90),
          );
          report['captureBytes'] = await io.File(output).length();
          report['stage'] = 'inspect';
          final metadata = jsonDecode(
            await _run(
              env['PURELIVE_FFPROBE']!,
              ['-v', 'error', '-show_packets', '-show_streams', '-show_format', '-of', 'json', output],
              directory,
              'inspect',
              const Duration(seconds: 20),
            ),
          ) as Map<String, dynamic>;
          final streams = (metadata['streams'] as List).cast<Map<String, dynamic>>();
          expect(streams.where((s) => s['codec_type'] == 'video').length, 1);
          expect(streams.where((s) => s['codec_type'] == 'audio').length, 1);
          final duration = double.parse((metadata['format'] as Map)['duration'] as String);
          report['durationSeconds'] = duration;
          final contract = inspectNiconicoCapture(metadata);
          report['captureContract'] = contract;
          report['streams'] = streams
              .map(
                (s) => <String, Object?>{
                  'type': s['codec_type'],
                  'codec': s['codec_name'],
                  if (s['width'] != null) 'width': s['width'],
                  if (s['height'] != null) 'height': s['height'],
                },
              )
              .toList();
          report['stage'] = 'decode';
          await _run(
            env['PURELIVE_FFMPEG']!,
            [
              '-hide_banner',
              '-v',
              'error',
              '-xerror',
              '-nostdin',
              '-i',
              output,
              '-map',
              '0:v:0',
              '-map',
              '0:a:0',
              '-f',
              'null',
              '-',
            ],
            directory,
            'decode',
            const Duration(seconds: 30),
          );
          expect(owned.isClosed, false);
          report['decoded'] = true;
          report['keepSeatSent'] = owned.seatKeepAlivesSent;
          report['stage'] = 'duration';
          expect(contract['passed'], true, reason: '${contract['failures']}');
          report['result'] = 'passed';
          await relay.close();
          await owned.close();
          await seatCleanup;
        } catch (error) {
          report['result'] = 'failed';
          report['failureType'] = error.runtimeType.toString();
          fail('Niconico relay probe failed at ${report['stage']} (${report['failureType']})');
        } finally {
          try {
            await relay?.close();
          } finally {
            await session?.close();
            HttpClient.instance.dio = previous;
            dio.close(force: true);
            configureWebSocketProxyRouting(null);
            report['requests'] = requests;
            await io.File('${directory.path}/relay.json').writeAsString(jsonEncode(diagnostics.snapshot()));
            report['sessionClosed'] = session?.isClosed;
            report['cleanupSucceeded'] = session?.cleanupSucceeded;
            report['retainedCookies'] = grant?.retainedCookieCount;
            // This opt-in test lives under tool/probes rather than test/.
            // ignore: invalid_use_of_visible_for_testing_member
            report['relayResources'] = relay?.resourceCount;
            // ignore: invalid_use_of_visible_for_testing_member
            if (session?.cleanupSucceeded != true || (relay?.resourceCount ?? 0) != 0) report['result'] = 'failed';
            await io.File('${directory.path}/report.json').writeAsString(jsonEncode(report));
            // ignore: avoid_print
            print(jsonEncode(report));
          }
          if (session != null) expect(session.cleanupSucceeded, true);
        }
      }, _RealNetwork());
    },
    skip: io.Platform.environment['PURELIVE_NICONICO_RELAY_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

class _RealNetwork extends io.HttpOverrides {}

class _QuietLogController extends GetxController implements LogController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  bool get enableLog => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<String> _run(
  String executable,
  List<String> args,
  io.Directory directory,
  String stage,
  Duration timeout,
) async {
  final process = await io.Process.start(executable, args);
  final stdout = <int>[];
  final stderr = <int>[];
  void capture(List<int> target, List<int> chunk) {
    final remaining = 1024 * 1024 - target.length;
    if (remaining > 0) target.addAll(chunk.take(remaining));
  }

  final out = process.stdout.listen((chunk) => capture(stdout, chunk));
  final err = process.stderr.listen((chunk) => capture(stderr, chunk));
  final drained = Future.wait<void>([out.asFuture<void>(), err.asFuture<void>()]);
  unawaited(drained.catchError((Object _) => <void>[]));
  var exited = false;
  try {
    final code = await process.exitCode.timeout(timeout);
    exited = true;
    await drained.timeout(const Duration(seconds: 5));
    if (code != 0) throw StateError('Native $stage failed ($code)');
    return utf8.decode(stdout);
  } finally {
    if (!exited) process.kill();
    await process.exitCode;
    await out.cancel();
    await err.cancel();
    await io.File('${directory.path}/$stage.stderr.log').writeAsBytes(stderr);
  }
}
