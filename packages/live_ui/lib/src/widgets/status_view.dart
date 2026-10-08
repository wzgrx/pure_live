import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/grid_columns.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/theme/text_wrapping.dart';
import 'package:live_ui/src/widgets/app_dialog.dart';
import 'package:live_ui/src/widgets/app_toast.dart';
import 'package:live_ui/src/widgets/loading_styles.dart';
import 'package:live_ui/src/widgets/scrolling.dart';
import 'package:live_ui/src/widgets/window_layout.dart';

// The one status component (docs/A-界面设计/A02-组件/A02.1-通用组件 c2–c7): six states
// (skeleton, loading, empty, error, restricted, offline) in four places
// (a page, a block, a card cover, on the video; the video has its own
// `VideoStateView`), always the same structure: an icon, one sentence, one
// reason, at most two buttons.

/// What [AppStatusView] shows.
enum AppStatusType {
  /// The loading animation the user picked and a line saying what it waits
  /// for (a list's first load shows a skeleton instead, [StatusSkeleton]).
  loading,

  /// Nothing to show.
  empty,

  /// Loading failed; the raw error goes into [AppStatusView.details].
  error,

  /// The platform wants a login (3.x "需要登录账号"): a lock, "前往登录".
  restricted,

  /// No network (3.x showed it as an error): reconnecting reloads.
  offline,
}

/// The window height under which a page's state lies on its side (icon
/// left, words right; a phone held sideways, whose content is about 300
/// high, U.1c c7): docs/specs/UI.md §5.1's compact height
/// ([WindowClass.isPhoneLandscape]).
const double statusSideBySideHeight = windowCompactHeight;

