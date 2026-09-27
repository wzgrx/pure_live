import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/web/cookie_text.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/account_status.dart';
import 'package:pure_live_app/features/accounts/douyu_account.dart';

/// Where to copy the cookie from, per platform.
const _cookieTips = {
  'douyu': '在电脑浏览器登录 www.douyu.com 后，从开发者工具里复制请求头中的 Cookie 粘贴到下面。要能续期，再复制 passport.douyu.com 请求的 Cookie（含 LTP0）粘贴进来，应用会取出 LTP0 和 dy_did。',
  'twitch': '在电脑浏览器登录 twitch.tv 后复制 Cookie。只会用到其中的 auth-token，用于订阅专属直播和免广告。',
  'soop': '在电脑浏览器登录 sooplive.co.kr 后复制 Cookie。只在打开 19 禁直播时随取流请求发送。',
};

/// Pastes a cookie by hand (F-ACC-01). The stored cookie is never shown
/// (constitution rule 8): the box starts empty and replaces it on save.
class CookieEditor extends ConsumerStatefulWidget {
  const new({required this.platform, super.key});

  /// Platform id.
  final String platform;

  @override
  ConsumerState<CookieEditor> createState() => _CookieEditorState();
}

class _CookieEditorState extends ConsumerState<CookieEditor> {
  final _cookie = TextEditingController();
  final _ltp0 = TextEditingController();
  final _did = TextEditingController();
  bool _saving = false;

  bool get _douyu => widget.platform == 'douyu';

  @override
  void initState() {
    super.initState();
    if (_douyu) _cookie.addListener(_absorbKeys);
  }

  /// §8.4 LTP0 and dy_did pasted inside the cookie fill their own fields;
  /// a field is never cleared by a paste without them.
  void _absorbKeys() {
    final ltp0 = DouyuSession.field(_cookie.text, DouyuSession.longTermName);
    final did = DouyuSession.field(_cookie.text, DouyuSession.deviceIdName);
    if (ltp0 != null && ltp0 != _ltp0.text) _ltp0.text = ltp0;
    if (did != null && did != _did.text) _did.text = did;
  }

  @override
  void dispose() {
    _cookie.dispose();
    _ltp0.dispose();
    _did.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(accountStoreProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    String message;
    try {
      if (_douyu) {
        message = await saveDouyuInput(
          store,
          pasted: _cookie.text,
          typedLtp0: _ltp0.text,
          typedDid: _did.text,
          now: DateTime.now(),
        );
      } else {
        final cookie = normalizeCookie(_cookie.text);
        if (cookie.isEmpty) {
          message = '先粘贴 Cookie';
        } else {
          await store.saveCookie(widget.platform, cookie);
          message = '已保存，重新进入直播间后生效';
          unawaited(ref.read(accountCheckProvider(widget.platform).notifier).verify());
        }
      }
    } on Object {
      message = '保存失败，请重试';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _cookie.clear();
      _ltp0.clear();
      _did.clear();
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRevisionProvider);
    final store = ref.watch(accountStoreProvider);
    final hasCookie = store.cookie(widget.platform) != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _cookieTips[widget.platform] ?? '在电脑浏览器登录该平台网页版后，从开发者工具里复制请求头中的 Cookie，粘贴到下面。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.s3),
          TextField(
            key: const ValueKey('cookie-input'),
            controller: _cookie,
            minLines: 3,
            maxLines: 6,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Cookie',
              hintText: hasCookie ? '已保存的 Cookie 不显示；粘贴新的会替换它' : null,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_douyu) ...[
            const SizedBox(height: Space.s3),
            TextField(
              key: const ValueKey('douyu-ltp0'),
              controller: _ltp0,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'LTP0（续期用）',
                hintText: store.douyuLtp0 == null ? null : '已保存；留空保持不变',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Space.s3),
            TextField(
              key: const ValueKey('douyu-did'),
              controller: _did,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'dy_did（设备标识）',
                hintText: store.douyuDid == null ? null : '已保存；留空保持不变',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: Space.s3),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _saving ? null : _save, child: const Text('保存')),
          ),
        ],
      ),
    );
  }
}
