import 'dart:async';

import 'package:live_record/src/segments.dart';
import 'package:meta/meta.dart';

/// Runs FFmpeg. Pure Dart defines the contract and the argument lists; the
/// app (M12) injects the implementation: 3.x's FFmpegKit plugin on Android
/// and Windows, or an `ffmpeg` process on the desktop. Arguments are always
/// a list, never a shell string (signed URLs, CRLF headers and paths with
/// spaces must reach FFmpeg exactly).
abstract interface class FfmpegRunner {
  /// Starts FFmpeg with [arguments].
  Future<FfmpegExecution> start(List<String> arguments);
}

/// One running FFmpeg.
abstract interface class FfmpegExecution {
  /// Log lines as FFmpeg writes them.
  Stream<String> get logs;

  /// Progress statistics.
  Stream<FfmpegStatistics> get statistics;

  /// The return code once FFmpeg ended (0 or AVERROR_EOF for a normal end).
  Future<int> get exitCode;

  /// Ends FFmpeg now (FFmpegKit's cancel, or killing the process). The
  /// recorder ends inputs cleanly first and calls this only when FFmpeg did
  /// not drain in time.
  void cancel();
}

/// One FFmpeg statistics sample (FFmpegKit's `Statistics`).
@immutable
final class FfmpegStatistics {
  /// Creates a sample.
  const new({this.time = 0, this.size = 0, this.bitrate = 0, this.speed = 0, this.videoFps = 0, this.videoFrame = 0});

  /// Media time, milliseconds.
  final int time;

  /// Output bytes.
  final int size;

  /// Bitrate, kbit/s.
  final double bitrate;

  /// Speed against real time.
  final double speed;

  /// Video frames per second.
  final double videoFps;

  /// Video frame number.
  final int videoFrame;
}

/// FFmpeg's AVERROR_EOF return code.
const ffmpegEndOfFile = -541478725;

const _protocolWhitelist = 'httpproxy,udp,rtp,rtsp,rtmp,rtmps,srt,tcp,tls,data,file,http,https,crypto';

/// FFmpeg argument lists of the recorder (3.x `FFmpegCommandBuilder`).
abstract final class FfmpegCommand {
  /// Capture of [url] into clock-v1 MPEG-TS segments of [filePrefix] in
  /// [outputDir] (3.x `buildRecordArguments`, unchanged options). [headers]
  /// go out as `-user_agent` and `-headers` (names lower case, CR/LF
  /// stripped); [proxyUrl] as `-http_proxy`; [caFile] before HTTPS inputs
  /// on builds whose OpenSSL has no trust store (3.x
  /// `FFmpegTlsTrustStore.injectCaFile`, the file is the app's).
  static List<String> record({
    required String url,
    required String outputDir,
    required String filePrefix,
    required int segmentTime,
    required bool preferBestStream,
    required int rwTimeout,
    required int threadQueueSize,
    Map<String, String> headers = const {},
    String proxyUrl = '',
    String? caFile,
    String separator = '/',
  }) {
    final normalized = normalizeHeaders(headers);
    final userAgent = normalized.remove('user-agent');
    final headerText = headerBlock(normalized);
    final scheme = Uri.tryParse(url.trim())?.scheme.toLowerCase() ?? '';
    return List.unmodifiable([
      '-n',
      '-hide_banner',
      '-loglevel',
      'info',
      '-analyzeduration',
      '5000000',
      '-probesize',
      '5000000',
      '-fflags',
      '+genpts+discardcorrupt',
      '-protocol_whitelist',
      _protocolWhitelist,
      ...inputProtocolOptions(url, rwTimeout: rwTimeout),
      '-thread_queue_size',
      threadQueueSize.clamp(64, 65536).toString(),
      if (userAgent != null && userAgent.isNotEmpty) ...['-user_agent', userAgent],
      if (headerText.isNotEmpty) ...['-headers', headerText],
      if (proxyUrl.isNotEmpty && (scheme == 'http' || scheme == 'https')) ...['-http_proxy', proxyUrl],
      if (caFile != null && caFile.isNotEmpty && scheme == 'https') ...['-ca_file', caFile],
      if (_networkSchemes.contains(scheme)) ...['-dts_delta_threshold', '2', '-dts_error_threshold', '2'],
      '-i',
      url,
      '-map',
      if (preferBestStream) '0:v:0?' else '0:v?',
      '-map',
      if (preferBestStream) '0:a:0?' else '0:a?',
      '-c',
      'copy',
      '-avoid_negative_ts',
      'make_non_negative',
      '-f',
      'segment',
      '-segment_format',
      'mpegts',
      '-segment_format_options',
      'flush_packets=1:avoid_negative_ts=disabled:max_delay=0:output_ts_offset=1.4',
      '-segment_list',
      '$outputDir$separator${SegmentClock.journalName(filePrefix)}',
      '-segment_list_type',
      'csv',
      '-segment_time',
      segmentTime.clamp(10, 86400).toString(),
      '-segment_start_number',
      '0',
      '-reset_timestamps',
      '1',
      '$outputDir$separator${SegmentClock.segmentPattern(filePrefix)}',
    ]);
  }