/// Loading, empty, error, restricted and offline states of a page, a block
/// or a card cover (3.x `AppStatusView`, docs/A-界面设计/A02-组件/A02.1-通用组件).
///
/// A page's state: a solid 80 circle (`surfaceContainer`) with a 40 icon in
/// the primary colour (no pop-in bounce, c6), the title 15/600, the reason
/// 13 in the variant ink (at most 320 wide), then up to two buttons: the
/// first tonal filled with an icon that says what it does, the second a text
/// button (C1). [details] (the raw error) adds "详情" as the second button
/// when there is none; it opens the whole text, selectable and copyable (C4).
/// On a phone held sideways ([WindowClass.isPhoneLandscape]: lower than
/// [statusSideBySideHeight] and at least 600 wide) the state lies on its
/// side; a phone's split screen (compact both ways) keeps it upright.
///
/// [compact] is the form inside a block (a tab, a panel): a 32 icon in the
/// variant ink without the circle. [isMini] is the card cover's: a small
/// icon, no button, a title or text only when given non-empty.
///
/// Loading shows the spinner of the user's "加载样式" sized by where it is
/// (24 in a block or a card, 28 on a page of a compact window, 32 on a page
/// of a wider one; 3.x chose 24 or 32 by the screen only) and a line under
/// it ([title], "加载中..." by default).
///
/// Where its words do not fit (a short window, large text; A04.1) the
/// state scrolls instead of overflowing. Inside a vertical list it uses no
/// `LayoutBuilder`: there it sits where its height is measured first
/// (`SliverFillRemaining`), which a `LayoutBuilder` cannot answer, and the
/// list scrolls it. It reads the classes of the app's area instead
/// ([WindowClassScope], kept on purpose by A02.1 and A04.1).
class AppStatusView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.type,
    this.title,
    this.subtitle,
    this.icon,
    this.buttonText,
    this.buttonIcon,
    this.onButtonPressed,
    this.busy = false,
    this.isMini = false,
    this.compact = false,
    this.details,
    this.iconColor,
    this.titleColor,
    this.subtitleColor,
    this.secondaryButtonText,
    this.onSecondaryButtonPressed,
    super.key,
  });

  /// The state.
  final AppStatusType type;

  /// Title; null takes the state's default.
  final String? title;

  /// Text under the title; null takes the state's default.
  final String? subtitle;

  /// Icon; null takes the state's default (a TV for empty, ⓘ-like error
  /// mark for errors, a lock when restricted, no Wi-Fi when offline).
  final IconData? icon;

  /// Button label; null takes "retry" ("前往登录" when restricted).
  final String? buttonText;

  /// Button icon, matching what [buttonText] does; null takes the retry
  /// icon (the login icon when restricted).
  final IconData? buttonIcon;

  /// Shows the first button (not in [isMini]).
  final VoidCallback? onButtonPressed;

  /// The first button's action runs: a spinner instead of its icon, no taps.
  final bool busy;

  /// The card cover's form.
  final bool isMini;

  /// The form inside a block (tab, panel).
  final bool compact;

  /// The raw error behind an error state ("详情", c4); null or empty hides
  /// it.
  final String? details;

  /// Icon colour, and the loading colour when the user picked none.
  final Color? iconColor;

  /// Title colour.
  final Color? titleColor;

  /// Text colour.
  final Color? subtitleColor;

  /// The second button's label (a text button after the first).
  final String? secondaryButtonText;

  /// Shows the second button (not in [isMini]).
  final VoidCallback? onSecondaryButtonPressed;

  /// The default icon of [type].
  static IconData defaultIcon(AppStatusType type) => switch (type) {
    AppStatusType.loading || AppStatusType.empty => Icons.live_tv_rounded,
    AppStatusType.error => Icons.error_outline_rounded,
    AppStatusType.restricted => Icons.lock_outline_rounded,
    AppStatusType.offline => Icons.wifi_off_rounded,
  };

  @override
  Widget build(BuildContext context) =>
      type == AppStatusType.loading ? _loading(context) : _scrollWhenShort(context, _state(context));

  /// [child] (centred) as it is where a list scrolls it or the height is
  /// open; in a bounded area of its own, a scroll that fills the area and
  /// centres it while it fits.
  static Widget _scrollWhenShort(BuildContext context, Widget child) {
    if (Scrollable.maybeOf(context, axis: Axis.vertical) != null) return child;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.hasBoundedHeight
          ? SingleChildScrollView(
              primary: false,
              physics: const PureLiveScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: child,
              ),
            )
          : child,
    );
  }

  Widget _loading(BuildContext context) {
    final theme = Theme.of(context);
    final config = LiveUiScope.of(context);
    final small = isMini || compact;
    final wide = WindowClassScope.of(context).width != WindowWidthClass.compact;
    final size = small ? 24.0 : (wide ? 32.0 : 28.0);
    final spinner = LoadingStyles.build(
      LoadingStyles.normalize(config.loadingStyle),
      color: config.loadingColor ?? iconColor ?? theme.colorScheme.primary,
      size: size,
      colors: theme.colorScheme,
    );
    final line = title ?? config.strings.loading;
    if (isMini || line.isEmpty) return Center(child: spinner);
    return Center(
      child: Semantics(
        liveRegion: true,
        label: line,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            spinner,
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: context.textStyles.t13.copyWith(color: subtitleColor ?? theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _state(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final words = LiveUiScope.of(context).strings;
    final styles = context.textStyles;
    final finalTitle =
        title ??
        switch (type) {
          AppStatusType.empty || AppStatusType.loading => words.emptyTitle,
          AppStatusType.error => words.loadFailed,
          AppStatusType.restricted => words.restrictedTitle,
          AppStatusType.offline => words.offlineTitle,
        };
    // An explanation: no one-character last line (A01.4 c1).
    final finalSubtitle = withoutOrphan(
      subtitle ??
          switch (type) {
            AppStatusType.empty || AppStatusType.loading => words.emptySubtitle,
            AppStatusType.error => words.errorSubtitle,
            AppStatusType.restricted => words.restrictedSubtitle,
            AppStatusType.offline => words.offlineSubtitle,
          },
    );
    final glyph = icon ?? defaultIcon(type);

    if (isMini) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(glyph, size: 16, color: iconColor ?? scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            if (finalTitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                finalTitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.t12.copyWith(color: titleColor ?? scheme.onSurfaceVariant),
              ),
            ],
            if (finalSubtitle.isNotEmpty)
              Text(
                finalSubtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: styles.t12.copyWith(color: subtitleColor ?? scheme.onSurfaceVariant),
              ),
          ],
        ),
      );
    }

    final sideways = !compact && WindowClassScope.of(context).isPhoneLandscape;
    final mark = compact
        ? Icon(glyph, size: 32, color: iconColor ?? scheme.onSurfaceVariant)
        : Container(
            width: sideways ? 64 : 80,
            height: sideways ? 64 : 80,
            decoration: BoxDecoration(color: scheme.surfaceContainer, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(glyph, size: sideways ? 32 : 40, color: iconColor ?? scheme.primary),
          );
    final align = sideways ? TextAlign.start : TextAlign.center;
    final buttons = _buttons(context, words, alignStart: sideways);
    final texts = <Widget>[
      Text(
        finalTitle,
        textAlign: align,
        style: styles.t15.copyWith(fontWeight: FontWeight.w600, height: 1.4, color: titleColor ?? scheme.onSurface),
      ),
      if (finalSubtitle.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _MaxWidth(
            maxWidth: sideways ? 360 : 320,
            child: Text(
              finalSubtitle,
              textAlign: align,
              style: styles.t13.copyWith(color: subtitleColor ?? scheme.onSurfaceVariant, height: 1.5),
            ),
          ),
        ),
      if (buttons != null)
        Padding(
          padding: EdgeInsets.only(top: sideways ? 12 : 16),
          child: buttons,
        ),
    ];

    if (sideways) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(width: 20),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: texts,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 16 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            mark,
            SizedBox(height: compact ? 10 : 16),
            ...texts,
          ],
        ),
      ),
    );
  }

  Widget? _buttons(BuildContext context, LiveUiStrings words, {required bool alignStart}) {
    final details = this.details;
    final showDetails = onSecondaryButtonPressed == null && details != null && details.trim().isNotEmpty;
    final restricted = type == AppStatusType.restricted;
    final children = [
      if (onButtonPressed case final pressed?)
        FilledButton.tonalIcon(
          key: const ValueKey('status-button'),
          onPressed: busy ? null : pressed,
          icon: busy
              ? const SizedBox.square(
                  key: ValueKey('status-button-busy'),
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(buttonIcon ?? (restricted ? Icons.login_rounded : Icons.refresh_rounded), size: 18),
          label: Text(buttonText ?? (restricted ? words.login : words.retry)),
        ),
      if (onSecondaryButtonPressed case final pressed?)
        TextButton(
          key: const ValueKey('status-secondary-button'),
          onPressed: pressed,
          child: Text(secondaryButtonText ?? words.retry),
        )
      else if (showDetails)
        TextButton(
          key: const ValueKey('status-details-button'),
          onPressed: () => unawaited(showStatusDetails(context, details)),
          child: Text(words.details),
        ),
    ];
    if (children.isEmpty) return null;
    return Wrap(
      alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: children,
    );
  }
}

