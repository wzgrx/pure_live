import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/theme/live_colors.dart';

/// The width of a panel on the right (docs/ui/UI_PLAN.md §7).
const double sidePanelWidth = 360;

/// Opens a panel of a page without a picture (docs/ui/UI_PLAN.md §7): the
/// same content rises from the bottom on narrow screens, or slides in on
/// the right ([sidePanelWidth] wide, the full height) when [side]; the page
/// behind is dimmed. ✕ in the content's [PanelHeader], Back, Esc, a tap
/// outside and (from the bottom) a downward drag close it.
Future<T?> showAdaptivePanel<T>(
  BuildContext context, {
  required bool side,
  required WidgetBuilder builder,
  String? barrierLabel,
}) {
  if (!side) {
    final height = MediaQuery.sizeOf(context).height;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: height * 0.85),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
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

/// The top of a panel: its title, [actions] and ✕.
class PanelHeader extends StatelessWidget {
  /// Creates the header.
  const new({required this.title, required this.closeTooltip, this.actions = const [], this.onClose, super.key});

  /// The panel's name.
  final String title;

  /// The ✕ button's tooltip ("关闭").
  final String closeTooltip;

  /// Between the title and ✕.
  final List<Widget> actions;

  /// Closes the panel; null pops the route.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 4, 0),
      child: SizedBox(
        height: kMinInteractiveDimension + 4,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                key: const ValueKey('panel-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.emphasis.copyWith(fontSize: 18, color: theme.colorScheme.onSurface),
              ),
            ),
            ...actions,
            IconButton(
              key: const ValueKey('panel-close'),
              tooltip: closeTooltip,
              onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(AppIcons.close),
            ),
          ],
        ),
      ),
    );
  }
}
