import 'dart:developer';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/dialogs/live_dlna_dialog.dart';
import 'package:pure_live/modules/search/web_search_room_parser.dart';

class LiveUrlTool {
  /// Extract complete HTTP URLs before inspecting host/path. This also avoids
  /// treating an embedded www address in an FTP URL as a second HTTP link.
  static Iterable<Uri> sharedHttpUris(String text) sync* {
    final urls = RegExp(r'(?:[a-z][a-z0-9+.-]*://|www\.)[^\s<>]+', caseSensitive: false);
    for (final match in urls.allMatches(text)) {
      var candidate = match.group(0)!.replaceFirst(RegExp(r'''[.,!?;:)\]}。！？、，；：）》」』”’"']+$'''), '');
      if (candidate.toLowerCase().startsWith('www.')) candidate = 'https://$candidate';
      final uri = Uri.tryParse(candidate);
      if (uri == null ||
          uri.userInfo.isNotEmpty ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        continue;
      }
      yield uri;
    }
  }

  static bool _hostIs(String host, String root) => host == root || host.endsWith('.$root');

  static bool containsSupportedLink(String text) {
    const roots = {
      'bilibili.com',
      'b23.tv',
      'douyu.com',
      'huya.com',
      'douyin.com',
      'webcast.amemv.com',
      'live.kuaishou.com',
      'live.kuaishou.cn',
      'cc.163.com',
      'twitch.tv',
      'sooplive.com',
      'sooplive.co.kr',
      'yy.com',
      'live.acfun.cn',
    };
    return sharedHttpUris(text).any((uri) => roots.any((root) => _hostIs(uri.host.toLowerCase(), root)));
  }

  static Future<List<String>> parseLiveUrl(String text) async {
    for (final uri in sharedHttpUris(text)) {
      final host = uri.host.toLowerCase();
      final realUrl = uri.toString();
      late List<String> segments;
      try {
        segments = uri.pathSegments.where((part) => part.isNotEmpty).toList(growable: false);
      } on FormatException {
        continue;
      }
      if (segments.isEmpty) continue;
      if (_hostIs(host, 'b23.tv')) {
        final location = await _getRedirectLocation(realUrl);
        final target = await parseLiveUrl(location);
        if (target.isNotEmpty) return target;
        continue;
      }
      if (host == 'v.douyin.com') {
        final id = await _getRealDouyinRoomId(realUrl);
        if (id.isNotEmpty) return [id, Sites.douyinSite];
        continue;
      }
      final target = WebSearchRoomParser.parse(realUrl);
      if (target != null) return [target.roomId, target.platform];
      // Preserve manual-tool aliases not exposed by the web-search parser.
      String? platform;
      String? id;
      var pattern = RegExp(r'^[a-zA-Z0-9_-]+$');
      if (_hostIs(host, 'bilibili.com')) {
        platform = Sites.bilibiliSite;
        id = segments.first;
        pattern = RegExp(r'^\d+$');
      } else if (_hostIs(host, 'douyu.com')) {
        platform = Sites.douyuSite;
        id = segments.first;
      } else if (host == 'www.douyin.com') {
        platform = Sites.douyinSite;
        id = segments.last;
      } else if (host == 'webcast.amemv.com') {
        platform = Sites.douyinSite;
        id = RegExp(r'(?:^|/)reflow/(\d+)(?:/|$)').firstMatch(uri.path)?.group(1);
      } else if (host == 'live.kuaishou.cn' && segments.length >= 2 && segments.first == 'u') {
        platform = Sites.kuaishouSite;
        id = segments[1];
      } else if (host == 'cc.163.com') {
        platform = Sites.ccSite;
        id = segments.first;
      } else if (_hostIs(host, 'sooplive.com')) {
        platform = Sites.soopSite;
        id = segments.first;
      }
      if (platform != null && id != null && WebSearchRoomParser.isRoomIdentifier(id, pattern)) {
        return [id, platform];
      }
    }
    return [];
  }

