import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pure_live_app/core/web/web_engine.dart';

/// An in-app browser without a browser, for tests: pages record what they
/// were asked to do, and [FakeWebPage.navigate] plays a user navigation in
/// the engines' order (filter, then started, url change, progress, finished).
final class FakeWebEngine implements WebEngine {
  new({this.state = WebAvailability.available, Map<String, List<WebCookie>>? jar}) : jar = jar ?? {};

  /// What [availability] answers.
  WebAvailability state;

  /// Cookies by host.
  final Map<String, List<WebCookie>> jar;

  /// Pages opened, in order.
  final pages = <FakeWebPage>[];

  /// How often [clearCookies] ran.
  int cleared = 0;

  @override
  Future<WebAvailability> availability() async => state;

  @override
  WebPage open({WebNavigationFilter? filter, String? userAgent}) {
    final page = FakeWebPage(filter);
    pages.add(page);
    return page;
  }

  @override
  Future<List<WebCookie>> cookies(Uri url) async => jar[url.host] ?? const [];

  @override
  Future<void> clearCookies() async {
    cleared++;
    jar.clear();
  }
}

/// A page of [FakeWebEngine].
final class FakeWebPage implements WebPage {
  new(this.filter);

  /// The navigation filter the page was opened with.
  final WebNavigationFilter? filter;

  final _events = StreamController<WebPageEvent>.broadcast(sync: true);

  /// Addresses loaded by the app, in order.
  final loads = <Uri>[];

  /// History of shown documents.
  final history = <Uri>[];

  /// What [evaluate] returns.
  Object? scriptResult;

  /// Whether [dispose] ran.
  bool disposed = false;

  int reloads = 0;

  void _show(Uri url) {
    history.add(url);
    _events
      ..add(WebPageStarted(url))
      ..add(WebUrlChanged(url))
      ..add(const WebPageProgress(100))
      ..add(WebPageFinished(url));
  }

  /// The user follows a link to [url]: true when the filter let it load.
  Future<bool> navigate(Uri url) async {
    final allowed = await (filter?.call(url) ?? true);
    if (allowed) _show(url);
    return allowed;
  }

  /// The page changes its address without a load (history API).
  void pushState(Uri url) {
    history.add(url);
    _events.add(WebUrlChanged(url));
  }

  /// The main document failed.
  void fail() => _events.add(const WebPageFailed('net::ERR_FAILED'));

  @override
  Stream<WebPageEvent> get events => _events.stream;

  @override
  Future<void> load(Uri url) async {
    loads.add(url);
    _show(url);
  }

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<bool> goBack() async {
    if (history.length < 2) return false;
    history.removeLast();
    return true;
  }

  @override
  Future<Uri?> currentUrl() async => history.lastOrNull;

  @override
  Future<Object?> evaluate(String script) async => scriptResult;

  @override
  Widget build(BuildContext context) => const ColoredBox(key: ValueKey('fake-web-page'), color: Colors.white);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}
