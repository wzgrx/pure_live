import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';

// The one toast of the app (docs/ui/compare/U.1d c11–c13; 3.x ToastUtil and
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
/// action or ✕).
@immutable
final class AppToast {
  /// Creates the toast.
  const new(this.message, {this.actionLabel, this.onAction, this.closable = false, this.persistent = false, this.key});

  /// How long a toast shows (3.x `initialized.dart:172`).
  static const Duration shortDuration = Duration(seconds: 3);

  /// How long a toast with an action shows (U.1d c13).
  static const Duration actionDuration = Duration(seconds: 4);

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

  /// The snack bar, [width] wide (centred) or across the screen less the
  /// theme's margins. With a screen reader ([accessible]) a toast with an
  /// action stays until it is used or closed (Flutter's rule for snack bar
  /// actions).
  SnackBar snackBar({double? width, bool accessible = false}) => SnackBar(
    key: key,
    width: width,
    behavior: SnackBarBehavior.floating,
    duration: persistent ? const Duration(days: 1) : duration,
    persist: persistent || (accessible && actionLabel != null),
    padding: EdgeInsetsDirectional.only(start: 16, end: actionLabel != null || closable || persistent ? 4 : 16),
    content: _AppToastContent(toast: this),
  );
}

class _AppToastContent extends StatelessWidget {
  const new({required this.toast});

  final AppToast toast;

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
        if (toast.closable || toast.persistent)
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
  return messenger.showSnackBar(
    toast.snackBar(width: appToastWidth(media.size.width), accessible: media.accessibleNavigation),
  );
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
