import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';

/// The width of a panel on the right (docs/ui/UI_PLAN.md §7).
const double sidePanelWidth = 360;

/// The width from which a page without a picture opens its panels on the
/// right (docs/ui/compare/U.1d c10: the bottom on phones, the right on wide
/// screens).
const double sidePanelBreakpoint = 600;

/// Opens a panel of a page without a picture (docs/ui/UI_PLAN.md §7,
/// docs/ui/compare/U.1d c10): the same content rises from the bottom with
/// a handle on narrow screens, or slides in on the right ([sidePanelWidth]
/// wide, the full height) when [side] (by default from
/// [sidePanelBreakpoint]); the page behind is dimmed. ✕ in the content's
/// [PanelHeader], Back, Esc, a tap outside and (from the bottom) a downward
/// drag close it.
Future<T?> showAdaptivePanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool? side,
  String? barrierLabel,
}) {
  if (!(side ?? MediaQuery.sizeOf(context).width >= sidePanelBreakpoint)) {
    final height = MediaQuery.sizeOf(context).height;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: height * 0.85),
      builder: builder,
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: OnVideoColors.scrimMid,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (dialogContext, _, _) {
      final width = math.min(sidePanelWidth, MediaQuery.sizeOf(dialogContext).width);
      final scheme = Theme.of(dialogContext).colorScheme;
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          key: const ValueKey('side-panel'),
          width: width,
          height: double.infinity,
          child: Material(
            color: scheme.surface,
            elevation: 2,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(16))),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(left: false, child: Builder(builder: builder)),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  );
}

/// The top of a panel (docs/ui/compare/U.1d, U.2f): 52 high, the title
/// (17, semi-bold), [actions] (a text link such as "录制中心 ›") and ✕ (48,
/// the variant ink); [leading] before the title (the back of a second
/// page).
class PanelHeader extends StatelessWidget {
  /// Creates the header.
  const new({
    required this.title,
    this.closeTooltip,
    this.actions = const [],
    this.onClose,
    this.leading,
    this.titleKey = const ValueKey('panel-title'),
    this.closeKey = const ValueKey('panel-close'),
    super.key,
  });

  /// The panel's name.
  final String title;

  /// The ✕ button's tooltip; "关闭" by default.
  final String? closeTooltip;

  /// Between the title and ✕.
  final List<Widget> actions;

  /// Closes the panel; null pops the route.
  final VoidCallback? onClose;

  /// Before the title.
  final Widget? leading;

  /// The title's key.
  final Key titleKey;

  /// ✕'s key.
  final Key closeKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: leading == null ? 20 : 4, end: 4),
      child: SizedBox(
        height: kMinInteractiveDimension + 4,
        child: Row(
          children: [
            ?leading,
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  key: titleKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.emphasis.copyWith(fontSize: 17, color: scheme.onSurface),
                ),
              ),
            ),
            ...actions,
            IconButton(
              key: closeKey,
              tooltip: closeTooltip ?? LiveUiScope.of(context).strings.close,
              color: scheme.onSurfaceVariant,
              onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(AppIcons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// A panel's [header] over its [child] (U.1d: one panel in three places):
/// once the content has scrolled, a line under the header, which stays put.
/// With [expand] the content takes the rest of the height (a panel of a
/// fixed size); otherwise the panel is as tall as its content.
class PanelFrame extends StatefulWidget {
  /// Creates the frame.
  const new({required this.header, required this.child, this.expand = true, super.key});

  /// The [PanelHeader] (or a widget around one: the drag area of a room
  /// panel).
  final Widget header;

  /// The content.
  final Widget child;

  /// Whether the content fills the panel's height.
  final bool expand;

  @override
  State<PanelFrame> createState() => _PanelFrameState();
}

class _PanelFrameState extends State<PanelFrame> {
  bool _scrolled = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      final scrolled = notification.metrics.extentBefore > 0.5;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final content = NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child);
    return Column(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        Divider(
          key: const ValueKey('panel-header-line'),
          height: 1,
          thickness: 1,
          color: _scrolled ? Theme.of(context).colorScheme.outlineVariant : Colors.transparent,
        ),
        if (widget.expand) Expanded(child: content) else Flexible(child: content),
      ],
    );
  }
}
