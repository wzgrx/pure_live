import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_tls_trust_store.dart';

void main() {
  test('reviewed Mozilla CA asset matches its pinned digest and contains roots', () async {
    final bytes = await File(FFmpegTlsTrustStore.assetPath).readAsBytes();
    final text = String.fromCharCodes(bytes);

    expect(sha256.convert(bytes).toString(), FFmpegTlsTrustStore.bundleSha256);
    expect(RegExp('-----BEGIN CERTIFICATE-----').allMatches(text).length, greaterThan(100));
    expect(text, contains('Certificate data from Mozilla as of: Thu Aug 13 03:12:01 2026 GMT'));
  });
}
