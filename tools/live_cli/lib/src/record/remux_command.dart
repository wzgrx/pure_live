import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:live_cli/src/record/record_command.dart';
import 'package:live_record/live_record.dart';
import 'package:path/path.dart' as p;

/// Top-level boxes of an ISO BMFF file, in file order.
Future<List<({String type, int offset, int size})>> topLevelBoxes(String path) async {
  final file = await File(path).open();
  try {
    final length = await file.length();
    final boxes = <({String type, int offset, int size})>[];
    var offset = 0;
    while (offset + 8 <= length) {
      await file.setPosition(offset);
      final head = await file.read(16);
      final data = ByteData.sublistView(head);
      var size = data.getUint32(0);
      final type = String.fromCharCodes(head, 4, 8);
      if (size == 1 && head.length >= 16) size = data.getUint32(8) * 0x100000000 + data.getUint32(12);
      if (size == 0) size = length - offset;
      if (size < 8) break;
      boxes.add((type: type, offset: offset, size: size));
      offset += size;
    }
    return boxes;
  } finally {
    await file.close();
  }
}

/// What ffprobe and ffmpeg say about one media file.
final class MediaCheck {
  /// Creates a check result.
  const new({
    required this.packets,
    required this.durations,
    required this.backwards,
    required this.formatDuration,
    required this.decodeErrors,
    required this.plainOutput,
    required this.codecs,
    required this.payloadHashes,
  });

  /// Packet count per stream type (`video`, `audio`).
  final Map<String, int> packets;

  /// Stream duration per stream type, in seconds (0 when unknown).
  final Map<String, double> durations;

  /// DTS values per stream type that did not increase.
  final Map<String, int> backwards;

  /// Container duration in seconds.
  final double formatDuration;

  /// Output of a full decode that passes frame timestamps through
  /// (`ffmpeg -v error -i … -map 0 -fps_mode passthrough -enc_time_base demux -f null -`);
  /// empty when every packet decoded without error.
  final String decodeErrors;

  /// Output of the plain `ffmpeg -v error -i … -f null -`. Besides decode
  /// errors it holds the null muxer's complaints about frame timestamps that
  /// collide in its 1/frame-rate time base, which FLV sources show as well.
  final String plainOutput;

  /// Codec name per stream type.
  final Map<String, String> codecs;

  /// MD5 of the packet payloads per stream type (`-c copy -f streamhash`).
  final Map<String, String> payloadHashes;
}

/// MD5 of every decoded video frame (or audio frame with [audio]) of
/// [path], in presentation order.
Future<List<String>> decodedFrameHashes(String path, {bool audio = false}) async {
  final result = await Process.run('ffmpeg', [
    '-v',
    'error',
    '-nostdin',
    '-i',
    path,
    '-map',
    if (audio) '0:a' else '0:v',
    '-fps_mode',
    'passthrough',
    '-f',
    'framemd5',
    '-',
  ]);
  return [
    for (final line in const LineSplitter().convert(result.stdout as String))
      if (!line.startsWith('#')) line.split(',').last.trim(),
  ];
}

