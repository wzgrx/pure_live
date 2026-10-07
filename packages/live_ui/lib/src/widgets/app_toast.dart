import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';

// The one toast of the app (docs/A-界面设计/A02-组件/A02.2-弹窗组件 c11–c13; 3.x ToastUtil and
// v4's snack bars): a floating snack bar on the root messenger, so it sits
// above the bottom navigation bar, a floating button and the keyboard.

/// The widest a toast gets (U.1d c12: wide screens, centred).
const double appToastMaxWidth = 560;

/// A short message at the bottom (U.1d): the theme's inverse colours (dark
/// on a light theme, light on a dark one, D1), 8-point corners, 14-point
/// text on at most two lines, left aligned (D3); optionally one
/// [actionLabel] ("撤销", "重试", "进入") in the inverse primary colour and
/// ✕ ([closable]).
///
/// It goes after [duration] (3 s like 3.x; 4 s with an action) unless it
/// asks the user something ([persistent]: it stays, with ✕, until the
/// action or ✕). With an accessibility service on, one with an action
/// stays [accessibleActionDuration], with ✕ (A02.4).
@immutable
final class AppToast {
  /// Creates the toast.
  const new(this.message, {this.actionLabel, this.onAction, this.closable = false, this.persistent = false, this.key});

  /// How long a toast shows (3.x `initialized.dart:172`).
  static const Duration shortDuration = Duration(seconds: 3);

  /// How long a toast with an action shows (U.1d c13).
  static const Duration actionDuration = Duration(seconds: 4);

  /// How long a toast with an action shows with an accessibility service
  /// on (A02.4 c2): time to reach the action without a screen reader
  /// racing 4 s, yet not for good (any service, such as select-to-speak,
  /// turns `accessibleNavigation` on).
  static const Duration accessibleActionDuration = Duration(seconds: 30);

  /// The words.
  final String message;

  /// The action's words.
  final String? actionLabel;

  /// The action; the toast closes with it.
  final VoidCallback? onAction;

  /// Shows ✕.
  final bool closable;

  /// Stays until the action or ✕ (implies [closable]).
  final bool persistent;

  /// The toast's key (tests find it by this).
  final Key? key;

  /// How long it shows.
  Duration get duration => actionLabel != null ? actionDuration : shortDuration;

  /// Whether its action belongs to the page it was shown on ("撤销",
  /// "重试"): a new page closes it ([closePageAppToast], A02.4 c3). One the
  /// user has to answer ([persistent]) stays.
  bool get belongsToPage => actionLabel != null && !persistent;

  /// The snack bar, [width] wide (centred) or across the screen less the
  /// theme's margins. With an accessibility service on ([accessible]) a
  /// toast with an action stays [accessibleActionDuration] with ✕ (A02.4:
  /// Flutter's rule kept it until used, and without ✕ it stayed for good).
  SnackBar snackBar({double? width, bool accessible = false}) {
    final longer = accessible && belongsToPage;
    final close = closable || persistent || longer;
    return SnackBar(
      key: key,
      width: width,
      behavior: SnackBarBehavior.floating,
      duration: persistent ? const Duration(days: 1) : (longer ? accessibleActionDuration : duration),
      persist: persistent,
      padding: EdgeInsetsDirectional.only(start: 16, end: actionLabel != null || close ? 4 : 16),
      content: _AppToastContent(toast: this, close: close),
    );
  }
}

class _AppToastContent extends StatelessWidget {
  const new({required this.toast, required this.close});

  final AppToast toast;

  /// Shows ✕.
  final bool close;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme.bodyLarge?.copyWith(color: scheme.onInverseSurface, height: 1.4);
    final action = toast.actionLabel;
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(toast.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: text),
          ),
        ),
        if (action != null)
          TextButton(
            key: const ValueKey('app-toast-action'),
            style: TextButton.styleFrom(
              foregroundColor: scheme.inversePrimary,
              textStyle: text?.emphasis,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () {
              ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
              toast.onAction?.call();
            },
            child: Text(action),
          ),
        if (close)
          IconButton(
            key: const ValueKey('app-toast-close'),
            tooltip: LiveUiScope.of(context).strings.close,
            color: scheme.onInverseSurface,
            icon: const Icon(AppIcons.close, size: 22),
            onPressed: () =>
                ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss),
          ),
      ],
    );
  }
}

/// The width of a toast on a screen [screenWidth] wide: across the screen
/// less 16 on each side on phones (null: the theme's margins), centred and
/// [appToastMaxWidth] wide on wide screens.
double? appToastWidth(double screenWidth) => screenWidth - 32 > appToastMaxWidth ? appToastMaxWidth : null;

/// Shows [toast] at the bottom of the page of [context] (the root
/// messenger), replacing the one shown (one at a time, the new one wins).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showAppToast(BuildContext context, AppToast toast) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  return showAppToastOn(messenger, toast);
}

/// Shows [toast] through [messenger] (see [showAppToast]).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppToastOn(
  ScaffoldMessengerState messenger,
  AppToast toast,
) {
  final media = MediaQuery.of(messenger.context);
  messenger.clearSnackBars();
  final controller = messenger.showSnackBar(
    toast.snackBar(width: appToastWidth(media.size.width), accessible: media.accessibleNavigation),
  );
  _shown[messenger] = toast;
  controller.closed.then((_) {
    if (identical(_shown[messenger], toast)) _shown[messenger] = null;
  }).ignore();
  return controller;
}

/// The toast each messenger shows ([closePageAppToast]).
final Expando<AppToast> _shown = Expando('app toast');

/// A new page is up (A02.4 c3): closes the toast [messenger] shows when its
/// action belongs to the page left ([AppToast.belongsToPage]). Plain words
/// run out as before (3.x's toasts outlived the page too).
void closePageAppToast(ScaffoldMessengerState messenger) {
  if (_shown[messenger]?.belongsToPage ?? false) messenger.hideCurrentSnackBar();
}

/// Shows the app's toasts through one messenger (the app's [show] for
/// `AppNavigator.toast`): the new one replaces the one shown, and the same
/// words are not shown again while they still show (3.x `ToastUtil`: not
/// twice within 3 s).
final class AppToaster {
  /// Shows through the messenger [messenger] returns (null before the app
  /// is up: nothing shows).
  new(this.messenger, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The root messenger.
  final ScaffoldMessengerState? Function() messenger;

  final DateTime Function() _now;
  String? _last;
  DateTime _lastUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Shows [toast] unless the same words still show.
  void show(AppToast toast) {
    final target = messenger();
    if (target == null) return;
    final now = _now();
    if (toast.message == _last && now.isBefore(_lastUntil)) return;
    _last = toast.message;
    _lastUntil = toast.persistent ? now.add(const Duration(days: 1)) : now.add(toast.duration);
    final controller = showAppToastOn(target, toast);
    // Closed early (✕, the action, a newer toast): the same words may come
    // again.
    controller.closed.then((_) {
      if (_last == toast.message) _lastUntil = DateTime.fromMillisecondsSinceEpoch(0);
    }).ignore();
  }
}
