import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/dialogs/live_dlna_dialog.dart';
import 'package:pure_live/modules/toolbox/toolbox_action_scope.dart';
import 'package:pure_live/modules/toolbox/toolbox_direct_link_flow.dart';

/// One route-owned action shared by the player's menu and control bar.
class KnownRoomLinkDialog extends StatefulWidget {
  const KnownRoomLinkDialog({
    super.key,
    required this.room,
    required this.cast,
    required this.flow,
    required this.isCurrentRoom,
    required this.notify,
    this.sourceRoute,
    this.openCast,
  });

  final LiveRoom room;
  final bool cast;
  final ToolBoxDirectLinkFlow flow;
  final bool Function() isCurrentRoom;
  final void Function(String) notify;
  final Route<dynamic>? sourceRoute;
  final Future<void> Function(String)? openCast;
  static final _active = <NavigatorState, Future<void>>{};

  static Future<void> show({
    required BuildContext context,
    required LiveRoom room,
    required bool cast,
    required ToolBoxDirectLinkFlow flow,
    required bool Function() isCurrentRoom,
    required void Function(String) notify,
    Future<void> Function(String)? openCast,
  }) {
    if (!context.mounted || !isCurrentRoom()) return Future.value();
    final navigator = Navigator.of(context, rootNavigator: true);
    final current = _active[navigator];
    if (current != null) return current;
    final done = Completer<void>();
    _active[navigator] = done.future;
    final route = DialogRoute<void>(
      context: context,
      builder: (_) => KnownRoomLinkDialog(
        room: room,
        cast: cast,
        flow: flow,
        isCurrentRoom: isCurrentRoom,
        notify: notify,
        sourceRoute: ModalRoute.of(context),
        openCast: openCast,
      ),
    );
    Future<void> push() async {
      try {
        await navigator.push(route);
      } catch (_) {
        if (context.mounted && isCurrentRoom()) notify('toolbox_get_url_failed');
      } finally {
        if (identical(_active[navigator], done.future)) _active.remove(navigator);
        done.complete();
      }
    }

    unawaited(push());
    return done.future;
  }

  @override
  State<KnownRoomLinkDialog> createState() => _KnownRoomLinkDialogState();
}

class _KnownRoomLinkDialogState extends State<KnownRoomLinkDialog> {
  late final ToolBoxActionScope _scope;
  Route<dynamic>? _route;
  Route<dynamic>? _child;
  NavigatorState? _navigator;
  bool _finishing = false;
  String? _title;
  Widget _body = const Padding(
    padding: EdgeInsets.all(20),
    child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator())),
  );

  @override
  void initState() {
    super.initState();
    _scope = ToolBoxActionScope(
      ownerAlive: () =>
          mounted &&
          widget.isCurrentRoom() &&
          (widget.sourceRoute?.isActive ?? true) &&
          ((_route?.isCurrent ?? false) || (_child?.isCurrent ?? false)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _navigator = Navigator.of(context);
  }

  Future<void> _run() async {
    try {
      await widget.flow.run(
        room: widget.room,
        scope: _scope,
        notify: widget.notify,
        chooseQuality: (items) =>
            _choose<LivePlayQuality>(i18n('toolbox_select_quality'), items, (item, _) => item.quality),
        chooseLine: (items) => _choose<String>(
          i18n('toolbox_select_line'),
          items,
          (_, index) => i18n('toolbox_line', args: {'index': '${index + 1}'}),
          subtitle: (url) => url,
        ),
        useUrl: widget.cast ? _cast : null,
      );
    } on ToolBoxActionCancelled {
      // The source room, route or user intent no longer owns this result.
    } catch (_) {
      if (_scope.isActive) widget.notify('toolbox_get_url_failed');
    } finally {
      _finish();
    }
  }

  Future<T?> _choose<T>(String title, List<T> items, String Function(T, int) label, {String Function(T)? subtitle}) {
    _scope.checkActive();
    final result = Completer<T?>();
    setState(() {
      _title = title;
      _body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            ListTile(
              title: Text(label(items[i], i), textAlign: TextAlign.center),
              subtitle: subtitle == null
                  ? null
                  : Text(subtitle(items[i]), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                if (result.isCompleted) return;
                if (!_scope.isActive) {
                  _finish();
                  return;
                }
                setState(
                  () => _body = const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator())),
                  ),
                );
                result.complete(items[i]);
              },
            ),
        ],
      );
    });
    return result.future;
  }

  Future<void> _cast(String url) async {
    _scope.checkActive();
    final openCast = widget.openCast;
    if (openCast != null) {
      await openCast(url);
      return;
    }
    final navigator = _navigator!;
    final route = DialogRoute<void>(
      context: context,
      builder: (_) => LiveDlnaPage(datasource: url),
    );
    _child = route;
    unawaited(
      _scope.cancelToken.whenCancel.then((_) {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      }),
    );
    try {
      await navigator.push(route);
    } finally {
      if (identical(_child, route)) _child = null;
    }
  }

  void _finish() {
    if (_finishing) return;
    _finishing = true;
    _scope.cancel();
    final route = _route;
    final navigator = _navigator;
    if (!mounted || navigator == null || !navigator.mounted || route == null || !route.isActive) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  void dispose() {
    _scope.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: Text(_title ?? i18n(widget.cast ? 'cast_screen' : 'toolbox_get_direct_link')),
    children: [
      _body,
      TextButton(onPressed: _finish, child: Text(i18n('cancel'))),
    ],
  );
}