/// Runs ffprobe and a full ffmpeg decode on [path]; null when they are not installed.
Future<MediaCheck?> checkMedia(String path) async {
  try {
    final streams = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'stream=index,codec_type,codec_name,duration:format=duration',
      '-of',
      'json',
      path,
    ]);
    final info = jsonDecode(streams.stdout as String) as Map<String, Object?>;
    final types = <int, String>{};
    final durations = <String, double>{};
    final codecs = <String, String>{};
    for (final stream in (info['streams'] as List<Object?>? ?? const []).cast<Map<String, Object?>>()) {
      final type = stream['codec_type']! as String;
      types[stream['index']! as int] = type;
      durations[type] = double.tryParse('${stream['duration']}') ?? 0;
      codecs[type] = '${stream['codec_name']}';
    }
    final format = info['format'] as Map<String, Object?>? ?? const {};
    final packets = <String, int>{};
    final backwards = <String, int>{};
    final last = <String, double>{};
    final dts = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'packet=stream_index,dts_time',
      '-of',
      'csv=p=0',
      path,
    ], stdoutEncoding: latin1);
    for (final line in const LineSplitter().convert(dts.stdout as String)) {
      final parts = line.split(',');
      if (parts.length < 2) continue;
      final type = types[int.tryParse(parts[0]) ?? -1];
      final value = double.tryParse(parts[1]);
      if (type == null) continue;
      packets[type] = (packets[type] ?? 0) + 1;
      if (value == null) continue;
      final previous = last[type];
      if (previous != null && value <= previous) backwards[type] = (backwards[type] ?? 0) + 1;
      last[type] = value;
    }
    final decode = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-nostdin',
      '-i',
      path,
      '-map',
      '0:v?',
      '-map',
      '0:a?',
      '-fps_mode',
      'passthrough',
      '-enc_time_base',
      'demux',
      '-f',
      'null',
      '-',
    ]);
    final plain = await Process.run('ffmpeg', ['-v', 'error', '-nostdin', '-i', path, '-f', 'null', '-']);
    final hashes = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-nostdin',
      '-i',
      path,
      '-map',
      '0:v?',
      '-map',
      '0:a?',
      '-c',
      'copy',
      '-f',
      'streamhash',
      '-hash',
      'md5',
      '-',
    ]);
    final payloadHashes = <String, String>{};
    for (final line in const LineSplitter().convert(hashes.stdout as String)) {
      final parts = line.split(',');
      if (parts.length == 3) payloadHashes[parts[1] == 'v' ? 'video' : 'audio'] = parts[2];
    }
    return MediaCheck(
      packets: packets,
      durations: durations,
      backwards: backwards,
      formatDuration: double.tryParse('${format['duration']}') ?? 0,
      decodeErrors: (decode.stderr as String).trim(),
      plainOutput: (plain.stderr as String).trim(),
      codecs: codecs,
      payloadHashes: payloadHashes,
    );
  } on ProcessException {
    return null;
  }
}

/// `live_cli remux <file>…`: converts recordings (FLV, MPEG-TS, fragmented
/// MP4) to MP4 with the pure-Dart remuxer (or ffmpeg) and checks the result
/// against the source with ffprobe and a full ffmpeg decode.
class RemuxCommand extends Command<int> {
  /// Creates the command.
  new() {
    argParser
      ..addOption('out', help: 'Output directory; next to each input by default.')
      ..addOption('remuxer', allowed: ['dart', 'ffmpeg'], defaultsTo: 'dart', help: 'Which remuxer to run.')
      ..addFlag('check', defaultsTo: true, help: 'Compare FLV and MP4 with ffprobe and decode the MP4 with ffmpeg.');
  }

  @override
  String get name => 'remux';

  @override
  String get description => 'Remux recordings (FLV, MPEG-TS, fragmented MP4) to MP4 and check the result.';

  @override
  String get invocation => 'live_cli remux <file.flv|file.ts|file.m4s>... [options]';