/// The raw text behind a failure (U.1c C4): the whole text, selectable,
/// with "复制" (copies it and says so) and "关闭".
Future<void> showStatusDetails(BuildContext context, String details) {
  final words = LiveUiScope.of(context).strings;
  return showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      key: const ValueKey('status-details'),
      title: words.details,
      message: details,
      selectable: true,
      wide: true,
      actions: [
        DialogCancelButton(label: words.close),
        DialogActionButton(
          key: const ValueKey('status-details-copy'),
          label: words.copy,
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: details)));
            Navigator.of(dialogContext).pop();
            showAppToast(context, AppToast(words.copied));
          },
        ),
      ],
    ),
  );
}

/// The empty state (3.x `EmptyView`): [AppStatusView] with
/// [AppStatusType.empty].
class EmptyView extends StatelessWidget {
  /// Creates the view.
  const new({
    this.title,
    this.subtitle,
    this.icon,
    this.buttonText,
    this.buttonIcon,
    this.onButtonPressed,
    this.isMini = false,
    this.compact = false,
    this.iconColor,
    this.titleColor,
    this.subtitleColor,
    this.secondaryButtonText,
    this.onSecondaryButtonPressed,
    super.key,
  });

  /// See [AppStatusView.title].
  final String? title;

  /// See [AppStatusView.subtitle].
  final String? subtitle;

