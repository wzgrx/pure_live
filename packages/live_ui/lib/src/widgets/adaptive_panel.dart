import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/live_theme.dart';
import 'package:live_ui/src/theme/metrics.dart';

/// The width of a panel on the right (docs/specs/UI.md §7).
const double sidePanelWidth = 360;

/// The width from which a page without a picture opens its panels on the
/// right (docs/A-界面设计/A02-组件/A02.2-弹窗组件 c10: the bottom on phones, the right on wide
/// screens).
const double sidePanelBreakpoint = 600;

/// Opens a panel of a page without a picture (docs/specs/UI.md §7,
/// docs/A-界面设计/A02-组件/A02.2-弹窗组件 c10): the same content rises from the bottom with
/// a handle on narrow screens, or slides in on the right ([sidePanelWidth]
/// wide, the full height) when [side] (by default from
/// [sidePanelBreakpoint]); the page behind is dimmed. ✕ in the content's
/// [PanelHeader], Back, Esc, a tap outside and (from the bottom) a downward
/// drag close it.
///
/// With [openHeight] (a share of the screen's height) a bottom panel opens
/// that tall and can be dragged up to the full height (the top stop of
/// docs/A-界面设计/A03-动效和手感/A03.2-翻页和面板's panels; A09.12 c3): the content's
/// list scrolls with the [PrimaryScrollController] (`primary: true`), which
/// moves the panel first. Without it the panel is as tall as its content,
/// at most 85% of the screen.
///
/// A fold or hinge that splits the window (A04.1) keeps the panel on one
/// side of it: the lower half when the fold lies across (tabletop posture:
/// the controls on the part that rests on the table), otherwise the end half
/// for the side panel and the start half for the bottom one.
Future<T?> showAdaptivePanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool? side,
  String? barrierLabel,
  double? openHeight,
}) {
  final rtl = Directionality.of(context) == TextDirection.rtl;
  // Where the panel goes on a split window (DisplayFeatureSubScreen).
  final bottomAnchor = Offset(rtl ? double.maxFinite : 0, double.maxFinite);
  if (!(side ?? MediaQuery.sizeOf(context).width >= sidePanelBreakpoint)) {
    final height = MediaQuery.sizeOf(context).height;
    if (openHeight != null) {
      // The sheet's room: under the status bar, below the 48 of the handle.
      final room = height - MediaQuery.paddingOf(context).top - kMinInteractiveDimension;
      final open = room <= 0 ? 1.0 : ((height * openHeight - kMinInteractiveDimension) / room).clamp(0.3, 1.0);
      return showModalBottomSheet<T>(
        context: context,
        anchorPoint: bottomAnchor,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        constraints: const BoxConstraints(),
        builder: (context) => DraggableScrollableSheet(
          key: const ValueKey('panel-docked'),
          expand: false,
          initialChildSize: open,
          // Dragged below this the panel closes.
          minChildSize: open * 0.4,
          snap: true,
          snapSizes: [if (open < 1) open],
          builder: (context, controller) => PrimaryScrollController(
            controller: controller,
            child: Builder(builder: builder),
          ),
        ),
      );
    }
    return showModalBottomSheet<T>(
      context: context,
      anchorPoint: bottomAnchor,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: height * 0.85),
      builder: builder,
    );
  }
  return showGeneralDialog<T>(
    context: context,
    anchorPoint: Offset(rtl ? 0 : double.maxFinite, double.maxFinite),
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
            shape: const RoundedRectangleBorder(borderRadius: AppRadii.panelSide),
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

/// The top of a panel (docs/A-界面设计/A02-组件/A02.2-弹窗组件, U.2f): 52 high, the title
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
                  // 17 by default: the card title size × 17 / 15, so it follows the
                  // font settings (A01.2).
                  style: theme.textTheme.titleMedium?.emphasis.copyWith(
                    fontSize: LiveFontSizes.of(theme.textTheme).titleMedium * 17 / 15,
                    color: scheme.onSurface,
                  ),
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
