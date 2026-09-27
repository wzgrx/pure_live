import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_http_body_metadata.dart';
import 'package:pure_live/recorder/services/hls_retained_window.dart';

void main() {
  test('whole and decompressed responses retain only replayable metadata', () {
    final whole = HlsHttpBodyMetadata.validate(
      statusCode: 200,
      contentLength: 3,
      contentType: 'video/mp4',
      acceptRanges: 'bytes',
    );
    expect(whole.statusCode, 200);
    expect(whole.expectedLength, 3);
    expect(whole.contentType, 'video/mp4');
    expect(whole.acceptRanges, 'bytes');
    expect(whole.contentRange, isNull);
    final decoded = HlsHttpBodyMetadata.validate(
      statusCode: 200,
      contentLength: 20,
      contentEncoding: 'gzip',
      decompressed: true,
    );
    expect(decoded.expectedLength, -1);
    expect(HlsHttpBodyMetadata.validate(statusCode: 200, contentLength: -1).expectedLength, -1);
  });
  test('exact range seals against range length even when transfer length is unknown', () {
    for (final total in ['100', '*']) {
      final metadata = HlsHttpBodyMetadata.validate(
        statusCode: 206,
        contentLength: -1,
        contentRange: 'bytes 10-12/$total',
        requestedRange: const HlsSegmentRange(10, 3),
      );
      expect(metadata.expectedLength, 3);
      expect(metadata.contentRange, 'bytes 10-12/$total');
    }
  });
  for (final bad in [
    'bytes 11-13/100',
    'bytes 10-11/100',
    'bytes 10-12/12',
    'bytes 10-12/9223372036854775808',
    'bytes 10-12/-1',
    'bytes */100',
    'bytes 10-12/100, bytes 20-22/100',
    'garbage',
  ]) {
    test('reject mismatched range: $bad', () {
      expect(
        () => HlsHttpBodyMetadata.validate(
          statusCode: 206,
          contentLength: 3,
          contentRange: bad,
          requestedRange: const HlsSegmentRange(10, 3),
        ),
        throwsFormatException,
      );
    });
  }
  test('HTTP success alone is not proof of an exact cache identity', () {
    for (final status in [206, 204, 301, 403, 410, 500]) {
      expect(() => HlsHttpBodyMetadata.validate(statusCode: status, contentLength: 3), throwsFormatException);
    }
    expect(
      () =>
          HlsHttpBodyMetadata.validate(statusCode: 200, contentLength: 3, requestedRange: const HlsSegmentRange(10, 3)),
      throwsFormatException,
    );
    expect(
      () => HlsHttpBodyMetadata.validate(
        statusCode: 206,
        contentLength: 4,
        contentRange: 'bytes 10-12/100',
        requestedRange: const HlsSegmentRange(10, 3),
      ),
      throwsFormatException,
    );
    expect(
      () => HlsHttpBodyMetadata.validate(statusCode: 200, contentLength: 3, contentRange: 'bytes 0-2/3'),
      throwsFormatException,
    );
  });
  test('encoded range or undecoded whole response is not published as media bytes', () {
    expect(
      () => HlsHttpBodyMetadata.validate(statusCode: 200, contentLength: 3, contentEncoding: 'gzip'),
      throwsFormatException,
    );
    for (final decompressed in [true, false]) {
      expect(
        () => HlsHttpBodyMetadata.validate(
          statusCode: 206,
          contentLength: 3,
          contentRange: 'bytes 10-12/100',
          contentEncoding: 'gzip',
          decompressed: decompressed,
          requestedRange: const HlsSegmentRange(10, 3),
        ),
        throwsFormatException,
      );
    }
  });
  test('length, integer overflow and header retention are bounded before staging', () {
    for (final range in [
      const HlsSegmentRange(-1, 3),
      const HlsSegmentRange(0, 0),
      const HlsSegmentRange(0x7ffffffffffffffe, 3),
    ]) {
      expect(() => HlsHttpBodyMetadata.validateRequestRange(range), throwsFormatException);
    }
    expect(() => HlsHttpBodyMetadata.validate(statusCode: 200, contentLength: -2), throwsFormatException);
    for (final type in ['x' * 4097, 'video/mp4\r\nInjected: yes']) {
      expect(
        () => HlsHttpBodyMetadata.validate(statusCode: 200, contentLength: 3, contentType: type),
        throwsFormatException,
      );
    }
  });
}