  /// See [AppStatusView.icon].
  final IconData? icon;

  /// See [AppStatusView.buttonText].
  final String? buttonText;

  /// See [AppStatusView.buttonIcon].
  final IconData? buttonIcon;

  /// See [AppStatusView.onButtonPressed].
  final VoidCallback? onButtonPressed;

  /// See [AppStatusView.isMini].
  final bool isMini;

  /// See [AppStatusView.compact].
  final bool compact;

  /// See [AppStatusView.iconColor].
  final Color? iconColor;

  /// See [AppStatusView.titleColor].
  final Color? titleColor;

  /// See [AppStatusView.subtitleColor].
  final Color? subtitleColor;

  /// See [AppStatusView.secondaryButtonText].
  final String? secondaryButtonText;

  /// See [AppStatusView.onSecondaryButtonPressed].
  final VoidCallback? onSecondaryButtonPressed;

  @override
  Widget build(BuildContext context) {
    return AppStatusView(
      type: AppStatusType.empty,
      title: title,
      subtitle: subtitle,
      icon: icon,
      buttonText: buttonText,
      buttonIcon: buttonIcon,
      onButtonPressed: onButtonPressed,
      isMini: isMini,
      compact: compact,
      iconColor: iconColor,
      titleColor: titleColor,
      subtitleColor: subtitleColor,
      secondaryButtonText: secondaryButtonText,
      onSecondaryButtonPressed: onSecondaryButtonPressed,
    );
  }
}

/// The static skeleton of a list of rows while it first loads (U.1c c3;
/// UI_PLAN §9.3: no shimmer): rows of an icon, two bars and a pill on a
/// rounded card, as many as fill the space. Room grids use
/// `RoomCardSkeleton`.
class StatusSkeleton extends StatelessWidget {
  /// Creates the skeleton.
  const new({this.rows, this.trailing = true, this.padding = const EdgeInsets.all(16), super.key});

  /// How many rows; null draws 12, cut where the space ends.
  final int? rows;

  /// Whether each row has a pill at the end (a switch, a value).
  final bool trailing;

  /// Space around the card.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = scheme.surfaceContainerHigh;
    Widget bar(double factor, double height) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: factor,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(height / 2)),
      ),
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(6)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(0.55, 11), const SizedBox(height: 9), bar(0.8, 9)],
            ),
          ),
          if (trailing) ...[
            const SizedBox(width: 16),
            Container(
              width: 44,
              height: 24,
              decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(12)),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      key: const ValueKey('status-skeleton'),
      label: LiveUiScope.of(context).strings.loading,
      // Cut at the bottom of the space it has (no LayoutBuilder, see
      // AppStatusView).
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
          child: Column(children: [for (var i = 0; i < (rows ?? 12); i++) row]),
        ),
      ),
    );
  }
}

/// A [ConstrainedBox] of at most [maxWidth] whose height measured ahead of
/// layout (`SliverFillRemaining`) is its height at that width: a plain one
/// measures its child at the full width, fewer lines than it then takes.
class _MaxWidth extends SingleChildRenderObjectWidget {
  const new({required this.maxWidth, super.child});

  final double maxWidth;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMaxWidth(maxWidth);

  @override
  void updateRenderObject(BuildContext context, _RenderMaxWidth renderObject) =>
      renderObject.additionalConstraints = BoxConstraints(maxWidth: maxWidth);
}

class _RenderMaxWidth extends RenderConstrainedBox {
  new(double maxWidth) : super(additionalConstraints: BoxConstraints(maxWidth: maxWidth));

  double _within(double width) => math.min(width, additionalConstraints.maxWidth);

  @override
  double computeMinIntrinsicHeight(double width) => super.computeMinIntrinsicHeight(_within(width));

  @override
  double computeMaxIntrinsicHeight(double width) => super.computeMaxIntrinsicHeight(_within(width));
}
