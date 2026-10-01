/// A short, persistable diagnostic of [value] without stream credentials
/// (3.x `RecorderDiagnostics.sanitize`): media URLs, cookies, authorization
/// and signing query values are replaced, control characters collapsed and
/// the text cut to [maxLength]. Tasks survive restarts and show their last
/// error, so raw exceptions with signed URLs must never be stored.
String sanitizeRecordDiagnostic(Object? value, {int maxLength = 320}) {
  var text = value?.toString() ?? '';
  text = text
      .replaceAll(RegExp(r'(?:https?|rtmps?|rtsp|srt|udp|rtp)://[^\s\]\)\}]+', caseSensitive: false), '[stream-url]')
      .replaceAll(RegExp(r'(?:(?:cookie|authorization)\s*[:=]\s*)[^\r\n]+', caseSensitive: false), '[credential]')
      .replaceAllMapped(
        RegExp(
          r'(^|[?&\s])((?:access_)?token|sign|auth|key|wssecret|txsecret)=([^&\s]+)',
          caseSensitive: false,
          multiLine: true,
        ),
        (match) => '${match.group(1)}${match.group(2)}=[redacted]',
      )
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.length > maxLength) text = '${text.substring(0, maxLength - 1)}…';
  return text;
}

/// FFmpeg log text with media URLs, cookie and authorization lines and
/// signing values redacted, keeping line structure (3.x
/// `FFmpegService._sanitizeLogs`).
String sanitizeFfmpegLog(String logs) => logs
    .replaceAll(RegExp(r'(?:https?|rtmps?|rtsp|srt|udp|rtp)://[^\s]+', caseSensitive: false), '[stream-url]')
    .replaceAllMapped(
      RegExp(r'^(cookie|authorization):.*$', caseSensitive: false, multiLine: true),
      (match) => '${match.group(1)}: [redacted]',
    )
    .replaceAllMapped(
      RegExp(r'((?:access_)?token|sign|auth|key|wssecret|txsecret)=([^&\s]+)', caseSensitive: false),
      (match) => '${match.group(1)}=[redacted]',
    );
