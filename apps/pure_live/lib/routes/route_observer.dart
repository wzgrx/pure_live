import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pure_live/routes/route_path.dart';

/// Tracks the route on top (3.x `RouteObserverController.currentRoute` and
/// the hooks of `LiveRouteObserver`).
///
/// 3.x's observer also drove the player on entering and leaving the live
/// room (floating window, hiding the Windows video texture under the
/// recording centre). That belongs to the live room and the player (M7.2,
/// M13), which listen here through [addListener] instead of the observer
/// reaching into GetX controllers.
final class LiveRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  final ValueNotifier<String> _current = ValueNotifier('');
  final ValueNotifier<int> _popups = ValueNotifier(0);
  final Set<Route<dynamic>> _openPopups = {};
  final List<void Function(RouteEvent event)> _listeners = [];

  /// The name of the page on top ('' before the first page).
  ValueListenable<String> get currentRoute => _current;

  /// How many menus, dialogs and sheets are open (3.x `PopupRouteTracker`:
  /// the in-app floating window hides meanwhile).
  ValueListenable<int> get openPopups => _popups;

  void _track(Route<dynamic> route, {required bool open}) {
    if (route is! PopupRoute<dynamic>) return;
    if (open) {
      _openPopups.add(route);
    } else {
      _openPopups.remove(route);
    }
    _popups.value = _openPopups.length;
  }

  /// Calls [listener] for every push and pop of a page.
  void addListener(void Function(RouteEvent event) listener) => _listeners.add(listener);

  /// Stops calling [listener].
  void removeListener(void Function(RouteEvent event) listener) => _listeners.remove(listener);

  void _emit(RouteEventKind kind, Route<dynamic> route, Route<dynamic>? top) {
    _current.value = top?.settings.name ?? '';
    final event = RouteEvent(kind, route);
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route, open: true);
    _emit(RouteEventKind.push, route, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(route, open: false);
    _emit(RouteEventKind.pop, route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _track(route, open: false);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) _track(oldRoute, open: false);
    if (newRoute != null) {
      _track(newRoute, open: true);
      _emit(RouteEventKind.push, newRoute, newRoute);
    }
  }
}

/// What happened to a route.
enum RouteEventKind {
  /// Shown.
  push,

  /// Left.
  pop,
}

/// A push or pop of [route].
final class RouteEvent {
  /// Creates the event.
  const new(this.kind, this.route);

  /// What happened.
  final RouteEventKind kind;

  /// The route.
  final Route<dynamic> route;

  /// The route's name ([RoutePath] value).
  String? get name => route.settings.name;
}

/// The app's route observer (one per process, like 3.x's).
final LiveRouteObserver liveRouteObserver = LiveRouteObserver();
