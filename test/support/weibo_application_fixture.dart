import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:pure_live/core/site/weibo/weibo_api.dart';
import 'package:pure_live/core/site/weibo/weibo_site.dart';
import 'package:pure_live/core/sites.dart';

const weiboFixtureId = '1022:2321325000000000000000';
const weiboFixtureWatch = 'https://weibo.com/l/wblive/p/show/$weiboFixtureId';

Map<String, dynamic> weiboFixture(String name) =>
    jsonDecode(File('test/fixtures/weibo/$name.json').readAsStringSync()) as Map<String, dynamic>;

class WeiboApplicationFixture {
  final requests = <Uri>[];
  int directoryCalls = 0;
  int detailCalls = 0;
  bool failDirectory = false;
  bool emptyDirectory = false;
  int status = 1;
  int watchLimit = 0;

  late final adapter = WeiboSite(api: WeiboApi(request: _request));
  Site get site => Site(id: 'weibo', name: 'Weibo', logo: 'assets/images/logo.png', liveSite: adapter);

  Future<({int status, String body})> _request(
    String method,
    Uri uri,
    Map<String, String>? form,
    CancelToken cancel,
  ) async {
    requests.add(uri);
    if (uri.path.contains('pc_recommend')) {
      directoryCalls++;
      if (failDirectory) return (status: 503, body: '');
      final payload = weiboFixture('recommend');
      final data = payload['data'] as Map;
      if (emptyDirectory) data['data'] = [];
      for (final row in data['data'] as List) {
        (row as Map)['cover'] = '';
      }
      return (status: 200, body: jsonEncode(payload));
    }
    if (!uri.path.endsWith('show_pc_live.json')) throw StateError('Unexpected fixture request: $method $uri');
    detailCalls++;
    final payload = weiboFixture('live-detail');
    final data = payload['data'] as Map;
    data['status'] = status;
    data['watch_limit'] = watchLimit;
    data['cover'] = '';
    (data['user'] as Map)['profileImageUrl'] = '';
    (data['user'] as Map)['avatar'] = '';
    final url = 'https://media.example.test/source-$detailCalls.flv?token=fixture$detailCalls';
    data['live_origin_hls_url'] = url;
    data['live_origin_flv_url'] = url;
    return (status: 200, body: jsonEncode(payload));
  }
}
