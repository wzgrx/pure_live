import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';

/// One action of a [TvStatusView].
@immutable
final class TvStatusAction {
  /// Creates the action.
  const new({required this.label, required this.onTap, this.icon});

  /// The words.
  final String label;

  /// The icon before the words.
  final IconData? icon;

  /// What it does.
  final VoidCallback onTap;
}

/// The state of a TV list that has no rooms to show (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件
/// c14, the phone's status page in the TV style): an icon in a soft circle
/// (no bounce, P15), the title (22, 600), a line saying what to do with
/// the remote (16, secondary) and up to two buttons; the first is where the
/// focus lands when the page is entered (or at once with [autofocus]).
///
/// [TvStatusView.failure] words a failed load by its cause (never the
/// adapter's text, P14) and offers "前往登录" when the platform wants a
/// login; the first load is [TvSkeletonGrid], not a spinner.
class TvStatusView extends StatelessWidget {
  /// Creates the state.
  const new({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.autofocus = false,
    super.key,
  });

  /// A failed load: "前往登录" when [error] asks for a login (the account
  /// page, or [onLogin]), else "重试" ([onRetry]).
  factory failure(Object? error, {VoidCallback? onRetry, VoidCallback? onLogin, bool autofocus = false, Key? key}) {
    if (isLoginError(error)) {
      return TvStatusView(
        key: key,
        icon: TvIcons.needsLogin,
        title: i18n('login_required_title'),
        subtitle: describeLoadError(error),
        autofocus: autofocus,
        actions: [
          TvStatusAction(
            icon: AppIcons.login,
            label: i18n('go_to_login'),
            onTap: onLogin ?? () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsAccount)),
          ),
        ],
      );
    }
    final network =
        error is Offline || error is NetworkFailure || error is TransportFailure || error is HttpStatusFailure;
    return TvStatusView(
      key: key,
      icon: TvIcons.loadFailed,
      title: i18n(network ? 'network_error_title' : 'tv_load_failed'),
      subtitle: describeLoadError(error),
      autofocus: autofocus,
      actions: [if (onRetry != null) TvStatusAction(icon: AppIcons.refresh, label: i18n('retry'), onTap: onRetry)],
    );
  }

  /// The icon.
  final IconData icon;

  /// The main line.
  final String title;

  /// What to do (with the remote).
  final String? subtitle;

  /// The buttons.
  final List<TvStatusAction> actions;

  /// Focuses the first button when shown.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(scale.px(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: scale.px(88),
              height: scale.px(88),
              decoration: BoxDecoration(color: palette.accent.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, size: scale.px(44), color: palette.accent),
            ),
            SizedBox(height: scale.px(20)),
            Text(
              title,
              key: const ValueKey('tv-status-title'),
              textAlign: TextAlign.center,
              style: scale.font(TvTextSize.title, weight: FontWeight.w600, color: palette.text, height: 1.3),
            ),
            if (subtitle case final subtitle? when subtitle.isNotEmpty && subtitle != title)
              Padding(
                padding: EdgeInsets.only(top: scale.px(6)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: scale.pxText(420)),
                  child: Text(
                    subtitle,
                    key: const ValueKey('tv-status-subtitle'),
                    textAlign: TextAlign.center,
                    style: scale.font(TvTextSize.body, color: palette.textSecondary, height: 1.6),
                  ),
                ),
              ),
            if (actions.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: scale.px(22)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, action) in actions.indexed) ...[
                      if (index > 0) SizedBox(width: scale.px(12)),
                      TvButton(
                        key: ValueKey('tv-status-action-$index'),
                        icon: action.icon,
                        label: action.label,
                        autofocus: autofocus && index == 0,
                        onTap: action.onTap,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The first load of a TV grid (U.15a c14): static skeleton cards in the
/// grid's columns, no shimmer and no spinner (UI_PLAN §9.3). Loading more
/// keeps the "加载样式" setting's indicator.
class TvSkeletonGrid extends StatelessWidget {
  /// Creates the skeleton of a grid of [columns].
  const new({this.columns = 4, this.rows = 2, super.key});

  /// Cards per row.
  final int columns;

  /// Rows drawn.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    Widget line(double left, double? width) => Container(
      margin: EdgeInsets.only(left: scale.px(left), right: scale.px(12), top: scale.px(8)),
      width: width,
      height: scale.px(12),
      decoration: BoxDecoration(color: palette.raised, borderRadius: BorderRadius.circular(scale.px(6))),
    );
    return ExcludeFocus(
      child: Padding(
        key: const ValueKey('tv-skeleton'),
        padding: EdgeInsets.all(scale.px(12)),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gap = scale.px(16);
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < columns * rows; i++)
                    Container(
                      width: width,
                      decoration: BoxDecoration(
                        color: palette.card,
                        borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
                      ),
                      padding: EdgeInsets.only(bottom: scale.px(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.raised,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(scale.px(TvRadius.card))),
                              ),
                            ),
                          ),
                          SizedBox(height: scale.px(4)),
                          line(48, null),
                          line(48, width / 2),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
