import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/web/cookie_text.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// How a platform signs in on its own web page (F-ACC-01).
@immutable
final class WebLoginSpec {
  /// Creates a spec.
  const new({required this.platform, required this.start, required this.isSignedIn});

  /// Platform id.
  final String platform;

  /// The sign-in page.
  final Uri start;

  /// Whether a main-frame navigation to the address means the sign-in is
  /// over; the browser's cookies for that address are then read.
  final bool Function(Uri url) isSignedIn;
}

/// spec/sites/bilibili.md §8.4: the passport page; done when it goes to
/// HTTPS `m.bilibili.com` or `www.bilibili.com`.
final bilibiliWebLogin = WebLoginSpec(
  platform: 'bilibili',
  start: Uri.parse('https://passport.bilibili.com/login'),
  isSignedIn: (url) => url.isScheme('https') && (url.host == 'm.bilibili.com' || url.host == 'www.bilibili.com'),
);

/// Platforms with a web sign-in.
final Map<String, WebLoginSpec> webLoginSpecs = {'bilibili': bilibiliWebLogin};

/// Checks a cookie collected from the browser before it is stored; throws
/// `NeedsLogin` when it is not signed in.
typedef CookieVerifier = Future<AccountIdentity> Function(String cookie);

/// The verifier of a web sign-in's cookie, by platform.
final ProviderFamily<CookieVerifier?, String> webLoginVerifierProvider = Provider.family<CookieVerifier?, String>(
  (ref, platform) => switch (platform) {
    'bilibili' => ref.watch(bilibiliLoginProvider).account,
    _ => null,
  },
);

/// Where a web sign-in stands.
enum WebLoginPhase {
  /// The user is on the platform's pages.
  browsing,

  /// The sign-in finished; reading and checking the cookie.
  verifying,

  /// Stored.
  done,
}

/// The web sign-in flow (spec/sites/bilibili.md §8.4): the navigation that
/// ends the sign-in is cancelled, the browser's cookies for that address are
/// read, verified and stored. A failure goes back to the page with a message.
final class WebLoginFlow extends ChangeNotifier {
  /// Creates the flow.
  new({required this.spec, required this.cookies, required this.verify, required this.save});

  /// The platform's sign-in.
  final WebLoginSpec spec;

  /// Reads the browser's cookies for an address.
  final Future<List<WebCookie>> Function(Uri url) cookies;

  /// Checks the collected cookie.
  final CookieVerifier verify;

  /// Stores the verified cookie.
  final Future<void> Function(String cookie, AccountIdentity identity) save;

  WebLoginPhase _phase = WebLoginPhase.browsing;
  String? _message;
  AccountIdentity? _identity;
  Future<void>? _running;
  bool _disposed = false;

  /// The current phase.
  WebLoginPhase get phase => _phase;

  /// Why the last attempt failed.
  String? get message => _message;

  /// Who signed in, once done.
  AccountIdentity? get identity => _identity;

  void _set(WebLoginPhase phase, {String? message}) {
    _phase = phase;
    _message = message;
    if (!_disposed) notifyListeners();
  }

  /// The navigation filter: false (cancel) for the address that ends the
  /// sign-in, which then completes it.
  bool allow(Uri url) {
    if (!spec.isSignedIn(url)) return true;
    unawaited(complete(url));
    return false;
  }

  /// Watches page events for an end address the filter did not see (a
  /// redirect some engines report only as a new page).
  void onEvent(WebPageEvent event) {
    final url = switch (event) {
      WebPageStarted(:final url) || WebPageFinished(:final url) || WebUrlChanged(:final url) => url,
      _ => null,
    };
    if (url != null && spec.isSignedIn(url)) unawaited(complete(url));
  }

  /// Reads, verifies and stores the cookie of [url]; one run at a time.
  Future<void> complete(Uri url) {
    if (_phase == WebLoginPhase.done) return Future.value();
    return _running ??= _complete(url).whenComplete(() => _running = null);
  }

  Future<void> _complete(Uri url) async {
    _set(WebLoginPhase.verifying);
    String cookie;
    try {
      cookie = cookieHeader(await cookies(url));
    } on Object {
      if (!_disposed) _set(WebLoginPhase.browsing, message: t.accounts.webReadFailed);
      return;
    }
    if (_disposed) return;
    if (cookie.isEmpty) {
      _set(WebLoginPhase.browsing, message: t.accounts.webNoCookie);
      return;
    }
    try {
      final identity = await verify(cookie);
      if (_disposed) return;
      await save(cookie, identity);
      _identity = identity;
      _set(WebLoginPhase.done);
    } on NeedsLogin {
      if (!_disposed) _set(WebLoginPhase.browsing, message: t.accounts.webRejected);
    } on Object catch (error) {
      if (!_disposed) {
        _set(WebLoginPhase.browsing, message: t.accounts.qrVerifyFailed(reason: describeError(error).title));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Signs in on the platform's web page in the in-app browser.
class WebLoginPage extends ConsumerStatefulWidget {
  const new({required this.platform, super.key});

  /// Platform id; must have a [webLoginSpecs] entry.
  final String platform;

  @override
  ConsumerState<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends ConsumerState<WebLoginPage> {
  WebLoginFlow? _flow;
  WebPage? _page;
  StreamSubscription<WebPageEvent>? _events;
  int _progress = 100;

  @override
  void initState() {
    super.initState();
    final spec = webLoginSpecs[widget.platform];
    final engine = ref.read(webEngineProvider);
    final verify = ref.read(webLoginVerifierProvider(widget.platform));
    if (spec == null || engine == null || verify == null) return;
    final store = ref.read(accountStoreProvider);
    final flow = WebLoginFlow(
      spec: spec,
      cookies: engine.cookies,
      verify: verify,
      save: (cookie, identity) => store.saveCookie(spec.platform, cookie, uid: int.tryParse(identity.uid ?? '')),
    )..addListener(_changed);
    final page = engine.open(filter: flow.allow);
    _events = page.events.listen((event) {
      flow.onEvent(event);
      if (event is WebPageProgress && mounted) setState(() => _progress = event.percent);
    });
    _flow = flow;
    _page = page;
    unawaited(page.load(spec.start));
  }

  void _changed() {
    final flow = _flow!;
    if (!mounted) return;
    if (flow.phase == WebLoginPhase.done) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.accounts.signedInName(name: flow.identity?.name ?? ''))));
      context.pop(true);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_page?.dispose());
    _flow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    final page = _page;
    final name = platformNames[widget.platform] ?? widget.platform;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (page != null && await page.goBack()) return;
        if (context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.accounts.webTitle(name: name)),
          actions: [
            if (page != null)
              IconButton(tooltip: t.common.refresh, icon: const LiveIcon(LiveIcons.refresh), onPressed: page.reload),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 2),
                )
              : null,
        ),
        body: flow == null || page == null
            ? MessageView(
                icon: LiveIcons.webUnavailable,
                title: t.accounts.webUnavailable,
                message: t.accounts.webUnavailableHint,
              )
            : Column(
                children: [
                  if (flow.message != null)
                    MaterialBanner(
                      content: Text(flow.message!),
                      actions: [TextButton(onPressed: page.reload, child: Text(t.accounts.reload))],
                    ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        page.build(context),
                        if (flow.phase == WebLoginPhase.verifying)
                          ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                            child: LoadingView(label: t.accounts.verifyingSignIn),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
