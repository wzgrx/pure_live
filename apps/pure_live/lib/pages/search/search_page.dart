import 'package:flutter/widgets.dart';
import 'package:pure_live/pages/search/search_view.dart';
import 'package:pure_live/pages/search/web_search_view.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// Search and web search (3.x `lib/modules/search`).
///
/// Routes: `RoutePath.kSearch` ([SearchView]; a `String` argument is
/// searched at once) and `RoutePath.kWebSearch` ([WebSearchView]; 3.x's
/// `{'url': …, 'platform': …}` argument).
class SearchPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => switch (route.path) {
    RoutePath.kWebSearch => WebSearchView(arguments: route.arguments),
    _ => SearchView(
      initialKeyword: switch (route.arguments) {
        final String keyword => keyword,
        _ => null,
      },
    ),
  };
}
