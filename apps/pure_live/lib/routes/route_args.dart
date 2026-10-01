import 'package:flutter/foundation.dart';

/// How a page was opened: its path (a `RoutePath` value), the arguments
/// (3.x `Get.arguments`), and whether it is a tab of the home shell.
///
/// Every page takes one, so the route table never changes when a page is
/// rebuilt (M13 replaces only `lib/pages/<page>/`).
@immutable
final class RouteArgs {
  /// Creates the arguments.
  const new(this.path, {this.arguments, this.inHome = false});

  /// The route path.
  final String path;

  /// The arguments: a `LiveRoom` for the live room, `[LiveSite, LiveArea]`
  /// for an area's rooms, null for most pages.
  final Object? arguments;

  /// Whether the page is a home tab (the phone layout puts the menu and the
  /// search menu in its app bar, 3.x `showAction`).
  final bool inHome;
}
