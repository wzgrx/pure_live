import 'package:flutter/widgets.dart';
import 'package:pure_live/pages/under_construction.dart';
import 'package:pure_live/routes/route_args.dart';

/// Open a link (3.x `lib/modules/toolbox`).
///
/// Routes: `RoutePath.kToolbox`.
///
/// A placeholder until M13 rebuilds it: M13 replaces only this folder and
/// keeps the class name and constructor, so the route table stays as it is.
class ToolboxPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => UnderConstruction(route: route);
}
