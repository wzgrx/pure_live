import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/web/cookie_text.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/account_status.dart';
import 'package:pure_live_app/features/accounts/douyu_account.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Where to copy the cookie from, per platform.
Map<String, String> get _cookieTips => {
  'douyu': t.accounts.cookieTip.douyu,
  'twitch': t.accounts.cookieTip.twitch,
  'soop': t.accounts.cookieTip.soop,
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
          message = t.accounts.pasteCookieFirst;
        } else {
          await store.saveCookie(widget.platform, cookie);
          message = t.accounts.cookieSavedRejoin;
          unawaited(ref.read(accountCheckProvider(widget.platform).notifier).verify());
        }
      }
    } on Object {
      message = t.accounts.saveFailed;
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
            _cookieTips[widget.platform] ?? t.accounts.cookieTip.other,
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
              hintText: hasCookie ? t.accounts.cookieHidden : null,
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
                labelText: t.accounts.ltp0Label,
                hintText: store.douyuLtp0 == null ? null : t.accounts.keptIfEmpty,
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
                labelText: t.accounts.didLabel,
                hintText: store.douyuDid == null ? null : t.accounts.keptIfEmpty,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: Space.s3),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _saving ? null : _save, child: Text(t.common.save)),
          ),
        ],
      ),
    );
  }
}