  /// 获取直播播放直链
  /// [liveUrl] 直播间链接
  static Future<void> getLivePlayUrl(String liveUrl) async {
    if (liveUrl.isEmpty) {
      ToastUtil.show(i18n("toolbox_empty_link"));
      return;
    }

    // 1. 解析链接
    List<String> parseResult = await parseLiveUrl(liveUrl);
    if (parseResult.length < 2 || parseResult[0].isEmpty) {
      ToastUtil.show(i18n("toolbox_parse_failed"));
      return;
    }

    String roomId = parseResult[0];
    String platform = parseResult[1];

    try {
      // 2. 获取房间详情
      SmartDialog.showLoading(msg: "");
      final detail = await Sites.of(platform).liveSite.getRoomDetail(roomId: roomId, platform: platform);

      // 3. 获取清晰度列表
      final qualities = await Sites.of(platform).liveSite.getPlayQualites(detail: detail);
      SmartDialog.dismiss(status: SmartStatus.loading);

      if (qualities.isEmpty) {
        ToastUtil.show(i18n("toolbox_quality_failed"));
        return;
      }

      // 4. 选择清晰度
      final selectedQuality = await Get.dialog(
        SimpleDialog(
          title: Text(i18n("toolbox_select_quality")),
          children: qualities
              .map(
                (e) => ListTile(
                  title: Text(e.quality, textAlign: TextAlign.center),
                  onTap: () => Navigator.pop(Get.context!, e),
                ),
              )
              .toList(),
        ),
      );
      if (selectedQuality == null) return;

      // 5. 获取播放线路
      SmartDialog.showLoading(msg: "");
      final playUrls = await Sites.of(platform).liveSite.getPlayUrls(detail: detail, quality: selectedQuality);
      SmartDialog.dismiss(status: SmartStatus.loading);

      // 6. 选择线路并复制
      await Get.dialog(
        SimpleDialog(
          title: Text(i18n("toolbox_select_line")),
          children: playUrls
              .asMap()
              .entries
              .map(
                (entry) => ListTile(
                  title: Text(i18n("toolbox_line", args: {"index": "${entry.key + 1}"})),
                  subtitle: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: entry.value));
                    Navigator.pop(Get.context!);
                    ToastUtil.show(i18n("toolbox_copy_success"));
                  },
                ),
              )
              .toList(),
        ),
      );
    } catch (e) {
      log("获取直链失败: $e", name: "LiveUrlTool");
      ToastUtil.show(i18n("toolbox_get_url_failed"));
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  static Future<String> _getRedirectLocation(String url) async {
    try {
      await dio.Dio().get(url, options: dio.Options(followRedirects: false));
    } on dio.DioException catch (e) {
      if (e.response?.statusCode == 302) {
        return e.response?.headers.value("Location") ?? "";
      }
    } catch (e) {
      log(e.toString(), name: "_getRedirectLocation");
    }
    return "";
  }

  static Future<String> _getRealDouyinRoomId(String url) async {
    try {
      final headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "*/*",
        "Origin": "https://live.douyin.com",
        "Referer": "https://live.douyin.com/",
      };

      final resp = await dio.Dio().get(
        url,
        options: dio.Options(followRedirects: true, headers: headers, maxRedirects: 100),
      );

      final reg = RegExp(r"reflow/(\d+)");
      String? roomId = reg.firstMatch(resp.realUri.toString())?.group(1);
      if (roomId == null) return "";

      final infoResp = await dio.Dio().get(
        "https://webcast.amemv.com/webcast/room/reflow/info/",
        queryParameters: {
          "room_id": roomId,
          'verifyFp': '',
          'type_id': 0,
          'live_id': 1,
          'sec_user_id': '',
          'app_id': 1128,
        },
      );

      return infoResp.data['data']['room']['owner']['web_rid']?.toString() ?? "";
    } catch (e) {
      log(e.toString(), name: "_getRealDouyinRoomId");
      return "";
    }
  }

  static Future<void> getPlayUrlByRoomId({required String roomId, required String platform}) async {
    if (roomId.isEmpty || platform.isEmpty) {
      ToastUtil.show(i18n("toolbox_empty_link"));
      return;
    }
    try {
      SmartDialog.showLoading(msg: "");

      final detail = await Sites.of(platform).liveSite.getRoomDetail(roomId: roomId, platform: platform);

      final qualities = await Sites.of(platform).liveSite.getPlayQualites(detail: detail);
      SmartDialog.dismiss(status: SmartStatus.loading);

      if (qualities.isEmpty) {
        ToastUtil.show(i18n("toolbox_quality_failed"));
        return;
      }

      final selectedQuality = await Get.dialog(
        SimpleDialog(
          title: Text(i18n("toolbox_select_quality")),
          children: qualities
              .map(
                (e) => ListTile(
                  title: Text(e.quality, textAlign: TextAlign.center),
                  onTap: () => Navigator.pop(Get.context!, e),
                ),
              )
              .toList(),
        ),
      );
      if (selectedQuality == null) return;

      SmartDialog.showLoading(msg: "");
      final playUrls = await Sites.of(platform).liveSite.getPlayUrls(detail: detail, quality: selectedQuality);
      SmartDialog.dismiss(status: SmartStatus.loading);

      await Get.dialog(
        SimpleDialog(
          title: Text(i18n("toolbox_select_line")),
          children: playUrls
              .asMap()
              .entries
              .map(
                (entry) => ListTile(
                  title: Text(i18n("toolbox_line", args: {"index": "${entry.key + 1}"})),
                  subtitle: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: entry.value));
                    Navigator.pop(Get.context!);
                    ToastUtil.show(i18n("toolbox_copy_success"));
                  },
                ),
              )
              .toList(),
        ),
      );
    } catch (e) {
      log("已知房间号获取直链失败: $e", name: "LiveUrlTool");
      ToastUtil.show(i18n("toolbox_get_url_failed"));
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  static Future<void> castPlayUrlByRoomId({required String roomId, required String platform}) async {
    if (roomId.isEmpty || platform.isEmpty) {
      ToastUtil.show(i18n("toolbox_empty_link"));
      return;
    }

    try {
      SmartDialog.showLoading(msg: "");
      final detail = await Sites.of(platform).liveSite.getRoomDetail(roomId: roomId, platform: platform);

      final qualities = await Sites.of(platform).liveSite.getPlayQualites(detail: detail);
      SmartDialog.dismiss(status: SmartStatus.loading);

      if (qualities.isEmpty) {
        ToastUtil.show(i18n("toolbox_quality_failed"));
        return;
      }

      final selectedQuality = await Get.dialog(
        SimpleDialog(
          title: Text(i18n("toolbox_select_quality")),
          children: qualities
              .map(
                (e) => ListTile(
                  title: Text(e.quality, textAlign: TextAlign.center),
                  onTap: () {
                    Navigator.pop(Get.context!, e);
                  },
                ),
              )
              .toList(),
        ),
      );
      if (selectedQuality == null) return;

      SmartDialog.showLoading(msg: "");
      final playUrls = await Sites.of(platform).liveSite.getPlayUrls(detail: detail, quality: selectedQuality);
      SmartDialog.dismiss(status: SmartStatus.loading);

      if (playUrls.isEmpty) {
        ToastUtil.show(i18n("toolbox_get_url_failed"));
        return;
      }

      final selectedUrl = await Get.dialog(
        SimpleDialog(
          title: Text(i18n("toolbox_select_line")),
          children: playUrls
              .asMap()
              .entries
              .map(
                (entry) => ListTile(
                  title: Text(i18n("toolbox_line", args: {"index": "${entry.key + 1}"})),
                  subtitle: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(Get.context!, entry.value);
                  },
                ),
              )
              .toList(),
        ),
      );

      // 选中url后直接投屏
      if (selectedUrl != null && selectedUrl.isNotEmpty) {
        Get.dialog(LiveDlnaPage(datasource: selectedUrl));
      }
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      ToastUtil.show(i18n("toolbox_get_url_failed"));
    }
  }
}

extension StringTrim on String {
  String trimEndChar(String char) {
    if (endsWith(char)) return substring(0, length - 1);
    return this;
  }
}
