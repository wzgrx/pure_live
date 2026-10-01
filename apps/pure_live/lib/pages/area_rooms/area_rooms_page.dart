import 'package:flutter/widgets.dart';
import 'package:pure_live/pages/under_construction.dart';
import 'package:pure_live/routes/route_args.dart';

/// The rooms of an area (arguments: `[LiveSite, LiveArea]`) (3.x `lib/modules/area_rooms`).
///
/// Routes: `RoutePath.kAreaRooms`.
///
/// A placeholder until M13 rebuilds it: M13 replaces only this folder and
/// keeps the class name and constructor, so the route table stays as it is.
class AreaRoomsPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => UnderConstruction(route: route);
}