  /// Joins the concat [manifest] file into the MP4 [output] (3.x
  /// `VideoProcessorService`): stream copy, `-xerror` so demux and mux
  /// errors fail before the commit, `+faststart`.
  static List<String> merge({required String manifest, required String output}) => List.unmodifiable([
    '-y',
    '-hide_banner',
    '-loglevel',
    'warning',
    '-xerror',
    '-f',
    'concat',
    '-safe',
    '0',
    '-i',
    manifest,
    '-map',
    '0:v?',
    '-map',
    '0:a?',
    '-c',
    'copy',
    '-movflags',
    '+faststart',
    '-f',
    'mp4',
    output,
  ]);

  /// Protocol options before `-i` for [url]: reconnects on network and 5xx
  /// errors only (401/403/404 need a fresh signed URL), read timeout.
  static List<String> inputProtocolOptions(String url, {required int rwTimeout}) {
    final scheme = Uri.tryParse(url.trim())?.scheme.toLowerCase() ?? '';
    final timeout = (rwTimeout.clamp(1, 3600) * 1000000).clamp(1, 2147483647).toString();
    return switch (scheme) {
      'http' || 'https' => [
        '-reconnect',
        '1',
        '-reconnect_streamed',
        '1',
        '-reconnect_on_network_error',
        '1',
        '-reconnect_on_http_error',
        '5xx',
        '-reconnect_delay_max',
        '5',
        '-rw_timeout',
        timeout,
      ],
      'rtsp' => ['-rtsp_transport', 'tcp', '-rw_timeout', timeout],
      'udp' || 'rtp' => ['-fifo_size', '5000000', '-overrun_nonfatal', '1'],
      'file' || '' => const [],
      _ => ['-rw_timeout', timeout],
    };
  }

  /// [headers] with lower-case valid names and values without CR, LF or NUL.
  static Map<String, String> normalizeHeaders(Map<String, String> headers) {
    final normalized = <String, String>{};
    final validName = RegExp(r'^[A-Za-z0-9-]+$');
    for (final MapEntry(:key, :value) in headers.entries) {
      final name = key.trim().toLowerCase();
      final text = value.replaceAll(RegExp(r'[\r\n\u0000]+'), ' ').trim();
      if (name.isEmpty || text.isEmpty || !validName.hasMatch(name)) continue;
      normalized[name] = text;
    }
    return normalized;
  }

  /// FFmpeg's `-headers` block: `name: value\r\n` per header.
  static String headerBlock(Map<String, String> headers) =>
      headers.isEmpty ? '' : '${headers.entries.map((entry) => '${entry.key}: ${entry.value}').join('\r\n')}\r\n';

  /// The arguments quoted for logs and tests only.
  static String format(Iterable<String> arguments) =>
      arguments.map((value) => '"${value.replaceAll('\r', '').replaceAll('\n', '').replaceAll('"', r'\"')}"').join(' ');

  static const _networkSchemes = {'http', 'https', 'rtmp', 'rtmps', 'rtsp', 'rtp', 'udp', 'srt'};
}

/// Why FFmpeg failed (3.x `FFmpegFailureKind`).
enum FfmpegFailureKind {
  /// No space left.
  storageFull,

  /// The output cannot be written.
  outputPath,

  /// The generated command is invalid.
  command,

  /// HTTP 401, 403 or 404: the signed URL needs renewing.
  httpAccess,

  /// Network or TLS failure.
  transport,

  /// The input did not open.
  inputOpen,

  /// The input is not media FFmpeg understands.
  inputFormat,

  /// A decoder error.
  decoder,

  /// Anything else.
  native,

