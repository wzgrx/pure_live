import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';

/// Closes a toast whose action belongs to the page left when [router]'s top
/// page changes (A02.4 c3: "已取消关注 X · 撤销" followed the user from the
/// room to home). Dialogs, sheets and menus are not pages of the router, so
/// they leave it. Plain words run out as before ([closePageAppToast]).
///
/// Returns the function that stops listening.
VoidCallback closeToastsOnNewPage(GoRouter router, ScaffoldMessengerState? Function() messenger) {
  final delegate = router.routerDelegate;
  Object? topPage() => delegate.currentConfiguration.lastOrNull?.pageKey;
  var page = topPage();
  void changed() {
    final now = topPage();
    if (now == page) return;
    page = now;
    final target = messenger();
    if (target != null) closePageAppToast(target);
  }

  delegate.addListener(changed);
  return () => delegate.removeListener(changed);
}
