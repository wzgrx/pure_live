import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

/// A quality the playurl answer offers (`support_formats`).
@immutable
final class VodQuality {
  /// Creates a quality.
  const new({required this.qn, required this.label, this.needsVip = false, this.needsLogin = false});

  /// Quality id (`qn`): 16 360P, 32 480P, 64 720P, 80 1080P, 112 1080P+,
  /// 116 1080P60, 120 4K, 125 HDR, 126 Dolby Vision, 127 8K.
  final int qn;

  /// The platform's label (`new_description`), or [labelOf].
  final String label;

  /// Only members (大会员) get it.
  final bool needsVip;

  /// Only signed-in users get it.
  final bool needsLogin;

  /// Chinese label of a quality id when the answer has none.
  static String labelOf(int qn) => switch (qn) {
    127 => '8K 超高清',
    126 => '杜比视界',
    125 => 'HDR 真彩色',
    120 => '4K 超清',
    116 => '1080P 60帧',
    112 => '1080P 高码率',
    80 => '1080P 高清',
    74 => '720P 60帧',
    64 => '720P 高清',
    32 => '480P 清晰',
    16 => '360P 流畅',
    6 => '240P 极速',
    _ => '$qn',
  };
}

/// One DASH rendition (video or audio): a byte-range MP4 (m4s) with backup
/// hosts.
@immutable
final class VodRendition {
  /// Creates a rendition.
  const new({
    required this.id,
    required this.url,
    this.backupUrls = const [],
    this.codecs = '',
    this.bandwidth = 0,
    this.width = 0,
    this.height = 0,
    this.frameRate = '',
  });

  /// Quality id for video, audio id for audio (30216 64K, 30232 132K,
  /// 30280 192K, 30250 Dolby, 30251 Hi-Res).
  final int id;

  /// Main URL.
  final String url;

  /// Backup URLs, other CDN hosts.
  final List<String> backupUrls;

  /// RFC 6381 codecs, e.g. `avc1.64001F`, `hev1.1.6.L120.90`, `mp4a.40.2`.
  final String codecs;

  /// Bits per second.
  final int bandwidth;

  /// Video width; 0 for audio.
  final int width;

  /// Video height; 0 for audio.
  final int height;

  /// Frame rate text.
  final String frameRate;

  /// `avc`, `hevc`, `av1`, `aac`, `ec-3`, `flac`, or the raw codecs.
  String get codec => switch (codecs.split('.').first.toLowerCase()) {
    'avc1' || 'avc3' => 'avc',
    'hev1' || 'hvc1' => 'hevc',
    'av01' => 'av1',
    'mp4a' => 'aac',
    'ec-3' => 'ec-3',
    'flac' || 'fLaC' => 'flac',
    final other => other,
  };

  /// Every URL, main first.
  List<String> get urls => [url, ...backupUrls];
}

/// One `durl` segment: a complete MP4/FLV with audio and video.
@immutable
final class VodSegment {
  /// Creates a segment.
  const new({
    required this.url,
    this.backupUrls = const [],
    this.order = 1,
    this.length = Duration.zero,
    this.size = 0,
  });

  /// Main URL.
  final String url;

  /// Backup URLs.
  final List<String> backupUrls;

  /// 1-based order.
  final int order;

  /// Length.
  final Duration length;

  /// Bytes.
  final int size;
}

/// What one playurl answer offers for one part (UGC or PGC).
///
/// DASH answers keep video and audio apart: the player opens one video
/// rendition and attaches one audio rendition (mpv `audio-files`). `durl`
/// answers are muxed MP4 files. Every request to the media hosts must carry
/// [headers]: without a Referer the CDN answers 403, and the COS hosts also
/// answer 403 to FFmpeg's own `Lavf` user agent (M14.0).
@immutable
final class VodStreams {
  /// Creates the streams.
  const new({
    required this.quality,
    required this.headers,
    this.qualities = const [],
    this.duration = Duration.zero,
    this.videos = const [],
    this.audios = const [],
    this.dolbyAudio,
    this.flacAudio,
    this.segments = const [],
    this.isPreview = false,
    this.needsVip = false,
    this.expiresAt,
  });