  /// A live input ended (code 0 or EOF) while the room may still be live.
  unexpectedEof,

  /// The recorder ended the input at a lease boundary.
  leaseRefresh,

  /// Joining hit damaged media.
  outputIntegrity,
}

/// The kind of a failure from FFmpeg's [logs] (3.x
/// `FFmpegFailureClassifier`, same markers and order) and whether retrying
/// with a fresh URL can help.
({FfmpegFailureKind kind, bool retryable}) classifyFfmpegFailure(String logs) {
  final value = logs.toLowerCase();
  bool any(List<String> markers) => markers.any(value.contains);
  if (any(const ['no space left on device', 'disk quota exceeded', 'not enough space on the disk'])) {
    return (kind: FfmpegFailureKind.storageFull, retryable: false);
  }
  if (any(const [
    'error opening output',
    'unable to open output',
    'could not open output',
    'failed to open segment',
    'error writing trailer',
    'av_interleaved_write_frame',
    'read-only file system',
    'permission denied',
  ])) {
    return (kind: FfmpegFailureKind.outputPath, retryable: false);
  }
  if (any(const [
    'server returned 401',
    'server returned 403',
    'server returned 404',
    'http error 401',
    'http error 403',
    'http error 404',
  ])) {
    return (kind: FfmpegFailureKind.httpAccess, retryable: true);
  }
  if (any(const [
    'connection timed out',
    'timed out',
    'connection refused',
    'connection reset',
    'network is unreachable',
    'host is unreachable',
    'failed to resolve',
    'name or service not known',
    'tls handshake',
    'ssl handshake',
    'certificate verify failed',
    'input/output error',
    'i/o error',
  ])) {
    return (kind: FfmpegFailureKind.transport, retryable: true);
  }
  if (any(const ['error opening input', 'unable to open input', 'failed to open input', 'could not open input'])) {
    return (kind: FfmpegFailureKind.inputOpen, retryable: true);
  }
  if (any(const [
    'invalid data found when processing input',
    'could not find codec parameters',
    'no streams found',
    'moov atom not found',
  ])) {
    return (kind: FfmpegFailureKind.inputFormat, retryable: true);
  }
  if (any(const ['decoder', 'decode', 'codec', 'invalid nal'])) {
    return (kind: FfmpegFailureKind.decoder, retryable: true);
  }
  if (any(const [
    'option not found',
    'unrecognized option',
    'error parsing options',
    'unknown protocol',
    'protocol not found',
    'muxer not found',
  ])) {
    return (kind: FfmpegFailureKind.command, retryable: false);
  }
  return (kind: FfmpegFailureKind.native, retryable: true);
}

/// Explicit media damage in FFmpeg logs (3.x `FFmpegMediaIntegrity`).
abstract final class FfmpegMediaIntegrity {
  /// Packet or bitstream damage of the input; a plain I/O error is not.
  static bool hasPacketError(String message) {
    final value = message.toLowerCase();
    return const [
      'packet corrupt (stream',
      'corrupt input packet in stream',
      'pes packet size mismatch',
      'missing picture in access unit with size',
      'error while decoding',
      'corrupt decoded frame',
    ].any(value.contains);
  }

  /// The stream of a demuxer's "Packet corrupt (stream = N, dts = …)", or
  /// null for any other line.
  static int? corruptPacketStream(String message) {
    final match = _corruptPacket.firstMatch(message);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static final _corruptPacket = RegExp(r'packet corrupt \(stream = (\d+)', caseSensitive: false);

  /// Damage that makes a join output untrustworthy.
  static bool hasError(String message) {
    final value = message.toLowerCase();
    return const [
      'packet corrupt (stream',
      'corrupt input packet in stream',
      'pes packet size mismatch',
      'missing picture in access unit with size',
      'error writing trailer',
      'error muxing a packet',
      'error during demuxing',
    ].any(value.contains);
  }
}

/// A live duration from FFmpeg's statistics time (3.x
/// `normalizeLiveRecordedSeconds`): a source PTS or sentinel far ahead of
/// the wall clock (`596523:14:08`) falls back to wall time.
int normalizeLiveRecordedSeconds({required int rawMilliseconds, required int wallSeconds}) {
  final wall = wallSeconds < 0 ? 0 : wallSeconds;
  if (rawMilliseconds <= 0) return 0;
  final seconds = rawMilliseconds ~/ 1000;
  return seconds > wall + 15 ? wall : seconds;
}
