import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/fonts/fonts.dart';

final _ttf = Uint8List.fromList([0, 1, 0, 0, ...List.filled(60, 7)]);

/// jsDelivr fails, fastly answers with HTML, GitHub has the font.
final class _Http implements LiveHttp {
  final requests = <Uri>[];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request.url);
    final host = request.url.host;
    if (host == 'cdn.jsdelivr.net') throw const TransportFailure('fonts', TransportReason.timeout);
    if (host == 'fastly.jsdelivr.net') return LiveResponse(status: 200, bytes: utf8.encode('<html>'), url: request.url);
    return LiveResponse(status: 200, bytes: _ttf, url: request.url);
  }

  @override
  void close() {}
}

void main() {
  const font = FontEntry(id: 'demo', name: '示例', files: ['demo/Demo-Regular.ttf'], licenseName: 'SIL OFL 1.1');

  test('F-DM-06: the catalogue only lists fonts with a clear licence', () {
    final list = jsonDecode(File('assets/fonts/fonts.json').readAsStringSync()) as List<Object?>;
    final fonts = [for (final item in list) FontEntry.fromJson(item! as Map<String, Object?>)];
    expect(fonts, isNotEmpty);
    expect(fonts.map((font) => font.licenseName).toSet(), {'SIL OFL 1.1', 'IPA Font License 1.0'});
    expect(fonts.every((font) => font.files.every((file) => file.endsWith('.ttf') || file.endsWith('.otf'))), isTrue);
  });

  test('F-DM-06: a download tries the sources in order and keeps only a real font', () async {
    final temp = await Directory.systemTemp.createTemp('fonts-');
    addTearDown(() => temp.delete(recursive: true));
    final http = _Http();
    final files = FontFiles(temp, http);
    final progress = <double>[];
    expect(await files.installed(font), isFalse);
    await files.download(font, progress: progress.add);
    expect(http.requests.map((url) => url.host), [
      'cdn.jsdelivr.net',
      'fastly.jsdelivr.net',
      'raw.githubusercontent.com',
    ]);
    expect(await files.installed(font), isTrue);
    expect(progress, [1.0]);
    await files.delete(font);
    expect(await files.installed(font), isFalse);
  });

  test('font checks and names', () {
    expect(looksLikeFont(_ttf), isTrue);
    expect(looksLikeFont(Uint8List.fromList(utf8.encode('OTTO and more bytes'))), isTrue);
    expect(looksLikeFont(Uint8List.fromList(utf8.encode('<html><body>'))), isFalse);
    expect(familyForSetting(''), isNull);
    expect(familyForSetting('judousansui'), 'PureLive-judousansui');
    expect(
      fontSources('a b/c.ttf').first.toString(),
      'https://cdn.jsdelivr.net/gh/liuchuancong/fonts@master/a%20b/c.ttf',
    );
  });

  test("3.x's font names map to font ids", () {
    Object? convert(Setting<Object> setting, String key, Object? value) =>
        setting.decode(setting.legacy.firstWhere((legacy) => legacy.name == key).apply(value));
    expect(convert(Settings.appFontFamily, 'fontFamilyName', 'Default'), '');
    expect(convert(Settings.appFontFamily, 'fontFamilyName', 'judousansui'), 'judousansui');
    expect(convert(Settings.danmakuFontFamily, 'danmakuFontFamilyName', '../evil'), '');
  });
}