  /// The quality the server applied.
  final int quality;

  /// Every quality the answer names, best first.
  final List<VodQuality> qualities;

  /// Full length of the part (a preview plays less, see [isPreview]).
  final Duration duration;

  /// DASH video renditions, best quality first.
  final List<VodRendition> videos;

  /// DASH audio renditions, best first.
  final List<VodRendition> audios;

  /// Dolby audio, when offered.
  final VodRendition? dolbyAudio;

  /// Hi-Res (FLAC) audio, when offered.
  final VodRendition? flacAudio;

  /// Muxed `durl` segments (MP4 route or PGC previews).
  final List<VodSegment> segments;

  /// Only a preview is playable (PGC `is_preview`, member-only episodes for
  /// non-members: about three minutes).
  final bool isPreview;

  /// The episode needs a membership (`status` 13 or `error_code` -10403).
  final bool needsVip;

  /// Media request headers: browser UA, the page as Referer, the login
  /// cookie when there is one.
  final Map<String, String> headers;

  /// When the URLs stop working (`deadline`), if known.
  final DateTime? expiresAt;

  /// Whether this is a DASH answer.
  bool get isDash => videos.isNotEmpty || audios.isNotEmpty;

  /// The best audio: Hi-Res, then Dolby when [lossless]/[dolby] allow, else
  /// the highest bandwidth AAC.
  VodRendition? bestAudio({bool lossless = false, bool dolby = false}) {
    if (lossless && flacAudio != null) return flacAudio;
    if (dolby && dolbyAudio != null) return dolbyAudio;
    if (audios.isEmpty) return flacAudio ?? dolbyAudio;
    return audios.reduce((a, b) => b.bandwidth > a.bandwidth ? b : a);
  }

  /// The video rendition for [qn] (the best one at or below it when absent),
  /// preferring [codecs] in order (default AVC, HEVC, AV1 — AVC decodes in
  /// hardware almost everywhere).
  VodRendition? videoFor(int qn, {List<String> codecs = const ['avc', 'hevc', 'av1']}) {
    if (videos.isEmpty) return null;
    final ids = {for (final video in videos) video.id}.toList()..sort((a, b) => b.compareTo(a));
    final target = ids.firstWhere((id) => id <= qn, orElse: () => ids.last);
    final candidates = [
      for (final video in videos)
        if (video.id == target) video,
    ];
    for (final codec in codecs) {
      for (final video in candidates) {
        if (video.codec == codec) return video;
      }
    }
    return candidates.first;
  }

  /// [rendition] as play lines, one per URL, with [headers] and the expiry.
  /// The line id is the CDN code (`os=`), like the live lines.
  List<LivePlayLine> linesOf(VodRendition rendition) => [
    for (final url in rendition.urls) _line(url, codec: rendition.codec),
  ];

  /// The muxed segment's URLs as play lines.
  List<LivePlayLine> linesOfSegment(VodSegment segment) => [
    for (final url in [segment.url, ...segment.backupUrls]) _line(url),
  ];

  LivePlayLine _line(String url, {String? codec}) {
    final uri = Uri.tryParse(url);
    final cdn = uri?.queryParameters['os'];
    final expires = expiresAt;
    return LivePlayLine(
      url,
      headers: headers,
      format: StreamFormat.other,
      codec: codec == 'avc' || codec == 'hevc' ? codec : null,
      lineId: cdn == null ? uri?.host : '$cdn@${uri!.host}',
      lease: expires == null
          ? null
          : PlayLease(refreshAt: expires.subtract(const Duration(minutes: 5)), expiresAt: expires),
    );
  }
}
