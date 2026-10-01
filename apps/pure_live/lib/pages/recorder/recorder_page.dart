import 'package:flutter/widgets.dart';
import 'package:pure_live/pages/under_construction.dart';
import 'package:pure_live/routes/route_args.dart';

/// Recording centre (3.x `lib/recorder/pages/recorder`).
///
/// Routes: `RoutePath.kRecordPage`.
///
/// A placeholder until M13 rebuilds it: M13 replaces only this folder and
/// keeps the class name and constructor, so the route table stays as it is.
class RecorderPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => UnderConstruction(route: route);
}
