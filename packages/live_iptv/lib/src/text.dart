import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Decodes playlist bytes that are not UTF-8 (3.x fell back to GBK through
/// the `charset_converter` plugin). Pure Dart has no GBK codec, so the app
/// supplies one; throw [FormatException] when the bytes cannot be decoded.
typedef IptvLegacyDecoder = FutureOr<String> Function(Uint8List bytes);

/// Text of a playlist: a UTF-8 BOM is dropped; bytes that are not UTF-8 go
/// to [legacy] (GBK in the app), or fail with [FormatException] without one.
Future<String> decodePlaylistBytes(Uint8List bytes, {IptvLegacyDecoder? legacy}) async {
  final body = _withoutUtf8Bom(bytes);
  try {
    return utf8.decode(body);
  } on FormatException {
    if (legacy == null) rethrow;
    return _withoutBomChar(await legacy(body));
  }
}

/// Text of a programme guide: gzip is detected by its magic bytes (3.x
/// only unpacked files named `.gz`), an XML declaration of ISO-8859-1 is
/// honoured, everything else must be strict UTF-8 so a broken file fails
/// before saved data is replaced.
String decodeGuideBytes(List<int> bytes) {
  var data = bytes;
  if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) data = gzip.decode(data);
  final head = latin1.decode(data.take(512).toList());
  final declaredLatin1 = RegExp(
    r'''^\s*<\?xml\b[^>]*\bencoding\s*=\s*["'](?:iso-8859-1|latin1)["']''',
    caseSensitive: false,
  ).hasMatch(head);
  if (declaredLatin1) return latin1.decode(data);
  return _withoutBomChar(utf8.decode(_withoutUtf8Bom(data)));
}

Uint8List _withoutUtf8Bom(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  return data.length >= 3 && data[0] == 0xef && data[1] == 0xbb && data[2] == 0xbf ? data.sublist(3) : data;
}

String _withoutBomChar(String text) => text.startsWith('\uFEFF') ? text.substring(1) : text;
