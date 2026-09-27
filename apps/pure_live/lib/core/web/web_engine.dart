import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live_app/core/web/web_engine_android.dart';
import 'package:pure_live_app/core/web/web_engine_windows.dart';

/// Whether the in-app browser can run (docs/adr/0032-webview.md).
enum WebAvailability {
  /// Ready.
  available,

  /// Windows without the Microsoft Edge WebView2 Runtime: entries stay
  /// visible and explain how to install it (spec/product.md F-SRC-02).
  missingRuntime,

  /// No browser on this platform: entries are hidden.
  unsupported,
}

/// One cookie the browser holds. Values never reach logs or the interface
/// (constitution rule 8).
@immutable
final class WebCookie {
  /// Creates a cookie.
  const new({required this.name, required this.value});

  /// Name.
  final String name;

  /// Value.
  final String value;
}

/// What a page reports while it loads (all main-frame events).
sealed class WebPageEvent {
  const new();
}

/// A main-frame load started.
final class WebPageStarted extends WebPageEvent {
  /// Creates the event.
  const new(this.url);

  /// The document's address.
  final Uri url;
}

/// A main-frame load finished.
final class WebPageFinished extends WebPageEvent {
  /// Creates the event.
  const new(this.url);

  /// The document's address.
  final Uri url;
}

/// The address changed without a load (history API in single-page sites).
final class WebUrlChanged extends WebPageEvent {
  /// Creates the event.
  const new(this.url);

  /// The new address.
  final Uri url;
}

/// Load progress in percent.
final class WebPageProgress extends WebPageEvent {
  /// Creates the event.
  const new(this.percent);

  /// 0–100.
  final int percent;
}

/// The main document failed to load.
final class WebPageFailed extends WebPageEvent {
  /// Creates the event; [description] is for diagnostics only.
  const new(this.description);

  /// What the engine said.
  final String description;
}

/// Decides a main-frame navigation before it happens: true lets it go on.
/// Non-HTTP(S) schemes (app links such as `bilibili://`) never reach it; the
/// engine blocks them.
typedef WebNavigationFilter = FutureOr<bool> Function(Uri url);

/// A browser page behind the interface (PLAN §04: the web view is isolated
/// behind an interface; ADR ADR 0032).
abstract interface class WebPage {
  /// Main-frame events.
  Stream<WebPageEvent> get events;

  /// Loads [url].
  Future<void> load(Uri url);

  /// Reloads the current document.
  Future<void> reload();

  /// Goes back in the page's history; false when there is nothing to go back to.
  Future<bool> goBack();

  /// The current address, or null before the first load.
  Future<Uri?> currentUrl();

  /// Runs [script] in the page and returns its JSON-compatible result.
  Future<Object?> evaluate(String script);

  /// The page's view.
  Widget build(BuildContext context);

  /// Releases the page; events stop.
  Future<void> dispose();
}

/// The platform's browser engine: Android WebView (webview_flutter) or
/// Windows WebView2 (webview_all_windows).
abstract interface class WebEngine {
  /// Whether pages can open now.
  Future<WebAvailability> availability();

  /// A new page; [filter] decides main-frame navigations, [userAgent]
  /// replaces the engine's default when set.
  WebPage open({WebNavigationFilter? filter, String? userAgent});

  /// Cookies the browser sends to [url], HttpOnly ones included.
  Future<List<WebCookie>> cookies(Uri url);

  /// Removes every cookie of the in-app browser.
  Future<void> clearCookies();
}

/// Whether [url] is a web address the page may load; everything else (app
/// links, `javascript:`, `data:`) is blocked by every engine.
bool isWebAddress(Uri url) => (url.isScheme('http') || url.isScheme('https')) && url.host.isNotEmpty;

/// The browser engine of this platform; null where there is none (Linux,
/// macOS, iOS in this project: hidden entries, principles rule 10).
final webEngineProvider = Provider<WebEngine?>((ref) {
  if (Platform.isAndroid) return AndroidWebEngine();
  if (Platform.isWindows) return WindowsWebEngine();
  return null;
});

/// Whether the in-app browser is usable, checked once per run.
final webAvailabilityProvider = FutureProvider<WebAvailability>((ref) async {
  final engine = ref.watch(webEngineProvider);
  if (engine == null) return WebAvailability.unsupported;
  try {
    return await engine.availability();
  } on Object {
    return WebAvailability.unsupported;
  }
});
