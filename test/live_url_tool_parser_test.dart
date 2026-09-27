import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';

void main() {
  final valid = <String, List<String>>{
    'https://live.bilibili.com/123?source=share': ['123', 'bilibili'],
    'HTTPS://LIVE.BILIBILI.COM/123': ['123', 'bilibili'],
    'https://www.huya.com/room-name?source=share': ['room-name', 'huya'],
    'https://www.douyu.com/123/': ['123', 'douyu'],
    'https://live.douyin.com/123/': ['123', 'douyin'],
    'https://live.kuaishou.com/u/profile_name?source=share': ['profile_name', 'kuaishou'],
    'https://live.kuaishou.cn/u/profile-name/': ['profile-name', 'kuaishou'],
    'https://cc.163.com/123?source=share': ['123', 'cc'],
    'https://www.twitch.tv/fixture_channel#chat': ['fixture_channel', 'twitch'],
    'https://play.sooplive.co.kr/fixture/456': ['fixture', 'soop'],
    'https://play.sooplive.com/fixture?source=share': ['fixture', 'soop'],
    'https://www.yy.com/123/456?tempId=789': ['123', 'yy'],
    'See https://example.org/article then https://live.acfun.cn/live/42': ['42', 'acfun'],
    'www.huya.com/fixture': ['fixture', 'huya'],
    'https://www.bilibili.com/123': ['123', 'bilibili'],
    'https://www.douyin.com/123?source=share': ['123', 'douyin'],
    'https://webcast.amemv.com/douyin/webcast/reflow/123?source=share': ['123', 'douyin'],
    'https://cc.163.com/channel123/': ['channel123', 'cc'],
    '“https://live.bilibili.com/123”。': ['123', 'bilibili'],
    'https://live.acfun.cn/search then https://www.huya.com/fixture': ['fixture', 'huya'],
    'https://www.huya.com/fixture then https://live.bilibili.com/123': ['fixture', 'huya'],
  };
  test('a Douyu alias resolves through its redirect (v4 bridge), not as a room id', () async {
    final http = _AliasRedirect();
    V4Bridge.instance = V4Bridge.withHttp(http);
    addTearDown(() => V4Bridge.instance = null);
    expect(await parseWithoutNetwork('https://www.douyu.com/fixtureAlias'), ['288016', 'douyu']);
    expect(http.requests.single.url.path, '/fixtureAlias');
  });
  for (final entry in valid.entries) {
    test('parses shared room identity: ${entry.key}', () async {
      expect(LiveUrlTool.containsSupportedLink(entry.key), isTrue);
      expect(await parseWithoutNetwork(entry.key), entry.value);
    });
  }
  for (final text in [
    'https://notbilibili.com/123',
    'https://www.huya.com.example.org/123',
    'https://example.org/?next=https://www.huya.com/123',
    'https://user@www.huya.com/123',
    'https://www.douyin.com/',
    'https://www.douyin.com/search/123?type=live',
    'https://www.douyin.com/video/123',
    'https://www.twitch.tv/directory',
    'https://www.huya.com/search?keyword=123',
    'ftp://www.huya.com/123',
    'https://live.bilibili.com/',
    'https://live.kuaishou.com/u/',
    'https://www.yy.com/',
    'https://live.acfun.cn/live/0',
    'https://live.bilibili.com/%FF',
    'https://live.bilibili.com/123%2F456',
    'https://example.org/?next=https://b23.tv/abc',
    'https://example.org/?next=https://v.douyin.com/abc',
    'https://b23.tv/',
    'https://v.douyin.com/',
    'https://www.huya.com/%00bad',
    'https://www.acfun.cn/u/42',
    'https://www.bilibili.com/video/BV123',
  ]) {
    test('ignores non-room or ambiguous input: $text', () async {
      expect(await parseWithoutNetwork(text), isEmpty);
    });
  }
  for (final locale in ['zh', 'en']) {
    test('$locale toolbox help includes the supported AcFun room format', () async {
      final content = jsonDecode(await File('assets/translations/$locale.json').readAsString()) as Map<String, dynamic>;
      expect(content['toolbox_support_content'], contains('https://live.acfun.cn/live/123456'));
    });
  }
}

Future<List<String>> parseWithoutNetwork(String text) async {
  var attempts = 0;
  final result = await HttpOverrides.runZoned(
    () => LiveUrlTool.parseLiveUrl(text),
    createHttpClient: (_) {
      attempts++;
      throw StateError('Unexpected network access in direct URL parsing');
    },
  );
  expect(attempts, 0, reason: text);
  return result;
}

/// Answers the alias page with the relative redirect Douyu sends.
final class _AliasRedirect implements LiveHttp {
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    return LiveResponse(
      status: 302,
      bytes: const [],
      url: request.url,
      headers: const {
        'location': ['/288016'],
      },
    );
  }

  @override
  void close() {}
}
