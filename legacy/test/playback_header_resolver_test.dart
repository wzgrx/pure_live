import 'package:pure_live/core/site/huya/huya_site.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/core/playback_header_resolver.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/common/services/settings/iptv_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';

void main() {
  test('Huya cold startup has the same native media headers as recording', () async {
    final previous = HuyaSite.playUserAgent;
    HuyaSite.playUserAgent = null;
    try {
      final playback = await PlaybackHeaderResolver.resolve(platform: 'huya', roomId: '123');
      final recording = await FFmpegHeaderFactory.build(platform: 'huya', roomId: '123');
      expect(playback['user-agent'], HuyaSite.nativePlayUserAgent);
      expect(recording, playback);
    } finally {
      HuyaSite.playUserAgent = previous;
    }
  });

  test('Douyu playback and recording share room-scoped anti-hotlink headers', () async {
    final playback = await PlaybackHeaderResolver.resolve(platform: 'DOUYU', roomId: '12345');
    final recording = await FFmpegHeaderFactory.build(platform: 'douyu', roomId: '12345');

    expect(playback, recording);
    expect(playback['origin'], 'https://www.douyu.com');
    expect(playback['referer'], 'https://www.douyu.com/12345');
    expect(playback['user-agent'], isNotEmpty);
    expect(playback['cookie'], contains('dy_did='));
    expect(playback['cookie'], contains('acf_did='));
  });

  test('YY gets browser origin headers and unknown platforms stay header-free', () async {
    final yy = await PlaybackHeaderResolver.resolve(platform: 'yy', roomId: '1');
    final unknown = await PlaybackHeaderResolver.resolve(platform: 'unknown', roomId: '1');

    expect(yy['origin'], 'https://www.yy.com');
    expect(yy['referer'], 'https://www.yy.com/');
    expect(yy['user-agent'], isNotEmpty);
    expect(unknown, isEmpty);
  });

  test('every built-in HTTP platform has a deterministic media origin profile', () async {
    final expectedOrigins = <String, String>{
      'bilibili': 'https://live.bilibili.com',
      'douyu': 'https://www.douyu.com',
      'huya': 'https://www.huya.com',
      'douyin': 'https://live.douyin.com',
      'kuaishou': 'https://live.kuaishou.com',
      'cc': 'https://cc.163.com',
      'twitch': 'https://www.twitch.tv',
      'soop': 'https://www.sooplive.co.kr',
      'yy': 'https://www.yy.com',
      'acfun': 'https://live.acfun.cn',
      'picarto': 'https://picarto.tv',
    };

    for (final entry in expectedOrigins.entries) {
      final headers = await PlaybackHeaderResolver.resolve(platform: entry.key, roomId: 'room 1');
      expect(headers['origin'], entry.value, reason: entry.key);
      expect(headers['referer'], isNotEmpty, reason: entry.key);
      expect(headers['user-agent'], isNotEmpty, reason: entry.key);
      expect(headers.keys, everyElement(matches(RegExp(r'^[a-z0-9-]+$'))), reason: entry.key);
      expect(headers.values, everyElement(isNot(contains('\n'))), reason: entry.key);
    }
  });

  test('AcFun uses anonymous media headers identically for playback and FFmpeg', () async {
    final playback = await PlaybackHeaderResolver.resolve(platform: 'acfun', roomId: '42');
    final recording = await FFmpegHeaderFactory.build(platform: 'acfun', roomId: '42');
    expect(recording, playback);
    expect(playback['referer'], 'https://live.acfun.cn/');
    expect(playback.containsKey('cookie'), isFalse);
  });

  test('IPTV channel headers override the global profile identically for playback and recording', () async {
    final settings = Get.put<SettingsService>(_HeaderSettings());
    addTearDown(() => Get.delete<SettingsService>(force: true));
    settings.iptv.customIptvUserAgent.value = 'Global Agent';
    const channelHeaders = <String, String>{
      'USER-AGENT': 'Playlist Agent',
      'Referrer': 'https://fixture/room',
      'Authorization': 'Bearer fixture',
      'X-Test': 'first\r\nsecond',
      'bad name': 'discarded',
    };
    final playback = await PlaybackHeaderResolver.resolve(
      platform: 'IPTV',
      roomId: 'channel',
      roomHeaders: channelHeaders,
    );
    final recording = await FFmpegHeaderFactory.build(platform: 'iptv', roomId: 'channel', roomHeaders: channelHeaders);

    expect(recording, playback);
    expect(playback, {
      'user-agent': 'Playlist Agent',
      'referer': 'https://fixture/room',
      'authorization': 'Bearer fixture',
      'x-test': 'first second',
    });
    final controllerHeaders = await PlayerController.resolvePlaybackHeaders(
      site: Site(id: Sites.iptvSite, name: 'IPTV', logo: '', liveSite: LiveSite()),
      room: LiveRoom(roomId: 'channel', platform: 'iptv', httpHeaders: channelHeaders),
    );
    expect(controllerHeaders, playback);
    expect(await PlaybackHeaderResolver.resolve(platform: 'iptv', roomHeaders: const {'Referer': 'https://fixture'}), {
      'referer': 'https://fixture',
      'user-agent': 'Global Agent',
    });
    expect(await PlaybackHeaderResolver.resolve(platform: 'unknown', roomHeaders: channelHeaders), isEmpty);
  });
}

class _HeaderSettings extends SettingsService {
  @override
  final iptv = _HeaderIptvSettings();

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _HeaderIptvSettings implements IptvSettingsController {
  @override
  final customIptvUserAgent = 'Global Agent'.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
