import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';

class ToolBoxController extends GetxController {
  ToolBoxController() {
    roomJumpToController.addListener(_roomEdited);
    getUrlController.addListener(_urlEdited);
  }

  final TextEditingController roomJumpToController = TextEditingController();
  final TextEditingController getUrlController = TextEditingController();
  int _roomRevision = 0;
  int _urlRevision = 0;
  bool _clipboardChecked = false;
  bool _disposed = false;

  void _roomEdited() => _roomRevision++;
  void _urlEdited() => _urlRevision++;

  @override
  void onReady() {
    super.onReady();
    unawaited(autoCheckClipboard());
  }

  Future<void> jumpToRoom(String e) async {
    if (e.isEmpty) {
      ToastUtil.show(i18n("toolbox_empty_link"));
      return;
    }
    var parseResult = await LiveUrlTool.parseLiveUrl(e);
    if (parseResult.isEmpty || parseResult.first == "") {
      ToastUtil.show(i18n("toolbox_parse_failed"));
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();

    final platform = parseResult[1];
    await AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(
        roomId: parseResult.first,
        platform: platform,
        title: "",
        cover: '',
        nick: "",
        watching: '',
        avatar: "",
        area: '',
        liveStatus: LiveStatus.live,
        status: true,
        data: '',
        danmakuData: '',
      ),
    );
  }

  void getPlayUrl(String e) async {
    await LiveUrlTool.getLivePlayUrl(e);
  }

  Future<void> autoCheckClipboard() async {
    if (_disposed || isClosed || _clipboardChecked) return;
    _clipboardChecked = true;
    final roomEmpty = roomJumpToController.text.isEmpty;
    final urlEmpty = getUrlController.text.isEmpty;
    if (!roomEmpty && !urlEmpty) return;
    final roomRevision = _roomRevision;
    final urlRevision = _urlRevision;
    ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
    if (_disposed || isClosed) return;
    final text = data?.text;
    if (text == null || !containsSupportedLink(text)) return;

    // A type-and-clear is still an edit: checking only the current text would
    // silently refill a field the user deliberately cleared while we waited.
    final fillRoom = roomEmpty && _roomRevision == roomRevision;
    final fillUrl = urlEmpty && _urlRevision == urlRevision;
    if (fillRoom || fillUrl) {
      if (fillRoom) roomJumpToController.text = text;
      if (fillUrl) getUrlController.text = text;
      Get.snackbar(
        i18n("toolbox_detect_link"),
        i18n("toolbox_auto_fill"),
        snackPosition: SnackPosition.bottom,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(15),
      );
    }
  }

  /// Local detection only; resolving a short link waits for a user action.
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
    final urls = RegExp(r'(?:[a-z][a-z0-9+.-]*://|www\.)[^\s<>]+', caseSensitive: false);
    for (final match in urls.allMatches(text)) {
      var candidate = match.group(0)!;
      if (candidate.toLowerCase().startsWith('www.')) candidate = 'https://$candidate';
      final uri = Uri.tryParse(candidate);
      if (uri == null || uri.userInfo.isNotEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) continue;
      final host = uri.host.toLowerCase();
      if (roots.any((root) => host == root || host.endsWith('.$root'))) return true;
    }
    return false;
  }

  @override
  void onClose() {
    _disposed = true;
    roomJumpToController.removeListener(_roomEdited);
    getUrlController.removeListener(_urlEdited);
    roomJumpToController.dispose();
    getUrlController.dispose();
    super.onClose();
  }
}