  @override
  Future<int> run() async {
    final options = argResults!;
    if (options.rest.isEmpty) usageException('Expected at least one recording.');
    final useFfmpeg = options.option('remuxer') == 'ffmpeg';
    final check = options.flag('check');
    var clean = true;
    for (final input in options.rest) {
      final out = options.option('out');
      final base = p.setExtension(p.basename(input), useFfmpeg ? '.ffmpeg.mp4' : '.mp4');
      final output = p.join(out ?? p.dirname(input), base);
      if (out != null) await Directory(out).create(recursive: true);
      final existing = File(output);
      if (existing.existsSync()) existing.deleteSync();
      final size = File(input).lengthSync();
      final watch = Stopwatch()..start();
      RemuxResult? result;
      try {
        if (useFfmpeg) {
          await const FfmpegProcessRemuxer().remux(
            RemuxJob(
              input: input,
              output: output,
              inputBytes: size,
              onProgress: (_) {},
              cancelled: Completer<void>().future,
            ),
          );
        } else {
          result = await remuxRecording(input: input, output: output);
        }
      } on RemuxException catch (error) {
        stdout.writeln('${p.basename(input)}: FAIL $error');
        clean = false;
        continue;
      }
      watch.stop();
      final seconds = watch.elapsedMicroseconds / 1e6;
      final outSize = File(output).lengthSync();
      stdout
        ..writeln('${p.basename(input)} → ${p.basename(output)}')
        ..writeln(
          '  size          ${_mib(size)} → ${_mib(outSize)} in ${seconds.toStringAsFixed(2)} s '
          '(${(size / 1048576 / seconds).toStringAsFixed(0)} MiB/s)',
        );
      if (result != null) {
        stdout.writeln(
          '  remuxer       ${result.videoCodec?.name ?? 'no video'} ${result.videoSamples} samples '
          '(${result.keyframes} sync), audio ${result.audioSampleRate ?? '-'} Hz ${result.audioSamples} samples, '
          '${result.duration.inMilliseconds / 1000} s, moov ${result.moovBytes} B${result.co64 ? ' co64' : ''}, '
          'tables ${(result.tableBytes / 1024).round()} KiB, dropped ${result.droppedTags}',
        );
      }
      final boxes = await topLevelBoxes(output);
      final order = boxes.map((box) => box.type).join(' ');
      final faststart = order.contains('moov') && order.indexOf('moov') < order.indexOf('mdat');
      stdout.writeln('  boxes         $order${faststart ? '' : '  ← moov not before mdat'}');
      clean = clean && faststart;
      if (!check) continue;
      final source = await checkMedia(input);
      final mp4 = await checkMedia(output);
      if (source == null || mp4 == null) {
        stdout.writeln('  check         skipped (ffprobe/ffmpeg not installed)');
        continue;
      }
      var ok = faststart;
      for (final type in const ['video', 'audio']) {
        final a = source.packets[type];
        final b = mp4.packets[type];
        if (a == null && b == null) continue;
        final same = a == b;
        final back = mp4.backwards[type] ?? 0;
        ok = ok && same && back == 0;
        stdout.writeln(
          '${'  $type'.padRight(16)}${mp4.codecs[type]} packets source $a / MP4 $b${same ? '' : ' ← differ'}, '
          'MP4 duration ${mp4.durations[type]?.toStringAsFixed(3)} s, DTS backwards $back',
        );
      }
      final delta = (source.formatDuration - mp4.formatDuration).abs();
      stdout
        ..writeln(
          '  duration      source ${source.formatDuration.toStringAsFixed(3)} s, '
          'MP4 ${mp4.formatDuration.toStringAsFixed(3)} s (Δ ${(delta * 1000).round()} ms)',
        )
        ..writeln('  decode        source ${_lines(source.decodeErrors)}, MP4 ${_lines(mp4.decodeErrors)}')
        ..writeln(
          '  plain decode  source ${_lines(source.plainOutput)}, MP4 ${_lines(mp4.plainOutput)} (-f null - as is)',
        );
      for (final type in const ['video', 'audio']) {
        final a = source.payloadHashes[type];
        if (a == null) continue;
        if (a == mp4.payloadHashes[type]) {
          stdout.writeln('${'  $type payload'.padRight(16)}identical (${a.split('=').last})');
        } else {
          // Annex B or ADTS input: samples get length prefixes, parameter sets
          // move to the sample entry, ADTS headers go; compare what decodes.
          final before = await decodedFrameHashes(input, audio: type == 'audio');
          final after = await decodedFrameHashes(output, audio: type == 'audio');
          // The decoder trims the last AAC frame by the container's end
          // (ffmpeg's own -c copy MP4 differs there too): compare the others.
          final compared = type == 'audio' ? before.length - 1 : before.length;
          final same =
              before.length == after.length && Iterable<int>.generate(compared).every((i) => before[i] == after[i]);
          final last = type == 'audio' && same && before.isNotEmpty && before.last != after.last;
          stdout.writeln(
            '${'  $type payload'.padRight(16)}rewritten; decoded frames ${same ? 'identical' : 'DIFFER'} '
            '(${before.length} / ${after.length})${last ? ', the last one trimmed at the end' : ''}',
          );
          ok = ok && same;
        }
      }
      for (final line in mp4.decodeErrors.split('\n').where((line) => line.isNotEmpty).take(5)) {
        stdout.writeln('    $line');
      }
      ok = ok && mp4.decodeErrors.isEmpty && _count(mp4.plainOutput) <= _count(source.plainOutput);
      stdout.writeln('  result        ${ok ? 'PASS' : 'FAIL'}');
      clean = clean && ok;
    }
    return clean ? 0 : 1;
  }

  static int _count(String output) => output.isEmpty ? 0 : output.split('\n').length;

  static String _lines(String output) => output.isEmpty ? 'clean' : '${_count(output)} lines';

  static String _mib(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MiB';
}
